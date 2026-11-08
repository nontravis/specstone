import 'dart:io';

import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:specstone_core/src/document_writing/rewrite_refs.dart'
    show PathMove;
import 'package:specstone_core/src/setup_migration/agent_targets.dart';
import 'package:specstone_core/src/templates/code_point_order.dart';

const _docsPrefix = 'docs/';

/// The ProjectPath of the index's ignore file; `MoveJournal.run` creates it
/// before any step.
const specstoneGitignorePath = '.specstone/.gitignore';

/// Returns the plan line naming the docs the layout pass rewrites, or null
/// when [docPaths] is empty.
///
/// [docPaths] are DocPaths, shown in code point order.
String? formatLayoutLine(Iterable<String> docPaths) {
  final sorted = docPaths.toList()..sort(compareCodePoints);
  return sorted.isEmpty ? null : 'format layout: ${sorted.join(', ')}';
}

/// A doc commit 2 rewrites in place.
final class PlannedRewrite {
  const new({
    required this.path,
    required this.text,
    required this.before,
    required this.changes,
    this.note = '',
  });

  /// The ProjectPath of the doc, after the moves.
  final String path;

  /// The [textHashOf] of the file's text when the plan was made.
  final String before;

  /// The text as written to disk.
  final String text;

  /// The labels of the changes made, in the order they apply.
  final List<String> changes;

  /// The text the plan prints after the changes, such as `; project-layer
  /// section Data integrity`.
  final String note;
}

/// A file commit 2 creates.
final class PlannedCreate {
  const new({required this.path, required this.text, this.note = ''});

  /// The ProjectPath of the file.
  final String path;

  /// The text as written to disk.
  final String text;

  /// The text the plan prints after the path, such as ` (draft)`.
  final String note;
}

/// What a `specstone migrate` run moves, rewrites, and creates.
final class RunPlan {
  const new({
    required this.header,
    required this.moves,
    required this.prunes,
    required this.rewrites,
    required this.creates,
    required this.left,
    required this.commit1Message,
    required this.commit2Message,
    this.rewriteLines,
    this.closingLine,
    this.agentFiles,
  });

  /// The first line the plan prints.
  final String header;

  /// The renames of commit 1, as DocPaths, in the order they run.
  ///
  /// Each is a doc's original and final path; a cycle's stage slot shows up
  /// only in [journalSteps].
  final List<PathMove> moves;

  /// The ProjectPath folders the moves empty, the deepest first.
  final List<String> prunes;

  /// The docs commit 2 rewrites, in print order.
  final List<PlannedRewrite> rewrites;

  /// The files commit 2 creates, in print order.
  final List<PlannedCreate> creates;

  /// The DocPaths no rule places.
  final List<String> left;

  /// The message of commit 1.
  final String commit1Message;

  /// The message of commit 2.
  final String commit2Message;

  /// The lines printed under `commit 2, rewrites:` in place of [rewrites].
  final List<String>? rewriteLines;

  /// What an applied run prints after its commit lines.
  final String? closingLine;

  /// The agent file writes the run adds after every other write, or null.
  ///
  /// Root files join commit 2; top files lie outside both commits. Its plan
  /// line prints once: where [rewriteLines] holds it, else last under
  /// `commit 2, creates:`.
  final AgentWritePlan? agentFiles;

  /// Returns the plan as the lines `migrate --dry-run` prints.
  String toText() {
    final rewriteBlock = rewriteLines ?? _rewriteLines();
    final agentLine = agentFiles?.line ?? '';
    final buffer = StringBuffer('$header\n');
    void block(String title, Iterable<String> lines) {
      if (lines.isEmpty) return;
      buffer.write('$title\n');
      for (final line in lines) {
        buffer.write('  $line\n');
      }
    }

    block('commit 1, moves:', [
      for (final move in moves) '${move.from} -> ${move.to}',
    ]);
    block('commit 2, rewrites:', rewriteBlock);
    block('commit 2, creates:', [
      for (final create in creates) '${_shown(create.path)}${create.note}',
      if (agentLine.isNotEmpty && !rewriteBlock.contains(agentLine)) agentLine,
    ]);
    block('left in place for specstone check:', left);
    return buffer.toString();
  }

