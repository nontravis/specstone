// The test titles and literals are plan values kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:io';

import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/check_report.dart';
import 'package:specstone_core/src/consistency_check/feature_pattern_rules.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/consistency_check/models/skip_line.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/index_fixture.dart' show openSession;
import '../../helpers/shipped_pins.dart';

const _patternsField =
    'fields:\n  - id: patterns\n    type: string\n    list: true\n';
const _noPatternsField = 'fields:\n  - id: patterns\n    disabled: true\n';

const _signIn = '''
id: sign_in
description: Sign-in checklist.
items:
  - id: lockout
    text: Name the lockout rule.
  - id: reset
    text: Name the reset path.
''';

const _signUp = '''
id: sign_up
description: Sign-up checklist.
extends: sign_in
items:
  - id: verify
    text: Name the email check.
''';

const _crudWithoutPaging = '''
id: crud
items:
  - id: paged_list
    disabled: true
''';

const _outOfScope = '## Out-of-scope\n\n- Social sign-in — not planned\n';

const Set<FindingKind> _kinds = {
  FindingKind.featurePatternMissing,
  FindingKind.featurePatternItemMissing,
};

/// The login feature listing [patterns] one per line, with [skips] added
/// under its Out-of-scope section.
Map<String, String> _feature(
  List<String> patterns, [
  List<String> skips = const [],
]) => edit(loginFeature, [
  (
    'goals:\n  - PG-01\n',
    'goals:\n  - PG-01\npatterns:\n${[for (final id in patterns) '  - $id\n'].join()}',
  ),
  (_outOfScope, '$_outOfScope${[for (final skip in skips) '$skip\n'].join()}'),
]);

Future<Directory> _project({
  List<String> patterns = const ['crud'],
  List<String> skips = const [],
  Map<String, String> files = const {},
}) => writeCheckProject(
  extra: {
    '.specstone/templates/feature.yaml': _patternsField,
    ..._feature(patterns, skips),
    ...files,
  },
);

/// The findings of this rule's kinds.
List<Finding> _found(CheckReport report) => [
  for (final finding in report.findings)
    if (_kinds.contains(finding.kind)) finding,
];

/// The skip lines of the login feature of [project], read as the rule reads
/// them.
Map<int, SkipLine> _skipsOf(Directory project) {
  final session = openSession(project);
  try {
    final context = CheckContext(session);
    return skipLinesOf(context, context.index.at(loginFeature)!);
  } finally {
    session.close();
  }
}

