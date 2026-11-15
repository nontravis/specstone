import 'dart:io';

import 'package:specstone_core/src/setup_migration/old_plugin.dart';
import 'package:test/test.dart';

import '../../helpers/temp_tree.dart';

const _on = '{"enabledPlugins": {"specstone@specstone": true}}';
const _off = '{"enabledPlugins": {"specstone@specstone": false}}';

bool _enabled({
  required Directory root,
  Directory? home,
  Map<String, String> environment = const {},
}) => oldPluginEnabled(projectRoot: root, environment: environment, home: home);

void main() {
  for (final path in ['.claude/settings.json', '.claude/settings.local.json']) {
    test('the project file $path enabling the plugin reads as on', () async {
      final root = await writeTree({path: _on});

      expect(_enabled(root: root), isTrue);
    });
  }

  test('the home settings file enabling the plugin reads as on', () async {
    final root = await writeTree({});
    final home = await writeTree({'.claude/settings.json': _on});

    expect(_enabled(root: root, home: home), isTrue);
  });

  test('CLAUDE_CONFIG_DIR wins over the home folder', () async {
    final root = await writeTree({});
    final home = await writeTree({'.claude/settings.json': _on});
    final config = await writeTree({'settings.json': _off});

    expect(
      _enabled(
        root: root,
        home: home,
        environment: {'CLAUDE_CONFIG_DIR': config.path},
      ),
      isFalse,
    );
  });

  test('CLAUDE_CONFIG_DIR holding the plugin reads as on', () async {
    final root = await writeTree({});
    final config = await writeTree({'settings.json': _on});

    expect(
      _enabled(root: root, environment: {'CLAUDE_CONFIG_DIR': config.path}),
      isTrue,
    );
  });

  test('an empty CLAUDE_CONFIG_DIR falls back to the home folder', () async {
    final root = await writeTree({});
    final home = await writeTree({'.claude/settings.json': _on});

    expect(
      _enabled(root: root, home: home, environment: {'CLAUDE_CONFIG_DIR': ''}),
      isTrue,
    );
  });

  test('a plugin set to false reads as off', () async {
    final root = await writeTree({'.claude/settings.json': _off});

    expect(_enabled(root: root), isFalse);
  });

  test('a file without the key reads as off', () async {
    final root = await writeTree({'.claude/settings.json': '{}'});

    expect(_enabled(root: root), isFalse);
  });

  test('another plugin enabled alone reads as off', () async {
    final root = await writeTree({
      '.claude/settings.json': '{"enabledPlugins": {"other@market": true}}',
    });

    expect(_enabled(root: root), isFalse);
  });

  test('the plugin enabled beside another plugin reads as on', () async {
    final root = await writeTree({
      '.claude/settings.json':
          '{"enabledPlugins": {"other@market": true, '
          '"specstone@specstone": true}}',
    });

    expect(_enabled(root: root), isTrue);
  });

  test('a missing file, a missing home, and no files read as off', () async {
    final root = await writeTree({});

    expect(_enabled(root: root), isFalse);
    expect(_enabled(root: root, home: Directory('${root.path}/none')), isFalse);
  });

  test(
    'an unparseable file holds no key, and the others still count',
    () async {
      final root = await writeTree({
        '.claude/settings.json': '{ not json',
        '.claude/settings.local.json': _on,
      });

      expect(_enabled(root: root), isTrue);
    },
  );

  test('a file whose top level is no object reads as off', () async {
    final root = await writeTree({'.claude/settings.json': '[1, 2]'});

    expect(_enabled(root: root), isFalse);
  });

  test('an enabledPlugins that is no object reads as off', () async {
    final root = await writeTree({
      '.claude/settings.json': '{"enabledPlugins": ["specstone@specstone"]}',
    });

    expect(_enabled(root: root), isFalse);
  });

  test('the string "true" does not enable the plugin', () async {
    final root = await writeTree({
      '.claude/settings.json':
          '{"enabledPlugins": {"specstone@specstone": "true"}}',
    });

    expect(_enabled(root: root), isFalse);
  });
}
