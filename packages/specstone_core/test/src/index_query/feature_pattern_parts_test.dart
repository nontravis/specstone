// The test titles and literals are plan values kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:io';

import 'package:specstone_core/src/index_query/bundle.dart';
import 'package:specstone_core/src/index_query/code_bundle.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/feature_pattern_parts.dart';
import 'package:specstone_core/src/index_query/models/feature_pattern_part.dart';
import 'package:specstone_core/src/index_query/read_session.dart';
import 'package:test/test.dart';

import '../../helpers/index_fixture.dart';
import '../../helpers/nested_fixture.dart';

const _patternsField =
    'fields:\n  - id: patterns\n    type: string\n    list: true\n';

const _outOfScopeSection =
    'sections:\n  - id: out_of_scope\n    header: Out-of-scope\n';

// The ids stay clear of the shipped feature patterns, which a project layer
// would merge over.
const _signIn = '''
id: sign_in
description: Sign-in checklist.
items:
  - id: lockout
    text: Name the lockout rule.
  - id: reset
    text: Name the reset path.
reference:
  - title: Handbook
    url: https://example.com/handbook
''';

const _records = '''
id: records
description: Record checklist.
items:
  - id: create
    text: Name the create path.
  - id: delete
    text: Name the delete path.
''';

const _signUp = '''
id: sign_up
description: Sign-up checklist.
extends: sign_in
items:
  - id: verify
    text: Name the email check.
''';

const _signUpRewrite = '''
id: sign_up
description: Sign-up checklist.
extends: sign_in
items:
  - id: lockout
    text: Name the sign-up lockout rule.
''';

Map<String, String> _patternFiles(Map<String, String> byId) => {
  for (final MapEntry(:key, :value) in byId.entries)
    '.specstone/templates/patterns/$key.yaml': value,
};

Map<String, String> get _allPatterns => _patternFiles({
  'sign_in': _signIn,
  'records': _records,
  'sign_up': _signUp,
});

String _featureWith(String title, Object? patterns) =>
    '---\nvision:\n  - PV-01\ngoals:\n  - PG-01\npatterns: $patterns\n---\n\n'
    '# $title\n\n## Problem\nNeeded.\n';

/// Each part as its pattern id, lister name, and item ids joined by spaces.
List<(String, String, String)> _summary(List<FeaturePatternPart> parts) => [
  for (final part in parts)
    (
      part.pattern.id,
      part.lister.name,
      [for (final item in part.items) item.id].join(' '),
    ),
];

List<FeaturePatternPart> _partsOf(
  DocIndex index,
  String target, {
  BundleMode mode = BundleMode.design,
}) {
  final bundle = pickBundle(index, target, mode, noProject: false);
  return featurePatternParts(index, bundle, bundle.printOrder(index));
}

Future<DocIndex> _loginWith(
  Object? patterns, {
  Map<String, String> files = const {},
}) => indexWith({
  '.specstone/templates/feature.yaml': _patternsField,
  featureKey: _featureWith('Login', patterns),
  ..._allPatterns,
  ...files,
});

