import 'package:specstone_core/src/setup_migration/migration_chain.dart';
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
  for (final (:from, step: _) in upgrade.steps) from.toString(),
];

void main() {
  test('f06/us02/fr01: entries from the pin up to below the available version '
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

  test('f06/us02/fr01: steps of one entry keep their list order', () {
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
      [for (final (from: _, :step) in upgrades.single.steps) step.kind],
      ['rename_field', 'rename_field'],
    );
    expect(_froms(upgrades.single), ['1.0.0', '1.0.0']);
  });

  test('f06/us02/fr01/e01, f06/us02/s1: no entry in range changes the pin '
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

  test('f06/us02/fr01/e02: a pack with no migrations list changes the pin '
      'only', () {
    final upgrades = selectUpgrades(
      {'acme': _v('1.0.0')},
      {'acme': _manifest('1.2.0')},
    );

    expect(upgrades.single.steps, isEmpty);
  });

  test('f06/us02/fr01/e04, f06/us02/s4: two releases behind gives both '
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

  test('f06/us02/fr01/e05: a pin at any past version finds every step '
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

  test('f06/us02/fr01: a pin equal to the available version gives no upgrade '
      'for that pack', () {
    final upgrades = selectUpgrades(
      {'acme': _v('1.2.0')},
      {
        'acme': _manifest('1.2.0', entries: [_entry('1.1.0', 'B')]),
      },
    );

    expect(upgrades, isEmpty);
  });

  test('f06/us02/fr01: a pin newer than the available version gives no '
      'upgrade for that pack', () {
    final upgrades = selectUpgrades(
      {'acme': _v('1.3.0')},
      {
        'acme': _manifest('1.2.0', entries: [_entry('1.1.0', 'B')]),
      },
    );

    expect(upgrades, isEmpty);
  });

  test('f06/us02/fr01: upgrades come in code point order of the pack name', () {
    final upgrades = selectUpgrades(
      {'zeta': _v('1.0.0'), 'alpha': _v('1.0.0')},
      {
        'zeta': _manifest('2.0.0', name: 'zeta'),
        'alpha': _manifest('2.0.0', name: 'alpha'),
      },
    );

    expect([for (final u in upgrades) u.pack], ['alpha', 'zeta']);
  });

  test('f06/us02/fr01: a pin with no available pack throws a StateError '
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
