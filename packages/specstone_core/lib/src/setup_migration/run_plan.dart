import 'dart:io';

import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:specstone_core/src/document_writing/rewrite_refs.dart'
    show PathMove;
import 'package:specstone_core/src/document_writing/stale_mentions.dart'
    show StaleMention;
import 'package:specstone_core/src/plan_hash.dart';
import 'package:specstone_core/src/setup_migration/agent_targets.dart';
import 'package:specstone_core/src/setup_migration/migrate_fault.dart';

const _docsPrefix = 'docs/';

/// Returns whether a ProjectPath under [root] holds an entry once [moves], as
/// DocPaths, ran: a move lands on it, or a file, folder, or link is there and
/// no move takes it away.
///
/// The file system matches the name, so where the volume ignores case a name
/// that differs only in case is taken too.
bool Function(String projectPath) takenAfterMoves(
  Directory root,
  List<PathMove> moves,
) {
  final landed = {for (final move in moves) '$_docsPrefix${move.to}'};
  final vacated = {for (final move in moves) '$_docsPrefix${move.from}'};
  final base = '${root.path}${Platform.pathSeparator}';
  bool holdsEntry(String projectPath) =>
      FileSystemEntity.typeSync(
        '$base${projectPath.split('/').join(Platform.pathSeparator)}',
        followLinks: false,
      ) !=
      FileSystemEntityType.notFound;
  return (projectPath) =>
      landed.contains(projectPath) ||
      !vacated.contains(projectPath) && holdsEntry(projectPath);
}

/// The ProjectPath of the index's ignore file; `MoveJournal.run` creates it
/// before any step.
const specstoneGitignorePath = '.specstone/.gitignore';

/// Returns the plan line counting the docs the layout pass rewrites, or null
/// when [docPaths] is empty.
///
/// [docPaths] are DocPaths.
String? formatLayoutLine(Iterable<String> docPaths) {
  final count = docPaths.length;
  return count == 0 ? null : 'format layout: $count docs';
}

/// Returns the plan line counting the mentions in code and agent files that
/// the run's moves stop resolving, or null when [mentions] is empty.
String? mentionsLine(List<StaleMention> mentions) =>
    mentions.isEmpty ? null : 'mentions: ${mentions.length}';

/// One step line of a pack upgrade, `from <version>: <step>: <n> docs`, and
/// the files it rewrites.
final class UpgradeStepLine {
  const new({required this.from, required this.step, required this.paths});

  /// The `from:` version of the migration entry holding the step.
  final String from;

  /// The step as the line words it, between the version and the count.
  final String step;

  /// The ProjectPath or DocPath of each file the step rewrites, docs first and
  /// each project-layer override after them, each group in code point order.
  final List<String> paths;

  /// The plan line.
  String get text => 'from $from: $step: ${paths.length} docs';
}

/// The path lists the plan's count lines print as numbers, each kept whole
/// for the JSON plan.
final class PlanLists {
  const new({
    this.formatLayout = const [],
    this.numberLabelsRewritten = const [],
    this.numberLabelsLeft = const [],
    this.renumberIds = const [],
    this.agentFiles = const [],
    this.stampsSkipped = const [],
    this.steps = const [],
    this.mentions = const [],
  });

  /// The DocPath of each doc the layout pass rewrites, in code point order.
  final List<String> formatLayout;

  /// Each doc the label pass rewrites, and each operation heading it cuts as
  /// `<DocPath>:<line> <operation>`.
  final List<String> numberLabelsRewritten;

  /// Each label the label pass keeps, `<DocPath>:<line> <label>`.
  final List<String> numberLabelsLeft;

  /// Each renumbering as `<DocPath> <old> -> <new>`, then each doc the pass
  /// rewrites or cannot fully rewrite.
  final List<String> renumberIds;

  /// The path from the project root of each agent file the run writes.
  final List<String> agentFiles;

  /// The DocPath of each doc the stamp pass leaves for its frontmatter.
  final List<String> stampsSkipped;

  /// One entry per step line.
  final List<UpgradeStepLine> steps;

  /// Each mention in a code or agent file the run's moves stop resolving.
  final List<StaleMention> mentions;
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

/// The `note` of a created draft.
const draftNote = ' (draft)';

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
  new({
    required this.header,
    required this.moves,
    required this.prunes,
    required this.rewrites,
    required this.creates,
    required this.left,
    required this.commit1Message,
    required this.commit2Message,
    required this.inputs,
    this.rewriteLines,
    this.closingLine,
    this.agentFiles,
    this.lists = const PlanLists(),
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

  /// The files the planner read, each with the hash of its bytes.
  final PlanInputs inputs;

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

  /// The path lists the count lines of [rewriteLines] print as numbers.
  final PlanLists lists;

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

  /// Throws [MigrateFault] `value_unplaced` for each create whose path under
  /// [root] is [takenAfterMoves], the first as the fault and the rest in
  /// `more`, so the plan refuses before it prints and nothing is written.
  ///
  /// Its create step would find that entry and stop the run after commit 1.
  void refuseTakenCreates(Directory root) {
    final isTaken = takenAfterMoves(root, moves);
    final faults = [
      for (final create in creates)
        if (isTaken(create.path))
          MigrateFault(
            MigrateFaultCode.valueUnplaced,
            'the run creates ${_shown(create.path)}, but a file or folder '
            'already holds that path, or a name the volume reads as the same; '
            'move or rename it, then run specstone migrate again',
            file: create.path,
          ),
    ];
    if (faults.isEmpty) return;
    final first = faults.first;
    throw MigrateFault(
      first.code,
      first.message,
      file: first.file,
      more: faults.sublist(1),
    );
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
  /// stays a link. The plan lists no agent file whose real path lies outside
  /// the project (R99), so each step lands inside the project root.
  ///
  /// Throws [StateError] when two text steps land on one path: both would
  /// carry one `before` text, so the first would make the second skip.
  List<JournalStep> journalSteps({
    required String base,
    required Directory projectRoot,
  }) {
    final steps = _journalSteps(base: base, projectRoot: projectRoot);
    final written = <String>{};
    for (final step in steps) {
      final path = switch (step) {
        WriteStep(:final path) || CreateStep(:final path) => path,
        _ => null,
      };
      if (path != null && !written.add(path)) {
        throw StateError('two steps of the run write $path');
      }
    }
    return steps;
  }

  List<JournalStep> _journalSteps({
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
        if (!write.isAtTop) path,
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
