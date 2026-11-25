import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:specstone_core/src/templates/models/pattern_entry.dart';
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

const _lowerWithRequired = '''
id: feature
description: d
path: prds/features/f{nn}_{slug}/FEATURE.md
sections:
  - id: goal
    header: Feature goal
    lint:
      required_patterns:
        - id: r1
          pattern: 'x'
          message: lower r1
lint:
  banned_patterns:
    - id: a
      pattern: 'old'
      message: lower a
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

/// Runs [run] and returns the fault it throws.
Future<TemplateFault> _faultOf(Future<Object?> run) async {
  try {
    await run;
  } on TemplateFault catch (fault) {
    return fault;
  }
  throw StateError('the layers merged with no fault');
}

void main() {
  test('banned_patterns, required_patterns, and '
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

  test('a bad regex is unknown_value', () async {
    for (final (key, entry) in [
      ('pattern', "pattern: '(['\n      message: m"),
      ('except', "pattern: 'x'\n      message: m\n      except: ['(']"),
    ]) {
      await _expectFault(
        _resolve(
          project: 'lint:\n  banned_patterns:\n    - id: a\n      $entry\n',
        ),
        code: FaultCode.unknownValue,
        keyEndsWith: 'banned_patterns[0].$key',
      );
    }
  });

  test('an in outside text, code, all is unknown_value', () async {
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
  });

  test('an entry without message is missing_key', () async {
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
    'a required_patterns entry keeps its in scope, text when absent',
    () async {
      final set = await _resolve(
        shipped: _lowerFeature,
        project: '''
sections:
  - id: goal
    lint:
      required_patterns:
        - id: spanned
          pattern: 'y'
          message: n
          in: code
        - id: plain
          pattern: 'z'
          message: n
''',
      );
      final patterns = {
        for (final p
            in set
                .lookup('feature')!
                .sections
                .singleWhere((s) => s.id == 'goal')
                .requiredPatterns!)
          p.id: p.scope,
      };

      expect(patterns, {
        'spanned': PatternScope.code,
        'plain': PatternScope.text,
      });
    },
  );

  test('a required_patterns entry with except is unknown_key', () async {
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
          except: [y]
''',
      ),
      code: FaultCode.unknownKey,
      keyEndsWith: 'required_patterns[0].except',
    );
  });

  test('a group naming no field of the merged type is '
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

  test('add replaces an entry with the same id and remove '
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

  test('add of a new id and of a lower id leaves every other entry'
      ' unchanged', () async {
    final set = await _resolve(
      shipped: _lowerFeature,
      project: '''
lint:
  banned_patterns:
    add:
      - id: a
        pattern: 'new'
        message: upper a
''',
    );
    final patterns = {
      for (final p in set.lookup('feature')!.lint.bannedPatterns!) p.id: p,
    };

    expect(patterns.keys, unorderedEquals(['a', 'b']));
    expect(patterns['a']!.pattern, 'new');
    expect(patterns['b']!.pattern, 'bee');
    expect(patterns['b']!.message, 'lower b');
  });

  test(
    'a remove-only layer leaves every other pattern entry unchanged',
    () async {
      final set = await _resolve(
        shipped: _lowerFeature,
        project: '''
lint:
  banned_patterns:
    remove: [b]
''',
      );
      final patterns = set.lookup('feature')!.lint.bannedPatterns!;

      expect([for (final p in patterns) p.id], ['a']);
      expect(patterns.single.pattern, 'old');
      expect(patterns.single.message, 'lower a');
    },
  );

  test('a remove of an id no lower layer holds names the file and key'
      ' and exits 78', () async {
    final banned = await _faultOf(
      _resolve(
        shipped: _lowerWithRequired,
        project: '''
lint:
  banned_patterns:
    remove: [zzz]
''',
      ),
    );
    final required = await _faultOf(
      _resolve(
        shipped: _lowerWithRequired,
        project: '''
sections:
  - id: goal
    lint:
      required_patterns:
        remove: [zzz]
''',
      ),
    );

    expect(banned.code, FaultCode.overrideIdNotFound);
    expect(banned.file, _projectFile);
    expect(banned.key, 'lint.banned_patterns');
    expect(banned.exitStatus, 78);
    expect(required.code, FaultCode.overrideIdNotFound);
    expect(required.file, _projectFile);
    expect(required.key, 'sections.goal.lint.required_patterns');
    expect(required.exitStatus, 78);
  });

  test('a plain pattern list over a lower list names the file and key'
      ' and exits 78', () async {
    final banned = await _faultOf(
      _resolve(
        shipped: _lowerWithRequired,
        project: '''
lint:
  banned_patterns:
    - id: c
      pattern: 'c'
      message: m
''',
      ),
    );
    final required = await _faultOf(
      _resolve(
        shipped: _lowerWithRequired,
        project: '''
sections:
  - id: goal
    lint:
      required_patterns:
        - id: c
          pattern: 'c'
          message: m
''',
      ),
    );

    expect(banned.code, FaultCode.listOverrideNeedsAddRemove);
    expect(banned.file, _projectFile);
    expect(banned.key, 'lint.banned_patterns');
    expect(banned.exitStatus, 78);
    expect(required.code, FaultCode.listOverrideNeedsAddRemove);
    expect(required.file, _projectFile);
    expect(required.key, 'sections.goal.lint.required_patterns');
    expect(required.exitStatus, 78);
  });

  test('an upper required_field_groups replaces the lower '
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

  test('section pattern lists merge per section id', () async {
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

  test('PatternEntry matches, excepts by full match, and '
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
