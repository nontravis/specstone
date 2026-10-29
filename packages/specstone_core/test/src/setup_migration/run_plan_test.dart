import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:specstone_core/src/document_writing/rewrite_refs.dart'
    show PathMove;
import 'package:specstone_core/src/setup_migration/run_plan.dart';
import 'package:test/test.dart';

const _runbook = 'prds/runbooks/deploy/RUNBOOK.md';
const _notes = 'prds/runbooks/deploy/NOTES.md';

/// Two docs trading places: each target is the other's source.
const _cycle = <PathMove>[
  (from: _runbook, to: _notes),
  (from: _notes, to: _runbook),
];

RunPlan _planOf(List<PathMove> moves) => RunPlan(
  header: 'pack upgrade: acme 1.0.0 -> 1.2.0',
  moves: moves,
  prunes: const [],
  rewrites: const [],
  creates: const [],
  left: const [],
  commit1Message: 'move',
  commit2Message: 'pin',
);

List<String> _moveLines(RunPlan plan) => [
  for (final step in plan.journalSteps(base: 'abc'))
    if (step is MoveStep) step.describe(),
];

void main() {
  test('f06/us02/fr02/e08, F6-D34: a move onto the source of a move not yet '
      'run parks in the stage until every move has run', () {
    expect(_moveLines(_planOf(_cycle)), [
      'move docs/$_runbook -> ${MoveJournal.stagePath}/0',
      'move docs/$_notes -> docs/$_runbook',
      'move ${MoveJournal.stagePath}/0 -> docs/$_notes',
    ]);
  });

  test('f06/us02/fr02/e08, F6-D34: a three-doc cycle parks one doc', () {
    final plan = _planOf(const [
      (from: 'c.md', to: 'a.md'),
      (from: 'b.md', to: 'c.md'),
      (from: 'a.md', to: 'b.md'),
    ]);

    expect(_moveLines(plan), [
      'move docs/c.md -> ${MoveJournal.stagePath}/0',
      'move docs/b.md -> docs/c.md',
      'move docs/a.md -> docs/b.md',
      'move ${MoveJournal.stagePath}/0 -> docs/a.md',
    ]);
  });

  test('f06/us02/fr02/e08: moves ordered so each target is free run straight, '
      'with no stage', () {
    final plan = _planOf(const [
      (from: 'b.md', to: 'c.md'),
      (from: 'a.md', to: 'b.md'),
    ]);

    expect(_moveLines(plan), [
      'move docs/b.md -> docs/c.md',
      'move docs/a.md -> docs/b.md',
    ]);
  });

  test('f06/us02/fr02/e08: a staged cycle prints and commits its final paths '
      'only', () {
    final plan = _planOf(_cycle);

    final commit1 = plan
        .journalSteps(base: 'abc')
        .whereType<CommitStep>()
        .first;

    expect(commit1.paths, [
      'docs/$_runbook',
      'docs/$_notes',
      'docs/$_notes',
      'docs/$_runbook',
    ]);
    expect(
      plan.toText(),
      'pack upgrade: acme 1.0.0 -> 1.2.0\n'
      'commit 1, moves:\n'
      '  $_runbook -> $_notes\n'
      '  $_notes -> $_runbook\n',
    );
  });
}
