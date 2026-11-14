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
  - id: approved
    description: The Owner approved the doc at least once; written only by approve and the hash stamps.
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
      'id': 'approved',
      'type': 'string',
      'description':
          'The Owner approved the doc at least once; '
          'written only by approve and the hash stamps.',
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

Banned words: `fast`, `robust`

## Feature goal

Why, problem, and audience, one sentence each.

Template:
```markdown
- **Why:**
- **Problem:**
- **Audience:**
```

## Out-of-scope

At most five one-line bullets, each naming its owner.

Guide sources:
- NASA Systems Engineering Handbook, Appendix C
''';

/// Returns every value reachable in [node], to look for a `null`.
Iterable<Object?> _leaves(Object? node) => switch (node) {
  Map<String, Object?>() => node.values.expand(_leaves),
  List<Object?>() => node.expand(_leaves),
  _ => [node],
};

void main() {
  group('MergedDocType.toJson', () {
    test('tpl-s03/inv28: toJson prints maxDepth right after path', () {
      final merged = _merge(_featureLayer, 'max_depth: 2');

      expect(merged.maxDepth, 2);
      expect(merged.nests, isTrue);
      expect(merged.toJson().keys.take(5), [
        'id',
        'description',
        'path',
        'maxDepth',
        'fields',
      ]);
      expect(merged.toJson()['maxDepth'], 2);
    });

    test('a per-target '
        'doc type prints perTarget right after maxDepth; one that is not '
        'prints no key', () {
      final perTarget = _merge(_featureLayer, 'max_depth: 2\nper_target: true');

      expect(perTarget.toJson().keys.take(6), [
        'id',
        'description',
        'path',
        'maxDepth',
        'perTarget',
        'fields',
      ]);
      expect(perTarget.toJson()['perTarget'], isTrue);
      expect(
        _merge(_featureLayer, 'per_target: false').toJson(),
        isNot(contains('perTarget')),
      );
    });

    test('tpl-s03/inv28: maxDepth 0 prints and does not nest; no key prints '
        'nothing', () {
      final flat = _merge(_featureLayer, 'max_depth: 0');
      expect(flat.toJson()['maxDepth'], 0);
      expect(flat.nests, isFalse);

      final unset = _merge(_featureLayer);
      expect(unset.toJson().containsKey('maxDepth'), isFalse);
      expect(unset.nests, isFalse);
    });

    test('E05: toJson '
        'prints maxItemChars only when a layer sets it', () {
      final unset = _merge(_featureLayer).toJson();
      expect(
        (unset['lint']! as Map<String, Object?>).containsKey('maxItemChars'),
        isFalse,
      );

      final set = _merge(_featureLayer, 'lint: {max_item_chars: 900}').toJson();
      expect((set['lint']! as Map<String, Object?>)['maxItemChars'], 900);
    });

    test('toJson prints titleNoNumber only when a layer sets it', () {
      final unset = _merge(_featureLayer).toJson();
      expect(
        (unset['lint']! as Map<String, Object?>).containsKey('titleNoNumber'),
        isFalse,
      );

      final set = _merge(
        _featureLayer,
        'lint: {title_no_number: true}',
      ).toJson();
      expect((set['lint']! as Map<String, Object?>)['titleNoNumber'], isTrue);
    });

    test('the merged schema matches the s02 example', () {
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

    test('banned words changed by add and remove print as '
        'one list', () {
      final json = _merge(
        _featureLayer,
        'lint: {banned_words: {add: [simply], remove: [fast]}}',
      ).toJson();

      final lint = json['lint']! as Map<String, Object>;
      expect(lint['bannedWords'], ['robust', 'simply']);
    });

    test('extends and prefixId are absent when unset, and '
        'no value is null', () {
      final json = featureDocType().toJson();

      expect(json.containsKey('extends'), isFalse);
      final sections = (json['sections']! as List<Object?>)
          .cast<Map<String, Object>>();
      expect(sections.any((s) => s.containsKey('prefixId')), isFalse);
      expect(_leaves(json), everyElement(isNotNull));
    });

    test('extends and prefixId print when set', () {
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

    test('a doc type with no lint, reference, or '
        'section lint omits those keys', () {
      final json = _merge('description: Bare\npath: bare.md').toJson();

      expect(json.keys, ['id', 'description', 'path', 'fields', 'sections']);
      expect(json['sections'], isEmpty);
    });

    test('a false list and required are absent', () {
      final json = featureDocType().toJson();

      final draft = (json['fields']! as List<Object?>)
          .cast<Map<String, Object>>()
          .singleWhere((f) => f['id'] == 'draft');
      expect(draft.keys, ['id', 'type', 'description']);
    });

    test('an output_ref field prints pointer between docTypes '
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

    test('a field with no pointer prints no pointer '
        'key', () {
      final fields = (featureDocType().toJson()['fields']! as List<Object?>)
          .cast<Map<String, Object>>();

      expect(fields.where((f) => f.containsKey('pointer')), isEmpty);
    });

    test('bundle prints right after path and query right after '
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

    test('f03/us01/fr03, db-r7: summary prints right after query', () {
      const section = MergedSection(
        id: 'goal',
        header: 'Goal',
        query: true,
        summary: true,
      );
      expect(section.toJson(), {
        'id': 'goal',
        'header': 'Goal',
        'query': true,
        'summary': true,
      });
    });

    test('no bundle and no query print no key, as E05 says', () {
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
        'goal and scope, with the doc banned words and the goal template', () {
      expect(featureDocType().renderGuide(), _s02Guide);
    });

    test("a section's own banned words follow its description, "
        'minus the allowed words, and name the line prefix they apply on', () {
      final guide = _merge('''
