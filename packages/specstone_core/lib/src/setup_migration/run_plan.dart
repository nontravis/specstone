import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:specstone_core/src/document_writing/rewrite_refs.dart'
    show PathMove;

const _docsPrefix = 'docs/';

/// The ProjectPath of the index's ignore file; `MoveJournal.run` creates it
/// before any step.
const specstoneGitignorePath = '.specstone/.gitignore';

/// A doc commit 2 rewrites in place.
final class PlannedRewrite {
  const new({
    required this.path,
    required this.text,
    required this.changes,
    this.note = '',
  });

  /// The ProjectPath of the doc, after the moves.
  final String path;

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

  /// Returns the plan as the lines `migrate --dry-run` prints.
  String toText() {
    final rewriteBlock = rewriteLines ?? _rewriteLines();
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
  List<JournalStep> journalSteps({required String base}) {
    final movedPaths = [
      for (final move in moves) ...[
        '$_docsPrefix${move.from}',
        '$_docsPrefix${move.to}',
      ],
    ];
    final commit2Paths = {
      for (final rewrite in rewrites) rewrite.path,
      for (final create in creates) create.path,
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
      for (final rewrite in rewrites) WriteStep(rewrite.path, rewrite.text),
      for (final create in creates) CreateStep(create.path, create.text),
      CommitStep(
        message: commit2Message,
        paths: commit2Paths.toList(),
        base: base,
      ),
    ];
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
