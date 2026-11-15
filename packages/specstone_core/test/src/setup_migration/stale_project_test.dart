import 'dart:io';

import 'package:specstone_core/src/setup_migration/stale_project.dart';
import 'package:specstone_core/src/version.dart';
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
const _above = '99.0.0';
const _newer =
    '$_lead come from specstone $_above, newer than this specstone '
    '$specstoneVersion; run specstone upgrade';
const _staleAgentMd = {'.specstone/AGENT.md': 'old\n'};

Future<Directory> _project({
  String config = '',
  Map<String, String> files = const {},
}) async {
  final root = await writeTree({
    '.specstone/config.yaml': '${shippedPinsConfig()}$config',
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
