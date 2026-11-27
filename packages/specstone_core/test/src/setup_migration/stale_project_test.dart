import 'dart:io';

import 'package:specstone_core/src/setup_migration/stale_project.dart';
import 'package:specstone_core/src/templates/project_config.dart'
    show agentFileGroupNames;
import 'package:specstone_core/src/version.dart';
import 'package:specstone_test_support/specstone_test_support.dart';
import 'package:test/test.dart';

import '../../helpers/shipped_pins.dart';
import '../../helpers/skill_files.dart';
import '../../helpers/temp_tree.dart';

const _lead = "specstone: this project's agent files";
const _older =
    '$_lead are older than specstone $specstoneVersion; run specstone migrate';
const _differ =
    '$_lead differ from what specstone $specstoneVersion writes; run '
    'specstone migrate';
final String _above = versionAbove(specstoneVersion);
final _newer =
    '$_lead come from specstone $_above, newer than this specstone '
    '$specstoneVersion; run specstone upgrade';
const _staleAgentMd = {'.specstone/AGENT.md': 'old\n'};

Future<Directory> _project({
  String config = '',
  List<String> groups = agentFileGroupNames,
  Map<String, String> files = const {},
}) async {
  final root = await writeTree({
    '.specstone/config.yaml':
        '${shippedPinsConfig(shippedPinsDefaultPacks, groups)}$config',
    ...files,
  });
  return Directory(root.resolveSymbolicLinksSync());
}

String? _line(Directory root) =>
    staleProjectLine(root, runningVersion: specstoneVersion);

void main() {
  group('the line form by stamp', () {
    test('no stamp names the older files and migrate', () async {
      final root = await _project(files: _staleAgentMd);

      expect(_line(root), _older);
    });

    test('a stamp below names the older files and migrate', () async {
      final root = await _project(
        config: 'agent_files_version: 0.0.1\n',
        files: _staleAgentMd,
      );

      expect(_line(root), _older);
    });

    test('an equal stamp says the files differ and names migrate', () async {
      final root = await _project(
        config: 'agent_files_version: $specstoneVersion\n',
        files: _staleAgentMd,
      );

      expect(_line(root), _differ);
    });

    test('a stamp above names both Versions and upgrade', () async {
      final root = await _project(
        config: 'agent_files_version: $_above\n',
        files: _staleAgentMd,
      );

      expect(_line(root), _newer);
    });
  });

  group('one line for every stale file', () {
    const staleBlock =
        '<!-- BEGIN specstone v1.0.0 -->\nold\n<!-- END specstone -->\n';

    test('several stale files at the project root give one line', () async {
      final skills = skillFileTexts();
      final skillPath = skills.keys.firstWhere((p) => p != settingsFilePath);
      final root = await _project(
        files: {
          ...skills,
          skillPath: 'older text\n',
          settingsFilePath: '{',
          ..._staleAgentMd,
          'AGENTS.md': staleBlock,
        },
      );

      final line = _line(root);

      expect(line, _older);
      expect(line, isNot(contains('\n')));
    });

    test('a stale root file beside a stale repository top gives one '
        'line', () async {
      final root = await _project(
        config: 'code_root: app\nagent_file_roots:\n  - app\n',
        files: {
          ..._staleAgentMd,
          'app/.git/HEAD': 'ref\n',
          'app/AGENTS.md': staleBlock,
        },
      );

      final line = _line(root);

      expect(line, _older);
      expect(line, isNot(contains('\n')));
    });
  });

  group('a refused unlisted group', () {
    // D16
    test('a refused unlisted group alone gives no line', () async {
      final root = await _project(
        config: 'agent_files_version: $specstoneVersion\n',
        groups: const ['claude_code', 'shared', 'codex_agents'],
        files: {
          for (final MapEntry(:key, :value) in skillFileTexts().entries)
            if (!key.startsWith('.cursor/')) key: value,
          '.cursor': 'not a folder\n',
        },
      );

      expect(_line(root), isNull);
    });
  });

  group('a stale file in a group the project opted out of', () {
    test('a malformed settings file with no skill of ours gives no '
        'line', () async {
      final root = await _project(
        files: {'.claude/skills/own/SKILL.md': 'own\n', settingsFilePath: '{'},
      );

      expect(_line(root), isNull);
    });
  });

  group('a group the config does not list', () {
    test('an unlisted group prints the migrate line', () async {
      final root = await _project(groups: const [], files: skillFileTexts());

      expect(_line(root), _older);
    });

    test('a refused agent_file_groups value lists no group', () async {
      final root = await _project(
        groups: const [],
        config: 'agent_file_groups: [bogus]\n',
        files: skillFileTexts(),
      );

      expect(_line(root), _older);
    });

    test('every group listed prints no line', () async {
      final root = await _project(files: skillFileTexts());

      expect(_line(root), isNull);
    });
  });

  test('a skill file another build of this Version wrote gives the differ '
      'line', () async {
    final skills = skillFileTexts();
    final skillPath = skills.keys.firstWhere((p) => p != settingsFilePath);
    final root = await _project(
      config: 'agent_files_version: $specstoneVersion\n',
      files: {
        ...skills,
        skillPath: '${skills[skillPath]}an older build line\n',
      },
    );

    expect(_line(root), _differ);
  });

  test('the running Version argument alone decides the direction', () async {
    final root = await _project(
      config: 'agent_files_version: 1.5.0\n',
      files: _staleAgentMd,
    );

    expect(
      staleProjectLine(root, runningVersion: '2.0.0'),
      '$_lead are older than specstone 2.0.0; run specstone migrate',
    );
    expect(
      staleProjectLine(root, runningVersion: '1.0.0'),
      '$_lead come from specstone 1.5.0, newer than this specstone 1.0.0; '
      'run specstone upgrade',
    );
  });

  group('what counts as stale', () {
    test('a project with no agent file gives no line', () async {
      expect(_line(await _project()), isNull);
    });

    test('a stamp above with every file current gives no line', () async {
      final root = await _project(config: 'agent_files_version: $_above\n');

      expect(_line(root), isNull);
    });

    test('a settings file that does not parse gives the line', () async {
      final root = await _project(
        files: {...skillFileTexts(), settingsFilePath: '{'},
      );

      expect(_line(root), _older);
    });

    test('a stamp that does not read gives no line', () async {
      final root = await _project(
        config: 'agent_files_version: nope\n',
        files: _staleAgentMd,
      );

      expect(_line(root), isNull);
    });

    test('a broken agent_file_roots list leaves the line', () async {
      final root = await _project(
        config: 'agent_file_roots: 5\n',
        files: _staleAgentMd,
      );

      expect(_line(root), _older);
    });
  });

  group('a repository top alone', () {
    const top = {
      'app/.git/HEAD': 'ref\n',
      'app/AGENTS.md':
          '<!-- BEGIN specstone v1.0.0 -->\nold\n<!-- END specstone -->\n',
    };

    test('a listed top with a stale file gives no line', () async {
      final root = await _project(
        config: 'code_root: app\nagent_file_roots:\n  - app\n',
        files: top,
      );

      expect(_line(root), isNull);
    });

    test('an unlisted top gives no line', () async {
      final root = await _project(config: 'code_root: app\n', files: top);

      expect(_line(root), isNull);
    });
  });
}
