import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/atomic_write.dart';
import 'package:specstone_core/src/git_process.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/index_store.dart';
import 'package:specstone_core/src/rendering/docs_project.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';

/// What a [JournalStep] acts on: the two roots and the `git` runner.
///
/// A legacy tree has no `.specstone/config.yaml`, so no [DocsProject]; every
/// step needs only these.
final class JournalTarget {
  const new({
    required this.projectRoot,
    required this.docsRoot,
    this.runGit = runRealGit,
  });

  /// Returns the target of an opened [project].
  factory of(DocsProject project) => JournalTarget(
    projectRoot: project.projectRoot,
    docsRoot: project.docsRoot,
  );

  /// The folder every step path is relative to.
  final Directory projectRoot;

  /// The folder of the docs, in the form the steps compare paths against.
  final Directory docsRoot;

  /// Starts `git`; replaced in tests.
  final RunGit runGit;
}

/// One idempotent step of a [MoveJournal].
///
/// Every path is relative to the project root and `/`-separated. Applying a
/// step twice, or after a crash left it half done, ends in the same state.
sealed class JournalStep {
  const new();

  /// Returns the step as the single-key JSON object the journal stores.
  Map<String, Object> toJson();

  /// Returns one line that tells what the step does.
  String describe();

  /// Whether the step's effect is already in place on [target].
  ///
  /// Throws [FileSystemException] or [ProcessException] when the state cannot
  /// be read.
  bool isDone(JournalTarget target);

  /// Applies the step to [target]; returns at once when it [isDone].
  ///
  /// [PruneStep] is the exception: it always runs, so a replay still prunes
  /// the parent folders an earlier run emptied.
  ///
  /// Throws [RenderFault] `output_not_writable` when the disk refuses, and
  /// [GitCommandFailed] when `git` refuses a [CommitStep].
  void apply(JournalTarget target);

  /// Reads one step back from its [json] form.
  ///
  /// Throws [FormatException] when [json] is not a step.
  static JournalStep fromJson(Object? json) {
    if (json is Map<String, Object?> && json.length == 1) {
      final MapEntry(:key, :value) = json.entries.single;
      if (value is Map<String, Object?>) {
        switch ((key, value)) {
          case ('move', {'from': final String from, 'to': final String to}):
            return MoveStep(from, to);
          case ('prune', {'folder': final String folder}):
            return PruneStep(folder);
          case (
            'write',
            {'path': final String path, 'text': final String text},
          ):
            return WriteStep(path, text);
          case (
            'create',
            {'path': final String path, 'text': final String text},
          ):
            return CreateStep(path, text);
          case (
                'commit',
                {
                  'message': final String message,
                  'paths': final List<Object?> paths,
                  'base': final String base,
                },
              )
              when paths.every((path) => path is String):
            return CommitStep(
              message: message,
              paths: paths.cast<String>(),
              base: base,
            );
        }
      }
    }
    throw FormatException('not a journal step', json);
  }
}

/// Moves a file, a folder, or a symbolic link as itself, creating the parent
/// folders of the target.
///
/// Skipped when [from] is gone, because an earlier run already moved it, and
/// when [to] is a stage slot that is taken, so a replay never lands on what
/// another move staged there.
final class MoveStep extends JournalStep {
  const new(this.from, this.to);

  /// The path to move.
  final String from;

  /// The path to move it to.
  final String to;

  @override
  Map<String, Object> toJson() => {
    'move': {'from': from, 'to': to},
  };

  @override
  String describe() => 'move $from -> $to';

  @override
  bool isDone(JournalTarget target) =>
      FileSystemEntity.typeSync(_absolute(target, from), followLinks: false) ==
      FileSystemEntityType.notFound;

  @override
  void apply(JournalTarget target) {
    if (isDone(target)) return;
    final destination = _absolute(target, to);
    if (to.startsWith('${MoveJournal.stagePath}/') &&
        FileSystemEntity.typeSync(destination, followLinks: false) !=
            FileSystemEntityType.notFound) {
      return;
    }
    _moveEntity(_absolute(target, from), destination);
  }