description: Avoid the listed words.
path: a.md
lint: {allowed_words: [small]}
sections:
  - id: statement
    header: Statement
    description: Remove the listed words.
    lint:
      banned_words: [fast, small, etc., fast, and/or]
      allowed_words: [and/or]
      line_prefix: "- **Statement:**"
''').renderGuide();

      expect(
        guide,
        'Avoid the listed words.\n\n'
        '## Statement\n\n'
        'Remove the listed words.\n\n'
        'Banned words on `- **Statement:**` lines: `fast`, `etc.`\n',
      );
    });

    test('a banned word list the allowed words empty prints '
        'no line', () {
      final guide = _merge(
        'description: A.\npath: a.md\n'
        'lint: {banned_words: [fast], allowed_words: [fast]}\n'
        'sections: [{id: s, header: S, lint: {banned_words: [fast]}}]',
      ).renderGuide();

      expect(guide, 'A.\n\n## S\n');
    });

    test('a template that holds a code fence prints inside a '
        'longer fence', () {
      final guide = _merge('''
description: A.
path: a.md
sections:
  - id: flow
    header: Flow
    template: |-
      ```mermaid
      flowchart TD
      ```
''').renderGuide();

      expect(
        guide,
        'A.\n\n## Flow\n\n'
        'Template:\n````markdown\n```mermaid\nflowchart TD\n```\n````\n',
      );
    });

    test('an empty template prints no template block', () {
      final guide = _merge(
        'description: A.\npath: a.md\n'
        "sections: [{id: s, header: S, template: ''}]",
      ).renderGuide();

      expect(guide, 'A.\n\n## S\n');
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

    test('a section with no description prints its header '
        'alone', () {
      final guide = _merge(
        'description: A.\npath: a.md\nsections: [{id: s, header: S}]',
      ).renderGuide();

      expect(guide, 'A.\n\n## S\n');
    });

    test('a section with an empty description prints its '
        'header alone', () {
      final guide = _merge(
        'description: A.\npath: a.md\n'
        "sections: [{id: s, header: S, description: ''}]",
      ).renderGuide();

      expect(guide, 'A.\n\n## S\n');
    });

    test('an empty doc description adds no blank paragraph', () {
      final guide = _merge(
        "description: ''\npath: a.md\nsections: [{id: s, header: S}]",
      ).renderGuide();

      expect(guide, '## S\n');
    });

    test('a doc type with an empty description and no sections '
        'renders nothing', () {
      expect(_merge("description: ''\npath: a.md").renderGuide(), '');
    });

    test('an entry with a url prints title, locator, and '
        'url', () {
      final guide = _merge(
        'description: A.\npath: a.md\n'
        'reference: [{title: T, url: "https://e.example/x", locator: L}]',
      ).renderGuide();

      expect(guide, 'A.\n\nGuide sources:\n- T, L: https://e.example/x\n');
    });

    test('a title-only entry prints its title alone', () {
      final guide = _merge(
        'description: A.\npath: a.md\nreference: [{title: T}]',
      ).renderGuide();

      expect(guide, endsWith('\n\nGuide sources:\n- T\n'));
    });

    test('a doc entry from the project layer prints the doc '
        'identity', () {
      final guide = _merge(
        'description: A.\npath: a.md',
        'reference: {add: [{title: T, doc: prd/feature}]}',
      ).renderGuide();

      expect(guide, endsWith('Guide sources:\n- T: prd/feature\n'));
    });

    test('no reference list prints no sources', () {
      final guide = _merge(
        'description: A.\npath: a.md\nsections: [{id: s, header: S}]',
      ).renderGuide();

      expect(guide, isNot(contains('Guide sources:')));
    });

    test('a project layer that removes every entry prints '
        'no sources', () {
      final guide = _merge(
        _featureLayer,
        'reference: {remove: [NASA Systems Engineering Handbook]}',
      ).renderGuide();

      expect(guide, isNot(contains('Guide sources:')));
      expect(guide, endsWith('each naming its owner.\n'));
    });

    test('a doc type with only a reference list prints the '
        'sources block alone', () {
      final guide = _merge(
        "description: ''\npath: a.md\nreference: [{title: T}]",
      ).renderGuide();

      expect(guide, 'Guide sources:\n- T\n');
    });
  });

  test('a section prints the lint keys a layer sets, and no '
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

  group('guide-rule lint values', () {
    const section = MergedSection(
      id: 'invariants',
      header: 'Invariants',
      catalog: CatalogLint(column: 'Code'),
      namesCodes: true,
      itemFields: [
        ItemFieldLint(field: 'Enforcer', values: ['a']),
      ],
      requiredWhen: RequiredWhenLint(section: 's', field: 'f', value: 'v'),
      diagram: DiagramLint(title: true),
      maxSentences: [SentenceLimit(count: 1, linePrefix: '-', column: 'C')],
      itemCount: ItemCountLint(min: 1, perSubsection: true),
      minLines: 2,
    );

    test('a section holds each guide-rule key as the layer wrote it', () {
      expect(section.catalog?.column, 'Code');
      expect(section.namesCodes, isTrue);
      expect(section.itemFields?.single.values, ['a']);
      expect(section.requiredWhen?.value, 'v');
      expect(section.diagram?.title, isTrue);
      expect(section.maxSentences?.single.column, 'C');
      expect(section.itemCount?.perSubsection, isTrue);
      expect(section.minLines, 2);
    });

    test('a section with no guide-rule key reads each as null', () {
      const bare = MergedSection(id: 'a', header: 'A');
      expect(bare.catalog, isNull);
      expect(bare.namesCodes, isNull);
      expect(bare.itemFields, isNull);
      expect(bare.requiredWhen, isNull);
      expect(bare.diagram, isNull);
      expect(bare.maxSentences, isNull);
      expect(bare.itemCount, isNull);
      expect(bare.minLines, isNull);
    });

    test('copyWith keeps a guide-rule key it is not given and replaces one '
        'it is given', () {
      final copy = section.copyWith(
        minLines: 4,
        diagram: const DiagramLint(edgeLabels: true),
      );
      expect(copy.minLines, 4);
      expect(copy.diagram?.title, isFalse);
      expect(copy.diagram?.edgeLabels, isTrue);
      expect(copy.catalog?.column, 'Code');
      expect(copy.itemCount?.min, 1);
    });

    test('a diagram, item count, and sentence limit default to no bound', () {
      const diagram = DiagramLint();
      expect(diagram.title, isFalse);
      expect(diagram.edgeLabels, isFalse);
      expect(diagram.bannedLabels, isEmpty);
      const count = ItemCountLint();
      expect(count.min, isNull);
      expect(count.max, isNull);
      expect(count.perSubsection, isFalse);
      expect(count.prefixes, isEmpty);
      const limit = SentenceLimit(count: 2);
      expect((limit.linePrefix, limit.column), (null, null));
    });

    test('the doc-level lint holds title_no_number and copyWith keeps it', () {
      const lint = MergedLint(titleNoNumber: true);
      expect(lint.titleNoNumber, isTrue);
      expect(lint.copyWith(maxChars: 3).titleNoNumber, isTrue);
      expect(const MergedLint().titleNoNumber, isNull);
    });
  });
}