void main() {
  test('skipLinesOf keys each skip line by its file line, with its pattern, item, and span', () async {
    final project = await _project(
      patterns: ['crud', 'auth'],
      skips: [
        '- `crud/paged_list` — one page is enough',
        '- `auth/lockout` — no lockout',
        '- `other/x` — not listed',
      ],
    );
    final first = lineOfFirst(project, loginFeature, 'crud/paged_list');

    expect(_skipsOf(project), {
      first: SkipLine(
        line: first,
        pattern: 'crud',
        item: 'paged_list',
        span: 'crud/paged_list',
      ),
      first + 1: SkipLine(
        line: first + 1,
        pattern: 'auth',
        item: 'lockout',
        span: 'auth/lockout',
      ),
    });
  });

  test(
    'skipLinesOf is empty for a doc whose type carries no patterns field',
    () async {
      final project = await writeCheckProject(
        extra: {
          '.specstone/templates/feature.yaml': _noPatternsField,
          ..._feature(['crud'], ['- `crud/paged_list` — one page is enough']),
        },
      );

      expect(_skipsOf(project), isEmpty);
    },
  );

  test(
    'isSkipSpan holds for the span at the skip line and for nothing else',
    () async {
      final project = await _project(
        skips: ['- `crud/paged_list` — one page is enough'],
      );
      final skips = _skipsOf(project);
      final line = lineOfFirst(project, loginFeature, 'crud/paged_list');

      expect(isSkipSpan(skips, line, 'crud/paged_list'), isTrue);
      expect(isSkipSpan(skips, line, 'crud/other'), isFalse);
      expect(isSkipSpan(skips, line + 1, 'crud/paged_list'), isFalse);
      expect(isSkipSpan(const {}, line, 'crud/paged_list'), isFalse);
    },
  );

  test(
    'a held skipped item, and an unskipped one, give no finding of any rule',
    () async {
      final project = await _project(
        skips: ['- `crud/paged_list` — one page is enough'],
      );

      expect(spots(await checkOf(project)), isEmpty);
    },
  );

  test('a skipped item its feature pattern does not hold is feature_pattern_item_missing at the bullet', () async {
    final project = await _project(
      skips: ['- `crud/paged_lis` — one page is enough'],
    );

    final found = _found(await checkOf(project));

    expect(found, hasLength(1));
    expect(found.single.kind, FindingKind.featurePatternItemMissing);
    expect(found.single.path, loginFeature);
    expect(found.single.name, 'login');
    expect(found.single.line, lineOfFirst(project, loginFeature, 'paged_lis'));
    expect(found.single.waitsFor, WaitsFor.agent);
    expect(found.single.toJson(), containsPair('pattern', 'crud'));
    expect(found.single.toJson(), containsPair('item', 'paged_lis'));
  });

  test('a patterns value no merged feature pattern holds is feature_pattern_missing at its line, and its skip lines add none', () async {
    final project = await _project(
      patterns: ['crud', 'cruds'],
      skips: ['- `cruds/paged_list` — one page is enough'],
    );

    final found = _found(await checkOf(project));

    expect(found, hasLength(1));
    expect(found.single.kind, FindingKind.featurePatternMissing);
    expect(found.single.line, lineOfFirst(project, loginFeature, '- cruds'));
    expect(found.single.waitsFor, WaitsFor.agent);
    expect(found.single.toJson(), containsPair('pattern', 'cruds'));
    expect(found.single.toJson().containsKey('item'), isFalse);
  });

  test('an item a pattern takes through extends is held, one a pattern it extends lacks is not', () async {
    final project = await _project(
      patterns: ['sign_in', 'sign_up'],
      skips: [
        '- `sign_up/lockout` — signed up by invitation',
        '- `sign_in/lockout` — no lockout',
        '- `sign_in/verify` — no email check',
      ],
      files: {
        '.specstone/templates/patterns/sign_in.yaml': _signIn,
        '.specstone/templates/patterns/sign_up.yaml': _signUp,
      },
    );

    final found = _found(await checkOf(project));

    expect(
      [for (final f in found) f.line],
      [lineOfFirst(project, loginFeature, 'sign_in/verify')],
    );
    expect(found.single.toJson(), containsPair('pattern', 'sign_in'));
    expect(found.single.toJson(), containsPair('item', 'verify'));
  });

  test(
    'an item a project layer disables is feature_pattern_item_missing',
    () async {
      final project = await _project(
        skips: ['- `crud/paged_list` — one page is enough'],
        files: {'.specstone/templates/patterns/crud.yaml': _crudWithoutPaging},
      );

      final found = _found(await checkOf(project));

      expect(found.map((f) => f.kind), [FindingKind.featurePatternItemMissing]);
      expect(found.single.toJson(), containsPair('item', 'paged_list'));
    },
  );

  test('a project that pins only prd-core holds no feature pattern, so each value is feature_pattern_missing', () async {
    final project = await _project(
      patterns: ['crud', 'auth'],
      files: {
        '.specstone/config.yaml': shippedPinsConfig(['prd-core']),
      },
    );

    final found = _found(await checkOf(project));

    expect(found.map((f) => f.kind), [
      FindingKind.featurePatternMissing,
      FindingKind.featurePatternMissing,
    ]);
    expect(found.map((f) => f.toJson()['pattern']), ['crud', 'auth']);
    expect(found.map((f) => f.line), [
      lineOfFirst(project, loginFeature, '- crud'),
      lineOfFirst(project, loginFeature, '- auth'),
    ]);
  });

  test(
    'another doc type that carries the field is checked the same way',
    () async {
      final project = await writeCheckProject(
        extra: {
          '.specstone/templates/user_story.yaml':
              '$_patternsField'
              'sections:\n  - id: out_of_scope\n    header: Out-of-scope\n',
          ...edit(loginStory, [
            (
              'goals:\n  - PG-01\n',
              'goals:\n  - PG-01\npatterns:\n  - cruds\n  - crud\n',
            ),
            (
              'the sign-in refused',
              'the sign-in refused\n\n## Out-of-scope\n\n- `crud/paged_lis` — one page is enough\n- `crud/paged_list` — one page is enough',
            ),
          ]),
        },
      );

      final found = _found(await checkOf(project));

      expect(found.map((f) => f.path).toSet(), {loginStory});
      expect(found.map((f) => f.kind), [
        FindingKind.featurePatternMissing,
        FindingKind.featurePatternItemMissing,
      ]);
      expect(found.map((f) => f.toJson()['pattern']), ['cruds', 'crud']);
    },
  );

  test(
    'a doc type without the patterns field reads no value and no skip line',
    () async {
      final project = await writeCheckProject(
        extra: {
          '.specstone/templates/feature.yaml': _noPatternsField,
          ..._feature(['cruds'], ['- `crud/paged_lis` — one page is enough']),
        },
      );

      expect(_found(await checkOf(project)), isEmpty);
    },
  );

  test(
    'a patterns value that is no string gives no crash and no finding',
    () async {
      for (final written in [
        'patterns: 5\n',
        'patterns:\n  - 12\n  - [crud]\n  - {a: b}\n  -\n',
        'patterns:\n  - crud: x\n',
      ]) {
        final project = await writeCheckProject(
          extra: {
            '.specstone/templates/feature.yaml': _patternsField,
            ...edit(loginFeature, [
              ('goals:\n  - PG-01\n', 'goals:\n  - PG-01\n$written'),
            ]),
          },
        );

        expect(_found(await checkOf(project)), isEmpty, reason: written);
      }
    },
  );

  test('a bullet whose separator is a hyphen or two is no skip line', () async {
    final project = await _project(
      skips: [
        '- `crud/paged_lis` - one page is enough',
        '- `crud/paged_lis` -- one page is enough',
        '- `crud/paged_lis`',
      ],
    );

    expect(_found(await checkOf(project)), isEmpty);
  });

  test('a bullet naming a pattern the doc does not list, text before the span, and a fenced bullet are no skip lines', () async {
    final project = await _project(
      skips: [
        '- `auth/lockout` — not this feature',
        '- see `crud/paged_lis` — one page is enough',
        '',
        '```text',
        '- `crud/paged_lis` — in a fence',
        '```',
      ],
    );

    expect(_found(await checkOf(project)), isEmpty);
  });

  test(
    'a skip line is read from the first span only, and a star bullet counts',
    () async {
      final project = await _project(
        skips: ['* `crud/paged_lis` — instead of `crud/paged_list`'],
      );

      final found = _found(await checkOf(project));

      expect(found.map((f) => f.toJson()['item']), ['paged_lis']);
    },
  );
}