  void _moveEntity(String source, String target) {
    try {
      Directory(File(target).parent.path).createSync(recursive: true);
      _entityAt(source).renameSync(target);
    } on FileSystemException catch (error) {
      throw _notWritable('move', from, error);
    }
  }
}

/// Removes an empty folder, then each empty parent below the docs root.
final class PruneStep extends JournalStep {
  const new(this.folder);

  /// The folder to remove when it is empty.
  final String folder;

  @override
  Map<String, Object> toJson() => {
    'prune': {'folder': folder},
  };

  @override
  String describe() => 'prune $folder';

  /// Whether [folder] is gone.
  ///
  /// [apply] does not return early when this holds: the folder may be gone
  /// while its emptied parents remain.
  @override
  bool isDone(JournalTarget target) =>
      !Directory(_underDocsRoot(target, folder)).existsSync();

  @override
  void apply(JournalTarget target) {
    try {
      final docsRoot = target.docsRoot.path;
      var current = Directory(_underDocsRoot(target, folder));
      while (current.path != docsRoot && _isInside(docsRoot, current.path)) {
        if (current.existsSync()) {
          if (current.listSync().isNotEmpty) return;
          current.deleteSync();
        }
        current = current.parent;
      }
    } on FileSystemException catch (error) {
      throw _notWritable('remove', folder, error);
    }
  }
}

/// Writes [text] to a file that exists and differs from it.
final class WriteStep extends JournalStep {
  const new(this.path, this.text);

  /// The file to write.
  final String path;

  /// The new UTF-8 text.
  final String text;

  @override
  Map<String, Object> toJson() => {
    'write': {'path': path, 'text': text},
  };

  @override
  String describe() => 'write $path';

  @override
  bool isDone(JournalTarget target) {
    final file = File(_absolute(target, path));
    return !file.existsSync() || file.readAsStringSync() == text;
  }

  @override
  void apply(JournalTarget target) {
    try {
      if (isDone(target)) return;
      writeFileAtomic(File(_absolute(target, path)), utf8.encode(text));
    } on FileSystemException catch (error) {
      throw _notWritable('write', path, error);
    } on FormatException catch (error) {
      throw _notWritable('write', path, error);
    }
  }
}

/// Writes [text] to a path that does not exist yet, creating its parent
/// folders; never overwrites.
final class CreateStep extends JournalStep {
  const new(this.path, this.text);

  /// The file to create.
  final String path;

  /// The UTF-8 text of the new file.
  final String text;

  @override
  Map<String, Object> toJson() => {
    'create': {'path': path, 'text': text},
  };

  @override
  String describe() => 'create $path';

  @override
  bool isDone(JournalTarget target) =>
      FileSystemEntity.typeSync(_absolute(target, path), followLinks: false) !=
      FileSystemEntityType.notFound;

  @override
  void apply(JournalTarget target) {
    if (isDone(target)) return;
    final file = File(_absolute(target, path));
    try {
      file.parent.createSync(recursive: true);
      writeFileAtomic(file, utf8.encode(text));
    } on FileSystemException catch (error) {
      throw _notWritable('create', path, error);
    }
  }
}

/// Commits [paths] with [message], once.
///
/// [base] is the HEAD sha when the journal was written; the step is done when
/// a commit after [base] carries [message] within a line (a hook may prefix
/// the subject), so a replay after any crash point makes the commit exactly
/// once. A step whose [paths] stage nothing is done and commits nothing.
final class CommitStep extends JournalStep {
  const new({required this.message, required this.paths, required this.base});

  /// The commit message.
  final String message;

  /// The paths to stage, relative to the project root and `/`-separated.
  final List<String> paths;

  /// The HEAD sha when the journal was written.
  final String base;

  @override
  Map<String, Object> toJson() => {
    'commit': {'message': message, 'paths': paths, 'base': base},
  };

  @override
  String describe() => 'commit "$message"';

  @override
  bool isDone(JournalTarget target) {
    final log = target.runGit([
      'log',
      '--format=%B',
      '$base..HEAD',
    ], workingDirectory: target.projectRoot.path);
    return log.exitCode == 0 &&
        const LineSplitter()
            .convert(log.stdout as String)
            .any((line) => line.contains(message));
  }

