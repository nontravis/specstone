import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' show sha256;
import 'package:specstone_core/src/atomic_write.dart';
import 'package:specstone_core/src/document_writing/journal_bounds.dart';
import 'package:specstone_core/src/document_writing/journal_records.dart';
import 'package:specstone_core/src/document_writing/root_trust.dart';
import 'package:specstone_core/src/git_process.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/index_store.dart';
import 'package:specstone_core/src/plan_hash.dart';
import 'package:specstone_core/src/rendering/doc_reader.dart'
    show byteOrderMark;
import 'package:specstone_core/src/rendering/docs_project.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';

/// What a [JournalStep] acts on: the roots, the home folder that keeps the
/// journal records, and the `git` runner.
///
/// A legacy tree has no `.specstone/config.yaml`, so no [DocsProject]; every
/// step needs only these.
final class JournalTarget {
  const new({
    required this.projectRoot,
    required this.docsRoot,
    required this.homeDirectory,
    this.trust,
    this.agentFiles = const {},
    this.runGit = runRealGit,
    this.warn = warnOnStderr,
  });

  /// Returns the target of an opened [project], its records under
  /// [homeDirectory].
  factory of(DocsProject project, {required Directory? homeDirectory}) =>
      JournalTarget(
        projectRoot: project.projectRoot,
        docsRoot: project.docsRoot,
        homeDirectory: homeDirectory,
        trust: project.trust,
      );

  /// The folder every step path is relative to.
  final Directory projectRoot;

  /// The folder of the docs, in the form the steps compare paths against.
  final Directory docsRoot;

  /// The user's home folder, under which [JournalRecords] keeps the digest and
  /// the agent files of each journal a run writes; null, a relative path, or a
  /// folder inside the project keeps none, so a run that writes a journal is
  /// refused and no journal replays.
  final Directory? homeDirectory;

  /// The roots of an opened project and whether the Owner trusts them; null
  /// for a legacy tree, whose roots are its own folder.
  ///
  /// Roots the Owner has not recorded bound no step: [requireTrusted] refuses
  /// first, and a replay finds every step path outside them.
  final RootTrust? trust;

  /// The canonical paths of the agent files a migrate writes inside the
  /// project root; [MoveJournal.run] records them with the journal, so its
  /// replay admits them.
  final Set<String> agentFiles;

  /// Starts `git`; replaced in tests.
  final RunGit runGit;

  /// Reports one warning line; writes it to stderr unless replaced.
  final void Function(String line) warn;

  JournalRecords get _records => JournalRecords(homeDirectory);

  /// Throws [RenderFault] `output_not_writable`, naming
  /// [MoveJournal.journalPath], unless the Owner trusts the roots.
  ///
  /// A command that writes a journal calls it before any prompt or change;
  /// [MoveJournal.run] calls it again as the backstop.
  void requireTrusted() => trust?.requireTrusted(MoveJournal.journalPath);

  /// The folders a step path must land in: the project and docs roots, each
  /// at its canonical path, none while the roots are untrusted. A code root
  /// outside the project is read, never written (R99).
  List<String> get _bounds => [
    if (trust?.refusal == null)
      for (final folder in [projectRoot, docsRoot])
        if (folder.existsSync()) folder.resolveSymbolicLinksSync(),
  ];
}

/// Writes [line] to stderr; the default of every `warn` hook.
void warnOnStderr(String line) => stderr.writeln(line);

/// Returns the hash of [text], read as a file's text without a byte-order
/// mark; a [WriteStep] records it for the text it replaces.
String textHashOf(String text) {
  final bare = text.startsWith(byteOrderMark) ? text.substring(1) : text;
  return sha256.convert(utf8.encode(bare)).toString();
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

  /// The paths the step acts on, each relative to the project root.
  List<String> get _paths;

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
            return switch (value['before']) {
              final String before => WriteStep(path, text, before: before),
              _ => WriteStep.unguarded(path, text),
            };
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
              moves: _movesOf(value['moves']),
            );
        }
      }
    }
    throw FormatException('not a journal step', json);
  }
}

/// Returns the move pairs of a commit step's `moves` entry, none when the
/// entry is absent.
///
/// Throws [FormatException] when [json] is not a list of `{from, to}` string
/// pairs.
List<({String from, String to})> _movesOf(Object? json) => switch (json) {
  null => const [],
  List<Object?>() => [
    for (final move in json)
      switch (move) {
        {'from': final String from, 'to': final String to} => (
          from: from,
          to: to,
        ),
        _ => throw FormatException('not a commit move', move),
      },
  ],
  _ => throw FormatException('not a list of commit moves', json),
};

