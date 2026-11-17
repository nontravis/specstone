import 'dart:convert';

import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:specstone_core/src/templates/shipped_pack_files.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import '../../helpers/shipped_pins.dart';
import '../../helpers/software_tech.dart';
import '../../helpers/temp_tree.dart';

/// The ten ids of the shipped feature patterns, in code point order.
const _patternIds = <String>[
  'audit_log',
  'auth',
  'crud',
  'file_upload',
  'import_export',
  'notification',
  'payment',
  'role_permission',
  'settings_profile',
  'signup',
];

YamlMap _fileOf(String id) {
  final bytes = shippedPackFiles['software-tech/patterns/$id.yaml'];
  expect(bytes, isNotNull, reason: id);
  return loadYaml(utf8.decode(bytes!)) as YamlMap;
}

List<YamlMap> _itemsOf(String id) => [
  for (final item in _fileOf(id)['items'] as YamlList) item as YamlMap,
];

void main() {
  group('software-tech feature patterns', () {
    late MergedSet set;

    setUpAll(() async {
      set = await resolveSoftwareTech();
    });

    test('the pack holds exactly the ten pattern files, each with its own '
        'id', () {
      final files =
          shippedPackFiles.keys
              .where((k) => k.startsWith('software-tech/patterns/'))
              .toList()
            ..sort();
      expect(files, [
        for (final id in _patternIds) 'software-tech/patterns/$id.yaml',
      ]);
      for (final id in _patternIds) {
        expect(_fileOf(id)['id'], id, reason: id);
      }
    });

    test('only signup carries extends, and it extends auth', () {
      for (final id in _patternIds) {
        expect(
          _fileOf(id)['extends'],
          id == 'signup' ? 'auth' : isNull,
          reason: id,
        );
      }
      expect(set.featurePatterns.map((p) => p.id), _patternIds);
      expect(
        {
          for (final p in set.featurePatterns)
            if (p.extendsId != null) p.id: p.extendsId,
        },
        {'signup': 'auth'},
      );
    });

    test('signup repeats no item id of auth', () {
      final auth = {for (final item in _itemsOf('auth')) item['id']};
      for (final item in _itemsOf('signup')) {
        expect(auth, isNot(contains(item['id'])), reason: '${item['id']}');
      }
    });

    test('signup merges the items of auth, then its own', () {
      final auth = set.featurePattern('auth')!;
      final signup = set.featurePattern('signup')!;
      final own = [for (final item in _itemsOf('signup')) item['id']];
      expect(signup.items.map((i) => i.id), [
        ...auth.items.map((i) => i.id),
        ...own,
      ]);
      expect(
        signup.items.take(auth.items.length).map((i) => i.text),
        auth.items.map((i) => i.text),
      );
    });

    test('a project that lists only prd-core loads none of the ten', () async {
      final project = await writeTree({
        '.specstone/config.yaml': shippedPinsConfig(['prd-core']),
      });
      final resolved = TemplateResolver().resolve(
        workingDirectory: project,
        homeDirectory: await writeTree({}),
      );
      expect(resolved.featurePatterns, isEmpty);
    });
  });
}
