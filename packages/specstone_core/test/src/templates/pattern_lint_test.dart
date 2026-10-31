import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:specstone_core/src/templates/pattern_entry.dart';
import 'package:specstone_core/src/templates/template_fault.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';

import '../../helpers/fixture_doc_types.dart';
import '../../helpers/prd_core.dart';

const _projectFile = '.specstone/templates/feature.yaml';

const _lowerFeature = '''
id: feature
description: A feature groups the stories that serve one goal.
path: prds/features/f{nn}_{slug}/FEATURE.md
fields:
  - id: vision
    type: string
    list: true
  - id: goals
    type: string
    list: true
sections:
  - id: goal
    header: Feature goal
    required: true
lint:
  banned_patterns:
    - id: a
      pattern: 'old'
      message: lower a
    - id: b
      pattern: 'bee'
      message: lower b
  required_field_groups:
    - [vision]
''';

/// Resolves the fixture set with [project] written as the project feature
/// layer, on top of [shipped] when given.
Future<MergedSet> _resolve({String? shipped, required String project}) async {
  final root = await fixtureProject({_projectFile: project});
  return TemplateResolver(
    shippedFiles: fixturePackFiles(extra: {'feature.yaml': ?shipped}),
  ).resolve(workingDirectory: root, homeDirectory: null);
}

Future<void> _expectFault(
  Future<Object?> run, {
  required FaultCode code,
  String? keyEndsWith,
}) => expectLater(
  run,
  throwsA(
    isA<TemplateFault>()
        .having((f) => f.code, 'code', code)
        .having(
          (f) => f.key ?? '',
          'key',
          keyEndsWith == null ? anything : endsWith(keyEndsWith),
        ),
  ),
);