/// Whether [from] and [to] name one path in two letter cases, so a case-blind
/// disk takes the new case only through a temporary name.
bool isCaseOnlyMove(String from, String to) =>
    from != to && from.toLowerCase() == to.toLowerCase();

/// Moves a file, a folder, or a symbolic link as itself, creating the parent
/// folders of the target.
///
/// Skipped when [from] is gone, because an earlier run already moved it, and
/// when [to] is a stage slot that is taken, so a replay never lands on what
/// another move staged there. A path pair that differs only in letter case
/// renames through a temporary sibling name, so a case-blind disk takes the
/// new case, and a replay stopped between the two renames finishes them.
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
  List<String> get _paths => [from, to];

  @override
  bool isDone(JournalTarget target) {
    final source = _absolute(target, from);
    if (!isCaseOnlyMove(from, to)) {
      return FileSystemEntity.typeSync(source, followLinks: false) ==
          FileSystemEntityType.notFound;
    }
    // A case-blind disk still lists the old spelling, and a stop between the
    // two renames lists the temporary name, so the case as the disk lists it
    // tells whether the step ran.
    final listed = _listedNameOf(source);
    return listed == null || listed == _lastSegmentOf(to);
  }

  @override
  void apply(JournalTarget target) {
    if (isDone(target)) return;
    final destination = _absolute(target, to);
    if (to.startsWith('${MoveJournal.stagePath}/') &&
        FileSystemEntity.typeSync(destination, followLinks: false) !=
            FileSystemEntityType.notFound) {
      return;
    }
    if (isCaseOnlyMove(from, to)) {
      _moveCaseOnly(_absolute(target, from), destination);
      return;
    }
    _moveEntity(_absolute(target, from), destination);
  }

  /// Renames the entry at [source] to [target] through a temporary sibling
  /// name, so a case-blind disk ends with [target]'s case.
  ///
  /// A stop between the two renames leaves the temporary name; the next run
  /// renames it to [target] in one hop.
  void _moveCaseOnly(String source, String target) {
    final listed = _listedNameOf(source);
    if (listed == null) return;
    final atOldSpelling =
        listed.toLowerCase() == _lastSegmentOf(source).toLowerCase();
    try {
      var entry = source;
      if (atOldSpelling) {
        var attempt = 0;
        String tempOf() {
          final nonce = DateTime.now().millisecondsSinceEpoch % 9973;
          return '$target$_tempCaseSuffix-$nonce-$attempt';
        }

        var temp = tempOf();
        while (FileSystemEntity.typeSync(temp, followLinks: false) !=
            FileSystemEntityType.notFound) {
          attempt++;
          temp = tempOf();
        }
        renameSyncRetrying(_entityAt(source), temp);
        entry = temp;
      } else {
        entry = _join(File(source).parent.path, listed);
      }
      renameSyncRetrying(_entityAt(entry), target);
    } on FileSystemException catch (error) {
      throw _notWritable('move', from, error);
    }
  }

  void _moveEntity(String source, String target) {
    try {
      Directory(File(target).parent.path).createSync(recursive: true);
      renameSyncRetrying(_entityAt(source), target);
    } on FileSystemException catch (error) {
      throw _notWritable('move', from, error);
    }
  }
}

/// The marker of a [MoveStep]'s temporary name in a case-only move.
const _tempCaseSuffix = '.specstone-case';

String _lastSegmentOf(String path) => path.split(RegExp(r'[/\\]')).last;

