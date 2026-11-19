import 'dart:convert';
import 'dart:typed_data';

import 'package:specstone_core/src/setup_migration/project_files.dart'
    show parseOverrides;
import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/doc_type_merger.dart';
import 'package:specstone_core/src/templates/layer.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';

import '../../helpers/temp_tree.dart';

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
  - id: summary
    type: string
    required: true
    description: One line on what the feature does.
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

final class _OneFile implements LayerFiles {
  const new(this.path);

  final String path;

  @override
  bool exists(String layerRelativePath) => layerRelativePath == path;
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
/// the `scope` section the s02 examples drop.
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
    {
      'id': 'summary',
      'type': 'string',
      'required': true,
      'description': 'One line on what the feature does.',
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

Fields (frontmatter):
- `summary` (required, string) — One line on what the feature does.

Limits: at most 300 lines; at most 12,000 characters; at most 600 characters per item; at most 25 words per sentence (ko 17); at most 100 characters per sentence in a script with no spaces (th 100, ja 60, zh 45).

## Feature goal

Required section. Limits: at most 5 lines.
Why, problem, and audience, one sentence each.

Template:
```markdown
- **Why:**
- **Problem:**
- **Audience:**
```

Guide sources:
- NASA Systems Engineering Handbook, Appendix C
''';

/// The doc `Limits:` line of a doc type whose layers set no limit.
const _defaultLimits = 'Limits: $_builtInClauses';

const _builtInClauses =
    'at most 600 characters per item; '
    'at most 25 words per sentence (ko 17); '
    'at most 100 characters per sentence in a script with no spaces '
    '(th 100, ja 60, zh 45).';

/// Returns every value reachable in [node], to look for a `null`.
Iterable<Object?> _leaves(Object? node) => switch (node) {
  Map<String, Object?>() => node.values.expand(_leaves),
  List<Object?>() => node.expand(_leaves),
  _ => [node],
};

void main() {
  group('max_subsections, per_subsection, and when_field', () {
    const lower = '''
path: docs/specs/{slug}/DOMAIN.md
fields:
  - {id: kind, type: string}
sections:
  - id: scope
    header: Scope
    required: true
    when_field: {field: kind, values: [api]}
    lint:
      max_subsections: 3
      required_patterns:
        - {id: why, pattern: Why, message: m, per_subsection: true}
        - {id: what, pattern: What, message: m}
  - id: plain
    header: Plain
''';

    MergedSection sectionOf(MergedDocType type, String id) =>
        type.sections.singleWhere((s) => s.id == id);

    test('a layer carries each key into the merged section', () {
      final section = sectionOf(_merge(lower), 'scope');
      expect(section.maxSubsections, 3);
      expect(section.whenField?.field, 'kind');
      expect(section.whenField?.values, ['api']);
      expect(section.required, isTrue);
      expect(section.requiredPatterns?.map((p) => p.perSubsection), [
        true,
        false,
      ]);
    });

    test('a section that writes none of the keys reads each as null', () {
      final plain = sectionOf(_merge(lower), 'plain');
      expect(plain.maxSubsections, isNull);
      expect(plain.whenField, isNull);
    });

    test('an upper layer that writes none keeps the lower values', () {
      final section = sectionOf(
        _merge(lower, 'sections: [{id: scope, description: New}]'),
        'scope',
      );
      expect(section.maxSubsections, 3);
      expect(section.whenField?.values, ['api']);
    });

    test('the top-most writer wins for max_subsections and when_field', () {
      final section = sectionOf(
        _merge(
          lower,
          'sections: [{id: scope, when_field: {field: kind, values: [cli]}, '
          'lint: {max_subsections: 5}}]',
        ),
        'scope',
      );
      expect(section.maxSubsections, 5);
      expect(section.whenField?.values, ['cli']);
    });

    test('an upper required pattern of the same id replaces the lower one, '
        'per_subsection included', () {
      final section = sectionOf(
        _merge(
          lower,
          'sections: [{id: scope, lint: {required_patterns: {add: '
          '[{id: why, pattern: Why, message: m}]}}}]',
        ),
        'scope',
      );
      expect(section.requiredPatterns?.map((p) => p.perSubsection), [
        false,
        false,
      ]);
    });

    test('a section a layer adds carries the keys', () {
      final added = sectionOf(
        _merge(
          lower,
          'sections: [{id: extra, header: Extra, '
          'when_field: {field: kind, values: [x, y]}, '
          'lint: {max_subsections: 2}}]',
        ),
        'extra',
      );
      expect(added.maxSubsections, 2);
      expect(added.whenField?.values, ['x', 'y']);
    });

    test('copyWith keeps both keys it is not given and replaces one it is', () {
      final section = sectionOf(_merge(lower), 'scope');
      final kept = section.copyWith(minLines: 2);
      expect(kept.maxSubsections, 3);
      expect(kept.whenField?.field, 'kind');
      final replaced = section.copyWith(
        maxSubsections: 9,
        whenField: const WhenField(field: 'other', values: ['z']),
      );
      expect(replaced.maxSubsections, 9);
      expect(replaced.whenField?.values, ['z']);
    });

    test('copyWith keeps maxItemLines it is not given and replaces it', () {
      final section = sectionOf(
        _merge(lower),
        'scope',
      ).copyWith(maxItemLines: 5);
      expect(section.copyWith(minLines: 2).maxItemLines, 5);
      expect(section.copyWith(maxItemLines: 8).maxItemLines, 8);
    });

    test('toJson prints maxSubsections in lint, whenField on the section, and '
        'perSubsection on a required pattern that sets it', () {
      final json = sectionOf(_merge(lower), 'scope').toJson();
      expect(json['whenField'], {
        'field': 'kind',
        'values': ['api'],
      });
      final lint = json['lint']! as Map<String, Object?>;
      expect(lint['maxSubsections'], 3);
      final patterns = (lint['requiredPatterns']! as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(patterns.map((p) => p['perSubsection']), [true, null]);
    });

    test('toJson prints none of the keys when no layer sets them', () {
      final json = sectionOf(_merge(lower), 'plain').toJson();
      expect(json.containsKey('whenField'), isFalse);
      expect(json.containsKey('lint'), isFalse);
    });
  });

  group('MergedDocType.toJson', () {
    test('toJson prints maxDepth right after path', () {
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

    test(
      'toJson prints root on a field when written, and omits it when not',
      () {
        final plain = _merge(_featureLayer).toJson();
        final plainFields = (plain['fields']! as List)
            .cast<Map<String, Object>>();
        expect(plainFields.every((f) => !f.containsKey('root')), isTrue);

        final written = _merge(
          _featureLayer,
          'fields:\n'
          '  - {id: covers, type: output_ref, pointer: exact, root: project}\n',
        ).toJson();
        final covers = (written['fields']! as List)
            .cast<Map<String, Object>>()
            .singleWhere((f) => f['id'] == 'covers');
        expect(covers['root'], 'project');
      },
    );

    test('maxDepth 0 prints and does not nest; no key prints '
        'nothing', () {
      final flat = _merge(_featureLayer, 'max_depth: 0');
      expect(flat.toJson()['maxDepth'], 0);
      expect(flat.nests, isFalse);

      final unset = _merge(_featureLayer);
      expect(unset.toJson().containsKey('maxDepth'), isFalse);
      expect(unset.nests, isFalse);
    });

    test('toJson '
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

    test('toJson prints no readability key when no layer writes one', () {
      final lint =
          _merge(_featureLayer).toJson()['lint']! as Map<String, Object?>;

      expect(lint.containsKey('maxSentenceWords'), isFalse);
      expect(lint.containsKey('maxSentenceChars'), isFalse);
      expect(lint.containsKey('traceNoteLast'), isFalse);
    });

    test('toJson prints maxSentenceWords with built-in entries', () {
      final lint =
          _merge(
                _featureLayer,
                'lint: {max_sentence_words: {default: 30}}',
              ).toJson()['lint']!
              as Map<String, Object?>;

      expect(lint['maxSentenceWords'], {'default': 30, 'ko': 17});
      expect(lint.containsKey('maxSentenceChars'), isFalse);
    });

    test('toJson prints maxSentenceChars with built-in entries', () {
      final lint =
          _merge(
                _featureLayer,
                'lint: {max_sentence_chars: {th: 90}}',
              ).toJson()['lint']!
              as Map<String, Object?>;

      expect(lint['maxSentenceChars'], {
        'default': 100,
        'th': 90,
        'ja': 60,
        'zh': 45,
      });
      expect(lint.containsKey('maxSentenceWords'), isFalse);
    });

    test('toJson prints traceNoteLast when written', () {
      final lint =
          _merge(
                _featureLayer,
                'lint: {trace_note_last: false}',
              ).toJson()['lint']!
              as Map<String, Object?>;

      expect(lint['traceNoteLast'], isFalse);
    });

    test('section toJson prints no readability key', () {
      final json = _merge(
        _featureLayer,
        'lint: {max_sentence_words: {default: 30}, trace_note_last: false}',
      ).toJson();
      final sections = (json['sections']! as List<Object?>)
          .cast<Map<String, Object?>>();

      for (final section in sections) {
        final lint = section['lint'] as Map<String, Object?>? ?? const {};
        expect(lint.keys.where((k) => k.startsWith('maxSentence')), isEmpty);
        expect(lint.containsKey('traceNoteLast'), isFalse);
      }
    });

    test('the merged schema matches the spec example', () {
      final json = _merge(
        _featureLayer,
        'sections: [{id: scope, disabled: true}]',
      ).toJson();

      expect(json, s02FeatureJson);
      expect(jsonEncode(json), jsonEncode(s02FeatureJson));
    });

    test('a disabled section has no JSON '
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

    test('a field a layer disables is absent from the printed '
        'object', () {
      final json = _merge(
        _featureLayer,
        'fields: [{id: summary, disabled: true}]',
      ).toJson();

      final fields = (json['fields']! as List<Object?>)
          .cast<Map<String, Object>>();
      expect(fields.map((f) => f['id']), [
        'slug',
        'status',
        'draft',
        'approved',
        'reference',
      ]);
    });

    test('a reference list that layers change with add and remove prints as '
        'one merged list', () {
      final json = _merge(
        _featureLayer,
        'reference: {add: [{title: Team Guide, url: "https://x.dev/guide"}], '
        'remove: [NASA Systems Engineering Handbook]}',
      ).toJson();

      expect(json['reference'], [
        {'title': 'Team Guide', 'url': 'https://x.dev/guide'},
      ]);
    });

    test('a banned pattern entry prints its scope and a field group prints '
        'its ids', () {
      final json = _merge(_featureLayer, '''
lint:
  banned_patterns:
    - {id: a, pattern: 'x+', message: m, in: code, except: [xx]}
    - {id: b, pattern: 'y', message: n, in: all}
  required_field_groups:
    - [status, summary]
''').toJson();

      final lint = json['lint']! as Map<String, Object?>;
      expect(lint['bannedPatterns'], [
        {
          'id': 'a',
          'pattern': 'x+',
          'message': 'm',
          'in': 'code',
          'except': ['xx'],
        },
        {'id': 'b', 'pattern': 'y', 'message': 'n', 'in': 'all'},
      ]);
      expect(lint['requiredFieldGroups'], [
        ['status', 'summary'],
      ]);
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

    test('summary prints right after query', () {
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

    test('summaryRows prints the count, or false when off', () {
      const section = MergedSection(
        id: 'results',
        header: 'Results',
        summaryRows: SummaryRows.rows(1),
      );
      expect(section.toJson()['summaryRows'], 1);
      expect(section.summaryRowCount, 1);
      final off = section.copyWith(summaryRows: const SummaryRows.off());
      expect(off.toJson()['summaryRows'], false);
      expect(off.summaryRowCount, isNull);
      expect(
        const MergedSection(
          id: 'r',
          header: 'R',
        ).toJson().containsKey('summaryRows'),
        isFalse,
      );
    });

    test('summaryFor prints after bundle and only when set', () {
      const docType = MergedDocType(
        id: 'measurement',
        fields: [],
        lint: MergedLint(),
        files: [],
        sections: [],
        bundle: ['design'],
        summaryFor: ['project'],
      );
      final json = docType.toJson();
      expect(json['summaryFor'], ['project']);
      expect(json.keys.toList(), [
        'id',
        'bundle',
        'summaryFor',
        'fields',
        'sections',
      ]);
      expect(
        const MergedDocType(
          id: 'x',
          fields: [],
          lint: MergedLint(),
          files: [],
          sections: [],
        ).toJson().containsKey('summaryFor'),
        isFalse,
      );
    });

    test('the merged schema prints bundleRefs', () {
      const docType = MergedDocType(
        id: 'goal',
        fields: [],
        lint: MergedLint(),
        files: [],
        sections: [],
        bundle: ['design'],
        bundleRefs: true,
      );
      final json = docType.toJson();
      expect(json['bundleRefs'], isTrue);
      final keys = json.keys.toList();
      expect(keys.indexOf('bundleRefs'), keys.indexOf('bundle') + 1);
      expect(
        const MergedDocType(
          id: 'x',
          fields: [],
          lint: MergedLint(),
          files: [],
          sections: [],
        ).toJson().containsKey('bundleRefs'),
        isFalse,
      );
    });

    test('printsSummaryFor with no summary_for is true for every target', () {
      const docType = MergedDocType(
        id: 'measurement',
        fields: [],
        lint: MergedLint(),
        files: [],
        sections: [],
      );
      expect(docType.printsSummaryFor('story'), isTrue);
      expect(docType.printsSummaryFor(null), isTrue);
    });

    test('printsSummaryFor is true for a listed target type only', () {
      const docType = MergedDocType(
        id: 'measurement',
        fields: [],
        lint: MergedLint(),
        files: [],
        sections: [],
        summaryFor: ['project'],
      );
      expect(docType.printsSummaryFor('project'), isTrue);
      expect(docType.printsSummaryFor('story'), isFalse);
      expect(docType.printsSummaryFor(null), isFalse);
    });

    test('no bundle and no query print no key', () {
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
    test('the guide matches the spec example for '
        'goal, with the doc banned words, the field block, and the goal '
        'template', () {
      final guide = _merge(
        _featureLayer,
        'sections: [{id: scope, disabled: true}]',
      ).renderGuide();

      expect(guide, _s02Guide);
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
        'Avoid the listed words.\n\n$_defaultLimits\n\n'
        '## Statement\n\n'
        'Optional section.\n'
        'Remove the listed words.\n\n'
        'Banned words on `- **Statement:**` lines: `fast`, `etc.`\n',
      );
    });

    test('allowed words that clear some of the doc-level banned words leave '
        'the rest in the line', () {
      final guide = _merge(
        'description: A.\npath: a.md\n'
        'lint: {banned_words: [fast, small, robust], allowed_words: [small]}',
      ).renderGuide();

      expect(
        guide,
        'A.\n\nBanned words: `fast`, `robust`\n\n$_defaultLimits\n',
      );
    });

    test('a section banned word list with no line prefix drops a word the '
        'doc-level allowed list holds', () {
      final guide = _merge('''
description: A.
path: a.md
lint: {allowed_words: [small]}
sections:
  - id: s
    header: S
    lint:
      banned_words: [fast, small, etc., and/or]
      allowed_words: [etc.]
''').renderGuide();

      expect(
        guide,
        'A.\n\n$_defaultLimits\n\n'
        '## S\n\nOptional section.\n\nBanned words: `fast`, `and/or`\n',
      );
    });

    test('a banned word list the allowed words empty prints '
        'no line', () {
      final guide = _merge(
        'description: A.\npath: a.md\n'
        'lint: {banned_words: [fast], allowed_words: [fast]}\n'
        'sections: [{id: s, header: S, lint: {banned_words: [fast]}}]',
      ).renderGuide();

      expect(guide, 'A.\n\n$_defaultLimits\n\n## S\n\nOptional section.\n');
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
        'A.\n\n$_defaultLimits\n\n## Flow\n\nOptional section.\n\n'
        'Template:\n````markdown\n```mermaid\nflowchart TD\n```\n````\n',
      );
    });

    test('an empty template prints no template block', () {
      final guide = _merge(
        'description: A.\npath: a.md\n'
        "sections: [{id: s, header: S, template: ''}]",
      ).renderGuide();

      expect(guide, 'A.\n\n$_defaultLimits\n\n## S\n\nOptional section.\n');
    });

    test('a disabled section prints neither '
        'header nor mark', () {
      final guide = _merge(
        _featureLayer,
        'sections: [{id: goal, disabled: true}]',
      ).renderGuide();

      expect(guide, isNot(contains('Feature goal')));
      expect(guide, isNot(contains('Required section.')));
      expect(guide, contains('## Out-of-scope\n\nOptional section.\n'));
    });

    test('a section with no description prints its mark '
        'alone', () {
      final guide = _merge(
        'description: A.\npath: a.md\nsections: [{id: s, header: S}]',
      ).renderGuide();

      expect(guide, 'A.\n\n$_defaultLimits\n\n## S\n\nOptional section.\n');
    });

    test('a section with an empty description prints its '
        'mark alone', () {
      final guide = _merge(
        'description: A.\npath: a.md\n'
        "sections: [{id: s, header: S, description: ''}]",
      ).renderGuide();

      expect(guide, 'A.\n\n$_defaultLimits\n\n## S\n\nOptional section.\n');
    });

    const conditionLines = {
      '{id: s, header: S}': 'Optional section.',
      '{id: s, header: S, required: true}': 'Required section.',
      '{id: s, header: S, required: true, '
              'when_field: {field: kind, values: [a]}}':
          'Required when `kind` is `a`; left out otherwise.',
      '{id: s, header: S, when_field: {field: kind, values: [a]}}':
          'Optional when `kind` is `a`; left out otherwise.',
      '{id: s, header: S, required: true, '
              'when_field: {field: kind, values: [a, b]}}':
          'Required when `kind` is `a` or `b`; left out otherwise.',
      '{id: s, header: S, required: true, '
              'when_field: {field: kind, values: [a, b, c]}}':
          'Required when `kind` is `a`, `b`, or `c`; left out otherwise.',
      '{id: s, header: S, required: true, lint: '
              '{required_when: {section: api, field: Kind, value: rest}}}':
          'Required when a `Interfaces` item holds `Kind: rest`; '
          'left out otherwise.',
      '{id: s, header: S, lint: '
              '{required_when: {section: api, field: Kind, value: rest}}}':
          'Required when a `Interfaces` item holds `Kind: rest`; '
          'left out otherwise.',
      '{id: s, header: S, required: true, '
              'when_field: {field: kind, values: [a, b]}, lint: '
              '{required_when: {section: api, field: Kind, value: rest}}}':
          'Required when `kind` is `a` or `b` and a `Interfaces` item holds '
          '`Kind: rest`; left out otherwise.',
    };
    for (final MapEntry(key: section, value: line) in conditionLines.entries) {
      test('a section $section prints "$line" under its header', () {
        final guide = _merge(
          'description: A.\npath: a.md\n'
          'sections: [{id: api, header: Interfaces}, $section]',
        ).renderGuide();

        expect(
          guide,
          'A.\n\n$_defaultLimits\n\n## Interfaces\n\nOptional section.\n\n'
          '## S\n\n$line\n',
        );
      });
    }

    test('a when_field of four values out of alphabetical order prints them '
        'in declared order', () {
      final guide = _merge(
        'description: A.\npath: a.md\n'
        'sections: [{id: s, header: S, required: true, '
        'when_field: {field: kind, values: [c, a, d, b]}}]',
      ).renderGuide();

      expect(
        guide,
        contains(
          'Required when `kind` is `c`, `a`, `d`, or `b`; left out '
          'otherwise.\n',
        ),
      );
    });

    test('an optional section that sets both conditions prints the one '
        'joined line', () {
      final guide = _merge('''
description: A.
path: a.md
fields:
  - {id: kind, type: string}
sections:
  - {id: api, header: Interfaces}
  - id: s
    header: S
    when_field: {field: kind, values: [a]}
    lint:
      required_when: {section: api, field: Kind, value: rest}
''').renderGuide();

      expect(
        guide,
        endsWith(
          '## S\n\nRequired when `kind` is `a` and a `Interfaces` item holds '
          '`Kind: rest`; left out otherwise.\n',
        ),
      );
    });

    test('an empty doc description adds no blank paragraph', () {
      final guide = _merge(
        "description: ''\npath: a.md\nsections: [{id: s, header: S}]",
      ).renderGuide();

      expect(guide, '$_defaultLimits\n\n## S\n\nOptional section.\n');
    });

    test('a bare doc type prints its doc-level line', () {
      expect(
        _merge("description: ''\npath: a.md").renderGuide(),
        '$_defaultLimits\n',
      );
    });

    test('the doc-level line follows the fields block and precedes the '
        'sections', () {
      final withFields = _merge(
        'description: A.\npath: a.md\n'
        'lint: {max_lines: 300, banned_words: [fast]}\n'
        'fields: [{id: note, type: string}]\n'
        'sections: [{id: s, header: S}]\n'
        'reference: [{title: T}]',
      ).renderGuide();
      final withoutFields = _merge(
        'description: A.\npath: a.md\n'
        'lint: {banned_words: [fast]}\n'
        'sections: [{id: s, header: S}]',
      ).renderGuide();

      expect(
        withFields,
        'A.\n\nBanned words: `fast`\n\n'
        'Fields (frontmatter):\n- `note` (optional, string)\n\n'
        'Limits: at most 300 lines; $_builtInClauses\n\n'
        '## S\n\nOptional section.\n\n'
        'Guide sources:\n- T\n',
      );
      expect(
        withoutFields,
        'A.\n\nBanned words: `fast`\n\n$_defaultLimits\n\n'
        '## S\n\nOptional section.\n',
      );
    });

    test("a condition line carries the section's limits", () {
      final guide = _merge('''
description: A.
path: a.md
fields:
  - {id: kind, type: string}
sections:
  - {id: api, header: Interfaces}
  - id: plain
    header: Plain
    lint: {min_lines: 2, max_lines: 4}
  - id: required
    header: Required
    required: true
    lint: {max_chars: 1500}
  - id: when
    header: When
    required: true
    when_field: {field: kind, values: [a, b]}
    lint: {max_item_lines: 1}
  - id: item
    header: Item
    lint:
      required_when: {section: api, field: Kind, value: rest}
      max_subsections: 2
  - id: both
    header: Both
    when_field: {field: kind, values: [a]}
    lint:
      required_when: {section: api, field: Kind, value: rest}
      max_sentences: [{count: 1}]
  - id: bare
    header: Bare
''').renderGuide();

      expect(
        guide,
        allOf(
          contains(
            '## Plain\n\nOptional section. '
            'Limits: at least 2 lines; at most 4 lines.\n',
          ),
          contains(
            '## Required\n\nRequired section. '
            'Limits: at most 1,500 characters.\n',
          ),
          contains(
            '## When\n\nRequired when `kind` is `a` or `b`; left out '
            'otherwise. Limits: at most 1 line per item.\n',
          ),
          contains(
            '## Item\n\nRequired when a `Interfaces` item holds '
            '`Kind: rest`; left out otherwise. '
            'Limits: at most 2 subsections.\n',
          ),
          contains(
            '## Both\n\nRequired when `kind` is `a` and a `Interfaces` item '
            'holds `Kind: rest`; left out otherwise. '
            'Limits: at most 1 sentence per item.\n',
          ),
          contains('## Bare\n\nOptional section.\n'),
        ),
      );
    });

    test('a prose field prints its limits after its description lines', () {
      final guide = _merge('''
description: A.
path: a.md
fields:
  - id: summary
    type: string
    required: true
    description: |-
      First line.
      Second line.
    lint:
      max_sentences: 1
      max_sentence_words: {default: 15, ko: 10}
      max_sentence_chars: {default: 60, th: 60}
  - id: note
    type: string
    lint: {max_sentences: 2}
''').renderGuide();

      expect(
        guide,
        contains(
          '- `summary` (required, string) — First line.\n'
          '  Second line.\n'
          '  Limits: at most 1 sentence; at most 15 words per sentence '
          '(ko 10); at most 60 characters per sentence in a script with no '
          'spaces (th 60).\n'
          '- `note` (optional, string)\n'
          '  Limits: at most 2 sentences.\n',
        ),
      );
    });

    test('a doc_ref field with doc types names them after its type', () {
      final guide = _merge('''
description: A.
path: a.md
fields:
  - id: persona
    type: doc_ref
    list: true
    required: true
    doc_types: [persona]
    description: Who the feature serves.
  - id: owner
    type: doc_ref
    doc_types: [persona, anti_persona]
  - id: link
    type: doc_ref
    list: true
''').renderGuide();

      expect(
        guide,
        contains(
          'Fields (frontmatter):\n'
          '- `persona` (required, doc_ref list → persona) — '
          'Who the feature serves.\n'
          '- `owner` (optional, doc_ref → persona, anti_persona)\n'
          '- `link` (optional, doc_ref list)\n',
        ),
      );
    });

    test('an entry with a url prints title, locator, and '
        'url', () {
      final guide = _merge(
        'description: A.\npath: a.md\n'
        'reference: [{title: T, url: "https://e.example/x", locator: L}]',
      ).renderGuide();

      expect(
        guide,
        'A.\n\n$_defaultLimits\n\nGuide sources:\n- T, L: https://e.example/x\n',
      );
    });

    test('a file entry prints its file, and two entries print in merged '
        'order', () {
      final layer = DocTypeLayer.parse(
        'description: A.\npath: a.md\n'
        'reference:\n'
        '  - {title: Z, file: refs/handbook.md, locator: p. 3}\n'
        '  - {title: B, url: "https://e.example/b"}\n'
        '  - {title: A}\n',
        file: _shippedFile,
        docTypeId: 'feature',
        kind: LayerKind.shipped,
        files: const _OneFile('refs/handbook.md'),
      );
      final guide = _merger
          .apply(_merger.builtInBase('feature'), layer)
          .renderGuide();

      expect(
        guide,
        endsWith(
          '\n\nGuide sources:\n'
          '- Z, p. 3: refs/handbook.md\n'
          '- B: https://e.example/b\n'
          '- A\n',
        ),
      );
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

      expect(guide, '$_defaultLimits\n\nGuide sources:\n- T\n');
    });

    test('a declared field prints in the field block ahead of the '
        'sections', () {
      final guide = _merge(
        'description: A.\npath: a.md\n'
        'fields: [{id: summary, type: string, required: true, '
        'description: One line.}]\n'
        'sections: [{id: s, header: S}]',
      ).renderGuide();

      expect(
        guide,
        'A.\n\nFields (frontmatter):\n'
        '- `summary` (required, string) — One line.\n\n'
        '$_defaultLimits\n\n## S\n\nOptional section.\n',
      );
    });

    test('the field block heading tells the writer the fields go in '
        'frontmatter', () {
      final guide = _merge(
        'description: A.\npath: a.md\n'
        'fields: [{id: note, type: string}]',
      ).renderGuide();

      expect(guide, contains('\n\nFields (frontmatter):\n- `note` '));
      expect(guide, isNot(contains('Fields:')));
    });

    test('a list field adds list after its type, and a description of two '
        'lines indents the second by two spaces', () {
      final guide = _merge(
        'description: A.\npath: a.md\n'
        'fields:\n'
        '  - id: traced_from\n'
        '    type: string\n'
        '    list: true\n'
        '    required: true\n'
        '    description: |-\n'
        '      First line.\n'
        '      Second line.',
      ).renderGuide();

      expect(
        guide,
        'A.\n\nFields (frontmatter):\n'
        '- `traced_from` (required, string list) — First line.\n'
        '  Second line.\n\n$_defaultLimits\n',
      );
    });

    test('an undescribed field line ends at its closing parenthesis', () {
      final guide = _merge(
        'description: A.\npath: a.md\nfields: [{id: note, type: string}]',
      ).renderGuide();

      expect(
        guide,
        'A.\n\nFields (frontmatter):\n- `note` (optional, string)\n\n'
        '$_defaultLimits\n',
      );
    });

    test('an enum field lists its values in declared order', () {
      final guide = _merge(
        'description: A.\npath: a.md\n'
        'fields: [{id: verify_method, type: enum, required: true, '
        'enum: [test, analysis, inspection, demonstration], '
        'description: Names how the requirement is proven.}]',
      ).renderGuide();

      expect(
        guide,
        contains(
          '- `verify_method` (required, enum: test, analysis, inspection, '
          'demonstration) — Names how the requirement is proven.',
        ),
      );
    });

    test('a built-in field is never listed', () {
      final guide = _merge(
        'description: A.\npath: a.md\n'
        'fields: [{id: status, description: Lifecycle of the doc.}]',
      ).renderGuide();

      expect(guide, isNot(contains('status')));
      expect(guide, isNot(contains('Fields')));
    });

    test('a type that declares only built-ins prints no field block', () {
      final guide = _merge(
        'description: A.\npath: a.md\nsections: [{id: s, header: S}]',
      ).renderGuide();

      expect(guide, isNot(contains('Fields')));
    });

    test('a required and an optional section each carry their mark under '
        'the header', () {
      final guide = _merge(
        'description: A.\npath: a.md\n'
        'sections:\n'
        '  - {id: r, header: R, required: true, description: Why.}\n'
        '  - {id: o, header: O, description: What.}\n'
        '  - {id: n, header: N, required: true}',
      ).renderGuide();

      expect(
        guide,
        'A.\n\n$_defaultLimits\n\n'
        '## R\n\nRequired section.\nWhy.\n\n'
        '## O\n\nOptional section.\nWhat.\n\n'
        '## N\n\nRequired section.\n',
      );
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

    test("a section lint prints an item field's when", () {
      const withWhen = MergedSection(
        id: 'invariants',
        header: 'Invariants',
        itemFields: [
          ItemFieldLint(
            field: 'P',
            when: ItemFieldWhen(field: 'K', value: 'v'),
          ),
        ],
      );
      final lint = withWhen.toJson()['lint']! as Map<String, Object?>;
      expect(lint['itemFields'], [
        {
          'field': 'P',
          'when': {'field': 'K', 'value': 'v'},
        },
      ]);
    });

    test('an item field applies when it has no when or its when is met', () {
      const bare = ItemFieldLint(field: 'P');
      const conditional = ItemFieldLint(
        field: 'P',
        when: ItemFieldWhen(field: 'K', value: 'v'),
      );
      expect(bare.appliesTo(const {}), isTrue);
      expect(conditional.appliesTo(const {'K': 'v'}), isTrue);
      expect(conditional.appliesTo(const {'K': 'V'}), isFalse);
      expect(conditional.appliesTo(const {}), isFalse);
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

  group('MergedDocType.extendsChain', () {
    MergedSet resolved() => TemplateResolver().resolveCarried(
      packNames: const ['prd-core', 'software-tech'],
      homeDirectory: null,
      projectLayers: parseOverrides({
        '.specstone/templates/edge_architecture_root.yaml':
            'id: edge_architecture_root\nextends: architecture\n'
            'path: specs/EDGE_ARCHITECTURE_ROOT.md\nparent:\n',
        '.specstone/templates/edge_architecture.yaml':
            'id: edge_architecture\nextends: edge_architecture_root\n'
            'path: specs/EDGE_ARCHITECTURE.md\nparent:\n',
      }),
    );

    test('a doc type built on another reports the whole extends chain', () {
      final set = resolved();

      expect(set.lookup('edge_architecture')!.extendsChain, [
        'edge_architecture_root',
        'architecture',
      ]);
      expect(set.lookup('edge_architecture_root')!.extendsChain, [
        'architecture',
      ]);
      expect(set.lookup('architecture')!.extendsChain, isEmpty);
    });

    test('buildsOn is true for the own id and every id of the chain', () {
      final edge = resolved().lookup('edge_architecture')!;

      expect(edge.buildsOn('edge_architecture'), isTrue);
      expect(edge.buildsOn('edge_architecture_root'), isTrue);
      expect(edge.buildsOn('architecture'), isTrue);
      expect(edge.buildsOn('feature'), isFalse);
    });

    test('copyWith keeps the chain', () {
      final edge = resolved().lookup('edge_architecture')!;

      expect(edge.copyWith(description: 'x').extendsChain, edge.extendsChain);
    });
  });

  group('shared lines and fields in the guide and the schema', () {
    const ownText = 'Describes one HTTP operation.';

    Uint8List bytes(String text) => Uint8List.fromList(utf8.encode(text));

    final shipped = <String, Uint8List>{
      'prd-core/pack.yaml': bytes('name: prd-core\nversion: 1.0.0\n'),
      'software-tech/pack.yaml': bytes('''
name: software-tech
version: 1.0.0
shared_lines:
  - id: first
    text: Say each thing once.
  - id: second
    text: Name the status code.
    for_doc_types: [api]
  - id: runbook_only
    text: List the steps.
    for_doc_types: [runbook]
shared_fields:
  - id: overrides
    type: string
    description: Shared overrides.
    for_doc_types: [api]
'''),
      'software-tech/api.yaml': bytes('''
id: api
description: $ownText
path: api/{slug}.md
fields:
  - id: base_url
    type: string
lint:
  banned_words: [fast]
'''),
      'software-tech/runbook.yaml': bytes('''
id: runbook
description: Describes one operating routine.
path: runbooks/{slug}.md
'''),
    };

    Future<MergedDocType> resolveApi([Map<String, String>? templates]) async {
      final project = await writeTree({
        '.specstone/config.yaml':
            'packs:\n  prd-core: 1.0.0\n  software-tech: 1.0.0\n',
        for (final MapEntry(:key, :value) in (templates ?? {}).entries)
          '.specstone/templates/$key': value,
      });
      final set = TemplateResolver(
        shippedFiles: shipped,
      ).resolve(workingDirectory: project, homeDirectory: await writeTree({}));
      return set.lookup('api')!;
    }

    const projectLayer = {
      'shared.yaml': '''
shared_lines:
  - id: first
    text: Say each thing once, short.
  - id: added
    text: Cite by link.
    for_doc_types: [api]
''',
      'api.yaml': 'fields:\n  - id: project_added\n    type: string\n',
    };

    test('the guide prints the shared lines after the own text and before '
        'the banned words, in print order', () async {
      final guide = (await resolveApi(projectLayer)).renderGuide();

      expect(
        guide,
        startsWith(
          '$ownText\n'
          'Say each thing once, short.\n'
          'Name the status code.\n'
          'Cite by link.\n\n'
          'Banned words: `fast`\n\n',
        ),
      );
    });

    test('the guide prints a reached shared field in Fields at its merged '
        'place', () async {
      final guide = (await resolveApi(projectLayer)).renderGuide();

      expect(
        guide,
        contains(
          'Fields (frontmatter):\n'
          '- `base_url` (optional, string)\n'
          '- `overrides` (optional, string) — Shared overrides.\n'
          '- `project_added` (optional, string)\n',
        ),
      );
    });

    test('a disabled or non-reaching shared line is not printed', () async {
      final api = await resolveApi({
        'shared.yaml': 'shared_lines:\n  - id: second\n    disabled: true\n',
      });

      final guide = api.renderGuide();

      expect(guide, contains('Say each thing once.'));
      expect(guide, isNot(contains('Name the status code.')));
      expect(guide, isNot(contains('List the steps.')));
    });

    test('toJson holds the own text then each shared line, and the shared '
        'field at its place', () async {
      final json = (await resolveApi(projectLayer)).toJson();

      expect(
        json['description'],
        '$ownText\nSay each thing once, short.\nName the status code.\n'
        'Cite by link.',
      );
      final fieldIds = [
        for (final field in json['fields']! as List<Object?>)
          (field! as Map<String, Object?>)['id'],
      ];
      expect(fieldIds.sublist(fieldIds.length - 3), [
        'base_url',
        'overrides',
        'project_added',
      ]);
    });

    test(
      'a type with a blank own description starts with its shared line',
      () async {
        final api = await resolveApi(projectLayer);
        final blank = MergedDocType(
          id: api.id,
          fields: api.fields,
          sections: api.sections,
          lint: api.lint,
          files: api.files,
          sharedLines: api.sharedLines,
        );

        expect(
          blank.renderGuide(),
          startsWith('Say each thing once, short.\n'),
        );
        expect(
          blank.toJson()['description'],
          'Say each thing once, short.\nName the status code.\nCite by link.',
        );
      },
    );

    test('renderGuide leaves out the shared lines it is told the shared block '
        'holds', () async {
      final api = await resolveApi(projectLayer);

      final guide = api.renderGuide(sharedOut: {'first', 'added'});

      expect(
        guide,
        startsWith('$ownText\nName the status code.\n\nBanned words:'),
      );
      expect(guide, isNot(contains('Say each thing once')));
      expect(guide, isNot(contains('Cite by link.')));
      expect(api.toJson()['description'], contains('Say each thing once'));
      expect(
        api.renderGuide(
          sharedOut: {for (final line in api.sharedLines) line.id},
        ),
        startsWith('$ownText\n\nBanned words:'),
      );
    });

    test('a type with no shared line prints its own text alone', () async {
      final api = await resolveApi({
        'shared.yaml':
            'shared_lines:\n'
            '  - id: first\n    disabled: true\n'
            '  - id: second\n    disabled: true\n',
      });

      expect(api.toJson()['description'], ownText);
      expect(api.renderGuide(), startsWith('$ownText\n\nBanned words:'));
    });
  });
}
