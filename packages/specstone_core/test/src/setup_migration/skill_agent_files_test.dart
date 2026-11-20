import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/canonical_path.dart';
import 'package:specstone_core/src/document_writing/owner_confirmation.dart';
import 'package:specstone_core/src/plan_hash.dart';
import 'package:specstone_core/src/setup_migration/agent_targets.dart';
import 'package:specstone_core/src/setup_migration/cite_pass.dart';
import 'package:specstone_core/src/setup_migration/host_render.dart';
import 'package:specstone_core/src/setup_migration/init_project.dart';
import 'package:specstone_core/src/setup_migration/migration_chain.dart';
import 'package:specstone_core/src/setup_migration/models/rendered_file.dart';
import 'package:specstone_core/src/setup_migration/models/skill_file_drift.dart';
import 'package:specstone_core/src/setup_migration/models/skill_file_plan.dart';
import 'package:specstone_core/src/setup_migration/skill_agent_files.dart';
import 'package:specstone_core/src/setup_migration/upgrade_plan.dart'
    show runsOneTimePasses;
import 'package:specstone_core/src/templates/pack_version.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:specstone_core/src/version.dart';
import 'package:test/test.dart';

import '../../helpers/forwarding_entities.dart';
import '../../helpers/skill_files.dart' show settingsFilePath, settingsFileText;
import '../../helpers/temp_tree.dart';
import '../../helpers/write_fixture.dart' show testHome;

final List<RenderedFile> _rendered = renderHostFiles();

/// Every rendered file of [folders], by its path from the root, and the
/// settings file when a folder of the Claude Code group is among them.
Map<String, String> _renderedIn(Iterable<AgentFolder> folders) => {
  for (final file in _rendered)
    if (folders.contains(file.folder)) file.path: file.text,
  if (folders.any((folder) => folder.group == AgentFolderGroup.claudeCode))
    settingsFilePath: settingsFileText,
};

Map<String, String> get _allRendered => _renderedIn(AgentFolder.values);

String _firstPathIn(AgentFolder folder) =>
    _rendered.firstWhere((file) => file.folder == folder).path;

/// The base folder of a fixture, canonical so paths compare on every platform.
Future<Directory> _base(Map<String, String> files) async {
  final base = await writeTree(files);
  return Directory(base.resolveSymbolicLinksSync());
}

Directory _at(Directory base, String path) => Directory(
  Directory.fromUri(base.uri.resolve(path)).path
      .replaceAll(RegExp(r'[\\/]$'), ''),
);

AgentFileInputs _inputs(
  Directory base, {
  List<String> code = const [],
  List<String> roots = const [],
}) => AgentFileInputs(
  projectRoot: _at(base, 'proj/'),
  cliVersion: specstoneVersion,
  codeRootFolders: [for (final folder in code) _at(base, folder)],
  agentFileRoots: roots,
);

Map<String, String> _under(String folder, Map<String, String> files) => {
  for (final MapEntry(:key, :value) in files.entries) '$folder/$key': value,
};

Set<String> _writtenPaths(SkillFilePlan plan) => {
  for (final write in plan.writes) write.path,
};

/// The drift list a plan implies for the skill and agent files: a write is
/// missing or differs, a trash entry is unshipped. The settings file is left
/// to the caller's explicit kinds, so no mapping here mirrors the code's.
Map<String, SkillFileDriftKind> _driftsOf(SkillFilePlan plan) => {
  for (final write in plan.writes)
    if (!write.path.endsWith(settingsFilePath))
      write.path: write.isNew
          ? SkillFileDriftKind.missing
          : SkillFileDriftKind.differs,
  for (final path in plan.trash) path: SkillFileDriftKind.unshipped,
};

/// Checks that the drifts are the plan's skill and agent drifts plus exactly
/// the [settings] kinds named by path, written out by the caller.
void _expectDriftsMatchPlan(
  AgentFileInputs inputs, {
  Map<String, SkillFileDriftKind> settings = const {},
}) {
  final plan = planSkillAndAgentFiles(inputs, full: false);
  final drifts = skillAndAgentFileDrifts(inputs);
  expect(
    {for (final drift in drifts) drift.path: drift.kind},
    {..._driftsOf(plan), ...settings},
  );
  expect(drifts, hasLength(_driftsOf(plan).length + settings.length));
}