/// Returns the name the disk lists for [path]'s segment, matched without
/// letter case, a leftover temporary name included, or null when no entry is
/// there.
String? _listedNameOf(String path) {
  final wanted = _lastSegmentOf(path).toLowerCase();
  final folder = Directory(File(path).parent.path);
  if (!folder.existsSync()) return null;
  String? leftover;
  for (final entity in folder.listSync(followLinks: false)) {
    final name = _lastSegmentOf(entity.path);
    final folded = name.toLowerCase();
    if (folded == wanted) return name;
    if (folded.startsWith('$wanted$_tempCaseSuffix')) leftover = name;
  }
  return leftover;
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

  @override
  List<String> get _paths => [folder];

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
///
/// The step writes only a file that still holds the text whose [textHashOf]
/// is [before], the text it had when the run was planned, and that is not
/// read-only; any other file is left as it is and named in a warning.
final class WriteStep extends JournalStep {
  const new(this.path, this.text, {required String this.before});

  /// A step from a journal an older release wrote, which recorded no hash and
  /// so writes over whatever the file holds.
  const new unguarded(this.path, this.text) : before = null;

  /// The file to write.
  final String path;

  /// The new UTF-8 text.
  final String text;

  /// The [textHashOf] of the text the step replaces; null for an unguarded
  /// step.
  final String? before;

  @override
  Map<String, Object> toJson() => {
    'write': {'path': path, 'text': text, 'before': ?before},
  };

  @override
  String describe() => 'write $path';

  @override
  List<String> get _paths => [path];

  @override
  bool isDone(JournalTarget target) {
    final file = File(_absolute(target, path));
    return !file.existsSync() || _textOf(file) == _withoutBom(text);
  }

  @override
  void apply(JournalTarget target) {
    try {
      if (isDone(target)) return;
      final file = File(_absolute(target, path));
      if (before case final expected?
          when textHashOf(_textOf(file)) != expected) {
        target.warn('$path changed since the stopped run; left as it is');
        return;
      }
      // A rename replaces a read-only file whatever its mode.
      if (isReadOnly(file)) {
        target.warn('$path is read-only; left as it is');
        return;
      }
      writeFileAtomic(file, utf8.encode(text));
    } on FileSystemException catch (error) {
      throw _notWritable('write', path, error);
    } on FormatException catch (error) {
      throw _notWritable('write', path, error);
    }
  }

  static String _textOf(File file) => _withoutBom(file.readAsStringSync());

  static String _withoutBom(String text) =>
      text.startsWith(byteOrderMark) ? text.substring(1) : text;
}

/// Writes [text] to a path that does not exist yet, creating its parent
/// folders; never overwrites.
///
/// A file there that holds [text] byte for byte is what a replay finds after
/// the step ran, so the step is done; anything else there stops the run.
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
  List<String> get _paths => [path];

  @override
  bool isDone(JournalTarget target) {
    final absolute = _absolute(target, path);
    return FileSystemEntity.typeSync(absolute, followLinks: false) ==
            FileSystemEntityType.file &&
        _sameBytes(File(absolute).readAsBytesSync(), utf8.encode(text));
  }

  /// Throws [RenderFault] `output_not_writable`, the journal kept, when
  /// anything but this step's own file is at [path].
  @override
  void apply(JournalTarget target) {
    final file = File(_absolute(target, path));
    try {
      if (isDone(target)) return;
      if (FileSystemEntity.typeSync(file.path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        throw RenderFault(
          RenderFaultCode.outputNotWritable,
          'cannot create ${_shown(path)}: a file it did not write is there',
        );
      }
      file.parent.createSync(recursive: true);
      writeFileAtomic(file, utf8.encode(text));
    } on FileSystemException catch (error) {
      throw _notWritable('create', path, error);
    }
  }

  static bool _sameBytes(List<int> a, List<int> b) =>
      a.length == b.length &&
      a.indexed.every((entry) => entry.$2 == b[entry.$1]);
}

/// Commits [paths] with [message], once.
///
/// [base] is the HEAD sha when the journal was written; the step is done when
/// a commit after [base] carries [message] within a line (a hook may prefix
/// the subject), so a replay after any crash point makes the commit exactly
/// once. A step whose [paths] stage nothing is done and commits nothing.
final class CommitStep extends JournalStep {
  const new({
    required this.message,
    required this.paths,
    required this.base,
    this.moves = const [],
  });

  /// The commit message.
  final String message;

  /// The files to stage, relative to the project root and `/`-separated.
  final List<String> paths;

  /// The HEAD sha when the journal was written.
  final String base;

  /// The moves this commit records, each once, by the original and final
  /// path of [paths]; an ignored final path is staged only through its pair.
  final List<({String from, String to})> moves;

  @override
  Map<String, Object> toJson() => {
    'commit': {
      'message': message,
      'paths': paths,
      'base': base,
      if (moves.isNotEmpty)
        'moves': [
          for (final move in moves) {'from': move.from, 'to': move.to},
        ],
    },
  };

  @override
  String describe() => 'commit "$message"';

  @override
  List<String> get _paths => [
    ...paths,
    for (final move in moves) ...[move.from, move.to],
  ];

  @override
  bool isDone(JournalTarget target) {
    final log = target.runGit([
      'log',
      '--format=%B',
      '$base..HEAD',
    ], workingDirectory: target.projectRoot.path);
    return log.exitCode == 0 && carriedBy(log.stdout as String);
  }

  /// Whether a line of [fullMessage], the whole text of one commit or of
  /// several, holds this step's [message].
  ///
  /// A hook may prefix the subject or put its own paragraph first, so the
  /// whole message is searched, not the subject alone.
  bool carriedBy(String fullMessage) => const LineSplitter()
      .convert(fullMessage)
      .any((line) => line.contains(message));

  /// Stages and commits the [paths] git can take, passing them through a
  /// pathspec file so no path reaches the command line.
  ///
  /// A path an ignore rule matches and HEAD lacks is force-staged only as the
  /// `to` of one of [moves] whose `from` HEAD tracks, so a tracked file moved
  /// onto an ignored path stays a rename (INV-6); any other such path stays
  /// on disk out of both commits. A path in neither the work tree nor the
  /// index is skipped, as a moved-away path is once an earlier, refused
  /// attempt already staged its deletion. A path HEAD holds stays committable,
  /// so the commit records its staged deletion. No commit runs when none of
  /// them is staged, as when a hook that rewrote the subject hid an earlier
  /// commit from [isDone]. A [moves] pair that differs only in letter case
  /// stages its old path as an index removal before the add, since `git add`
  /// alone is a no-op on a case-blind index.
  @override
  void apply(JournalTarget target) {
    if (isDone(target)) return;
    final scope = {for (final path in paths) path.split('/').first}.toList();
    final head = _listed(target, [
      'ls-tree',
      '-r',
      '-z',
      '--name-only',
      'HEAD',
      '--',
      ...scope,
    ]);
    // `--cached` keeps a path an interrupted attempt force-staged under the
    // same rule on the replay.
    final matchingIgnore = _listed(target, [
      'ls-files',
      '-z',
      '--others',
      '--cached',
      '--ignored',
      '--exclude-standard',
      '--',
      ...scope,
    ]);
    final ignored = {
      for (final path in paths)
        if (matchingIgnore.contains(path) && !head.contains(path)) path,
    };
    final caseOnlyTo = {
      for (final move in moves)
        if (isCaseOnlyMove(move.from, move.to) && head.contains(move.from))
          move.to,
    };
    // A case-only rename onto an ignored path never shows in git's ignored
    // listing while the old spelling is tracked: with `core.ignorecase` on,
    // git folds the new spelling onto the tracked alias. The ignore rule
    // itself decides, so the new spelling still stages by force.
    ignored.addAll(
      caseOnlyTo.where(
        (path) => !head.contains(path) && _isIgnored(target, path),
      ),
    );
    final forced = {
      for (final move in moves)
        if (ignored.contains(move.to) && head.contains(move.from)) move.to,
    };
    final indexed = _listed(target, ['ls-files', '-z', '--', ...scope]);
    final stageable = {
      for (final path in paths)
        if (!ignored.contains(path) &&
            (_onDisk(target, path) || indexed.contains(path)))
          path,
    };
    final caseOnlyFrom = {
      for (final move in moves)
        if (isCaseOnlyMove(move.from, move.to) &&
            head.contains(move.from) &&
            (stageable.contains(move.to) || forced.contains(move.to)))
          move.from,
    };
    if (caseOnlyFrom.isNotEmpty) {
      _runWrite(target, 'rm', [
        'rm',
        '-q',
        '--cached',
        '--ignore-unmatch',
        ..._pathspecFile(target, caseOnlyFrom),
      ], environment: _literalPathspecs);
    }
    // An empty pathspec file makes `git add` take the whole work tree.
    final added = stageable.difference(caseOnlyFrom);
    if (added.isNotEmpty) {
      _runWrite(target, 'add', [
        'add',
        '-A',
        ..._pathspecFile(target, added),
      ], environment: _literalPathspecs);
    }
    if (forced.isNotEmpty) {
      _runWrite(target, 'add', [
        'add',
        '-f',
        ..._pathspecFile(target, forced),
      ], environment: _literalPathspecs);
    }
    // The old spelling of a case-only move stays out of the commit's
    // pathspec: git would re-add its case-blind work-tree alias, refusing the
    // commit as a duplicate index entry.
    final committable = [
      for (final path in paths)
        if (!caseOnlyFrom.contains(path) &&
            (stageable.contains(path) ||
                forced.contains(path) ||
                head.contains(path)))
          path,
    ];
    final staged = _listed(target, [
      'diff',
      '--cached',
      '--name-only',
      '--no-renames',
      '--relative',
      '-z',
      '--',
      ...scope,
    ]);
    if (!committable.any(staged.contains)) return;
    // A partial commit rebuilds its index from HEAD for its pathspec, where
    // the old spelling of a case-only move still lives, so any pathspec
    // naming the new spelling fails as a duplicate alias. The whole staged
    // index is this step's own staging, so it commits as is.
    _runWrite(
      target,
      'commit',
      caseOnlyFrom.isEmpty
          ? [
              'commit',
              '-q',
              '-m',
              message,
              ..._pathspecFile(target, committable.map(_literalPathspec)),
            ]
          : ['commit', '-q', '-m', message],
    );
  }

  bool _onDisk(JournalTarget target, String path) =>
      FileSystemEntity.typeSync(_absolute(target, path), followLinks: false) !=
      FileSystemEntityType.notFound;

  /// Whether an ignore rule matches [path], by git's own check.
  ///
  /// `check-ignore` reads [path] as a file name, never a glob, and refuses
  /// `GIT_LITERAL_PATHSPECS`, so it runs with the plain environment.
  bool _isIgnored(JournalTarget target, String path) =>
      target.runGit([
        'check-ignore',
        '-q',
        '--',
        path,
      ], workingDirectory: target.projectRoot.path).exitCode ==
      0;

  /// Returns the paths a `-z` git listing prints, or none when git fails.
  Set<String> _listed(JournalTarget target, List<String> arguments) {
    final listed = target.runGit(
      arguments,
      workingDirectory: target.projectRoot.path,
      environment: _literalPathspecs,
    );
    if (listed.exitCode != 0) return const {};
    return {
      for (final path in '${listed.stdout}'.split('\x00'))
        if (path.isNotEmpty) path,
    };
  }

  /// Writes [pathspecs] NUL-separated to the pathspec file in the trash, and
  /// returns the options that make `git add` or `git commit` read it.
  ///
  /// Throws [RenderFault] `output_not_writable` when the file cannot be
  /// written.
  List<String> _pathspecFile(JournalTarget target, Iterable<String> pathspecs) {
    _requireFoldersInside(target, const [_pathspecPath]);
    final file = File(_absolute(target, _pathspecPath));
    try {
      file.parent.createSync(recursive: true);
      writeFileAtomic(file, utf8.encode(pathspecs.join('\x00')));
    } on FileSystemException catch (error) {
      throw _notWritable('write', _pathspecPath, error);
    }
    return ['--pathspec-from-file=${file.path}', '--pathspec-file-nul'];
  }
}

/// The file a [CommitStep] passes its paths to git through, relative to the
/// project root; the trash folder takes it away with the journal.
const _pathspecPath = '${MoveJournal.trashPath}/commit.pathspec';

/// Makes git read every path a [CommitStep] adds or lists as itself, never
/// as a glob, so `app/[slug]/page.ts` stages no other file.
const _literalPathspecs = {'GIT_LITERAL_PATHSPECS': '1'};

/// Returns [path] as a pathspec git reads as itself, so the commit needs no
/// [_literalPathspecs], which its hooks would inherit.
String _literalPathspec(String path) => ':(literal)$path';

/// Runs the `git` write [arguments] for [verb], with [environment] added.
///
/// Throws [GitCommandFailed] when git exits non-zero.
void _runWrite(
  JournalTarget target,
  String verb,
  List<String> arguments, {
  Map<String, String>? environment,
}) {
  final result = target.runGit(
    arguments,
    workingDirectory: target.projectRoot.path,
    environment: environment,
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
/// [run] saves the steps under [journalPath] once, before applying any, and
/// the count of steps finished under [cursorPath] before the first and after
/// each, so [replay]
/// finishes a run a crash stopped on the next command from where it stopped
/// (F6-D35).
final class MoveJournal {
  const new(this.steps);

  /// The journal file, relative to the project root.
  static const journalPath = '.specstone/trash/journal.json';

  /// The file holding the journal's cursor, the count of its steps finished,
  /// as decimal ASCII text, relative to the project root.
  static const cursorPath = '.specstone/trash/journal.cursor';

  /// The folder of the project's own files, relative to the project root.
  static const specstoneFolder = '.specstone';

  /// The folder holding the journal and the deleted files, relative to the
  /// project root.
  static const trashPath = '$specstoneFolder/trash';

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
  /// An unreadable or unparsable journal is not a migrate journal, so
  /// `document_writing`'s replay refuses it as before.
  static bool pendingMigrate(Directory projectRoot) {
    try {
      final steps = _parsedSteps(projectRoot);
      return steps?.any((step) => step is CommitStep) ?? false;
    } on RenderFault {
      return false;
    }
  }

  /// Returns every step of the pending journal of [target], the finished ones
  /// included, or null when there is none, it does not parse, or a replay
  /// would refuse it.
  static List<JournalStep>? read(JournalTarget target) {
    try {
      return _trustedSteps(target)?.steps;
    } on RenderFault {
      return null;
    }
  }

  /// Throws [RenderFault] `output_not_writable`, naming [journalPath], when
  /// the journal under [projectRoot] is not one a run on this machine wrote:
  /// its digest is not recorded under [homeDirectory].
  ///
  /// Does nothing when there is no journal.
  static void requireRecorded(
    Directory projectRoot, {
    required Directory? homeDirectory,
  }) => _recorded(projectRoot, JournalRecords(homeDirectory));

  /// Throws [RenderFault] `output_not_writable`, naming [journalPath], when
  /// [homeDirectory] is null, is not absolute, or lies inside [projectRoot]:
  /// such a run cannot record the journal it would write where a clone cannot
  /// forge the record.
  ///
  /// A command that writes a journal calls it before any prompt or change;
  /// [run] calls it again as the backstop.
  static void requireHomeFolder(
    Directory? homeDirectory,
    Directory projectRoot,
  ) {
    try {
      JournalRecords(homeDirectory).requireHome(projectRoot);
    } on FileSystemException catch (error) {
      throw RenderFault(
        RenderFaultCode.outputNotWritable,
        _notWritable('write', journalPath, error).message,
        file: journalPath,
      );
    }
  }

  /// Saves cursor 0 and then the journal, applies each step and saves the
  /// cursor after it, then removes the journal, the cursor, and the trash
  /// folder.
  ///
  /// Cursor 0 replaces any cursor no journal owns, which would skip this
  /// journal's first steps, and spares [remaining] the no-cursor rule, which
  /// reads an unpark whose slot is still empty as done.
  ///
  /// Throws [IndexFault] `index_not_writable` when `.specstone/.gitignore`
  /// cannot be written, and [RenderFault] `output_not_writable` before any
  /// change when there is no usable home folder to record the journal in, when
  /// `.specstone` or its trash folder leads outside the roots, when a step path
  /// leaves them, when a folder a file moves out of sits on another volume than
  /// the trash (before any file moves), when cursor 0 or the journal cannot be
  /// written, or when a step leaves the roots as the disk stands when it runs
  /// or a step or a later cursor write fails; the journal stays in the last
  /// case.
  void run(JournalTarget target) {
    target.requireTrusted();
    requireHomeFolder(target.homeDirectory, target.projectRoot);
    _requireFoldersInside(target, const ['.specstone/.gitignore', journalPath]);
    _requireInside(target, [
      for (final step in steps) ...step._paths,
    ], agentFiles: target.agentFiles);
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
    final journal = utf8.encode(jsonEncode(toJson()));
    try {
      final trash = Directory(_join(target.projectRoot.path, trashPath))
        ..createSync();
      restrictToOwner(trash);
      _saveCursor(target, 0);
      // Recorded first: a journal never sits on disk without its record.
      target._records.record(
        target.projectRoot,
        journal,
        agentFiles: target.agentFiles,
      );
      writeFileAtomic(
        File(_join(target.projectRoot.path, journalPath)),
        journal,
      );
    } on FileSystemException catch (error) {
      throw _notWritable('write', journalPath, error);
    }
    _finish(target, steps, cursor: 0, agentFiles: target.agentFiles);
  }

  /// Finishes an unfinished journal from the step at its cursor, then removes
  /// the trash folder.
  ///
  /// Every step before the cursor is done; the step at it, which a crash may
  /// have left half done, and each one after it skip themselves when done. A
  /// journal with no cursor file, as an older binary leaves, starts at its
  /// first step. A journal or cursor
  /// that does not parse is refused and left with the trash, since its steps
  /// may be the only record of where the files went. Does nothing when no
  /// trash folder exists.
  ///
  /// Throws [RenderFault] `output_not_writable` when a step fails, the journal
  /// stays, so the next replay resumes, or when the journal or its cursor
  /// cannot be read or parsed.
  static void replay(JournalTarget target) {
    final trusted = _trustedSteps(target);
    if (trusted == null) {
      _removeTrash(target);
      return;
    }
    _finish(
      target,
      trusted.steps,
      cursor: _cursorOf(target.projectRoot, trusted.steps) ?? 0,
      agentFiles: trusted.agentFiles,
    );
  }

  /// Returns the steps of the unfinished journal a replay still runs: the step
  /// at its cursor unless done, then every step after it; empty when no
  /// journal exists.
  ///
  /// A journal with no cursor file lists each of its steps not done.
  ///
  /// Throws [RenderFault] `output_not_writable` when the journal or its cursor
  /// cannot be read or parsed.
  static List<JournalStep> remaining(JournalTarget target) {
    final steps = _trustedSteps(target)?.steps;
    if (steps == null) return const [];
    final cursor = _cursorOf(target.projectRoot, steps);
    if (cursor == null) {
      return [
        for (final step in steps)
          if (!step.isDone(target)) step,
      ];
    }
    return [
      if (cursor < steps.length && !steps[cursor].isDone(target)) steps[cursor],
      ...steps.skip(cursor + 1),
    ];
  }
}

/// Returns the steps of the journal file, or null when there is none.
///
/// Reads the structure only: whether the journal is trusted is
/// [_trustedSteps]'s question.
List<JournalStep>? _parsedSteps(Directory projectRoot) {
  final journal = File(_join(projectRoot.path, MoveJournal.journalPath));
  if (!journal.existsSync()) return null;
  try {
    return _stepsIn(readPlanInput(journal));
  } on FileSystemException catch (error) {
    throw _notWritable('read', MoveJournal.journalPath, error);
  }
}

/// Returns the steps of the journal of [target] a replay may run and the agent
/// files recorded with it, or null when there is no journal.
///
/// A journal clones and other tools can carry is untrusted input: it runs
/// only when its digest is recorded under the home folder and every path of
/// every step lands inside the project, docs, or code root, or on one of the
/// agent files recorded with it, on no `.git` entry and through no link out
/// of them.
///
/// Throws [RenderFault] `output_not_writable` when the journal is unrecorded,
/// a path leaves those roots, or the journal cannot be read or parsed.
({List<JournalStep> steps, Set<String> agentFiles})? _trustedSteps(
  JournalTarget target,
) {
  final recorded = _recorded(target.projectRoot, target._records);
  if (recorded == null) return null;
  final steps = _stepsIn(recorded.bytes);
  _requireInside(target, [
    for (final step in steps) ...step._paths,
  ], agentFiles: recorded.agentFiles);
  return (steps: steps, agentFiles: recorded.agentFiles);
}

/// Throws [RenderFault] `output_not_writable` unless each of [paths], the step
/// paths of a journal, lands inside the project or docs root, as the disk
/// stands now, below no `.git` entry and through no link out of them.
///
/// A path in [agentFiles] that lies inside the project root also passes.
/// Judged afresh at every use: a step that ran earlier may have put a link in
/// place that the up-front check could not see.
void _requireInside(
  JournalTarget target,
  Iterable<String> paths, {
  Set<String> agentFiles = const {},
}) {
  final bad = _firstOutside(target, paths, agentFiles: agentFiles);
  if (bad == null) return;
  throw _untrusted('its step path $bad leaves the project and docs roots');
}

/// Throws [RenderFault] `output_not_writable` unless each of [paths], a file
/// or folder the journal machinery itself writes, lands inside the project or
/// docs root as the disk stands now.
///
/// The refusal names the path, not a step: a link in `.specstone` leads the
/// machinery out, and no journal need exist.
void _requireFoldersInside(JournalTarget target, Iterable<String> paths) {
  final bad = _firstOutside(target, paths);
  if (bad == null) return;
  throw RenderFault(
    RenderFaultCode.outputNotWritable,
    '$bad leads outside the project and docs roots; remove the link on its '
    'way in ${MoveJournal.specstoneFolder}/ to go on',
    file: MoveJournal.journalPath,
  );
}

/// Returns the first of [paths] outside the bounds, or null when all are in.
///
/// Throws [RenderFault] `output_not_writable` when the Owner does not trust
/// the roots: the bounds are then empty, and no path is outside for its own
/// fault.
String? _firstOutside(
  JournalTarget target,
  Iterable<String> paths, {
  Set<String> agentFiles = const {},
}) {
  target.requireTrusted();
  final project = target.projectRoot.resolveSymbolicLinksSync();
  final bounds = JournalBounds(
    target.projectRoot,
    target._bounds,
    agentFiles: {
      for (final file in agentFiles)
        if (_isInside(project, file)) file,
    },
  );
  for (final path in paths) {
    if (!bounds.holds(path)) return path;
  }
  return null;
}

/// Returns the bytes of the journal under [projectRoot] and the agent files
/// recorded with it, or null when there is no journal.
///
/// Throws [RenderFault] `output_not_writable` when [records] holds no digest
/// of them, or the file cannot be read.
({List<int> bytes, Set<String> agentFiles})? _recorded(
  Directory projectRoot,
  JournalRecords records,
) {
  final journal = File(_join(projectRoot.path, MoveJournal.journalPath));
  if (!journal.existsSync()) return null;
  final List<int> bytes;
  try {
    bytes = readPlanInput(journal);
  } on FileSystemException catch (error) {
    throw _notWritable('read', MoveJournal.journalPath, error);
  }
  final agentFiles = records.agentFilesOf(projectRoot, bytes);
  if (agentFiles == null) {
    throw _untrusted('no Specstone run on this machine wrote it');
  }
  return (bytes: bytes, agentFiles: agentFiles);
}

/// Returns the steps of the journal [bytes].
///
/// Throws [RenderFault] `output_not_writable` when they do not parse.
List<JournalStep> _stepsIn(List<int> bytes) {
  try {
    return _stepsOf(jsonDecode(utf8.decode(bytes)));
  } on FormatException catch (error) {
    throw RenderFault(
      RenderFaultCode.outputNotWritable,
      'cannot replay ${MoveJournal.journalPath}: ${error.message}; '
      'fix or remove it',
    );
  }
}

/// Returns the refusal of an untrusted journal for [reason].
RenderFault _untrusted(String reason) => RenderFault(
  RenderFaultCode.outputNotWritable,
  '$reason; check ${MoveJournal.trashPath}/ and delete it to go on',
  file: MoveJournal.journalPath,
);

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
    landed = renameSyncRetrying(probe, _join(trash.path, name));
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

/// Decimal ASCII digits and nothing else, so no sign, space, or point.
final _count = RegExp(r'^[0-9]+$');

/// Returns the count of [steps] done that the cursor file holds, or null when
/// there is no cursor file.
///
/// Throws [RenderFault] `output_not_writable` when the file cannot be read, or
/// holds anything but a count from 0 to the number of [steps].
int? _cursorOf(Directory projectRoot, List<JournalStep> steps) {
  final file = File(_join(projectRoot.path, MoveJournal.cursorPath));
  if (!file.existsSync()) return null;
  final String text;
  try {
    text = String.fromCharCodes(readPlanInput(file));
  } on FileSystemException catch (error) {
    throw _notWritable('read', MoveJournal.cursorPath, error);
  }
  final cursor = _count.hasMatch(text) ? int.tryParse(text) : null;
  if (cursor != null && cursor <= steps.length) return cursor;
  throw RenderFault(
    RenderFaultCode.outputNotWritable,
    'cannot replay ${MoveJournal.journalPath}: ${MoveJournal.cursorPath} '
    'holds ${jsonEncode(text)}, not a count of its ${steps.length} steps; '
    'fix or remove it',
  );
}

/// Writes [cursor] to the cursor file, atomically.
///
/// Throws [RenderFault] `output_not_writable` when the disk refuses.
void _saveCursor(JournalTarget target, int cursor) {
  _requireFoldersInside(target, const [MoveJournal.cursorPath]);
  try {
    writeFileAtomic(
      File(_join(target.projectRoot.path, MoveJournal.cursorPath)),
      ascii.encode('$cursor'),
    );
  } on FileSystemException catch (error) {
    throw _notWritable('write', MoveJournal.cursorPath, error);
  }
}

/// Applies [steps] from the one at [cursor] on, saving the cursor after each,
/// then deletes the journal, the cursor, and the trash folder.
///
/// A crash between a step and its save leaves the cursor on that step, which
/// skips itself when the replay finds it done.
void _finish(
  JournalTarget target,
  List<JournalStep> steps, {
  required int cursor,
  required Set<String> agentFiles,
}) {
  for (var index = cursor; index < steps.length; index++) {
    _requireInside(target, steps[index]._paths, agentFiles: agentFiles);
    steps[index].apply(target);
    _saveCursor(target, index + 1);
  }
  // The journal goes first: a cursor left alone is ignored, while a journal
  // left without its cursor would replay every step.
  _requireFoldersInside(target, const [MoveJournal.journalPath]);
  for (final path in [MoveJournal.journalPath, MoveJournal.cursorPath]) {
    try {
      _deleteIfPresent(File(_join(target.projectRoot.path, path)));
    } on FileSystemException catch (error) {
      throw _notWritable('remove', path, error);
    }
  }
  _removeTrash(target);
}

void _deleteIfPresent(File file) {
  if (file.existsSync()) file.deleteSync();
}

/// Removes the trash folder, then the journal's record.
void _removeTrash(JournalTarget target) {
  _requireFoldersInside(target, const [MoveJournal.journalPath]);
  final trash = Directory(
    _join(target.projectRoot.path, MoveJournal.trashPath),
  );
  try {
    if (trash.existsSync()) trash.deleteSync(recursive: true);
  } on FileSystemException catch (error) {
    throw _notWritable('remove', MoveJournal.trashPath, error);
  }
  target._records.clear(target.projectRoot);
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
  return RenderFault(
    RenderFaultCode.outputNotWritable,
    'cannot $verb ${_shown(path)}: $reason',
  );
}

/// Returns the step [path] as a fault names it: relative to the docs root
/// when it lies under it.
String _shown(String path) =>
    path.startsWith('docs/') ? path.substring(5) : path;
