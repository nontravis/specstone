import 'dart:io';

import 'package:specstone_core/src/canonical_path.dart';
import 'package:specstone_core/src/setup_migration/agent_targets.dart';
import 'package:specstone_core/src/setup_migration/host_render.dart';
import 'package:specstone_core/src/setup_migration/skill_agent_files.dart';
import 'package:specstone_core/src/version.dart';
import 'package:test/test.dart';

import '../../helpers/temp_tree.dart';

final List<RenderedFile> _rendered = renderHostFiles();

/// Every rendered file of [folders], by its path from the root.
Map<String, String> _renderedIn(Iterable<AgentFolder> folders) => {
  for (final file in _rendered)
    if (folders.contains(file.folder)) file.path: file.text,
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

/// The drift list a plan implies: a write is missing or differs, a trash entry
/// is unshipped.
Map<String, SkillFileDriftKind> _driftsOf(SkillFilePlan plan) => {
  for (final write in plan.writes)
    write.path: write.isNew
        ? SkillFileDriftKind.missing
        : SkillFileDriftKind.differs,
  for (final path in plan.trash) path: SkillFileDriftKind.unshipped,
};

void _expectDriftsMatchPlan(AgentFileInputs inputs) {
  final plan = planSkillAndAgentFiles(inputs, full: false);
  final drifts = skillAndAgentFileDrifts(inputs);
  expect({for (final drift in drifts) drift.path: drift.kind}, _driftsOf(plan));
  expect(drifts, hasLength(plan.writes.length + plan.trash.length));
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
      _expectDriftsMatchPlan(_inputs(base));
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
      _expectDriftsMatchPlan(_inputs(base, code: ['proj/vendor/lib/']));
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
}
