import 'dart:io';

import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';

const _frLayer = '.specstone/templates/fr.yaml';
const Set<FindingKind> _fieldKinds = {
  FindingKind.itemFieldMissing,
  FindingKind.itemFieldUnneeded,
  FindingKind.requiredSectionMissing,
  FindingKind.sectionUnneeded,
};

// Items sit under rationale; the conditional section is behavior.
const _layer = '''
sections:
  - id: rationale
    lint:
      item_fields:
        - field: Enforcer
        - field: Consistency
          values: [immediate, eventual]
  - id: behavior
    lint:
      required_when:
        section: rationale
        field: Consistency
        value: eventual
''';

const _whenLayer = '''
sections:
  - id: rationale
    lint:
      item_fields:
        - field: Consistency
        - field: Policy
          when: {field: Consistency, value: eventual}
''';

const _held =
    '- **R1** Refuse it.\n'
    '  - **Enforcer:** CheckRun\n'
    '  - **Consistency:** immediate';

late Directory _project;

Map<String, String> _withRationale(String body, {bool behavior = false}) =>
    edit(loginFr, [
      ('A wrong password must not sign in.', body),
      if (behavior) ('## Rationale', '## Behavior\n\nSteps.\n\n## Rationale'),
    ]);

Future<List<Finding>> _found(
  Map<String, String> edits, {
  String layer = _layer,
}) async {
  _project = await writeCheckProject(extra: {_frLayer: layer, ...edits});
  return [
    for (final f in checkOf(_project).findings)
      if (_fieldKinds.contains(f.kind)) f,
  ];
}

int _lineOf(String needle) =>
    File('${_project.path}/docs/$loginFr')
        .readAsLinesSync()
        .indexWhere((line) => line.contains(needle)) +
    1;