  @override
  void apply(JournalTarget target) {
    if (isDone(target)) return;
    final known = paths.where((path) => _isKnown(target, path)).toList();
    if (known.isNotEmpty) {
      _runWrite(target, 'add', ['add', '-A', '--', ...known]);
    }
    if (_nothingStaged(target)) return;
    _runWrite(target, 'commit', ['commit', '-q', '-m', message]);
  }

  /// Whether [path] sits in the work tree or the index.
  ///
  /// `git add` refuses a pathspec that matches neither, as a moved-away path
  /// does once an earlier, refused attempt already staged its deletion.
  bool _isKnown(JournalTarget target, String path) {
    final absolute = _absolute(target, path);
    if (FileSystemEntity.typeSync(absolute, followLinks: false) !=
        FileSystemEntityType.notFound) {
      return true;
    }
    final listed = target.runGit([
      'ls-files',
      '--',
      path,
    ], workingDirectory: target.projectRoot.path);
    return listed.exitCode == 0 && '${listed.stdout}'.trim().isNotEmpty;
  }

  /// Whether the staged changes under [paths] are empty, as when a hook that
  /// rewrote the subject hid an earlier commit from [isDone].
  bool _nothingStaged(JournalTarget target) =>
      target.runGit([
        'diff',
        '--cached',
        '--quiet',
        '--',
        ...paths,
      ], workingDirectory: target.projectRoot.path).exitCode ==
      0;
}

/// Runs the `git` write [arguments] for [verb].
///
/// Throws [GitCommandFailed] when git exits non-zero.
void _runWrite(JournalTarget target, String verb, List<String> arguments) {
  final result = target.runGit(
    arguments,
    workingDirectory: target.projectRoot.path,
  );
  if (result.exitCode != 0) {
    throw GitCommandFailed(verb, _decisiveLine(result));
  }
}

/// Returns the first stderr line of [result] that starts `fatal:` or `error:`,
/// else its last non-empty stderr line, else its last non-empty stdout line
/// (`nothing to commit` goes there), else the empty string.
String _decisiveLine(ProcessResult result) {
  List<String> linesOf(Object? text) => [
    for (final line in const LineSplitter().convert('$text'))
      if (line.trim().isNotEmpty) line.trim(),
  ];
  final errors = linesOf(result.stderr);
  if (errors.isEmpty) return linesOf(result.stdout).lastOrNull ?? '';
  return errors.firstWhere(
    (line) => line.startsWith('fatal:') || line.startsWith('error:'),
    orElse: () => errors.last,
  );
}

/// The steps of one move, rename, reorder, or delete, applied crash-safely.
///
/// [run] saves the steps under [journalPath] before applying any, so a run a
/// crash stopped is finished by [replay] on the next command.
final class MoveJournal {
  const new(this.steps);

  /// The journal file, relative to the project root.
  static const journalPath = '.specstone/trash/journal.json';

  /// The folder holding the journal and the deleted files, relative to the
  /// project root.
  static const trashPath = '.specstone/trash';

  /// The folder a reorder parks its docs in between its two phases, relative
  /// to the project root.
  static const stagePath = '$trashPath/stage';

  /// The steps, applied in order.
  final List<JournalStep> steps;

  /// Returns the journal as JSON: `{'steps': [<step>...]}`.
  Map<String, Object> toJson() => {
    'steps': [for (final step in steps) step.toJson()],
  };

  /// Whether a trash folder, so an unfinished journal or its leftovers, sits
  /// under [projectRoot].
  static bool pending(Directory projectRoot) =>
      Directory(_join(projectRoot.path, trashPath)).existsSync();

  /// Whether the journal under [projectRoot] belongs to an unfinished
  /// `specstone migrate`: it parses and holds a [CommitStep].
  ///
  /// An unreadable or unparsable journal is not a migrate journal, so F-02's
  /// replay refuses it as before.
  static bool pendingMigrate(Directory projectRoot) {
    try {
      final steps = _pendingSteps(projectRoot);
      return steps?.any((step) => step is CommitStep) ?? false;
    } on RenderFault {
      return false;
    }
  }

  /// Returns every step of the pending journal under [projectRoot], or null
  /// when there is none or it does not parse.
  static List<JournalStep>? read(Directory projectRoot) {
    try {
      return _pendingSteps(projectRoot);
    } on RenderFault {
      return null;
    }
  }