void main() {
  test('f03/us03/fr01: banned_patterns, required_patterns, and '
      'required_field_groups parse', () async {
    final set = await _resolve(
      project: '''
fields:
  - id: goals
    type: string
    list: true
lint:
  banned_patterns:
    - id: a
      pattern: 'x+'
      message: m
      in: code
      except: ['xx']
  required_field_groups:
    - [vision, goals]
sections:
  - id: goal
    lint:
      required_patterns:
        - id: r
          pattern: '^y'
          message: n
''',
    );
    final type = set.lookup('feature')!;

    expect(type.lint.bannedPatterns!.single.scope, PatternScope.code);
    expect(type.lint.bannedPatterns!.single.except, ['xx']);
    expect(type.lint.requiredFieldGroups, [
      ['vision', 'goals'],
    ]);
    expect(sectionOf(type, 'goal').requiredPatterns!.single.id, 'r');
    final lintJson = type.toJson()['lint']! as Map<String, Object?>;
    expect(lintJson, contains('bannedPatterns'));
    expect(lintJson, contains('requiredFieldGroups'));
  });

  test('f03/us03/fr01/e24: a bad regex is unknown_value', () async {
    await _expectFault(
      _resolve(
        project: '''
lint:
  banned_patterns:
    - id: a
      pattern: '(['
      message: m
''',
      ),
      code: FaultCode.unknownValue,
      keyEndsWith: 'banned_patterns[0].pattern',
    );
  });

  test('f03/us03/fr01/e24: a bad except regex is unknown_value', () async {
    await _expectFault(
      _resolve(
        project: '''
lint:
  banned_patterns:
    - id: a
      pattern: 'x'
      message: m
      except: ['(']
''',
      ),
      code: FaultCode.unknownValue,
      keyEndsWith: 'banned_patterns[0].except',
    );
  });

  test(
    'f03/us03/fr01/e25: an in outside text, code, all is unknown_value',
    () async {
      await _expectFault(
        _resolve(
          project: '''
lint:
  banned_patterns:
    - id: a
      pattern: 'x'
      message: m
      in: html
''',
        ),
        code: FaultCode.unknownValue,
        keyEndsWith: 'banned_patterns[0].in',
      );
    },
  );

  test('f03/us03/fr01/e27: an entry without message is missing_key', () async {
    await _expectFault(
      _resolve(
        project: '''
lint:
  banned_patterns:
    - id: a
      pattern: 'x'
''',
      ),
      code: FaultCode.missingKey,
      keyEndsWith: 'banned_patterns[0].message',
    );
  });

  test(
    'f03/us03/fr01: a required_patterns entry with in is unknown_key',
    () async {
      await _expectFault(
        _resolve(
          project: '''
sections:
  - id: goal
    lint:
      required_patterns:
        - id: r
          pattern: 'y'
          message: n
          in: code
''',
        ),
        code: FaultCode.unknownKey,
        keyEndsWith: 'required_patterns[0].in',
      );
    },
  );

  test('f03/us03/fr01/e26: a group naming no field of the merged type is '
      'unknown_value', () async {
    await _expectFault(
      _resolve(
        project: '''
lint:
  required_field_groups:
    - [vision, nope]
''',
      ),
      code: FaultCode.unknownValue,
      keyEndsWith: 'lint.required_field_groups',
    );
  });

  test('f03/us02/fr03/e10: add replaces an entry with the same id and remove '
      'drops one', () async {
    final set = await _resolve(
      shipped: _lowerFeature,
      project: '''
lint:
  banned_patterns:
    add:
      - id: a
        pattern: 'new'
        message: upper a
    remove: [b]
''',
    );
    final patterns = set.lookup('feature')!.lint.bannedPatterns!;

    expect([for (final p in patterns) p.id], ['a']);
    expect(patterns.single.pattern, 'new');
  });

  test('f03/us02/fr03/e11: remove of an id no lower layer holds is '
      'override_id_not_found', () async {
    await _expectFault(
      _resolve(
        shipped: _lowerFeature,
        project: '''
lint:
  banned_patterns:
    remove: [zzz]
''',
      ),
      code: FaultCode.overrideIdNotFound,
    );
  });

  test('f03/us02/fr03/e12: a plain list over a lower list is '
      'list_override_needs_add_remove', () async {
    await _expectFault(
      _resolve(
        shipped: _lowerFeature,
        project: '''
lint:
  banned_patterns:
    - id: c
      pattern: 'c'
      message: m
''',
      ),
      code: FaultCode.listOverrideNeedsAddRemove,
    );
  });

  test('f03/us02/fr03/e14: an upper required_field_groups replaces the lower '
      'value', () async {
    final set = await _resolve(
      shipped: _lowerFeature,
      project: '''
lint:
  required_field_groups:
    - [goals]
''',
    );

    expect(set.lookup('feature')!.lint.requiredFieldGroups, [
      ['goals'],
    ]);
  });

  test('f03/us02/fr03: section pattern lists merge per section id', () async {
    final set = await _resolve(
      shipped: '''
id: feature
description: d
path: prds/features/f{nn}_{slug}/FEATURE.md
sections:
  - id: goal
    header: Feature goal
    lint:
      banned_patterns:
        - id: s1
          pattern: 'p'
          message: m
''',
      project: '''
sections:
  - id: goal
    lint:
      banned_patterns:
        add:
          - id: s2
            pattern: 'q'
            message: m2
''',
    );

    expect(
      [
        for (final p in sectionOf(
          set.lookup('feature')!,
          'goal',
        ).bannedPatterns!)
          p.id,
      ],
      ['s1', 's2'],
    );
  });

  test('f03/us03/fr01: PatternEntry matches, excepts by full match, and '
      'prints JSON', () {
    final entry = PatternEntry(
      id: 'a',
      pattern: r'\bfoo\w*',
      message: 'm',
      except: ['foobar'],
    );

    expect(entry.regExp.hasMatch('Foo'), isFalse);
    expect(entry.regExp.hasMatch('food'), isTrue);
    expect(entry.isExcepted('foobar'), isTrue);
    expect(entry.isExcepted('foobarx'), isFalse);
    expect(entry.toJson(), {
      'id': 'a',
      'pattern': r'\bfoo\w*',
      'message': 'm',
      'in': 'text',
      'except': ['foobar'],
    });
    expect(
      PatternEntry(id: 'b', pattern: 'x', message: 'm').toJson(),
      isNot(contains('except')),
    );
  });
}
