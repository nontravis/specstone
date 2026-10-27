import 'dart:convert';

import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/doc_type_merger.dart';
import 'package:specstone_core/src/templates/layer.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:test/test.dart';

const _shippedFile = 'packs/prd-core/feature.yaml';
const _projectFile = '.specstone/templates/feature.yaml';

const _featureLayer = '''
description: A feature groups the stories that serve one goal.
path: prds/features/f{nn}_{slug}/FEATURE.md
fields:
  - id: slug
    description: Search aliases of the doc.
  - id: status
    required: true
    description: Lifecycle of the feature.
  - id: draft
    description: Content the Owner has not approved.
  - id: reference
    description: Reference docs the doc cites.
sections:
  - id: goal
    header: Feature goal
    required: true
    description: Why, problem, and audience, one sentence each.
    template: |-
      - **Why:**
      - **Problem:**
      - **Audience:**
    lint:
      max_lines: 5
  - id: scope
    header: Out-of-scope
    description: At most five one-line bullets, each naming its owner.
lint:
  max_chars: 12000
  max_lines: 300
  banned_words: [fast, robust]
  allowed_words: []
reference:
  - title: NASA Systems Engineering Handbook
    locator: Appendix C
''';

final class _NoFiles implements LayerFiles {
  const new();

  @override
  bool exists(String layerRelativePath) => false;
}

const _merger = DocTypeMerger();

DocTypeLayer _layer(String text, {LayerKind kind = LayerKind.shipped}) =>
    DocTypeLayer.parse(
      text,
      file: kind == LayerKind.shipped ? _shippedFile : _projectFile,
      docTypeId: 'feature',
      kind: kind,
      files: const _NoFiles(),
    );

MergedDocType _merge(String shipped, [String? project]) {
  final base = _merger.apply(_merger.builtInBase('feature'), _layer(shipped));
  return project == null
      ? base
      : _merger.apply(base, _layer(project, kind: LayerKind.project));
}

/// The doc type behind the s02 `specstone guide <type> --json` example, with
/// the `scope` section the s02 `specstone guide <type>` example adds.
MergedDocType featureDocType() => _merge(_featureLayer);

/// The s02 `specstone guide <type> --json` success example, with its `scope`
/// section removed (the example holds `goal` only).
final s02FeatureJson = <String, Object>{
  'id': 'feature',
  'description': 'A feature groups the stories that serve one goal.',
  'path': 'prds/features/f{nn}_{slug}/FEATURE.md',
  'fields': [
    {
      'id': 'slug',
      'type': 'string',
      'list': true,
      'description': 'Search aliases of the doc.',
    },
    {
      'id': 'status',
      'type': 'enum',
      'required': true,
      'enum': ['planned', 'implemented', 'deprecated'],
      'description': 'Lifecycle of the feature.',
    },
    {
      'id': 'draft',
      'type': 'boolean',
      'description': 'Content the Owner has not approved.',
    },
    {
      'id': 'reference',
      'type': 'doc_ref',
      'list': true,
      'description': 'Reference docs the doc cites.',
    },
  ],
  'sections': [
    {
      'id': 'goal',
      'required': true,
      'header': 'Feature goal',
      'description': 'Why, problem, and audience, one sentence each.',
      'template': '- **Why:**\n- **Problem:**\n- **Audience:**',
      'lint': {'maxLines': 5},
    },
  ],
  'lint': {
    'maxChars': 12000,
    'maxLines': 300,
    'bannedWords': ['fast', 'robust'],
    'allowedWords': <String>[],
  },
  'reference': [
    {'title': 'NASA Systems Engineering Handbook', 'locator': 'Appendix C'},
  ],
};

const _s02Guide = '''
A feature groups the stories that serve one goal.

## Feature goal

Why, problem, and audience, one sentence each.

## Out-of-scope

At most five one-line bullets, each naming its owner.
''';

/// Returns every value reachable in [node], to look for a `null`.
Iterable<Object?> _leaves(Object? node) => switch (node) {
  Map<String, Object?>() => node.values.expand(_leaves),
  List<Object?>() => node.expand(_leaves),
  _ => [node],
};

