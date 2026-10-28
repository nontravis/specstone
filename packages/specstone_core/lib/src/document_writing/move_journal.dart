import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/atomic_write.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/index_store.dart';
import 'package:specstone_core/src/rendering/docs_project.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';

/// One idempotent step of a [MoveJournal].
///
/// Every path is relative to the project root and `/`-separated. Applying a
/// step twice, or after a crash left it half done, ends in the same state.
sealed class JournalStep {
  const new();

  /// Returns the step as the single-key JSON object the journal stores.
  Map<String, Object> toJson();

  /// Applies the step to [project].
  ///
  /// Throws [RenderFault] `output_not_writable` when the disk refuses.
  void apply(DocsProject project);

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
  void apply(DocsProject project) {
    final source = _absolute(project, from);
    if (FileSystemEntity.typeSync(source, followLinks: false) ==
        FileSystemEntityType.notFound) {
      return;
    }
    final target = _absolute(project, to);
    if (to.startsWith('${MoveJournal.stagePath}/') &&
        FileSystemEntity.typeSync(target, followLinks: false) !=
            FileSystemEntityType.notFound) {
      return;
    }
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
  void apply(DocsProject project) {
    try {
      final docsRoot = project.docsRoot.path;
      var current = Directory(_underDocsRoot(project, folder));
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
  void apply(DocsProject project) {
    final file = File(_absolute(project, path));
    try {
      if (!file.existsSync() || file.readAsStringSync() == text) return;
      writeFileAtomic(file, utf8.encode(text));
    } on FileSystemException catch (error) {
      throw _notWritable('write', path, error);
    } on FormatException catch (error) {
      throw _notWritable('write', path, error);
    }
  }
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

  /// Saves the journal, applies each step, then removes the journal and the
  /// trash folder.
  ///
  /// Throws [IndexFault] `index_not_writable` when `.specstone/.gitignore`
  /// cannot be written, and [RenderFault] `output_not_writable` when the docs
  /// root sits on another volume than the trash (before any file moves), or
  /// when a step or the journal write fails; the journal stays in the last
  /// case.
  void run(DocsProject project) {
    final specstone = Directory(_join(project.projectRoot.path, '.specstone'));
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
    if (steps.any(_movesToTrash)) _requireSameVolume(project);
    try {
      Directory(_join(project.projectRoot.path, trashPath)).createSync();
      writeFileAtomic(
        File(_join(project.projectRoot.path, journalPath)),
        utf8.encode(jsonEncode(toJson())),
      );
    } on FileSystemException catch (error) {
      throw _notWritable('write', journalPath, error);
    }
    _finish(project, steps);
  }

  /// Finishes an unfinished journal, then removes the trash folder.
  ///
  /// A journal that does not parse is refused and left with the trash, since
  /// its steps may be the only record of where the files went. Does nothing
  /// when no trash folder exists.
  ///
  /// Throws [RenderFault] `output_not_writable` when a step fails, the journal
  /// stays, so the next replay resumes, or when the journal cannot be parsed.
  static void replay(DocsProject project) {
    final journal = File(
      _join(project.projectRoot.path, MoveJournal.journalPath),
    );
    if (!journal.existsSync()) {
      _removeTrash(project);
      return;
    }
    final List<JournalStep> steps;
    try {
      steps = _stepsOf(jsonDecode(journal.readAsStringSync()));
    } on FormatException catch (error) {
      throw RenderFault(
        RenderFaultCode.outputNotWritable,
        'cannot replay ${MoveJournal.journalPath}: ${error.message}; '
        'fix or remove it',
      );
    } on FileSystemException catch (error) {
      throw _notWritable('read', MoveJournal.journalPath, error);
    }
    _finish(project, steps);
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
/// from the docs root into the trash folder, as a docs root linked to another
/// volume cannot.
///
/// Probes with a fresh empty folder, so the refusal comes before the journal,
/// nothing is left half moved, and no user file is touched. A probe that
/// fails also removes the trash folder it made.
void _requireSameVolume(DocsProject project) {
  final trash = Directory(
    _join(project.projectRoot.path, MoveJournal.trashPath),
  );
  final trashExisted = trash.existsSync();
  Directory? probe;
  Directory? landed;
  try {
    probe = Directory(project.docsRoot.path)
        .createTempSync('.specstone-probe-');
    trash.createSync(recursive: true);
    landed = probe.renameSync(_join(trash.path, 'move-probe'));
  } on FileSystemException catch (error) {
    if (!trashExisted && trash.existsSync()) trash.deleteSync(recursive: true);
    throw RenderFault(
      RenderFaultCode.outputNotWritable,
      'cannot move docs into ${MoveJournal.trashPath}: '
      '${error.osError?.message ?? error.message}',
    );
  } finally {
    for (final folder in [?probe, ?landed]) {
      if (folder.existsSync()) folder.deleteSync();
    }
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
void _finish(DocsProject project, List<JournalStep> steps) {
  for (final step in steps) {
    step.apply(project);
  }
  try {
    final journal = File(
      _join(project.projectRoot.path, MoveJournal.journalPath),
    );
    if (journal.existsSync()) journal.deleteSync();
  } on FileSystemException catch (error) {
    throw _notWritable('remove', MoveJournal.journalPath, error);
  }
  _removeTrash(project);
}

void _removeTrash(DocsProject project) {
  final trash = Directory(
    _join(project.projectRoot.path, MoveJournal.trashPath),
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

String _absolute(DocsProject project, String relative) =>
    _join(project.projectRoot.path, relative);

/// Resolves a `docs/`-relative [relative] against the canonical docs root, so
/// a linked `docs` folder still compares equal to it.
String _underDocsRoot(DocsProject project, String relative) =>
    relative.startsWith('docs/')
    ? _join(project.docsRoot.path, relative.substring(5))
    : _absolute(project, relative);

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
