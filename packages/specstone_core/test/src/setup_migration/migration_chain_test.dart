// Test names stay one literal so `specstone check` finds them by exact text.
// ignore_for_file: lines_longer_than_80_chars

import 'package:specstone_core/src/setup_migration/migration_chain.dart';
import 'package:specstone_core/src/setup_migration/models/pack_step.dart';
import 'package:specstone_core/src/templates/models/migration_step.dart';
import 'package:specstone_core/src/templates/pack_manifest.dart';
import 'package:specstone_core/src/templates/pack_version.dart';
import 'package:test/test.dart';

const _file = 'acme/pack.yaml';

PackVersion _v(String text) =>
    PackVersion.parse(text, file: _file, key: 'version');

String _entry(String from, String oldHeader) =>
    '''
  - from: $from
    steps:
      - rename_section: {doc_type: spec, from: {id: a, header: $oldHeader}, to: {id: b, header: New $oldHeader}}
''';

PackManifest _manifest(
  String version, {
  String name = 'acme',
  List<String> entries = const [],
}) {
  final migrations = entries.isEmpty ? '' : 'migrations:\n${entries.join()}';
  return PackManifest.parse(
    'name: $name\nversion: $version\n$migrations',
    file: '$name/pack.yaml',
  );
}

List<String> _froms(PackUpgrade upgrade) => [
  for (final PackStep(:from) in upgrade.steps) from.toString(),
];

void main() {
  test('entries from the pin up to below the available version '
      'are chained, oldest first', () {
    final upgrades = selectUpgrades(
      {'acme': _v('1.0.0')},
      {
        'acme': _manifest(
          '1.2.0',
          entries: [
            _entry('1.1.0', 'B'),
            _entry('1.0.0', 'A'),
            _entry('0.9.0', 'Z'),
            _entry('1.2.0', 'C'),
          ],
        ),
      },
    );

    expect(upgrades, hasLength(1));
    expect(upgrades.single.pack, 'acme');
    expect(upgrades.single.pin.toString(), '1.0.0');
    expect(upgrades.single.target.toString(), '1.2.0');
    expect(_froms(upgrades.single), ['1.0.0', '1.1.0']);
  });

  test('steps of one entry keep their list order', () {
    final upgrades = selectUpgrades(
      {'acme': _v('1.0.0')},
      {
        'acme': PackManifest.parse('''
name: acme
version: 1.1.0
migrations:
  - from: 1.0.0
    steps:
      - rename_field: {doc_type: spec, from: owner, to: on_call}
      - rename_field: {doc_type: spec, from: on_call, to: oncall}
''', file: _file),
      },
    );

    expect(
      [for (final PackStep(:step) in upgrades.single.steps) step.kind],
      ['rename_field', 'rename_field'],
    );
    expect(_froms(upgrades.single), ['1.0.0', '1.0.0']);
  });

  test(
    'a relink step at 1.1.0 holds the 1.0.0 merge, drop, and rename rules',
    () {
      final step = selectUpgrades(
        {'acme': _v('1.1.0')},
        {
          'acme': PackManifest.parse('''
name: acme
version: 1.2.0
migrations:
  - from: 1.0.0
    steps:
      - merge_doc:
          from: {id: domain, path: "specs/f{nn}_{slug}/DOMAIN.md"}
          to: architecture
          sections:
            - from: {id: entities, header: Entities}
              to: data
      - drop_section: {doc_types: [architecture], section: {id: concerns, header: Concerns}}
      - rename_section: {doc_type: architecture, from: {id: component_diagram, header: Component diagram}, to: {id: technical_diagram, header: Technical diagram}}
  - from: 1.1.0
    steps:
      - relink_merged_docs: {}
''', file: _file),
        },
      ).single.steps.single;

      expect(step.step, isA<RelinkMergedDocs>());
      final rules = step.relinkRules!;
      expect(rules.folds.single.fromId, 'domain');
      expect(rules.drops.single.sectionId, 'concerns');
      expect(rules.renames.single.fromHeader, 'Component diagram');
    },
  );

  test('a relink step of a pack with no earlier merge, drop, or rename step has empty rules', () {
    final step = selectUpgrades(
      {'acme': _v('1.1.0')},
      {
        'acme': PackManifest.parse('''
name: acme
version: 1.2.0
migrations:
  - from: 1.0.0
    steps:
      - rename_field: {doc_type: spec, from: owner, to: on_call}
  - from: 1.1.0
    steps:
      - relink_merged_docs: {}
''', file: _file),
      },
    ).single.steps.single;

    expect(step.relinkRules!.isEmpty, isTrue);
  });

  test('no entry in range changes the pin '
      'only', () {
    final upgrades = selectUpgrades(
      {'acme': _v('1.0.0')},
      {
        'acme': _manifest('1.2.0', entries: [_entry('0.9.0', 'Z')]),
      },
    );

    expect(upgrades, hasLength(1));
    expect(upgrades.single.steps, isEmpty);
    expect(upgrades.single.target.toString(), '1.2.0');
  });

  test('a pack with no migrations list changes the pin '
      'only', () {
    final upgrades = selectUpgrades(
      {'acme': _v('1.0.0')},
      {'acme': _manifest('1.2.0')},
    );

    expect(upgrades.single.steps, isEmpty);
  });

  test('two releases behind gives both '
      "releases' steps, the older first", () {
    final upgrades = selectUpgrades(
      {'acme': _v('1.0.0')},
      {
        'acme': _manifest(
          '1.2.0',
          entries: [_entry('1.1.0', 'B'), _entry('1.0.0', 'A')],
        ),
      },
    );

    expect(_froms(upgrades.single), ['1.0.0', '1.1.0']);
  });

  test('a pin at any past version finds every step '
      'after it', () {
    final upgrades = selectUpgrades(
      {'acme': _v('1.1.0')},
      {
        'acme': _manifest(
          '1.2.0',
          entries: [_entry('1.0.0', 'A'), _entry('1.1.0', 'B')],
        ),
      },
    );

    expect(_froms(upgrades.single), ['1.1.0']);
  });

  test('a pin equal to the available version gives no upgrade '
      'for that pack', () {
    final upgrades = selectUpgrades(
      {'acme': _v('1.2.0')},
      {
        'acme': _manifest('1.2.0', entries: [_entry('1.1.0', 'B')]),
      },
    );

    expect(upgrades, isEmpty);
  });

  test('a pin newer than the available version gives no '
      'upgrade for that pack', () {
    final upgrades = selectUpgrades(
      {'acme': _v('1.3.0')},
      {
        'acme': _manifest('1.2.0', entries: [_entry('1.1.0', 'B')]),
      },
    );

    expect(upgrades, isEmpty);
  });

  test('upgrades come in code point order of the pack name', () {
    final upgrades = selectUpgrades(
      {'zeta': _v('1.0.0'), 'alpha': _v('1.0.0')},
      {
        'zeta': _manifest('2.0.0', name: 'zeta'),
        'alpha': _manifest('2.0.0', name: 'alpha'),
      },
    );

    expect([for (final u in upgrades) u.pack], ['alpha', 'zeta']);
  });

  test('a pin with no available pack throws a StateError '
      'naming the pack', () {
    expect(
      () => selectUpgrades(
        {'alpha': _v('1.0.0'), 'gone': _v('1.0.0')},
        {'alpha': _manifest('2.0.0', name: 'alpha')},
      ),
      throwsA(
        isA<StateError>().having((e) => e.message, 'message', contains('gone')),
      ),
    );
  });
}