void main() {
  group('MergedDocType.toJson', () {
    test('f03/us01/fr03: the merged schema matches the s02 example', () {
      final json = _merge(
        _featureLayer,
        'sections: [{id: scope, disabled: true}]',
      ).toJson();

      expect(json, s02FeatureJson);
      expect(jsonEncode(json), jsonEncode(s02FeatureJson));
    });

    test('f03/us01/s3, f03/us01/fr03/e02: a disabled section has no JSON '
        'entry', () {
      final json = _merge(
        _featureLayer,
        'sections: [{id: goal, disabled: true}]',
      ).toJson();

      final sections = json['sections']! as List<Object?>;
      expect(sections.cast<Map<String, Object>>().map((s) => s['id']), [
        'scope',
      ]);
    });

    test('f03/us01/fr03/e03: banned words changed by add and remove print as '
        'one list', () {
      final json = _merge(
        _featureLayer,
        'lint: {banned_words: {add: [simply], remove: [fast]}}',
      ).toJson();

      final lint = json['lint']! as Map<String, Object>;
      expect(lint['bannedWords'], ['robust', 'simply']);
    });

    test('f03/us01/fr03/e05: extends and prefixId are absent when unset, and '
        'no value is null', () {
      final json = featureDocType().toJson();

      expect(json.containsKey('extends'), isFalse);
      final sections = (json['sections']! as List<Object?>)
          .cast<Map<String, Object>>();
      expect(sections.any((s) => s.containsKey('prefixId')), isFalse);
      expect(_leaves(json), everyElement(isNotNull));
    });

    test('f03/us01/fr03/e05: extends and prefixId print when set', () {
      final json = _merge(
        _featureLayer,
        'extends: base\nsections: [{id: goal, prefix_id: G}]',
      ).toJson();

      expect(json['extends'], 'base');
      final goal =
          (json['sections']! as List<Object?>).first! as Map<String, Object>;
      expect(goal.keys, [
        'id',
        'prefixId',
        'required',
        'header',
        'description',
        'template',
        'lint',
      ]);
      expect(goal['prefixId'], 'G');
    });

    test('f03/us01/fr03/e05: a doc type with no lint, reference, or '
        'section lint omits those keys', () {
      final json = _merge('description: Bare\npath: bare.md').toJson();

      expect(json.keys, ['id', 'description', 'path', 'fields', 'sections']);
      expect(json['sections'], isEmpty);
    });

    test('f03/us01/fr03/e05: a false list and required are absent', () {
      final json = featureDocType().toJson();

      final draft = (json['fields']! as List<Object?>)
          .cast<Map<String, Object>>()
          .singleWhere((f) => f['id'] == 'draft');
      expect(draft.keys, ['id', 'type', 'description']);
    });

    test('f03/us01/fr03: an output_ref field prints pointer between docTypes '
        'and description', () {
      final json = _merge(
        _featureLayer,
        'fields: [{id: covers, type: output_ref, list: true, required: true, '
        'pointer: prefix, description: Code paths the doc covers.}]',
      ).toJson();

      final covers = (json['fields']! as List<Object?>)
          .cast<Map<String, Object>>()
          .singleWhere((f) => f['id'] == 'covers');
      expect(covers, {
        'id': 'covers',
        'type': 'output_ref',
        'list': true,
        'required': true,
        'pointer': 'prefix',
        'description': 'Code paths the doc covers.',
      });
      expect(covers.keys, [
        'id',
        'type',
        'list',
        'required',
        'pointer',
        'description',
      ]);
    });

    test('f03/us01/fr03/e05: a field with no pointer prints no pointer '
        'key', () {
      final fields = (featureDocType().toJson()['fields']! as List<Object?>)
          .cast<Map<String, Object>>();

      expect(fields.where((f) => f.containsKey('pointer')), isEmpty);
    });

    test('f03/us01/fr03: bundle prints right after path and query right after '
        'lint', () {
      const docType = MergedDocType(
        id: 'feature',
        path: 'f{nn}_{slug}.md',
        bundle: ['query'],
        fields: [],
        lint: MergedLint(),
        files: [],
        sections: [
          MergedSection(id: 'goal', header: 'Goal', maxLines: 5, query: true),
        ],
      );
      final json = docType.toJson();
      expect(json.keys.toList(), [
        'id',
        'path',
        'bundle',
        'fields',
        'sections',
      ]);
      expect((json['sections']! as List<Object?>).single, {
        'id': 'goal',
        'header': 'Goal',
        'lint': {'maxLines': 5},
        'query': true,
      });
    });

    test('f03/us01/fr03: no bundle and no query print no key, as E05 says', () {
      const docType = MergedDocType(
        id: 'feature',
        fields: [],
        lint: MergedLint(),
        files: [],
        sections: [MergedSection(id: 'goal', header: 'Goal')],
      );
      expect(docType.toJson().containsKey('bundle'), isFalse);
      expect((docType.toJson()['sections']! as List<Object?>).single, {
        'id': 'goal',
        'header': 'Goal',
      });
    });
  });

  group('MergedDocType.renderGuide', () {
    test('f03/us01/s1, f03/us01/fr02: the guide matches the s02 example for '
        'goal and scope', () {
      expect(featureDocType().renderGuide(), _s02Guide);
    });

    test('f03/us01/s3, f03/us01/fr02/e02: a disabled section has no ## '
        'line', () {
      final guide = _merge(
        _featureLayer,
        'sections: [{id: goal, disabled: true}]',
      ).renderGuide();

      expect(guide, isNot(contains('Feature goal')));
      expect(guide, contains('## Out-of-scope'));
    });

    test('f03/us01/fr02: a section with no description prints its header '
        'alone', () {
      final guide = _merge(
        'description: A.\npath: a.md\nsections: [{id: s, header: S}]',
      ).renderGuide();

      expect(guide, 'A.\n\n## S\n');
    });

    test('f03/us01/fr02: a section with an empty description prints its '
        'header alone', () {
      final guide = _merge(
        'description: A.\npath: a.md\n'
        "sections: [{id: s, header: S, description: ''}]",
      ).renderGuide();

      expect(guide, 'A.\n\n## S\n');
    });

    test('f03/us01/fr02: an empty doc description adds no blank paragraph', () {
      final guide = _merge(
        "description: ''\npath: a.md\nsections: [{id: s, header: S}]",
      ).renderGuide();

      expect(guide, '## S\n');
    });

    test('f03/us01/fr02: a doc type with an empty description and no sections '
        'renders nothing', () {
      expect(_merge("description: ''\npath: a.md").renderGuide(), '');
    });
  });

  test('f03/us02/fr03: a section prints the lint keys a layer sets, and no '
      'lint when none is set', () {
    const section = MergedSection(
      id: 'statement',
      header: 'Statement',
      maxLines: 5,
      bannedWords: ['fast'],
      allowedWords: ['API'],
      linePrefix: '- **Statement:**',
    );
    expect(section.toJson()['lint'], {
      'maxLines': 5,
      'bannedWords': ['fast'],
      'allowedWords': ['API'],
      'linePrefix': '- **Statement:**',
    });
    expect(
      const MergedSection(id: 'a', header: 'A').toJson().containsKey('lint'),
      isFalse,
    );
  });
}