  /// Saves the journal, applies each step, then removes the journal and the
  /// trash folder.
  ///
  /// Throws [IndexFault] `index_not_writable` when `.specstone/.gitignore`
  /// cannot be written, and [RenderFault] `output_not_writable` when a
  /// folder a file moves out of sits on another volume than the trash (before
  /// any file moves), or when a step or the journal write fails; the journal
  /// stays in the last case.
  void run(JournalTarget target) {
    final specstone = Directory(_join(target.projectRoot.path, '.specstone'));
    try {
      specstone.createSync(recursive: true);
      ensureSpecstoneGitignore(specstone);
    } on FileSystemException {
      throw IndexFault(
        IndexFaultCode.indexNotWritable,
        'cannot write .specstone/.gitignore; make it writable and run the '
        'command again',
      );
    }
    if (steps.any(_movesToTrash)) _requireSameVolume(target, steps);
    try {
      Directory(_join(target.projectRoot.path, trashPath)).createSync();
      writeFileAtomic(
        File(_join(target.projectRoot.path, journalPath)),
        utf8.encode(jsonEncode(toJson())),
      );
    } on FileSystemException catch (error) {
      throw _notWritable('write', journalPath, error);
    }
    _finish(target, steps);
  }

  /// Finishes an unfinished journal, then removes the trash folder.
  ///
  /// A journal that does not parse is refused and left with the trash, since
  /// its steps may be the only record of where the files went. Does nothing
  /// when no trash folder exists.
  ///
  /// Throws [RenderFault] `output_not_writable` when a step fails, the journal
  /// stays, so the next replay resumes, or when the journal cannot be parsed.
  static void replay(JournalTarget target) {
    final steps = _pendingSteps(target.projectRoot);
    if (steps == null) {
      _removeTrash(target);
      return;
    }
    _finish(target, steps);
  }

  /// Returns the steps of the unfinished journal that are not done yet; empty
  /// when no journal exists.
  ///
  /// Throws [RenderFault] `output_not_writable` when the journal cannot be
  /// parsed.
  static List<JournalStep> remaining(JournalTarget target) => [
    for (final step
        in _pendingSteps(target.projectRoot) ?? const <JournalStep>[])
      if (!step.isDone(target)) step,
  ];
}

/// Returns the steps of the journal file, or null when there is none.
List<JournalStep>? _pendingSteps(Directory projectRoot) {
  final journal = File(_join(projectRoot.path, MoveJournal.journalPath));
  if (!journal.existsSync()) return null;
  try {
    return _stepsOf(jsonDecode(journal.readAsStringSync()));
  } on FormatException catch (error) {
    throw RenderFault(
      RenderFaultCode.outputNotWritable,
      'cannot replay ${MoveJournal.journalPath}: ${error.message}; '
      'fix or remove it',
    );
  } on FileSystemException catch (error) {
    throw _notWritable('read', MoveJournal.journalPath, error);
  }
}

/// Returns [path] as the kind of entity it is, never following a link.
FileSystemEntity _entityAt(String path) =>
    switch (FileSystemEntity.typeSync(path, followLinks: false)) {
      FileSystemEntityType.link => Link(path),
      FileSystemEntityType.directory => Directory(path),
      _ => File(path),
    };

/// Whether [step] moves a file or folder into the trash folder.
bool _movesToTrash(JournalStep step) =>
    step is MoveStep && step.to.startsWith('${MoveJournal.trashPath}/');

