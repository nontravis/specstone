import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/document_writing/models/path_move.dart';
import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:specstone_core/src/plan_hash.dart';
import 'package:specstone_core/src/setup_migration/agent_targets.dart';
import 'package:specstone_core/src/setup_migration/models/agent_write.dart';
import 'package:specstone_core/src/setup_migration/run_plan.dart';
import 'package:test/test.dart';

import '../../helpers/write_fixture.dart' show testHome, trustOf;

/// The inputs of a plan built by hand, which read no file.
PlanInputs _noInputs() => PlanInputs(Directory.systemTemp);

const _runbook = 'prds/runbooks/deploy/RUNBOOK.md';
const _notes = 'prds/runbooks/deploy/NOTES.md';

/// Two docs trading places: each target is the other's source.
const _cycle = <PathMove>[
  PathMove(from: _runbook, to: _notes),
  PathMove(from: _notes, to: _runbook),
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
  inputs: _noInputs(),
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
  inputs: _noInputs(),
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
    'two writes '
    'of one path are refused, since the first would make the second skip',
    () {
      final plan = RunPlan(
        header: 'migrate',
        moves: [],
        prunes: [],
        rewrites: [
          const PlannedRewrite(
            path: 'AGENTS.md',
            text: 'a',
            before: 'b',
            changes: [],
          ),
          const PlannedRewrite(
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
        inputs: _noInputs(),
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

  test('a move onto the source of a move not yet '
      'run parks in the stage until every move has run', () {
    expect(_moveLines(_planOf(_cycle)), [
      'move docs/$_runbook -> ${MoveJournal.stagePath}/0',
      'move docs/$_notes -> docs/$_runbook',
      'move ${MoveJournal.stagePath}/0 -> docs/$_notes',
    ]);
  });

  test('a three-doc cycle parks one doc', () {
    final plan = _planOf(const [
      PathMove(from: 'c.md', to: 'a.md'),
      PathMove(from: 'b.md', to: 'c.md'),
      PathMove(from: 'a.md', to: 'b.md'),
    ]);

    expect(_moveLines(plan), [
      'move docs/c.md -> ${MoveJournal.stagePath}/0',
      'move docs/b.md -> docs/c.md',
      'move docs/a.md -> docs/b.md',
      'move ${MoveJournal.stagePath}/0 -> docs/a.md',
    ]);
  });

  test('moves ordered so each target is free run straight, '
      'with no stage', () {
    final plan = _planOf(const [
      PathMove(from: 'b.md', to: 'c.md'),
      PathMove(from: 'a.md', to: 'b.md'),
    ]);

    expect(_moveLines(plan), [
      'move docs/b.md -> docs/c.md',
      'move docs/a.md -> docs/b.md',
    ]);
  });

  test('a staged cycle prints and commits its final paths '
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

  test('commit 1 carries each move once as a '
      'ProjectPath pair, the stage hops left out; commit 2 carries none', () {
    final commits = _planOf(_cycle)
        .journalSteps(base: 'abc', projectRoot: _root)
        .whereType<CommitStep>()
        .toList();

    expect(commits.first.moves, [
      const PathMove(from: 'docs/$_runbook', to: 'docs/$_notes'),
      const PathMove(from: 'docs/$_notes', to: 'docs/$_runbook'),
    ]);
    expect(commits.last.moves, isEmpty);
  });

  group('agent files', () {
    test('one step per agent file follows every other write and create, '
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

    test('commit 2 carries the root agent files and no top file', () {
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

    test('a journal written and read back replays the same steps', () {
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

    test('a top path applies through the target and a write skips a '
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
        trust: trustOf(project),
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

    test('the agent files line prints last under commit 2, creates when '
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

    test('a planner that sets rewrite lines places the line itself', () {
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

    test('rewrite lines that leave out the agent files line keep it '
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

    test('a symbolic-link CLAUDE.md stays a link and '
        'its real file takes the write', () {
      final temp = Directory.systemTemp.createTempSync('run_plan_link');
      addTearDown(() => temp.deleteSync(recursive: true));
      File('${temp.path}/AGENTS.md').writeAsStringSync('Owner\n');
      Link('${temp.path}/CLAUDE.md').createSync('AGENTS.md');
      final target = JournalTarget(
        projectRoot: temp,
        docsRoot: temp,
        homeDirectory: testHome(),
        trust: trustOf(temp),
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
        inputs: _noInputs(),
        agentFiles: AgentWritePlan(
          rootWrites: [_agentWrite('CLAUDE.md', isNew: false, was: 'Owner\n')],
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
      expect(steps.whereType<CommitStep>().single.paths, contains('AGENTS.md'));
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
          inputs: _noInputs(),
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

      test('a repository top nested in the project '
          'joins no commit', () {
        final project = projectBeside({});
        final write = _agentWrite('lib/AGENTS.md', isNew: true, isAtTop: true);

        final paths = commit2Of(project, topWrites: [write]);

        expect(paths, [specstoneGitignorePath]);
      });

      test('a linked folder inside the project places the file by its '
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

      test('a new file below a linked folder is placed by the '
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

    group('the trash steps of unshipped agent files', () {
      const skipLinks = 'symbolic links need a privilege';
      const oldSkill = '.claude/skills/specstone-old';
      const trashed = '.specstone/trash/files';

      /// A project folder holding [files], each under its path.
      Directory projectWith(Map<String, String> files) {
        final project = Directory.systemTemp.createTempSync('run_plan_trash');
        addTearDown(() => project.deleteSync(recursive: true));
        for (final MapEntry(:key, :value) in files.entries) {
          File('${project.path}/$key')
            ..createSync(recursive: true)
            ..writeAsStringSync(value);
        }
        return project;
      }

      RunPlan trashPlan({
        required List<String> trash,
        List<String> topTrash = const [],
        Map<String, List<String>> contents = const {},
      }) => RunPlan(
        header: 'migrate',
        moves: const [],
        prunes: const [],
        rewrites: const [],
        creates: const [],
        left: const [],
        commit1Message: 'move',
        commit2Message: 'pin',
        inputs: _noInputs(),
        agentFiles: AgentWritePlan(
          rootWrites: const [],
          topWrites: const [],
          agentFileRoots: const [],
          addedRoots: const [],
          writeSet: const {},
          trash: trash,
          topTrash: topTrash,
          trashContents: contents,
        ),
      );

      test('a skill folder moves whole to the trash before commit 2, whose '
          'paths hold each file under it', () {
        final project = projectWith({
          '$oldSkill/SKILL.md': 'old\n',
          '$oldSkill/references/more.md': 'old\n',
        });
        final plan = trashPlan(
          trash: [oldSkill],
          contents: {
            oldSkill: ['$oldSkill/SKILL.md', '$oldSkill/references/more.md'],
          },
        );

        final steps = plan.journalSteps(base: 'abc', projectRoot: project);

        final move = steps.whereType<MoveStep>().single;
        expect(move.describe(), 'move $oldSkill -> $trashed/$oldSkill');
        final commit = steps.whereType<CommitStep>().single;
        expect(steps.indexOf(move), lessThan(steps.indexOf(commit)));
        expect(commit.paths, [
          oldSkill,
          '$oldSkill/SKILL.md',
          '$oldSkill/references/more.md',
          specstoneGitignorePath,
        ]);
      });

      test('a file inside a shipped skill folder moves alone', () {
        const extra = '.claude/skills/specstone-read/extra.md';
        final project = projectWith({extra: 'old\n'});
        final plan = trashPlan(trash: [extra]);

        final steps = plan.journalSteps(base: 'abc', projectRoot: project);

        expect(steps.whereType<MoveStep>().single.describe(), contains(extra));
        expect(steps.whereType<CommitStep>().single.paths, [
          extra,
          specstoneGitignorePath,
        ]);
      });

      test('an entry at a repository top moves but joins no commit', () {
        const topEntry = 'lib/.claude/skills/specstone-old';
        final project = projectWith({'$topEntry/SKILL.md': 'old\n'});
        final plan = trashPlan(
          trash: [topEntry],
          topTrash: [topEntry],
          contents: {
            topEntry: ['$topEntry/SKILL.md'],
          },
        );

        final steps = plan.journalSteps(base: 'abc', projectRoot: project);

        expect(
          steps.whereType<MoveStep>().single.describe(),
          'move $topEntry -> $trashed/$topEntry',
        );
        expect(steps.whereType<CommitStep>().single.paths, [
          specstoneGitignorePath,
        ]);
      });

      test('an entry below a linked folder moves from the folder real '
          'place, and the commit names that place', () {
        final project = projectWith({'$oldSkill/SKILL.md': 'old\n'});
        Directory('${project.path}/.agents').createSync();
        Link('${project.path}/.agents/skills').createSync('../.claude/skills');
        const linked = '.agents/skills/specstone-old';
        final plan = trashPlan(
          trash: [linked],
          contents: {
            linked: ['$linked/SKILL.md'],
          },
        );

        final steps = plan.journalSteps(base: 'abc', projectRoot: project);

        expect(
          steps.whereType<MoveStep>().single.describe(),
          'move $oldSkill -> $trashed/$oldSkill',
        );
        expect(steps.whereType<CommitStep>().single.paths, [
          oldSkill,
          '$oldSkill/SKILL.md',
          specstoneGitignorePath,
        ]);
      }, skip: Platform.isWindows ? skipLinks : null);

      test('a link entry moves as the link, never its target', () {
        final project = projectWith({'shared/SKILL.md': 'shared\n'});
        Directory('${project.path}/.claude/skills').createSync(recursive: true);
        Link('${project.path}/$oldSkill').createSync('../../shared');
        final plan = trashPlan(trash: [oldSkill]);
        final target = JournalTarget(
          projectRoot: project,
          docsRoot: project,
          homeDirectory: testHome(),
          trust: trustOf(project),
        );

        for (final step
            in plan
                .journalSteps(base: 'abc', projectRoot: project)
                .whereType<MoveStep>()) {
          step.apply(target);
        }

        expect(File('${project.path}/shared/SKILL.md').existsSync(), isTrue);
        expect(
          FileSystemEntity.isLinkSync('${project.path}/$trashed/$oldSkill'),
          isTrue,
        );
        expect(
          FileSystemEntity.typeSync(
            '${project.path}/$oldSkill',
            followLinks: false,
          ),
          FileSystemEntityType.notFound,
        );
      }, skip: Platform.isWindows ? skipLinks : null);

      test('a move that ran is not run again', () {
        final project = projectWith({'$oldSkill/SKILL.md': 'old\n'});
        final plan = trashPlan(
          trash: [oldSkill],
          contents: {
            oldSkill: ['$oldSkill/SKILL.md'],
          },
        );
        final target = JournalTarget(
          projectRoot: project,
          docsRoot: project,
          homeDirectory: testHome(),
          trust: trustOf(project),
        );
        final move =
            plan
                .journalSteps(base: 'abc', projectRoot: project)
                .whereType<MoveStep>()
                .single
              ..apply(target);

        expect(move.isDone(target), isTrue);
        expect(() => move.apply(target), returnsNormally);
        expect(
          File('${project.path}/$trashed/$oldSkill/SKILL.md')
              .readAsStringSync(),
          'old\n',
        );
      });
    });
  });

  test('the layout '
      'line prints its doc count, and is null without one', () {
    expect(
      formatLayoutLine(['prds/PROJECT.md', 'prds/GNFR.md']),
      'format layout: 2 docs',
    );
    expect(
      formatLayoutLine(const ['prds/PROJECT.md']),
      'format layout: 1 docs',
    );
    expect(formatLayoutLine(const []), isNull);
  });

  test('a drop_section step line names its doc types and section id', () {
    const line = UpgradeStepLine(
      from: '1.16.0',
      step: 'drop_section architecture, project_architecture design_references',
      paths: [
        'prds/architecture/a.md',
        'prds/architecture/b.md',
        'prds/architecture/c.md',
      ],
    );

    expect(
      line.text,
      'from 1.16.0: drop_section architecture, project_architecture '
      'design_references: 3 docs',
    );
  });

  group('the from docs of a merge_doc step', () {
    const toPath = 'docs/prds/runbooks/deploy/RUNBOOK.md';
    const fromPath = 'docs/prds/runbooks/deploy/PLAYBOOK.md';
    const layerPath = '.specstone/templates/playbook.yaml';
    const before = '# Deploy\n\n## Goals\n\nShip it.\n';
    const merged =
        '# Deploy\n\n## Goals\n\nShip it.\n\n## Procedure\n\nRun it.\n';
    const trashed = '.specstone/trash/files';

    Directory project() {
      final root = Directory.systemTemp.createTempSync('run_plan_fold');
      addTearDown(() => root.deleteSync(recursive: true));
      for (final MapEntry(:key, :value) in {
        toPath: before,
        fromPath: '# Deploy\n\n## Moves\n\nRun it.\n',
        layerPath: 'sections: []\n',
      }.entries) {
        File('${root.path}/$key')
          ..createSync(recursive: true)
          ..writeAsStringSync(value);
      }
      return root;
    }

    RunPlan foldPlan() => RunPlan(
      header: 'pack upgrade: acme 1.0.0 -> 1.2.0',
      moves: const [],
      prunes: const [],
      rewrites: [
        PlannedRewrite(
          path: toPath,
          text: merged,
          before: textHashOf(before),
          changes: const ['merge_doc playbook -> runbook'],
        ),
      ],
      creates: const [],
      left: const [],
      commit1Message: 'move',
      commit2Message: 'pin',
      inputs: _noInputs(),
      trashedDocs: const [fromPath],
      lists: const PlanLists(keptLayers: [layerPath]),
    );

    JournalTarget targetOf(Directory root) => JournalTarget(
      projectRoot: root,
      docsRoot: Directory('${root.path}/docs'),
      homeDirectory: testHome(),
      trust: trustOf(root),
    );

    test('the from file moves to the trash before commit 2, whose paths hold '
        'its place, and the layer file is not among them', () {
      final root = project();

      final steps = foldPlan().journalSteps(base: 'abc', projectRoot: root);

      final move = steps.whereType<MoveStep>().single;
      expect(move.describe(), 'move $fromPath -> $trashed/$fromPath');
      final commit = steps.whereType<CommitStep>().single;
      expect(steps.indexOf(move), lessThan(steps.indexOf(commit)));
      expect(commit.paths, containsAll([toPath, fromPath]));
      expect(commit.paths, isNot(contains(layerPath)));
    });

    test('the layer file is still on disk after the steps of commit 2 ran', () {
      final root = project();
      final target = targetOf(root);

      for (final step in foldPlan().journalSteps(
        base: 'abc',
        projectRoot: root,
      )) {
        if (step is! CommitStep) step.apply(target);
      }

      expect(File('${root.path}/$layerPath').existsSync(), isTrue);
      expect(File('${root.path}/$fromPath').existsSync(), isFalse);
      expect(File('${root.path}/$trashed/$fromPath').existsSync(), isTrue);
    });

    test('keptLayers lists each kept layer file', () {
      expect(foldPlan().keptLayers, [layerPath]);
    });

    test('a run stopped after the from file moved to the trash resumes, '
        'replaying its journal steps without git, to the text an '
        'uninterrupted run leaves', () {
      final whole = project();
      final stopped = project();
      for (final root in [whole, stopped]) {
        // The journal is built per project, as a run builds it.
        final steps = foldPlan().journalSteps(base: 'abc', projectRoot: root);
        final target = targetOf(root);
        final applied = root == whole
            ? steps
            : steps.sublist(0, steps.indexWhere((s) => s is MoveStep) + 1);
        for (final step in applied) {
          if (step is! CommitStep) step.apply(target);
        }
      }
      for (final step in foldPlan().journalSteps(
        base: 'abc',
        projectRoot: stopped,
      )) {
        if (step is! CommitStep) step.apply(targetOf(stopped));
      }

      expect(File('${stopped.path}/$toPath').readAsStringSync(), merged);
      expect(
        File('${stopped.path}/$toPath').readAsStringSync(),
        File('${whole.path}/$toPath').readAsStringSync(),
      );
      expect(File('${stopped.path}/$fromPath').existsSync(), isFalse);
    });
  });
}
