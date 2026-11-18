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

const _domainPath = 'docs/specs/f01_login/DOMAIN.md';

const _eventual =
    '- **INV-1** A reset link expires.\n'
    '  - **Enforcer:** Account\n'
    '  - **Consistency:** eventual';

const _immediate =
    '- **INV-2** An email is unique.\n'
    '  - **Enforcer:** Account\n'
    '  - **Consistency:** immediate';

const _policy = '  - **Corrective policy:** Sweep expired links daily.';

const _held =
    '- **R1** Refuse it.\n'
    '  - **Enforcer:** CheckRun\n'
    '  - **Consistency:** immediate';

late Directory _project;

Map<String, String> _withRationale(
  String body, {
  bool behavior = false,
  String behaviorBody = 'Steps.',
}) => edit(loginFr, [
  ('A wrong password must not sign in.', body),
  if (behavior)
    ('## Rationale', '## Behavior\n\n$behaviorBody\n\n## Rationale'),
]);

Future<List<Finding>> _found(
  Map<String, String> edits, {
  String layer = _layer,
}) async {
  _project = await writeCheckProject(extra: {_frLayer: layer, ...edits});
  return [
    for (final f in (await checkOf(_project)).findings)
      if (_fieldKinds.contains(f.kind)) f,
  ];
}