void main() {
  group('planSkillAndAgentFiles with full', () {
    test('writes every rendered file as a new file', () async {
      final base = await _base({'proj/keep.txt': ''});

      final plan = planSkillAndAgentFiles(_inputs(base), full: true);

      expect(
        {for (final write in plan.writes) write.path: write.text},
        {..._allRendered},
      );
      expect(plan.writes.every((write) => write.isNew), isTrue);
      expect(plan.writes.every((write) => write.before == null), isTrue);
      expect(plan.writes.every((write) => !write.isAtTop), isTrue);
      expect(plan.trash, isEmpty);
      expect(plan.skipped, isEmpty);
    });

    test('lists each written path in the write set', () async {
      final base = await _base({'proj/keep.txt': ''});

      final plan = planSkillAndAgentFiles(_inputs(base), full: true);

      expect(plan.writeSet, _writtenPaths(plan));
    });

    test(
      'rewrites a file whose bytes differ and keeps one that matches',
      () async {
        final edited = _firstPathIn(AgentFolder.claudeSkills);
        final kept = _firstPathIn(AgentFolder.agentsSkills);
        final base = await _base({
          'proj/$edited': 'edited\n',
          'proj/$kept': _allRendered[kept]!,
        });

        final plan = planSkillAndAgentFiles(_inputs(base), full: true);

        final write = plan.writes.singleWhere((write) => write.path == edited);
        expect(write.isNew, isFalse);
        expect(write.before, isNotNull);
        expect(_writtenPaths(plan), isNot(contains(kept)));
      },
    );
  });

  group('planSkillAndAgentFiles without full', () {
    test('refills each folder of a group that holds one entry', () async {
      final existing = _firstPathIn(AgentFolder.claudeSkills);
      final base = await _base({'proj/$existing': _allRendered[existing]!});

      final plan = planSkillAndAgentFiles(_inputs(base), full: false);

      expect(
        _writtenPaths(plan),
        {..._renderedIn(AgentFolderGroup.claudeCode.folders).keys}
          ..remove(existing),
      );
    });

    test('refills the skill folder from an agent entry alone', () async {
      final existing = _firstPathIn(AgentFolder.claudeAgents);
      final base = await _base({'proj/$existing': _allRendered[existing]!});

      final plan = planSkillAndAgentFiles(_inputs(base), full: false);

      expect(
        _writtenPaths(plan),
        _renderedIn(AgentFolderGroup.claudeCode.folders).keys.toSet()
          ..remove(existing),
      );
    });

    test(
      'writes a group only when one of its folders holds an entry',
      () async {
        final existing = _firstPathIn(AgentFolder.agentsSkills);
        final base = await _base({'proj/$existing': _allRendered[existing]!});

        final plan = planSkillAndAgentFiles(_inputs(base), full: false);

        expect(
          _writtenPaths(plan),
          _renderedIn(AgentFolderGroup.shared.folders).keys.toSet()
            ..remove(existing),
        );
        expect(
          _writtenPaths(plan).any(
            (path) =>
                path.startsWith('.claude/') ||
                path.startsWith('.cursor/') ||
                path.startsWith('.codex/'),
          ),
          isFalse,
        );
      },
    );

    test('writes nothing when no group holds an entry', () async {
      final base = await _base({'proj/keep.txt': ''});

      final plan = planSkillAndAgentFiles(_inputs(base), full: false);

      expect(plan.writes, isEmpty);
      expect(plan.trash, isEmpty);
      expect(plan.writeSet, isEmpty);
      expect(skillAndAgentFileDrifts(_inputs(base)), isEmpty);
    });

    test('rewrites a hand-edited file whole', () async {
      final path = _firstPathIn(AgentFolder.claudeSkills);
      final base = await _base({
        ..._under('proj', _renderedIn([AgentFolder.claudeSkills])),
        'proj/$path': 'hand edit\n',
      });

      final plan = planSkillAndAgentFiles(_inputs(base), full: false);

      final write = plan.writes.firstWhere((write) => write.path == path);
      expect(write.text, _allRendered[path]);
      expect(write.isNew, isFalse);
      expect(write.before, isNotNull);
    });

    test('leaves a file that differs in line endings alone', () async {
      final claude = _renderedIn(AgentFolderGroup.claudeCode.folders);
      final base = await _base({
        for (final MapEntry(:key, :value) in claude.entries)
          'proj/$key': value.replaceAll('\n', '\r\n'),
      });

      final plan = planSkillAndAgentFiles(_inputs(base), full: false);

      expect(plan.writes, isEmpty);
      expect(skillAndAgentFileDrifts(_inputs(base)), isEmpty);
    });

    test('leaves a group at its bytes when every file matches', () async {
      final base = await _base(_under('proj', _allRendered));

      final plan = planSkillAndAgentFiles(_inputs(base), full: false);

      expect(plan.writes, isEmpty);
      expect(plan.trash, isEmpty);
      expect(plan.writeSet, isEmpty);
    });
  });

  group('names the CLI does not own', () {
    const others = [
      'Specstone-mine',
      'specstone_mine',
      'my-skill',
      'specstone',
    ];

    test('are never written, read, or moved, and open no group', () async {
      final base = await _base({
        for (final name in others) ...{
          'proj/.claude/skills/$name/SKILL.md': 'mine\n',
          'proj/.claude/agents/$name.md': 'mine\n',
          'proj/.agents/skills/$name/SKILL.md': 'mine\n',
          'proj/.cursor/agents/$name.md': 'mine\n',
          'proj/.codex/agents/$name.toml': 'mine\n',
        },
      });

      final plan = planSkillAndAgentFiles(_inputs(base), full: false);

      expect(plan.writes, isEmpty);
      expect(plan.trash, isEmpty);
      expect(skillAndAgentFileDrifts(_inputs(base)), isEmpty);
    });

    test(
      'stay out of the writes and the trash beside a group in use',
      () async {
        final existing = _firstPathIn(AgentFolder.claudeSkills);
        final base = await _base({
          'proj/$existing': _allRendered[existing]!,
          for (final name in others) ...{
            'proj/.claude/skills/$name/SKILL.md': 'mine\n',
            'proj/.claude/agents/$name.md': 'mine\n',
          },
        });

        final full = planSkillAndAgentFiles(_inputs(base), full: true);
        final later = planSkillAndAgentFiles(_inputs(base), full: false);

        for (final plan in [full, later]) {
          final touched = [..._writtenPaths(plan), ...plan.trash];
          for (final name in others) {
            expect(
              touched.where((path) {
                final segments = path.split('/');
                return segments.contains(name) || segments.contains('$name.md');
              }),
              isEmpty,
            );
          }
        }
      },
    );
  });

  group('unshipped entries', () {
    test('move to the trash whole, folder or file', () async {
      final existing = _firstPathIn(AgentFolder.claudeSkills);
      final base = await _base({
        'proj/$existing': _allRendered[existing]!,
        'proj/.claude/skills/specstone-old/SKILL.md': 'old\n',
        'proj/.claude/skills/specstone-old/references/more.md': 'old\n',
        'proj/.claude/agents/specstone-old.md': 'old\n',
        'proj/.agents/skills/specstone-gone/SKILL.md': 'gone\n',
      });

      final plan = planSkillAndAgentFiles(_inputs(base), full: false);

      expect(plan.trash, [
        '.claude/skills/specstone-old',
        '.claude/agents/specstone-old.md',
        '.agents/skills/specstone-gone',
      ]);
      expect(_writtenPaths(plan).any((path) => path.contains('-old')), isFalse);
      _expectDriftsMatchPlan(
        _inputs(base),
        settings: {settingsFilePath: SkillFileDriftKind.settingsMissing},
      );
    });

    test(
      'move to the trash when a shipped skill holds an extra file',
      () async {
        final existing = _firstPathIn(AgentFolder.claudeSkills);
        final skill = existing.substring(0, existing.lastIndexOf('/'));
        final base = await _base({
          ..._under('proj', _renderedIn(AgentFolderGroup.claudeCode.folders)),
          'proj/$skill/extra.md': 'extra\n',
        });

        final plan = planSkillAndAgentFiles(_inputs(base), full: false);

        expect(plan.trash, ['$skill/extra.md']);
        expect(plan.writes, isEmpty);
      },
    );

    test('move to the trash when the name holds a hash or a percent', () async {
      final existing = _firstPathIn(AgentFolder.claudeSkills);
      final skill = existing.substring(0, existing.lastIndexOf('/'));
      final base = await _base({
        ..._under('proj', _renderedIn(AgentFolderGroup.claudeCode.folders)),
        'proj/$skill/notes#1.md': 'extra\n',
        'proj/$skill/a%20b.md': 'extra\n',
      });

      final plan = planSkillAndAgentFiles(_inputs(base), full: false);

      expect(plan.trash, ['$skill/a%20b.md', '$skill/notes#1.md']);
      expect(plan.skipped, isEmpty);
    });

    test('move to the trash on a full run too', () async {
      final base = await _base({
        'proj/.cursor/agents/specstone-old.md': 'old\n',
      });

      final plan = planSkillAndAgentFiles(_inputs(base), full: true);

      expect(plan.trash, ['.cursor/agents/specstone-old.md']);
    });
  });

  group('two names for one real file', () {
    test(
      'plan the file once when one skill folder links to the other',
      () async {
        final existing = _firstPathIn(AgentFolder.claudeSkills);
        final base = await _base({'proj/$existing': 'hand edit\n'});
        Directory(_at(base, 'proj/.agents').path).createSync();
        Link(_at(base, 'proj/.agents/skills').path)
            .createSync(_at(base, 'proj/.claude/skills').path);

        final plan = planSkillAndAgentFiles(_inputs(base), full: true);

        final real = {
          for (final write in plan.writes)
            canonicalPath(
              File.fromUri(_at(base, 'proj/').uri.resolve(write.path)).path,
            ),
        };
        expect(real, hasLength(plan.writes.length));
        expect(
          plan.writes.where((write) => write.path.contains('/specstone-init/')),
          hasLength(1),
        );
      },
      skip: Platform.isWindows ? 'symbolic links need a privilege' : null,
    );

    test('plan the file once when one entry links to the other copy', () async {
      final base = await _base({'proj/.claude/skills/keep': ''});
      final skill = _firstPathIn(AgentFolder.claudeSkills);
      final entry = skill.substring(0, skill.lastIndexOf('/'));
      final other = entry.replaceFirst('.claude/', '.agents/');
      Directory(_at(base, 'proj/.agents/skills').path)
          .createSync(recursive: true);
      Link(_at(base, 'proj/$other').path)
          .createSync(_at(base, 'proj/$entry').path);

      final plan = planSkillAndAgentFiles(_inputs(base), full: true);

      final paths = plan.writes.map((write) => write.path);
      final inEntry = paths.where(
        (path) => path.startsWith('$entry/') || path.startsWith('$other/'),
      );
      expect(inEntry.where((path) => path.startsWith('$entry/')), isNotEmpty);
      expect(inEntry.where((path) => path.startsWith('$other/')), isEmpty);
    }, skip: Platform.isWindows ? 'symbolic links need a privilege' : null);
  });

  group('an agent folder linked to another host folder', () {
    Map<String, String> allBut(AgentFolder skipped) =>
        _renderedIn(AgentFolder.values.where((folder) => folder != skipped));

    test(
      'holding the other host format is no drift and is not rewritten',
      () async {
        final base = await _base(
          _under('proj', allBut(AgentFolder.cursorAgents)),
        );
        Directory(_at(base, 'proj/.cursor').path).createSync();
        Link(_at(base, 'proj/.cursor/agents').path)
            .createSync(_at(base, 'proj/.claude/agents').path);

        expect(skillAndAgentFileDrifts(_inputs(base)), isEmpty);
        expect(
          planSkillAndAgentFiles(_inputs(base), full: true).writes,
          isEmpty,
        );
      },
      skip: Platform.isWindows ? 'symbolic links need a privilege' : null,
    );

    test('is planned under one name and settles once written', () async {
      final base = await _base(
        _under('proj', allBut(AgentFolder.claudeAgents)),
      );
      final cursorForm = _renderedIn([AgentFolder.cursorAgents]);
      for (final MapEntry(:key, :value) in cursorForm.entries) {
        File(_at(base, 'proj/$key').path)
          ..createSync(recursive: true)
          ..writeAsStringSync(value);
      }
      Link(_at(base, 'proj/.claude/agents').path)
          .createSync(_at(base, 'proj/.cursor/agents').path);

      final plan = planSkillAndAgentFiles(_inputs(base), full: true);

      expect(plan.writes.map((write) => write.path), [
        for (final path in _renderedIn([AgentFolder.claudeAgents]).keys)
          if (path != settingsFilePath) path,
      ]);
      for (final write in plan.writes) {
        File(_at(base, 'proj/${write.path}').path)
            .writeAsStringSync(write.text);
      }
      expect(skillAndAgentFileDrifts(_inputs(base)), isEmpty);
    }, skip: Platform.isWindows ? 'symbolic links need a privilege' : null);
  });

  group('an agent folder linked to a folder of another host format', () {
    // Each pair links `link` to `target`; the target holds its own format.
    final pairs = [
      (
        link: AgentFolder.codexAgents,
        target: AgentFolder.claudeAgents,
        otherFiles: AgentFolder.codexAgents,
      ),
      (
        link: AgentFolder.agentsAgents,
        target: AgentFolder.codexAgents,
        otherFiles: AgentFolder.agentsAgents,
      ),
    ];

    for (final pair in pairs) {
      test('${pair.link.path} to ${pair.target.path} keeps the target files '
          'and settles after one run', () async {
        final base = await _base(
          _under(
            'proj',
            _renderedIn(
              AgentFolder.values.where((folder) => folder != pair.link),
            ),
          ),
        );
        Link(_at(base, 'proj/${pair.link.path}').path).createSync(
          _at(base, 'proj/${pair.target.path}').path,
          recursive: true,
        );
        final targetFiles = _renderedIn([pair.target]).keys.toSet();

        final plan = planSkillAndAgentFiles(_inputs(base), full: false);

        expect(plan.trash, isEmpty);
        expect(
          _writtenPaths(plan),
          _renderedIn([pair.otherFiles]).keys.toSet(),
        );
        _expectDriftsMatchPlan(_inputs(base));
        for (final write in plan.writes) {
          File(_at(base, 'proj/${write.path}').path)
              .writeAsStringSync(write.text);
        }
        final settled = planSkillAndAgentFiles(_inputs(base), full: false);
        expect(settled.writes, isEmpty);
        expect(settled.trash, isEmpty);
        expect(skillAndAgentFileDrifts(_inputs(base)), isEmpty);
        for (final path in targetFiles) {
          expect(
            File(_at(base, 'proj/$path').path).readAsStringSync(),
            _allRendered[path],
          );
        }
      }, skip: Platform.isWindows ? 'symbolic links need a privilege' : null);
    }
  });

  group('an entry holding a repository', () {
    const unshipped = '.claude/skills/specstone-new';

    for (final gitFile in ['.git/HEAD', 'vendor/.git/HEAD']) {
      test('is left whole and named when it holds $gitFile', () async {
        final base = await _base({
          'proj/$unshipped/SKILL.md': 'mine\n',
          'proj/$unshipped/$gitFile': 'ref\n',
        });

        final plan = planSkillAndAgentFiles(_inputs(base), full: false);

        expect(plan.trash, isEmpty);
        expect(plan.skipped, ['$unshipped lies under .git; left as it is']);
        expect(
          skillAndAgentFileDrifts(_inputs(base))
              .where((drift) => drift.path.startsWith(unshipped)),
          isEmpty,
        );
      });
    }

    for (final goesOutside in [true, false]) {
      test('is left whole under the .git line when .git is a link '
          '${goesOutside ? 'out of' : 'inside'} the project', () async {
        final base = await _base({
          'proj/$unshipped/SKILL.md': 'mine\n',
          'outside/keep.txt': 'x\n',
          'proj/inside/keep.txt': 'x\n',
        });
        Link(
          _at(base, 'proj/$unshipped/.git').path,
        ).createSync(_at(base, goesOutside ? 'outside' : 'proj/inside').path);

        final plan = planSkillAndAgentFiles(_inputs(base), full: false);

        expect(plan.trash, isEmpty);
        expect(plan.skipped, ['$unshipped lies under .git; left as it is']);
      }, skip: Platform.isWindows ? 'symbolic links need a privilege' : null);
    }

    test('inside a shipped skill folder adds no line per .git file', () async {
      final shipped = _firstPathIn(AgentFolder.claudeSkills);
      final skill = shipped.substring(0, shipped.lastIndexOf('/'));
      final base = await _base({
        ..._under('proj', _renderedIn(AgentFolderGroup.claudeCode.folders)),
        'proj/$skill/.git/objects/a': 'x\n',
      });

      final plan = planSkillAndAgentFiles(_inputs(base), full: false);

      expect(plan.trash, isEmpty);
      expect(plan.skipped, isEmpty);
    });
  });

  group('a folder top that is not a folder', () {
    test('is named and skipped while the other folders are written', () async {
      final base = await _base({'proj/.cursor': 'mine\n'});

      final plan = planSkillAndAgentFiles(_inputs(base), full: true);

      expect(plan.skipped, ['.cursor is not a folder; left as it is']);
      expect(
        plan.writes.where((write) => write.path.startsWith('.cursor/')),
        isEmpty,
      );
      expect(plan.writes, isNotEmpty);
      expect(File(_at(base, 'proj/.cursor').path).readAsStringSync(), 'mine\n');
    });
  });

  group('a folder top that is not a folder and its group is not in use', () {
    test('stays silent while another group is written', () async {
      final base = await _base({
        ..._under('proj', _renderedIn(AgentFolderGroup.claudeCode.folders)),
        'proj/.cursor': 'mine\n',
        'proj/${_firstPathIn(AgentFolder.claudeSkills)}': 'hand edit\n',
      });

      final plan = planSkillAndAgentFiles(_inputs(base), full: false);

      expect(plan.writes, hasLength(1));
      expect(plan.skipped, isEmpty);
    });

    test('is named when another folder of its group is in use', () async {
      final agent = _firstPathIn(AgentFolder.claudeAgents);
      final base = await _base({
        'proj/.claude/skills': 'mine\n',
        'proj/$agent': 'hand edit\n',
      });

      final plan = planSkillAndAgentFiles(_inputs(base), full: false);

      expect(plan.skipped, ['.claude/skills is not a folder; left as it is']);
      expect(plan.writes, isNotEmpty);
    });
  });

  group('a folder that leaves the project and its group is not in use', () {
    test('stays silent while another group is written', () async {
      final existing = _firstPathIn(AgentFolder.agentsSkills);
      final base = await _base({
        'outside/keep.txt': 'x\n',
        'proj/$existing': 'hand edit\n',
      });
      Link(_at(base, 'proj/.claude').path)
          .createSync(_at(base, 'outside').path);

      final plan = planSkillAndAgentFiles(_inputs(base), full: false);

      expect(plan.writes, isNotEmpty);
      expect(plan.skipped, isEmpty);
    }, skip: Platform.isWindows ? 'symbolic links need a privilege' : null);

    test('is named when another folder of its group is in use', () async {
      final agent = _firstPathIn(AgentFolder.claudeAgents);
      final base = await _base({
        'outside/keep.txt': 'x\n',
        'proj/$agent': 'hand edit\n',
      });
      Link(_at(base, 'proj/.claude/skills').path)
          .createSync(_at(base, 'outside').path);

      final plan = planSkillAndAgentFiles(_inputs(base), full: false);

      expect(plan.skipped, hasLength(1));
      expect(plan.skipped.single, startsWith('.claude/skills '));
      expect(plan.skipped.single, contains('outside the project root'));
      expect(plan.writes, isNotEmpty);
    }, skip: Platform.isWindows ? 'symbolic links need a privilege' : null);
  });

  group('an unshipped entry that links to a file the run claims', () {
    test('is trashed and named as drift, and the claimed file stays', () async {
      final claimed = _firstPathIn(AgentFolder.claudeAgents);
      final name = claimed.substring(claimed.lastIndexOf('/') + 1);
      final unshipped = '.codex/agents/$name';
      expect(_rendered.map((file) => file.path), isNot(contains(unshipped)));
      final base = await _base(_under('proj', _allRendered));
      Link(_at(base, 'proj/$unshipped').path)
          .createSync(_at(base, 'proj/$claimed').path);

      final plan = planSkillAndAgentFiles(_inputs(base), full: false);

      expect(plan.trash, [unshipped]);
      expect(plan.writes, isEmpty);
      expect(skillAndAgentFileDrifts(_inputs(base)), [
        SkillFileDrift(path: unshipped, kind: SkillFileDriftKind.unshipped),
      ]);
    }, skip: Platform.isWindows ? 'symbolic links need a privilege' : null);
  });

  group('an entry that differs from a shipped name in case only', () {
    test('is a twin only when the disk folds case', () {
      expect(
        caseTwinOf('specstone-x', ['Specstone-x'], existsOnDisk: () => true),
        'Specstone-x',
      );
      expect(
        caseTwinOf('specstone-x', ['Specstone-x'], existsOnDisk: () => false),
        isNull,
      );
      expect(
        caseTwinOf('specstone-x', [
          'Specstone-x',
          'specstone-x',
        ], existsOnDisk: () => fail('the exact name is listed')),
        isNull,
      );
      expect(
        caseTwinOf('specstone-x', ['other'], existsOnDisk: () => true),
        isNull,
      );
    });

    test('is never written through on a disk that folds case, and is no '
        'obstacle on one that does not', () async {
      final shipped = _firstPathIn(AgentFolder.claudeSkills);
      final entry = shipped.split('/')[2];
      final twin = 'S${entry.substring(1)}';
      // A shipped file of another skill keeps the group in use, so the plan
      // reaches the twin's entry on a disk that tells the two names apart.
      final inUse = _rendered.firstWhere(
        (file) =>
            file.folder == AgentFolder.claudeSkills && file.entry != entry,
      );
      final base = await _base({
        'proj/.claude/skills/$twin/SKILL.md': 'mine\n',
        'proj/${inUse.path}': inUse.text,
      });
      final foldsCase = Directory(_at(base, 'proj/.claude/skills/$entry').path)
          .existsSync();

      final plan = planSkillAndAgentFiles(_inputs(base), full: false);
      final writesToEntry = plan.writes.where(
        (write) => write.path.startsWith('.claude/skills/$entry/'),
      );

      expect(writesToEntry.isEmpty, foldsCase);
      expect(plan.skipped, [
        if (foldsCase)
          '.claude/skills/$entry differs only in case from $twin; left as it is',
      ]);
      final drifted = skillAndAgentFileDrifts(_inputs(base))
          .where((drift) => drift.path.startsWith('.claude/skills/$entry/'));
      expect(drifted.isEmpty, foldsCase);
      expect(
        File(_at(base, 'proj/.claude/skills/$twin/SKILL.md').path)
            .readAsStringSync(),
        'mine\n',
      );
    });
  });

  group('a folder top that leaves the project', () {
    test('is skipped and named, never followed', () async {
      final existing = _firstPathIn(AgentFolder.agentsSkills);
      final base = await _base({
        'outside/skills/keep.txt': 'x\n',
        'outside/agents/keep.txt': 'x\n',
        'proj/$existing': _allRendered[existing]!,
      });
      Link(_at(base, 'proj/.claude').path)
          .createSync(_at(base, 'outside').path);

      final plan = planSkillAndAgentFiles(_inputs(base), full: true);

      expect(plan.skipped, hasLength(1));
      expect(plan.skipped.single, startsWith('.claude '));
      expect(plan.skipped.single, contains('outside the project root'));
      expect(
        plan.writes.where((write) => write.path.startsWith('.claude/')),
        isEmpty,
      );
      expect(plan.trash, isEmpty);
      expect(
        _writtenPaths(plan),
        _renderedIn(
          AgentFolder.values.where(
            (folder) => folder.group != AgentFolderGroup.claudeCode,
          ),
        ).keys.toSet()..remove(existing),
      );
      expect(File('${_at(base, 'outside').path}/skills').existsSync(), isFalse);
    });
  });

  group('repository tops', () {
    Future<Directory> topBase() => _base({
      'proj/keep.txt': '',
      'proj/vendor/.git/HEAD': 'ref\n',
      'proj/vendor/lib/a': '',
    });

    test('write every file once at a top the roots do not list', () async {
      final base = await topBase();

      final plan = planSkillAndAgentFiles(
        _inputs(base, code: ['proj/vendor/lib/']),
        full: false,
      );

      expect(_writtenPaths(plan), {
        for (final path in _allRendered.keys) 'vendor/$path',
      });
      expect(plan.writes.every((write) => write.isAtTop), isTrue);
      expect(plan.writeSet, _writtenPaths(plan));
      _expectDriftsMatchPlan(
        _inputs(base, code: ['proj/vendor/lib/']),
        settings: {
          'vendor/$settingsFilePath': SkillFileDriftKind.settingsMissing,
        },
      );
    });

    test('follow the group rule at a listed top', () async {
      final existing = _firstPathIn(AgentFolder.codexAgents);
      final base = await _base({
        'proj/vendor/.git/HEAD': 'ref\n',
        'proj/vendor/lib/a': '',
        'proj/vendor/$existing': 'hand edit\n',
      });
      final inputs = _inputs(
        base,
        code: ['proj/vendor/lib/'],
        roots: ['vendor'],
      );

      final plan = planSkillAndAgentFiles(inputs, full: true);

      expect(_writtenPaths(plan), {
        ..._allRendered.keys,
        for (final path in _renderedIn(
          AgentFolderGroup.codexAgents.folders,
        ).keys)
          'vendor/$path',
      });
    });

    test('skip a top outside the project root', () async {
      final base = await _base({
        'proj/keep.txt': '',
        'other/.git/HEAD': 'ref\n',
        'other/lib/a': '',
      });

      final plan = planSkillAndAgentFiles(
        _inputs(base, code: ['other/lib/']),
        full: true,
      );

      expect(_writtenPaths(plan), _allRendered.keys.toSet());
      expect(plan.skipped, [
        '../other reaches outside the project root; left as it is',
      ]);
    });
  });

  group('skillFolderOf', () {
    test('names the folder of a skill or agent file at the root or a top', () {
      expect(
        skillFolderOf('.claude/skills/specstone-x/SKILL.md'),
        '.claude/skills',
      );
      expect(skillFolderOf('.codex/agents/specstone-x.toml'), '.codex/agents');
      expect(
        skillFolderOf('../other/.agents/agents/specstone-x.md'),
        '../other/.agents/agents',
      );
      expect(
        skillFolderOf('top/.cursor/agents/specstone-x.md'),
        'top/.cursor/agents',
      );
    });

    test('is null for an instruction file and a Cursor rules file', () {
      expect(skillFolderOf('AGENTS.md'), isNull);
      expect(skillFolderOf('.cursor/rules/specstone.mdc'), isNull);
      expect(skillFolderOf('.specstone/AGENT.md'), isNull);
    });
  });

  group('skillAndAgentFileDrifts', () {
    test(
      'names a missing file, a differing file, and an unshipped one',
      () async {
        final claudeSkill = _firstPathIn(AgentFolder.claudeSkills);
        final base = await _base({
          ..._under('proj', _renderedIn(AgentFolderGroup.claudeCode.folders)),
          'proj/$claudeSkill': 'hand edit\n',
          'proj/.claude/agents/specstone-old.md': 'old\n',
        });
        File(
          '${_at(base, 'proj').path}/${_firstPathIn(AgentFolder.claudeAgents)}',
        ).deleteSync();
        final inputs = _inputs(base);

        final drifts = {
          for (final drift in skillAndAgentFileDrifts(inputs))
            drift.path: drift.kind,
        };

        expect(drifts, {
          claudeSkill: SkillFileDriftKind.differs,
          _firstPathIn(AgentFolder.claudeAgents): SkillFileDriftKind.missing,
          '.claude/agents/specstone-old.md': SkillFileDriftKind.unshipped,
        });
        _expectDriftsMatchPlan(inputs);
      },
    );

    test('is empty exactly when the plan has nothing to do', () async {
      final base = await _base(_under('proj', _allRendered));
      final inputs = _inputs(base);

      expect(skillAndAgentFileDrifts(inputs), isEmpty);
      expect(planSkillAndAgentFiles(inputs, full: false).writes, isEmpty);
    });
  });

  group('the settings file', () {
    const stale = '{"a": 1}\n';

    test('a missing file of a group in use is settingsMissing', () async {
      final base = await _base({
        ..._under('proj', {
          for (final MapEntry(:key, :value) in _renderedIn(
            AgentFolderGroup.claudeCode.folders,
          ).entries)
            if (key != settingsFilePath) key: value,
        }),
      });

      final drifts = skillAndAgentFileDrifts(_inputs(base));

      expect(drifts, [
        const SkillFileDrift(
          path: settingsFilePath,
          kind: SkillFileDriftKind.settingsMissing,
        ),
      ]);
      _expectDriftsMatchPlan(
        _inputs(base),
        settings: {settingsFilePath: SkillFileDriftKind.settingsMissing},
      );
    });

    test('a file that differs is settingsStale and keeps its place in the '
        'plan', () async {
      final base = await _base({
        ..._under('proj', _renderedIn(AgentFolderGroup.claudeCode.folders)),
        'proj/$settingsFilePath': stale,
      });

      final plan = planSkillAndAgentFiles(_inputs(base), full: false);

      expect(skillAndAgentFileDrifts(_inputs(base)), [
        const SkillFileDrift(
          path: settingsFilePath,
          kind: SkillFileDriftKind.settingsStale,
        ),
      ]);
      expect(plan.writes.single.before, isNotNull);
      expect(plan.writeSet, {settingsFilePath});
      _expectDriftsMatchPlan(
        _inputs(base),
        settings: {settingsFilePath: SkillFileDriftKind.settingsStale},
      );
    });

    test('a malformed file is settingsMalformed with its failure, no write, '
        'no throw', () async {
      final base = await _base({
        ..._under('proj', _renderedIn(AgentFolderGroup.claudeCode.folders)),
        'proj/$settingsFilePath': '{',
      });

      final plan = planSkillAndAgentFiles(_inputs(base), full: false);

      expect(plan.malformedSettings.single.path, settingsFilePath);
      expect(plan.malformedSettings.single.failure, isNotEmpty);
      expect(plan.writes, isEmpty);
      expect(skillAndAgentFileDrifts(_inputs(base)), [
        const SkillFileDrift(
          path: settingsFilePath,
          kind: SkillFileDriftKind.settingsMalformed,
        ),
      ]);
    });

    test('a settings path that is a folder is settingsMalformed', () async {
      final base = await _base({
        ..._under('proj', {
          for (final MapEntry(:key, :value) in _renderedIn(
            AgentFolderGroup.claudeCode.folders,
          ).entries)
            if (key != settingsFilePath) key: value,
        }),
        'proj/$settingsFilePath/keep': 'x',
      });

      expect(
        skillAndAgentFileDrifts(_inputs(base)).map((drift) => drift.kind),
        [SkillFileDriftKind.settingsMalformed],
      );
    });

    test('an opted-out group neither plans nor records the file', () async {
      final base = await _base({
        'proj/.claude/skills/own/SKILL.md': 'own\n',
        'proj/$settingsFilePath': '{',
      });

      final plan = planSkillAndAgentFiles(_inputs(base), full: false);

      expect(plan.writes, isEmpty);
      expect(plan.malformedSettings, isEmpty);
      expect(skillAndAgentFileDrifts(_inputs(base)), isEmpty);
    });

    test('every group opted out leaves no write, no trash, no skipped line, '
        'and no handler', () async {
      final base = await _base({
        for (final folder in AgentFolder.values)
          'proj/${folder.path}/own/keep.txt': 'own\n',
      });

      final plan = planSkillAndAgentFiles(_inputs(base), full: false);

      expect(plan.writes, isEmpty);
      expect(plan.trash, isEmpty);
      expect(plan.topTrash, isEmpty);
      expect(plan.skipped, isEmpty);
      expect(plan.malformedSettings, isEmpty);
      expect(plan.writeSet, isEmpty);
      expect(skillAndAgentFileDrifts(_inputs(base)), isEmpty);
    });

    test(
      'a full run records a malformed file though no skill is there',
      () async {
        final base = await _base({'proj/$settingsFilePath': '{'});

        final plan = planSkillAndAgentFiles(_inputs(base), full: true);

        expect(plan.malformedSettings.map((entry) => entry.path), [
          settingsFilePath,
        ]);
        expect(
          plan.writes.map((write) => write.path),
          isNot(contains(settingsFilePath)),
        );
      },
    );

    test('a .claude folder that leaves the project takes one line, none for '
        'the file', () async {
      final base = await _base({'outside/keep.txt': 'x\n', 'proj/a': ''});
      Link(_at(base, 'proj/.claude').path)
          .createSync(_at(base, 'outside').path);

      final plan = planSkillAndAgentFiles(_inputs(base), full: true);

      expect(plan.skipped, hasLength(1));
      expect(plan.malformedSettings, isEmpty);
    }, skip: Platform.isWindows ? 'symbolic links need a privilege' : null);
  });

  group('the plan hash', () {
    Future<String> hashWith(String skillText) async {
      final path = _firstPathIn(AgentFolder.claudeSkills);
      final base = await _base({
        ..._under('proj', _allRendered),
        'proj/$path': skillText,
      });
      final inputs = PlanInputs(_at(base, 'proj/'))
        ..collect(() => planSkillAndAgentFiles(_inputs(base), full: false));
      return planHashOf('plan', inputs);
    }

    test('changes when the bytes of a skill file change', () async {
      final path = _firstPathIn(AgentFolder.claudeSkills);
      final shipped = _allRendered[path]!;

      final current = await hashWith(shipped);
      final edited = await hashWith('${shipped}an edit\n');
      final other = await hashWith('${shipped}another edit\n');

      expect(edited, isNot(current));
      expect(other, isNot(edited));
      expect(await hashWith(shipped), current);
    });
  });

  test('settings.json is written whole through a temporary file and a '
      'rename', () async {
    final root = await writeTree({
      'keep.txt': 'x\n',
      settingsFilePath:
          '{\n  "permissions": {\n    "allow": ["Bash(ls)"]\n  }\n}\n',
    });
    final renames = <(String, String)>[];

    final status = await IOOverrides.runWithIOOverrides(
      () => runInit(
        InitRequest(
          workingDirectory: root,
          homeDirectory: testHome(),
          templates: TemplateResolver(),
          confirmation: OwnerConfirmation.missing,
          readLine: () => null,
          out: StringBuffer(),
        ),
      ),
      _RenameLog(renames),
    );

    expect(status, 0);
    final settingsRenames = [
      for (final (from, to) in renames)
        if (to.replaceAll(r'\', '/').endsWith('.claude/settings.json')) from,
    ];
    expect(settingsRenames, hasLength(1));
    expect(
      settingsRenames.single.split(Platform.pathSeparator).last,
      matches(RegExp(r'^\.settings\.json\.\d+\.[0-9a-f]{16}\.specstone\.tmp$')),
    );
    final written = jsonDecode(
      File('${root.path}/$settingsFilePath').readAsStringSync(),
    ) as Map<String, Object?>;
    expect(written, containsPair('permissions', isA<Map<String, Object?>>()));
    expect(written, contains('hooks'));
    expect(
      Directory('${root.path}/.claude')
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.specstone.tmp')),
      isEmpty,
    );
  });

  group('shipsSkillFiles', () {
    PackUpgrade upgrade(String pack, String pin, String target) => PackUpgrade(
      pack: pack,
      pin: PackVersion.parse(pin, file: 'test', key: pack),
      target: PackVersion.parse(target, file: 'test', key: pack),
      steps: const [],
    );

    test('holds when a prd-core or software-tech pin crosses the first '
        'version that ships the files', () {
      expect(shipsSkillFiles([upgrade('prd-core', '1.8.0', '1.9.0')]), isTrue);
      expect(
        shipsSkillFiles([upgrade('software-tech', '1.6.0', '1.7.0')]),
        isTrue,
      );
      expect(shipsSkillFiles([upgrade('prd-core', '1.0.0', '1.9.0')]), isTrue);
    });

    test('fails for a pin already at the version, a target short of it, and '
        'another pack', () {
      expect(shipsSkillFiles([upgrade('prd-core', '1.9.0', '1.9.1')]), isFalse);
      expect(shipsSkillFiles([upgrade('prd-core', '1.7.0', '1.8.0')]), isFalse);
      expect(shipsSkillFiles([upgrade('acme', '1.0.0', '2.0.0')]), isFalse);
      expect(shipsSkillFiles(const []), isFalse);
    });
  });

  test('a pin moving below a once-only version keeps the one-time passes and '
      'starts neither the cite pass nor the skill and agent files', () {
    final upgrade = PackUpgrade(
      pack: 'prd-core',
      pin: PackVersion.parse('1.0.0', file: 'test', key: 'prd-core'),
      target: PackVersion.parse('1.5.0', file: 'test', key: 'prd-core'),
      steps: const [],
    );

    expect(runsOneTimePasses([upgrade]), isTrue);
    expect(runsCitePass([upgrade]), isFalse);
    expect(shipsSkillFiles([upgrade]), isFalse);
  });
}

/// Records each `renameSync` of a file: its path, then its new path.
final class _RenameLog extends IOOverrides {
  new(this._renames);

  final List<(String, String)> _renames;

  @override
  File createFile(String path) =>
      _LoggedRenameFile(super.createFile(path), _renames);
}

final class _LoggedRenameFile extends ForwardingFile {
  const new(super.inner, this._renames);

  final List<(String, String)> _renames;

  @override
  File renameSync(String newPath) {
    _renames.add((path, newPath));
    return super.renameSync(newPath);
  }
}
