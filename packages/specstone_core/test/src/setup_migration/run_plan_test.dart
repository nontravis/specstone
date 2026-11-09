import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:specstone_core/src/document_writing/rewrite_refs.dart'
    show PathMove;
import 'package:specstone_core/src/setup_migration/agent_targets.dart';
import 'package:specstone_core/src/setup_migration/run_plan.dart';
import 'package:test/test.dart';

import '../../helpers/write_fixture.dart' show testHome;

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

AgentWrite _agentWrite(
  String path, {
  required bool isNew,
  bool isAtTop = false,
  String was = 'old\n',
}) => AgentWrite(
  path: path,
  text: 'text of $path\n',
  isNew: isNew,
  before: isNew ? null : textHashOf(was),
  isAtTop: isAtTop,
);

AgentWritePlan _agentPlan() => AgentWritePlan(
  rootWrites: [
    _agentWrite('.specstone/AGENT.md', isNew: true),
    _agentWrite('CLAUDE.md', isNew: false),
  ],
  topWrites: [
    _agentWrite('../code/CLAUDE.md', isNew: false, isAtTop: true),
    _agentWrite('../code/AGENTS.md', isNew: true, isAtTop: true),
  ],
  agentFileRoots: const ['../code'],
  addedRoots: const ['../code'],
  writeSet: const {},
);

RunPlan _planWithAgents({List<String>? rewriteLines}) => RunPlan(
  header: 'migrate',
  moves: const [],
  prunes: const [],
  rewrites: const [
    PlannedRewrite(path: 'docs/a.md', text: 'a', before: 'b', changes: ['x']),
  ],
  creates: const [PlannedCreate(path: 'docs/b.md', text: 'b')],
  left: const [],
  commit1Message: 'move',
  commit2Message: 'pin',
  rewriteLines: rewriteLines,
  agentFiles: _agentPlan(),
);

/// The project folder of the running test, empty and deleted afterwards.
late Directory _root;

List<String> _moveLines(RunPlan plan) => [
  for (final step in plan.journalSteps(base: 'abc', projectRoot: _root))
    if (step is MoveStep) step.describe(),
];