void main() {
  test(
    'a quote line under a heading opens no field entry of its own',
    () async {
      final found = await _found(
        _withRationale('### Group\n\n> en: One line.\n$_held'),
      );
      expect(found, isEmpty);
    },
  );

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
      expect(found.single.line, lineOfFirst(_project, loginFr, '- **R1**'));
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
    expect(found.single.line, lineOfFirst(_project, loginFr, '- **R2**'));
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
    expect(found.single.line, lineOfFirst(_project, loginFr, '## Behavior'));
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

  test(
    'a blank required_when section whose condition is met is missing',
    () async {
      final found = await _found(
        _withRationale(
          '- **R1** Refuse it.\n'
          '  - **Enforcer:** CheckRun\n'
          '  - **Consistency:** eventual',
          behavior: true,
          behaviorBody: '',
        ),
      );
      expect(found, hasLength(1));
      expect(found.single.kind, FindingKind.requiredSectionMissing);
      expect(found.single.line, lineOfFirst(_project, loginFr, '## Behavior'));
      expect(found.single.toJson(), containsPair('section', 'behavior'));
    },
  );

  test(
    'a blank required_when section whose condition is unmet is unneeded',
    () async {
      final found = await _found(
        _withRationale(_held, behavior: true, behaviorBody: ''),
      );
      expect(found, hasLength(1));
      expect(found.single.kind, FindingKind.sectionUnneeded);
      expect(found.single.line, lineOfFirst(_project, loginFr, '## Behavior'));
    },
  );

  test('a lone sentence under item_fields draws no field finding', () async {
    final found = await _found(_withRationale('A plain sentence.'));
    expect(found, isEmpty);
  });

  test('a sentence between an item and its fields cuts them off', () async {
    final found = await _found(
      _withRationale(
        '- **R1** Refuse it.\n\n'
        'A plain sentence.\n\n'
        '  - **Enforcer:** CheckRun',
      ),
    );
    expect(found, hasLength(2));
    expect(
      found.map((f) => f.kind),
      everyElement(FindingKind.itemFieldMissing),
    );
    expect(
      found.map((f) => f.line),
      everyElement(lineOfFirst(_project, loginFr, '- **R1**')),
    );
    expect(
      found.map((f) => f.toJson()['field']),
      unorderedEquals(['Enforcer', 'Consistency']),
    );
  });

  test('a doc type that sets neither key runs no item-field rule', () async {
    final project = await writeCheckProject(
      extra: _withRationale('- **R1** Refuse it.', behavior: true),
    );
    expect(
      (await checkOf(project)).findings
          .where((f) => _fieldKinds.contains(f.kind)),
      isEmpty,
    );
  });

  test('a layer of another doc type sets item_fields with no doc type id '
      'named', () async {
    _project = await writeCheckProject(
      extra: {
        '.specstone/templates/user_story.yaml': '''
sections:
  - id: rules
    lint:
      item_fields:
        - field: Enforcer
        - field: Consistency
          values: [immediate, eventual]
''',
        ...doc(
          loginStory,
          '## Acceptance Criteria',
          '## Rules\n\n- **BR-01** Refuse it.\n  - **Enforcer:** CheckRun\n\n'
              '## Acceptance Criteria',
        ),
      },
    );
    final found = [
      for (final f in (await checkOf(_project)).findings)
        if (_fieldKinds.contains(f.kind)) f,
    ];
    expect(found.map((f) => (f.kind, f.path, f.toJson()['field'])), [
      (FindingKind.itemFieldMissing, loginStory, 'Consistency'),
    ]);
  });

  group('the shipped domain invariants', () {
    const domainKinds = {
      FindingKind.itemFieldMissing,
      FindingKind.itemFieldUnneeded,
      FindingKind.sectionUndeclared,
    };

    Future<List<Finding>> domainFindings(
      String invariants, {
      String after = '',
    }) async {
      _project = await writeCheckProject(
        extra: {
          _domainPath:
              '# Login domain\n\n## Entities\n- Account\n\n'
              '## Invariants\n$invariants\n$after',
        },
      );
      return [
        for (final f in (await checkOf(_project)).findings)
          if (domainKinds.contains(f.kind)) f,
      ];
    }

    int domainLineOf(String needle) =>
        File('${_project.path}/$_domainPath')
            .readAsLinesSync()
            .indexWhere((line) => line.contains(needle)) +
        1;

    test('an eventual invariant with no corrective policy is reported at its '
        'line', () async {
      final found = await domainFindings(_eventual);
      expect(found, hasLength(1));
      expect(found.single.kind, FindingKind.itemFieldMissing);
      expect(found.single.toJson(), containsPair('field', 'Corrective policy'));
      expect(found.single.line, domainLineOf('- **INV-1**'));
    });

    test('an immediate invariant with a corrective policy is reported as not '
        'needing it', () async {
      final found = await domainFindings('$_immediate\n$_policy');
      expect(found, hasLength(1));
      expect(found.single.kind, FindingKind.itemFieldUnneeded);
      expect(found.single.toJson(), containsPair('field', 'Corrective policy'));
      expect(found.single.line, domainLineOf('- **INV-2**'));
    });

    test('an eventual invariant with its corrective policy and an immediate '
        'one without have no item-field finding', () async {
      expect(
        await domainFindings('$_eventual\n$_policy\n$_immediate'),
        isEmpty,
      );
    });

    test('a project entry for Corrective policy with no when makes every '
        'invariant need one', () async {
      const layer = '''
sections:
  - id: invariants
    lint:
      item_fields:
        add:
          - field: Corrective policy
''';
      _project = await writeCheckProject(
        extra: {
          '.specstone/templates/domain.yaml': layer,
          _domainPath:
              '# Login domain\n\n## Entities\n- Account\n\n'
              '## Invariants\n$_eventual\n$_policy\n$_immediate\n',
        },
      );
      final found = [
        for (final f in (await checkOf(_project)).findings)
          if (domainKinds.contains(f.kind)) f,
      ];
      expect(found, hasLength(1));
      expect(found.single.kind, FindingKind.itemFieldMissing);
      expect(found.single.toJson(), containsPair('field', 'Corrective policy'));
      expect(found.single.line, domainLineOf('- **INV-2**'));
    });

    test('a leftover corrective policies section is undeclared and its '
        'invariant still lacks the field', () async {
      final found = await domainFindings(
        _eventual,
        after: '## Corrective policies\n- **INV-1** Sweep expired links.\n',
      );
      expect(found.map((f) => f.kind), [
        FindingKind.itemFieldMissing,
        FindingKind.sectionUndeclared,
      ]);
      expect(found.last.line, domainLineOf('## Corrective policies'));
    });
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
      expect(result.single.line, lineOfFirst(_project, loginFr, '- **R1**'));
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
      expect(result.single.line, lineOfFirst(_project, loginFr, '- **R1**'));
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

    test('an item with neither Consistency nor the conditional field is '
        'missing only Consistency', () async {
      final result = await found('- **R1** Refuse it.');
      expect(result.map((f) => (f.kind, f.toJson()['field'])), [
        (FindingKind.itemFieldMissing, 'Consistency'),
      ]);
    });

    test(
      'an unmet item holding a field text outside values is unneeded',
      () async {
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
        final result = await found(
          '- **R1** Refuse it.\n'
          '  - **Consistency:** immediate\n'
          '  - **Policy:** later',
          layer: layer,
        );
        expect(result.map((f) => (f.kind, f.toJson()['field'])), [
          (FindingKind.itemFieldUnneeded, 'Policy'),
        ]);
      },
    );

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