  /// Returns the journal steps that apply the plan on top of HEAD [base].
  ///
  /// Moves and prunes, commit 1 when any file moves, the writes and creates,
  /// then commit 2. No step deletes a file (INV-6). Commit 1 carries each move
  /// once as a ProjectPath pair, its stage hops left out, so a tracked file
  /// moved onto an ignored path still commits as a rename.
  ///
  /// An agent file reached through a symbolic link, of the file or of a folder
  /// above it, gets its step on the real path from [projectRoot], so the link
  /// stays a link. A real path outside the project joins no commit (R49).
  List<JournalStep> journalSteps({
    required String base,
    required Directory projectRoot,
  }) {
    final agentWrites = [
      for (final write in agentFiles?.rootWrites ?? const <AgentWrite>[])
        (write: write, path: _realPath(write.path, projectRoot)),
      for (final write in agentFiles?.topWrites ?? const <AgentWrite>[])
        (write: write, path: _realPath(write.path, projectRoot)),
    ];
    final movedPaths = [
      for (final move in moves) ...[
        '$_docsPrefix${move.from}',
        '$_docsPrefix${move.to}',
      ],
    ];
    final commit2Paths = {
      for (final rewrite in rewrites) rewrite.path,
      for (final create in creates) create.path,
      for (final (:write, :path) in agentWrites)
        if (!write.isAtTop && !path.startsWith('../')) path,
      specstoneGitignorePath,
    };
    return [
      ..._moveSteps(),
      for (final folder in prunes) PruneStep(folder),
      if (moves.isNotEmpty)
        CommitStep(
          message: commit1Message,
          paths: movedPaths,
          base: base,
          moves: [
            for (final move in moves)
              (from: '$_docsPrefix${move.from}', to: '$_docsPrefix${move.to}'),
          ],
        ),
      for (final rewrite in rewrites)
        WriteStep(rewrite.path, rewrite.text, before: rewrite.before),
      for (final create in creates) CreateStep(create.path, create.text),
      for (final (:write, :path) in agentWrites)
        if (write.before case final before?)
          WriteStep(path, write.text, before: before)
        else
          CreateStep(path, write.text),
      CommitStep(
        message: commit2Message,
        paths: commit2Paths.toList(),
        base: base,
      ),
    ];
  }

  /// Returns [path] with every symbolic link on it resolved, as a
  /// `/`-separated path from [projectRoot].
  ///
  /// The part of [path] that does not exist yet stays as written, and a path
  /// that cannot be resolved stays whole.
  static String _realPath(String path, Directory projectRoot) {
    final sep = Platform.pathSeparator;
    final segments = path.split('/');
    var existing = segments.length;
    while (existing > 0 &&
        FileSystemEntity.typeSync(
              '${projectRoot.path}$sep${segments.take(existing).join(sep)}',
            ) ==
            FileSystemEntityType.notFound) {
      existing--;
    }
    try {
      final root = projectRoot.resolveSymbolicLinksSync().split(sep);
      final real = Directory(
        '${projectRoot.path}$sep${segments.take(existing).join(sep)}',
      ).resolveSymbolicLinksSync().split(sep);
      var shared = 0;
      while (shared < root.length &&
          shared < real.length &&
          root[shared] == real[shared]) {
        shared++;
      }
      return [
        for (var i = shared; i < root.length; i++) '..',
        ...real.skip(shared),
        ...segments.skip(existing),
      ].join('/');
    } on FileSystemException {
      return path;
    }
  }

  /// Returns one [MoveStep] per move, in order, except that a move onto the
  /// source of a move not yet run parks in a stage slot first and takes its
  /// target once every move has run.
  ///
  /// A cycle, such as two docs trading places, has no order in which each
  /// target is free; parking one of its moves breaks it (F6-D34).
  List<MoveStep> _moveSteps() {
    final unmoved = {for (final move in moves) move.from};
    final steps = <MoveStep>[];
    final unparks = <MoveStep>[];
    for (final (index, move) in moves.indexed) {
      unmoved.remove(move.from);
      final from = '$_docsPrefix${move.from}';
      final to = '$_docsPrefix${move.to}';
      if (unmoved.contains(move.to)) {
        final slot = '${MoveJournal.stagePath}/$index';
        steps.add(MoveStep(from, slot));
        unparks.add(MoveStep(slot, to));
      } else {
        steps.add(MoveStep(from, to));
      }
    }
    return [...steps, ...unparks];
  }

  List<String> _rewriteLines() => [
    for (final rewrite in rewrites)
      '${_shown(rewrite.path)}: ${rewrite.changes.join(', ')}${rewrite.note}',
  ];

  static String _shown(String projectPath) =>
      projectPath.startsWith(_docsPrefix)
      ? projectPath.substring(_docsPrefix.length)
      : projectPath;
}