void main() {
  test(
    'setup_migration/upgrade_pack_pins/apply_steps_and_pins: two writes '
    'of one path are refused, since the first would make the second skip',
    () {
      const plan = RunPlan(
        header: 'migrate',
        moves: [],
        prunes: [],
        rewrites: [
          PlannedRewrite(
            path: 'AGENTS.md',
            text: 'a',
            before: 'b',
            changes: [],
          ),
          PlannedRewrite(
            path: 'AGENTS.md',
            text: 'c',
            before: 'b',
            changes: [],
          ),
        ],
        creates: [],
        left: [],
        commit1Message: 'move',
        commit2Message: 'pin',
      );

      expect(
        () =>
            plan.journalSteps(base: 'HEAD', projectRoot: Directory.systemTemp),
        throwsStateError,
      );
    },
  );

  setUp(() {
    _root = Directory.systemTemp.createTempSync('run_plan_root');
    addTearDown(() => _root.deleteSync(recursive: true));
  });

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
        .journalSteps(base: 'abc', projectRoot: _root)
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

  test('f06/us01/fr07, dw-s03/inv6: commit 1 carries each move once as a '
      'ProjectPath pair, the stage hops left out; commit 2 carries none', () {
    final commits = _planOf(_cycle)
        .journalSteps(base: 'abc', projectRoot: _root)
        .whereType<CommitStep>()
        .toList();

    expect(commits.first.moves, [
      (from: 'docs/$_runbook', to: 'docs/$_notes'),
      (from: 'docs/$_notes', to: 'docs/$_runbook'),
    ]);
    expect(commits.last.moves, isEmpty);
  });

  group(
    'setup_migration/migrate_legacy_docs/commit_and_resume, '
    'setup_migration/upgrade_pack_pins/apply_steps_and_pins: agent files',
    () {
      test('E02: one step per agent file follows every other write and create, '
          'a new file created and an existing file written', () {
        final steps = _planWithAgents().journalSteps(
          base: 'abc',
          projectRoot: _root,
        );

        expect(
          [for (final step in steps) step.describe()],
          [
            'write docs/a.md',
            'create docs/b.md',
            'create .specstone/AGENT.md',
            'write CLAUDE.md',
            'write ../code/CLAUDE.md',
            'create ../code/AGENTS.md',
            steps.last.describe(),
          ],
        );
        expect(steps.last, isA<CommitStep>());
      });

      test('E02: commit 2 carries the root agent files and no top file', () {
        final commit = _planWithAgents()
            .journalSteps(base: 'abc', projectRoot: _root)
            .whereType<CommitStep>()
            .single;

        expect(
          commit.paths,
          containsAll([
            'docs/a.md',
            'docs/b.md',
            '.specstone/AGENT.md',
            'CLAUDE.md',
          ]),
        );
        expect(commit.paths.where((path) => path.startsWith('..')), isEmpty);
      });

      test('INV-6: a journal written and read back replays the same steps', () {
        final steps = _planWithAgents().journalSteps(
          base: 'abc',
          projectRoot: _root,
        );

        final replayed = [
          for (final step in steps)
            JournalStep.fromJson(jsonDecode(jsonEncode(step.toJson()))),
        ];

        expect(replayed.map((step) => step.toJson()), [
          for (final step in steps) step.toJson(),
        ]);
      });

      test('E20: a top path applies through the target and a write skips a '
          'file that is missing', () {
        final temp = Directory.systemTemp.createTempSync('run_plan_test');
        addTearDown(() => temp.deleteSync(recursive: true));
        final project = Directory('${temp.path}/project')..createSync();
        final code = Directory('${temp.path}/code')..createSync();
        File('${code.path}/CLAUDE.md').writeAsStringSync('old\n');
        final target = JournalTarget(
          projectRoot: project,
          docsRoot: project,
          homeDirectory: testHome(),
        );

        final steps = _planWithAgents().journalSteps(
          base: 'abc',
          projectRoot: _root,
        );
        for (final step in steps) {
          if (step is WriteStep && step.path == 'CLAUDE.md') {
            step.apply(target);
          }
          if (step is WriteStep && step.path == '../code/CLAUDE.md') {
            step.apply(target);
          }
          if (step is CreateStep && step.path == '../code/AGENTS.md') {
            step.apply(target);
          }
        }

        expect(
          File('${code.path}/CLAUDE.md').readAsStringSync(),
          'text of ../code/CLAUDE.md\n',
        );
        expect(
          File('${code.path}/AGENTS.md').readAsStringSync(),
          'text of ../code/AGENTS.md\n',
        );
        expect(File('${project.path}/CLAUDE.md').existsSync(), isFalse);
      });

      test('E08: the agent files line prints last under commit 2, creates when '
          'the plan has no rewrite lines', () {
        expect(
          _planWithAgents().toText(),
          'migrate\n'
          'commit 2, rewrites:\n'
          '  a.md: x\n'
          'commit 2, creates:\n'
          '  b.md\n'
          '  ${_agentPlan().line}\n',
        );
      });

      test('E08: a planner that sets rewrite lines places the line itself', () {
        expect(
          _planWithAgents(rewriteLines: ['own', _agentPlan().line]).toText(),
          'migrate\n'
          'commit 2, rewrites:\n'
          '  own\n'
          '  ${_agentPlan().line}\n'
          'commit 2, creates:\n'
          '  b.md\n',
        );
      });

      test('E08: rewrite lines that leave out the agent files line keep it '
          'last under commit 2, creates', () {
        expect(
          _planWithAgents(rewriteLines: const ['own']).toText(),
          'migrate\n'
          'commit 2, rewrites:\n'
          '  own\n'
          'commit 2, creates:\n'
          '  b.md\n'
          '  ${_agentPlan().line}\n',
        );
      });

      test('write_agent_files E22: a symbolic-link CLAUDE.md stays a link and '
          'its real file takes the write', () {
        final temp = Directory.systemTemp.createTempSync('run_plan_link');
        addTearDown(() => temp.deleteSync(recursive: true));
        File('${temp.path}/AGENTS.md').writeAsStringSync('Owner\n');
        Link('${temp.path}/CLAUDE.md').createSync('AGENTS.md');
        final target = JournalTarget(
          projectRoot: temp,
          docsRoot: temp,
          homeDirectory: testHome(),
        );
        final plan = RunPlan(
          header: 'migrate',
          moves: const [],
          prunes: const [],
          rewrites: const [],
          creates: const [],
          left: const [],
          commit1Message: 'move',
          commit2Message: 'pin',
          agentFiles: AgentWritePlan(
            rootWrites: [
              _agentWrite('CLAUDE.md', isNew: false, was: 'Owner\n'),
            ],
            topWrites: const [],
            agentFileRoots: const [],
            addedRoots: const [],
            writeSet: const {},
          ),
        );

        final steps = plan.journalSteps(base: 'abc', projectRoot: temp);
        for (final step in steps.whereType<WriteStep>()) {
          step.apply(target);
        }

        expect(FileSystemEntity.isLinkSync('${temp.path}/CLAUDE.md'), isTrue);
        expect(
          File('${temp.path}/AGENTS.md').readAsStringSync(),
          'text of CLAUDE.md\n',
        );
        expect(steps.whereType<WriteStep>().single.path, 'AGENTS.md');
        expect(
          steps.whereType<CommitStep>().single.paths,
          contains('AGENTS.md'),
        );
      }, skip: Platform.isWindows ? 'symbolic links need a privilege' : null);

      group('commit 2 paths of agent files', () {
        const skipLinks = 'symbolic links need a privilege';

        /// Returns the paths of the last commit of a plan that writes
        /// [rootWrites] and [topWrites] on [project].
        List<String> commit2Of(
          Directory project, {
          List<AgentWrite> rootWrites = const [],
          List<AgentWrite> topWrites = const [],
        }) {
          final plan = RunPlan(
            header: 'migrate',
            moves: const [],
            prunes: const [],
            rewrites: const [],
            creates: const [],
            left: const [],
            commit1Message: 'move',
            commit2Message: 'pin',
            agentFiles: AgentWritePlan(
              rootWrites: rootWrites,
              topWrites: topWrites,
              agentFileRoots: const [],
              addedRoots: const [],
              writeSet: const {},
            ),
          );
          return plan
              .journalSteps(base: 'abc', projectRoot: project)
              .whereType<CommitStep>()
              .last
              .paths;
        }

        /// Returns a project folder with a sibling `shared` folder holding
        /// [shared].
        Directory projectBeside(Map<String, String> shared) {
          final base = Directory.systemTemp.createTempSync('run_plan_beside');
          addTearDown(() => base.deleteSync(recursive: true));
          for (final MapEntry(:key, :value) in shared.entries) {
            File('${base.path}/shared/$key')
              ..createSync(recursive: true)
              ..writeAsStringSync(value);
          }
          return Directory('${base.path}/project')..createSync();
        }

        test('write_agent_files E22: a link to a file outside the project '
            'joins no commit', () {
          final project = projectBeside({'CLAUDE.md': 'x\n'});
          Link('${project.path}/CLAUDE.md').createSync('../shared/CLAUDE.md');

          final paths = commit2Of(
            project,
            rootWrites: [_agentWrite('CLAUDE.md', isNew: false)],
          );

          expect(paths, [specstoneGitignorePath]);
        }, skip: Platform.isWindows ? skipLinks : null);

        test('write_agent_files E15: a repository top nested in the project '
            'joins no commit', () {
          final project = projectBeside({});
          final write = _agentWrite(
            'lib/AGENTS.md',
            isNew: true,
            isAtTop: true,
          );

          final paths = commit2Of(project, topWrites: [write]);

          expect(paths, [specstoneGitignorePath]);
        });

        test('R49: a linked folder inside the project places the file by its '
            'real path', () {
          final project = projectBeside({});
          Directory('${project.path}/rules').createSync();
          Link('${project.path}/.github').createSync('rules');
          File('${project.path}/rules/copilot-instructions.md')
              .writeAsStringSync('x\n');

          final paths = commit2Of(
            project,
            rootWrites: [
              _agentWrite('.github/copilot-instructions.md', isNew: false),
            ],
          );

          expect(paths, [
            'rules/copilot-instructions.md',
            specstoneGitignorePath,
          ]);
        }, skip: Platform.isWindows ? skipLinks : null);

        test('R49: a linked folder outside the project holds its file out of '
            'every commit', () {
          final project = projectBeside({'copilot-instructions.md': 'x\n'});
          Link('${project.path}/.github').createSync('../shared');

          final paths = commit2Of(
            project,
            rootWrites: [
              _agentWrite('.github/copilot-instructions.md', isNew: false),
            ],
          );

          expect(paths, [specstoneGitignorePath]);
        }, skip: Platform.isWindows ? skipLinks : null);

        test('R49: a new file below a linked folder is placed by the '
            'folder real path', () {
          final project = projectBeside({});
          Directory('${project.path}/rules').createSync();
          Link('${project.path}/.cursor').createSync('rules');

          final paths = commit2Of(
            project,
            rootWrites: [_agentWrite('.cursor/rules/x.mdc', isNew: true)],
          );

          expect(paths, ['rules/rules/x.mdc', specstoneGitignorePath]);
        }, skip: Platform.isWindows ? skipLinks : null);
      });
    },
  );

  test('setup_migration/upgrade_pack_pins/apply_steps_and_pins E11: the layout '
      'line names the docs in code point order, and is null without one', () {
    expect(
      formatLayoutLine(['prds/PROJECT.md', 'prds/GNFR.md']),
      'format layout: prds/GNFR.md, prds/PROJECT.md',
    );
    expect(formatLayoutLine(const []), isNull);
  });
}
