import 'dart:io';

import 'package:specstone_core/src/setup_migration/old_plugin.dart';
import 'package:test/test.dart';

import '../../helpers/temp_tree.dart';

const _on = '{"enabledPlugins": {"specstone@specstone": true}}';
const _off = '{"enabledPlugins": {"specstone@specstone": false}}';

Future<Directory> _folder(Map<String, String> files) => writeTree(files);

bool _enabled({
  required Directory root,
  Directory? home,
  Map<String, String> environment = const {},
}) => oldPluginEnabled(projectRoot: root, environment: environment, home: home);

void main() {
  for (final path in ['.claude/settings.json', '.claude/settings.local.json']) {
    test('the project file $path enabling the plugin reads as on', () async {
      final root = await _folder({path: _on});

      expect(_enabled(root: root), isTrue);
    });
  }

  test('the home settings file enabling the plugin reads as on', () async {
    final root = await _folder({});
    final home = await _folder({'.claude/settings.json': _on});

    expect(_enabled(root: root, home: home), isTrue);
  });

  test('CLAUDE_CONFIG_DIR wins over the home folder', () async {
    final root = await _folder({});
    final home = await _folder({'.claude/settings.json': _on});
    final config = await _folder({'settings.json': _off});

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
    final root = await _folder({});
    final config = await _folder({'settings.json': _on});

    expect(
      _enabled(root: root, environment: {'CLAUDE_CONFIG_DIR': config.path}),
      isTrue,
    );
  });

  test('an empty CLAUDE_CONFIG_DIR falls back to the home folder', () async {
    final root = await _folder({});
    final home = await _folder({'.claude/settings.json': _on});

    expect(
      _enabled(root: root, home: home, environment: {'CLAUDE_CONFIG_DIR': ''}),
      isTrue,
    );
  });

  test('a plugin set to false, absent, or listed beside others reads as '
      'off or on by its own key', () async {
    final off = await _folder({'.claude/settings.json': _off});
    final absent = await _folder({'.claude/settings.json': '{}'});
    final other = await _folder({
      '.claude/settings.json': '{"enabledPlugins": {"other@market": true}}',
    });
    final beside = await _folder({
      '.claude/settings.json':
          '{"enabledPlugins": {"other@market": true, '
          '"specstone@specstone": true}}',
    });

    expect(_enabled(root: off), isFalse);
    expect(_enabled(root: absent), isFalse);
    expect(_enabled(root: other), isFalse);
    expect(_enabled(root: beside), isTrue);
  });

  test('a missing file, a missing home, and no files read as off', () async {
    final root = await _folder({});

    expect(_enabled(root: root), isFalse);
    expect(_enabled(root: root, home: Directory('${root.path}/none')), isFalse);
  });

  test('an unparseable file reads as holding no key, and the others still '
      'count', () async {
    final root = await _folder({
      '.claude/settings.json': '{ not json',
      '.claude/settings.local.json': _on,
    });
    final broken = await _folder({'.claude/settings.json': '[1, 2]'});
    final shape = await _folder({
      '.claude/settings.json': '{"enabledPlugins": ["specstone@specstone"]}',
    });

    expect(_enabled(root: root), isTrue);
    expect(_enabled(root: broken), isFalse);
    expect(_enabled(root: shape), isFalse);
  });

  test('the string "true" does not enable the plugin', () async {
    final root = await _folder({
      '.claude/settings.json':
          '{"enabledPlugins": {"specstone@specstone": "true"}}',
    });

    expect(_enabled(root: root), isFalse);
  });
}