void main() {
  test('patterns [sign_in, records] give the sign_in part, then the records part, after the feature', () async {
    final index = await _loginWith('[sign_in, records]');

    expect(_summary(_partsOf(index, 'login/email_login')), [
      ('sign_in', 'login', 'lockout reset'),
      ('records', 'login', 'create delete'),
    ]);
  });

  test(
    'a value that names no merged feature pattern gives no part and no fault',
    () async {
      final index = await _loginWith('[nothing, sign_in]');

      expect(_summary(_partsOf(index, 'login/email_login')), [
        ('sign_in', 'login', 'lockout reset'),
      ]);
    },
  );

  test(
    '[sign_up, sign_in] prints each shared item under sign_up only',
    () async {
      final index = await _loginWith('[sign_up, sign_in]');

      expect(_summary(_partsOf(index, 'login/email_login')), [
        ('sign_up', 'login', 'lockout reset verify'),
        ('sign_in', 'login', ''),
      ]);
    },
  );

  test('a later part drops the items an earlier part printed and shares through extends', () async {
    final index = await _loginWith('[sign_in, sign_up]');

    expect(_summary(_partsOf(index, 'login/email_login')), [
      ('sign_in', 'login', 'lockout reset'),
      ('sign_up', 'login', 'verify'),
    ]);
  });

  test('an item sign_up rewrites by id prints under both parts, each with its own text', () async {
    for (final order in ['sign_in, sign_up', 'sign_up, sign_in']) {
      final index = await _loginWith(
        '[$order]',
        files: _patternFiles({'sign_up': _signUpRewrite}),
      );

      final parts = _partsOf(index, 'login/email_login');
      expect(
        parts.map((p) => p.pattern.id).toList(),
        order.split(', '),
        reason: order,
      );
      final texts = {
        for (final part in parts)
          part.pattern.id: {for (final i in part.items) i.id: i.text},
      };
      expect(
        texts['sign_in']!['lockout'],
        'Name the lockout rule.',
        reason: order,
      );
      expect(
        texts['sign_up']!['lockout'],
        'Name the sign-up lockout rule.',
        reason: order,
      );
    }
  });

  test('a value written twice in one list prints one part', () async {
    final index = await _loginWith('[sign_in, sign_in, records, sign_in]');

    expect(_summary(_partsOf(index, 'login/email_login')).map((p) => p.$1), [
      'sign_in',
      'records',
    ]);
  });

  test('a value that is no string gives no crash and no part', () async {
    const cases = {
      '5': <String>[],
      '[1, [sign_in], {a: b}, true, sign_in]': ['sign_in'],
      '{sign_in: x}': <String>[],
      'null': <String>[],
    };
    for (final MapEntry(key: value, value: expected) in cases.entries) {
      final index = await _loginWith(value);

      final ids = _partsOf(index, 'login/email_login').map((p) => p.pattern.id);
      expect(ids, expected, reason: value);
    }
  });

  test(
    'any doc type with the patterns field lists parts, right after that doc',
    () async {
      final index = await indexWith({
        '.specstone/templates/user_story.yaml':
            '$_patternsField$_outOfScopeSection',
        'docs/prds/features/f01_login/us01_email_login/USER_STORY.md': '---\npatterns: [records]\ngoals:\n  - PG-01\n---\n\n# Agent signs in\n\n## Use Case\nSign in.\n',
        ..._allPatterns,
      });

      final parts = _partsOf(index, 'login/email_login');

      expect(_summary(parts), [
        ('records', 'login/email_login', 'create delete'),
      ]);
      expect(parts.single.lister.docTypeId, 'user_story');
    },
  );

  test(
    'a doc type without the patterns field lists no part, even with the value',
    () async {
      final index = await indexWith({
        '.specstone/templates/feature.yaml': _patternsField,
        'docs/prds/features/f01_login/us01_email_login/USER_STORY.md': '---\npatterns: [records]\ngoals:\n  - PG-01\n---\n\n# Agent signs in\n\n## Use Case\nSign in.\n',
        ..._allPatterns,
      });

      expect(_partsOf(index, 'login/email_login'), isEmpty);
    },
  );

  test('implement and query bundles give no part', () async {
    final index = await _loginWith('[sign_in]');

    expect(
      _partsOf(index, 'login/email_login', mode: BundleMode.implement),
      isEmpty,
    );
    expect(
      _partsOf(index, 'login/email_login', mode: BundleMode.query),
      isEmpty,
    );
  });

  test(
    'a project that loads no feature pattern named by its docs gives no part',
    () async {
      final index = await indexWith({
        '.specstone/templates/feature.yaml': _patternsField,
        featureKey: _featureWith('Login', '[unknown_pattern]'),
      });

      expect(_partsOf(index, 'login/email_login'), isEmpty);
    },
  );

  group('nested features', () {
    Future<DocIndex> shop(String parent, String sub) => nestedIndexWith({
      '.specstone/templates/feature.yaml': 'max_depth: 3\n$_patternsField',
      'docs/$shopFeature': _featureWith('Shop', parent),
      'docs/$cartFeature': _featureWith('Cart', sub),
      ..._allPatterns,
    });

    test('a parent and its sub-feature both listing records give one records part, right after the first', () async {
      final index = await shop('[records]', '[records, sign_in]');

      expect(_summary(_partsOf(index, 'shop/cart/add_item')), [
        ('records', 'shop', 'create delete'),
        ('sign_in', 'shop/cart', 'lockout reset'),
      ]);
    });

    test('the parent lists sign_in, the sub-feature sign_up: the sign_up part drops the sign_in items', () async {
      final index = await shop('[sign_in]', '[sign_up]');

      expect(_summary(_partsOf(index, 'shop/cart/add_item')), [
        ('sign_in', 'shop', 'lockout reset'),
        ('sign_up', 'shop/cart', 'verify'),
      ]);
    });
  });

  group('--code', () {
    late Directory project;
    late ReadSession session;
    late DocIndex index;
    setUp(() async {
      project = await writeLoginProject(
        extra: {
          ...loginRecords,
          '.specstone/templates/feature.yaml': _patternsField,
          featureKey: _featureWith('Login', '[records, sign_in]'),
          'docs/prds/features/f02_signup/FEATURE.md': _featureWith(
            'Sign up',
            '[records, sign_up]',
          ),
          ..._allPatterns,
        },
      );
      session = openSession(project);
      addTearDown(session.close);
      index = session.index;
    });

    test('two features bundled by one path, both listing records, give one records part after the first feature doc', () {
      final bundle = pickCodeBundle(
        index,
        resolveCodePath(
          'app/lib/src',
          workingDirectory: project,
          targets: session.project.targets,
          codeRootOf: session.project.codeRootOf,
        ),
        BundleMode.design,
        noProject: false,
      );

      final parts = featurePatternParts(
        index,
        bundle,
        bundle.printOrder(index),
      );

      expect(_summary(parts), [
        ('records', 'login', 'create delete'),
        ('sign_in', 'login', 'lockout reset'),
        ('sign_up', 'signup', 'verify'),
      ]);
    });
  });
}