void main() {
  test('an item holding every listed field with an allowed value has no '
      'finding', () async {
    final found = await _found(_withRationale(_held));
    expect(found, isEmpty);
  });

  test(
    'an item without a listed field reports the field at the item line',
    () async {
      final found = await _found(
        _withRationale('- **R1** Refuse it.\n  - **Enforcer:** CheckRun'),
      );
      expect(found, hasLength(1));
      expect(found.single.kind, FindingKind.itemFieldMissing);
      expect(found.single.line, _lineOf('- **R1**'));
      expect(found.single.toJson(), containsPair('field', 'Consistency'));
      expect(found.single.waitsFor, WaitsFor.agent);
    },
  );

  test('a value outside the entry values reports the field', () async {
    final found = await _found(
      _withRationale(
        '- **R1** Refuse it.\n'
        '  - **Enforcer:** CheckRun\n'
        '  - **Consistency:** soon',
      ),
    );
    expect(found, hasLength(1));
    expect(found.single.kind, FindingKind.itemFieldMissing);
    expect(found.single.toJson(), containsPair('field', 'Consistency'));
  });

  test('a field with no values takes any text but an empty one', () async {
    final found = await _found(
      _withRationale(
        '- **R1** Refuse it.\n'
        '  - **Enforcer:**\n'
        '  - **Consistency:** immediate',
      ),
    );
    expect(found, hasLength(1));
    expect(found.single.toJson(), containsPair('field', 'Enforcer'));
  });

  test('only the item missing a field is reported among several', () async {
    final found = await _found(
      _withRationale('$_held\n- **R2** Log it.\n  - **Enforcer:** CheckRun'),
    );
    expect(found, hasLength(1));
    expect(found.single.line, _lineOf('- **R2**'));
  });

  test('a required_when section the doc lacks while an item meets its '
      'condition is a missing required section', () async {
    final found = await _found(
      _withRationale(
        '- **R1** Refuse it.\n'
        '  - **Enforcer:** CheckRun\n'
        '  - **Consistency:** eventual',
      ),
    );
    expect(found, hasLength(1));
    expect(found.single.kind, FindingKind.requiredSectionMissing);
    expect(found.single.line, 1);
    expect(found.single.toJson(), containsPair('section', 'behavior'));
    expect(found.single.waitsFor, WaitsFor.agent);
  });

  test('a required_when section held while no item meets its condition is '
      'unneeded at its header', () async {
    final found = await _found(_withRationale(_held, behavior: true));
    expect(found, hasLength(1));
    expect(found.single.kind, FindingKind.sectionUnneeded);
    expect(found.single.line, _lineOf('## Behavior'));
    expect(found.single.toJson(), containsPair('section', 'behavior'));
    expect(found.single.waitsFor, WaitsFor.agent);
  });

  test('a required_when section held while an item meets its condition has no '
      'finding', () async {
    final found = await _found(
      _withRationale(
        '- **R1** Refuse it.\n'
        '  - **Enforcer:** CheckRun\n'
        '  - **Consistency:** eventual',
        behavior: true,
      ),
    );
    expect(found, isEmpty);
  });

  test('a doc type that sets neither key runs no item-field rule', () async {
    final project = await writeCheckProject(
      extra: _withRationale('- **R1** Refuse it.', behavior: true),
    );
    expect(
      checkOf(project).findings.where((f) => _fieldKinds.contains(f.kind)),
      isEmpty,
    );
  });

  group('a conditional item field', () {
    Future<List<Finding>> found(String body, {String layer = _whenLayer}) =>
        _found(_withRationale(body), layer: layer);

    test(
      'an eventual item holding the conditional field has no finding',
      () async {
        expect(
          await found(
            '- **R1** Refuse it.\n'
            '  - **Consistency:** eventual\n'
            '  - **Policy:** Retry.',
          ),
          isEmpty,
        );
      },
    );

    test('an eventual item without the conditional field reports it at the '
        'item line', () async {
      final result = await found(
        '- **R1** Refuse it.\n  - **Consistency:** eventual',
      );
      expect(result, hasLength(1));
      expect(result.single.kind, FindingKind.itemFieldMissing);
      expect(result.single.toJson(), containsPair('field', 'Policy'));
      expect(result.single.line, _lineOf('- **R1**'));
    });

    test('an immediate item holding the conditional field reports it as '
        'unneeded', () async {
      final result = await found(
        '- **R1** Refuse it.\n'
        '  - **Consistency:** immediate\n'
        '  - **Policy:** Retry.',
      );
      expect(result, hasLength(1));
      expect(result.single.kind, FindingKind.itemFieldUnneeded);
      expect(result.single.toJson(), containsPair('field', 'Policy'));
      expect(result.single.line, _lineOf('- **R1**'));
      expect(result.single.waitsFor, WaitsFor.agent);
      expect(
        await found('- **R1** Refuse it.\n  - **Consistency:** immediate'),
        isEmpty,
      );
    });

    test('an item with no Consistency needs no conditional field', () async {
      final result = await found('- **R1** Refuse it.\n  - **Policy:** Retry.');
      expect(result.map((f) => (f.kind, f.toJson()['field'])), [
        (FindingKind.itemFieldMissing, 'Consistency'),
        (FindingKind.itemFieldUnneeded, 'Policy'),
      ]);
    });

    test('an entry with values and when reports a met item value outside '
        'values and an unmet item field whatever its text', () async {
      const layer = '''
sections:
  - id: rationale
    lint:
      item_fields:
        - field: Consistency
        - field: Policy
          values: [retry]
          when: {field: Consistency, value: eventual}
''';
      final met = await found(
        '- **R1** Refuse it.\n'
        '  - **Consistency:** eventual\n'
        '  - **Policy:** later',
        layer: layer,
      );
      expect(met.single.kind, FindingKind.itemFieldMissing);
      final unmet = await found(
        '- **R1** Refuse it.\n'
        '  - **Consistency:** immediate\n'
        '  - **Policy:** retry',
        layer: layer,
      );
      expect(unmet.single.kind, FindingKind.itemFieldUnneeded);
    });

    test('a Consistency in another letter case meets no condition', () async {
      final result = await found(
        '- **R1** Refuse it.\n'
        '  - **Consistency:** Eventual\n'
        '  - **Policy:** Retry.',
      );
      expect(result.map((f) => f.kind), [FindingKind.itemFieldUnneeded]);
    });

    test('the first of two Consistency items decides the condition', () async {
      final result = await found(
        '- **R1** Refuse it.\n'
        '  - **Consistency:** eventual\n'
        '  - **Consistency:** immediate',
      );
      expect(result.single.kind, FindingKind.itemFieldMissing);
      expect(result.single.toJson(), containsPair('field', 'Policy'));
    });

    test('an empty conditional field on a met item is missing', () async {
      final result = await found(
        '- **R1** Refuse it.\n'
        '  - **Consistency:** eventual\n'
        '  - **Policy:**',
      );
      expect(result.single.kind, FindingKind.itemFieldMissing);
      expect(result.single.toJson(), containsPair('field', 'Policy'));
    });

    test('a condition reads a nested field no entry lists', () async {
      const layer = '''
sections:
  - id: rationale
    lint:
      item_fields:
        - field: Policy
          when: {field: Kind, value: async}
''';
      final result = await found(
        '- **R1** Refuse it.\n  - **Kind:** async',
        layer: layer,
      );
      expect(result.single.kind, FindingKind.itemFieldMissing);
      expect(result.single.toJson(), containsPair('field', 'Policy'));
    });
  });

  group('a closed generated block', () {
    const body =
        '$_held\n\n'
        '<!-- specstone:generated scenario_copy (do not edit) -->\n'
        '- **R2** Copied.\n'
        '<!-- specstone:generated end -->';

    test('gives no item-field finding for its bullets', () async {
      final found = await _found(
        _withRationale(body),
        layer: 'generators: [scenario_copy]\n$_layer',
      );
      expect(found, isEmpty);
    });

    test('is read as items when the doc type lists no generator', () async {
      final found = await _found(_withRationale(body));
      expect(found, isNotEmpty);
      expect(found.map((f) => f.kind).toSet(), {FindingKind.itemFieldMissing});
    });
  });
}
