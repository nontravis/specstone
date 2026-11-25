import 'package:specstone_core/src/doc_model/default_enforcer.dart';
import 'package:test/test.dart';

EntityRow _row(String entity, String kind) =>
    EntityRow(entity: entity, kind: kind);

void main() {
  group('entityRowsOf', () {
    test('reads the Entity and Kind columns by header', () {
      final rows = entityRowsOf(const [
        '',
        '| Entity | Kind | Identity | Owns |',
        '|---|---|---|---|',
        '| CheckRun | Aggregate root | its target | findings |',
        '| Finding | Entity | its kind | keys |',
      ]);
      expect(rows.map((row) => (row.entity, row.kind)), [
        ('CheckRun', 'Aggregate root'),
        ('Finding', 'Entity'),
      ]);
    });

    test('finds the columns wherever the header places them', () {
      final rows = entityRowsOf(const [
        '| Identity | Kind | Entity |',
        '|---|---|---|',
        '| id | Service | Engine |',
      ]);
      expect(rows.single.entity, 'Engine');
      expect(rows.single.kind, 'Service');
    });

    test('a second table in the section adds no row', () {
      final rows = entityRowsOf(const [
        '| Entity | Kind |',
        '|---|---|',
        '| CheckRun | Aggregate root |',
        '',
        '| Entity | Kind |',
        '|---|---|',
        '| Other | Aggregate root |',
      ]);
      expect(rows.map((row) => row.entity), ['CheckRun']);
    });

    test('a section with no table gives no rows', () {
      expect(entityRowsOf(const ['None of its own.']), isEmpty);
    });
  });

  group('defaultEnforcerOf', () {
    test('own aggregate root wins over a service', () {
      final chain = [
        [_row('Engine', 'Service'), _row('CheckRun', 'Aggregate root')],
      ];
      expect(defaultEnforcerOf(chain), 'CheckRun');
    });

    test('a service decides only with no aggregate root', () {
      final chain = [
        [_row('Engine', 'Service'), _row('Finding', 'Entity')],
      ];
      expect(defaultEnforcerOf(chain), 'Engine');
    });

    test('two aggregate roots give no default', () {
      final chain = [
        [_row('A', 'Aggregate root'), _row('B', 'Aggregate root')],
        [_row('Parent', 'Aggregate root')],
      ];
      expect(defaultEnforcerOf(chain), isNull);
    });

    test('two services with no aggregate root give no default', () {
      final chain = [
        [_row('A', 'Service'), _row('B', 'Service')],
      ];
      expect(defaultEnforcerOf(chain), isNull);
    });

    test('a doc with no deciding row defers to the closest parent that has '
        'one', () {
      final chain = [
        [_row('Finding', 'Entity')],
        <EntityRow>[],
        [_row('Near', 'Aggregate root')],
        [_row('Far', 'Aggregate root')],
      ];
      expect(defaultEnforcerOf(chain), 'Near');
    });

    test('no deciding doc gives no default', () {
      final chain = [
        [_row('Finding', 'Entity')],
        <EntityRow>[],
      ];
      expect(defaultEnforcerOf(chain), isNull);
      expect(defaultEnforcerOf(const []), isNull);
    });
  });

  group('namesDefaultEnforcer', () {
    test('a closing parenthesized link and backticks are stripped before '
        'comparing', () {
      expect(
        namesDefaultEnforcer(
          'CheckRun ([rulebook:consistency_check](../DOMAIN.md))',
          'CheckRun',
        ),
        isTrue,
      );
      expect(namesDefaultEnforcer('`CheckRun`', 'CheckRun'), isTrue);
      expect(namesDefaultEnforcer('  CheckRun  ', '`CheckRun`'), isTrue);
    });

    test('a differently cased name is no match', () {
      expect(namesDefaultEnforcer('checkrun', 'CheckRun'), isFalse);
      expect(namesDefaultEnforcer('Finding', 'CheckRun'), isFalse);
    });
  });

  group('ancestorTwinPaths', () {
    test('twin paths walk up one folder at a time', () {
      expect(ancestorTwinPaths('specs/f03_packs/f01_ship/DOMAIN.md'), [
        'specs/f03_packs/DOMAIN.md',
        'specs/DOMAIN.md',
      ]);
    });

    test('a doc directly under the spec folder has no twin', () {
      expect(ancestorTwinPaths('specs/DOMAIN.md'), isEmpty);
    });
  });
}