/// Throws [RenderFault] `output_not_writable` when a folder cannot be renamed
/// from a folder a file moves out of into the trash folder, as a folder
/// linked to another volume cannot.
///
/// Probes from the parent folder of each file [steps] move to the trash, with
/// a fresh empty folder, so the refusal comes before the journal, nothing is
/// left half moved, and no user file is touched. A source folder that is gone
/// is skipped; its step faults when it runs. A probe that fails also removes
/// the trash folder it made. A probe folder that cannot be removed stays;
/// the next replay removes it from the trash, and a source folder keeps it as
/// a dot folder.
void _requireSameVolume(JournalTarget target, List<JournalStep> steps) {
  final trash = Directory(
    _join(target.projectRoot.path, MoveJournal.trashPath),
  );
  final trashExisted = trash.existsSync();
  final sources = {
    for (final step in steps)
      if (step is MoveStep && _movesToTrash(step))
        File(_absolute(target, step.from)).parent.path,
  };
  try {
    for (final source in sources) {
      if (Directory(source).existsSync()) _probeRename(source, trash);
    }
  } on FileSystemException catch (error) {
    if (!trashExisted && trash.existsSync()) {
      _removeQuietly(trash, recursive: true);
    }
    throw RenderFault(
      RenderFaultCode.outputNotWritable,
      'cannot move docs into ${MoveJournal.trashPath}: '
      '${error.osError?.message ?? error.message}',
    );
  }
}

/// Renames a fresh empty folder from [source] into [trash] under its own
/// name, then removes it.
void _probeRename(String source, Directory trash) {
  Directory? probe;
  Directory? landed;
  try {
    probe = Directory(source).createTempSync('.specstone-probe-');
    trash.createSync(recursive: true);
    final name = probe.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
    landed = probe.renameSync(_join(trash.path, name));
  } finally {
    [?probe, ?landed].forEach(_removeQuietly);
  }
}

/// Removes [folder] when it exists, ignoring a disk that refuses.
void _removeQuietly(Directory folder, {bool recursive = false}) {
  try {
    if (folder.existsSync()) folder.deleteSync(recursive: recursive);
  } on FileSystemException {
    // Best effort: the next replay removes a leftover in the trash.
  }
}

/// Returns the steps of a decoded [journal].
///
/// Throws [FormatException] when [journal] is not `{'steps': [<step>...]}`.
List<JournalStep> _stepsOf(Object? journal) {
  if (journal is Map<String, Object?> && journal['steps'] is List<Object?>) {
    return [
      for (final step in journal['steps']! as List<Object?>)
        JournalStep.fromJson(step),
    ];
  }
  throw const FormatException('not a journal');
}

/// Applies [steps], then deletes the journal and the trash folder.
void _finish(JournalTarget target, List<JournalStep> steps) {
  for (final step in steps) {
    step.apply(target);
  }
  try {
    final journal = File(
      _join(target.projectRoot.path, MoveJournal.journalPath),
    );
    if (journal.existsSync()) journal.deleteSync();
  } on FileSystemException catch (error) {
    throw _notWritable('remove', MoveJournal.journalPath, error);
  }
  _removeTrash(target);
}

void _removeTrash(JournalTarget target) {
  final trash = Directory(
    _join(target.projectRoot.path, MoveJournal.trashPath),
  );
  try {
    if (trash.existsSync()) trash.deleteSync(recursive: true);
  } on FileSystemException catch (error) {
    throw _notWritable('remove', MoveJournal.trashPath, error);
  }
}

/// Joins [root] and the `/`-separated [relative] with the platform separator,
/// so every path this file builds and compares has one form.
String _join(String root, String relative) =>
    '$root${Platform.pathSeparator}'
    '${relative.split('/').join(Platform.pathSeparator)}';

String _absolute(JournalTarget target, String relative) =>
    _join(target.projectRoot.path, relative);

/// Resolves a `docs/`-relative [relative] against the canonical docs root, so
/// a linked `docs` folder still compares equal to it.
String _underDocsRoot(JournalTarget target, String relative) =>
    relative.startsWith('docs/')
    ? _join(target.docsRoot.path, relative.substring(5))
    : _absolute(target, relative);

bool _isInside(String root, String path) =>
    path.startsWith('$root${Platform.pathSeparator}');

/// Builds the `output_not_writable` fault for a failed [verb] on [path].
///
/// A path under the docs root reads relative to it.
RenderFault _notWritable(String verb, String path, Exception error) {
  final reason = switch (error) {
    FileSystemException(:final osError, :final message) =>
      osError?.message ?? message,
    FormatException(:final message) => message,
    _ => '$error',
  };
  final shown = path.startsWith('docs/') ? path.substring(5) : path;
  return RenderFault(
    RenderFaultCode.outputNotWritable,
    'cannot $verb $shown: $reason',
  );
}
