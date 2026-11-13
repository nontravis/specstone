import 'dart:convert';

import 'package:specstone_core/src/doc_model/path_pattern.dart';
import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:specstone_core/src/templates/pack_manifest.dart';
import 'package:specstone_core/src/templates/pack_migration.dart';
import 'package:specstone_core/src/templates/pattern_entry.dart';
import 'package:specstone_core/src/templates/shipped_pack_files.dart';
import 'package:test/test.dart';

import '../../helpers/prd_core.dart';
import '../../helpers/software_tech.dart';

void main() {
  test('f03/us03/fr03/e08: decodes base64 constants back to bytes', () {
    final files = decodeShippedPacks({
      'a/x.pdf': base64Encode([0xff, 0, 1]),
    });

    expect(files['a/x.pdf'], [0xff, 0, 1]);
  });

  test('f03/us03/fr03/e08: the shipped pack files are decoded', () {
    expect(shippedPackFiles.keys, contains('prd-core/pack.yaml'));
  });

  test(
    'f03/us06/fr01, f03/us07/fr01: shippedPackVersions reads the version each '
    'shipped pack.yaml carries',
    () {
      final versions = shippedPackVersions();
      expect(versions.keys, ['prd-core', 'software-tech']);
      for (final MapEntry(:key, :value) in versions.entries) {
        final manifest = PackManifest.parse(
          utf8.decode(shippedPackFiles['$key/pack.yaml']!),
          file: 'packs/$key/pack.yaml',
        );
        expect(value, manifest.version.toString());
      }
    },
  );

  test('the shipped software-tech pack is 1.6.0 and adds no migrations '
      'entry', () {
    expect(shippedPackVersions()['software-tech'], '1.6.0');
    final manifest = PackManifest.parse(
      utf8.decode(shippedPackFiles['software-tech/pack.yaml']!),
      file: 'packs/software-tech/pack.yaml',
    );
    expect(
      [for (final entry in manifest.migrations) '${entry.from}'],
      ['1.4.0'],
    );
  });

  group('template_packs/write_spec_docs_from_software_tech/'
      'ship_software_tech_pack', () {
    late MergedSet both;
    late MergedSet prdOnly;
    setUpAll(() async {
      both = await resolveSoftwareTech();
      prdOnly = await resolvePrdCore();
    });

    test('E01: the merged set holds the eleven prd-core and the nine '
        'software-tech doc types, the record among them', () {
      expect(
        both.docTypes.map((d) => d.id).toList(),
        [...prdCoreIds, ...softwareTechIds]..sort(),
      );
      for (final id in softwareTechIds) {
        expect(prdCoreDocType(both, id).pack, 'software-tech', reason: id);
      }
    });

    test('S1, E01: each doc type takes the path and the parent of the Output '
        'table', () {
      const outputTable = <String, (String, String?)>{
        'tech_stack': ('specs/TECH_STACK.md', null),
        'architecture': ('specs/f{nn}_{slug}/ARCHITECTURE.md', 'feature'),
        'domain': ('specs/f{nn}_{slug}/DOMAIN.md', 'feature'),
        'api': ('specs/f{nn}_{slug}/API.md', 'feature'),
        'integration': ('specs/f{nn}_{slug}/INTEGRATION.md', 'feature'),
        'error': ('specs/f{nn}_{slug}/ERROR.md', 'feature'),
        'auth': ('specs/f{nn}_{slug}/AUTH.md', 'feature'),
        'topic': ('specs/topics/{slug}.md', null),
        'implementation': ('specs/f{nn}_{slug}/IMPLEMENTATION.md', 'feature'),
      };
      expect(outputTable.keys, unorderedEquals(softwareTechIds));
      for (final MapEntry(key: id, value: (path, parent))
          in outputTable.entries) {
        final docType = prdCoreDocType(both, id);
        expect(docType.path, path, reason: id);
        expect(docType.parent, parent, reason: id);
      }
    });

    test('S4, E08: the pack writes no layer over a prd-core doc type, so a '
        'story and an FR carry no code-pointer field', () {
      final files = shippedPackFiles.keys
          .where((k) => k.startsWith('software-tech/'))
          .toList();
      expect(
        files,
        unorderedEquals([
          'software-tech/pack.yaml',
          for (final id in softwareTechIds) 'software-tech/$id.yaml',
        ]),
      );
      for (final id in ['user_story', 'fr']) {
        final merged = prdCoreDocType(both, id);
        expect(
          merged.fields.map((f) => f.id),
          prdCoreDocType(prdOnly, id).fields.map((f) => f.id),
          reason: id,
        );
        expect(
          merged.fields.where((f) => f.type == FieldType.outputRef),
          isEmpty,
          reason: id,
        );
      }
    });

    test('E09, E01: every software-tech doc type is per target and no '
        'prd-core one is, so each reads specs/<target>/ with two targets', () {
      for (final docType in both.docTypes) {
        expect(
          docType.isPerTarget,
          softwareTechIds.contains(docType.id),
          reason: docType.id,
        );
      }
      expect(
        PathPattern(prdCoreDocType(both, 'implementation').path!)
            .forTarget('jaspr')
            .source,
        'specs/jaspr/f{nn}_{slug}/IMPLEMENTATION.md',
      );
      expect(
        PathPattern(prdCoreDocType(both, 'tech_stack').path!)
            .forTarget('jaspr')
            .source,
        'specs/jaspr/TECH_STACK.md',
      );
    });

    test('E02: a project that lists only prd-core gets no implementation '
        'doc type and no record doc type', () {
      expect(prdOnly.lookup('implementation'), isNull);
      expect(prdOnly.recordDocType, isNull);
      for (final id in ['user_story', 'fr']) {
        expect(
          prdCoreDocType(prdOnly, id).fields.map((f) => f.id),
          contains('status'),
          reason: id,
        );
      }
    });

    test('E07: the implementation record holds the status and the code '
        'lines, each optional, and no section', () {
      final record = both.recordDocType!;
      expect(record.id, 'implementation');
      expect(record.isPerTarget, isTrue);
      expect(record.sections, isEmpty);
      expectOwnFields(record, const [
        FieldSpec('statuses', FieldType.recordStatus, list: true),
        FieldSpec(
          'implements',
          FieldType.outputRef,
          list: true,
          pointer: PointerKind.itemExact,
        ),
        FieldSpec(
          'tests',
          FieldType.outputRef,
          list: true,
          pointer: PointerKind.itemTest,
        ),
      ]);
      for (final id in ['implements', 'tests']) {
        expect(
          fieldOf(record, id).description,
          contains(
            "relative to the code root of the doc's target "
            '(`.specstone/config.yaml`, else the project root)',
          ),
          reason: id,
        );
      }
      expect(
        fieldOf(record, 'tests').description,
        allOf(
          contains('`<item>:<test file path>[:<test or group name>]`'),
          contains('quoted YAML string'),
        ),
      );
    });

    test('E07: the other pointer fields keep their kind and requirement', () {
      expectOwnFields(prdCoreDocType(both, 'architecture'), const [
        FieldSpec(
          'covers',
          FieldType.outputRef,
          list: true,
          required: true,
          pointer: PointerKind.prefix,
        ),
      ]);
      expectOwnFields(prdCoreDocType(both, 'topic'), const [
        FieldSpec(
          'covers',
          FieldType.outputRef,
          list: true,
          required: true,
          pointer: PointerKind.prefix,
        ),
      ]);
      expectOwnFields(prdCoreDocType(both, 'tech_stack'), const [
        FieldSpec('code', FieldType.string, list: true),
      ]);
    });

    test('S1: the pack carries the one migrations entry from 1.4.0, a '
        'move_to_record step', () {
      final manifest = PackManifest.parse(
        utf8.decode(shippedPackFiles['software-tech/pack.yaml']!),
        file: 'packs/software-tech/pack.yaml',
      );
      expect(manifest.migrations, hasLength(1));
      final entry = manifest.migrations.single;
      expect(entry.from.toString(), '1.4.0');
      final step = entry.steps.single as MoveToRecord;
      expect(step.docTypes, ['user_story', 'fr']);
      expect(step.fields, ['status', 'implements']);
      expect(step.to, 'implementation');
    });
  });

  group('the software-tech guide-rule lint', () {
    late MergedSet set;
    setUpAll(() async {
      set = await resolveSoftwareTech();
    });

    Iterable<(MergedDocType, MergedSection)> specSections() sync* {
      for (final docType in set.docTypes) {
        if (docType.pack != 'software-tech') continue;
        for (final s in docType.sections) {
          yield (docType, s);
        }
      }
    }

    MergedSection section(String docType, String id) =>
        sectionOf(prdCoreDocType(set, docType), id);

    test('the section banned and required patterns are exactly the guide-rule '
        'list, each on its section', () {
      expect(
        {
          for (final (docType, s) in specSections())
            if (s.bannedPatterns != null)
              '${docType.id}.${s.id}': [
                for (final p in s.bannedPatterns!) p.id,
              ],
        },
        {
          'architecture.components': ['table_only'],
          'architecture.concerns': ['concern_ending'],
          'api.operations': ['operation_heading'],
          'auth.scopes': ['scope_form'],
          'auth.resource_matrix': ['matrix_cell'],
          'domain.entities': ['entity_kind'],
          'domain.invariants': ['numbered_invariant'],
        },
      );
      expect(
        {
          for (final (docType, s) in specSections())
            if (s.requiredPatterns != null)
              '${docType.id}.${s.id}': [
                for (final p in s.requiredPatterns!) p.id,
              ],
        },
        {
          'architecture.concerns': [
            'concern_integration',
            'concern_errors',
            'concern_auth',
            'concern_lifecycle',
            'concern_events',
            'concern_rollout',
            'concern_observability',
          ],
        },
      );
    });

    for (final rule in _specGuideRules) {
      test('${rule.docType}.${rule.section} ${rule.id}: fires on a broken '
          'line, passes a sound one, and cites its guide line', () {
        final docType = prdCoreDocType(set, rule.docType);
        final sectionOfRule = section(rule.docType, rule.section!);
        final patterns = rule.required
            ? sectionOfRule.requiredPatterns!
            : sectionOfRule.bannedPatterns!;
        final pattern = patterns.singleWhere((p) => p.id == rule.id);
        for (final line in rule.hits) {
          expect(pattern.regExp.hasMatch(line), isTrue, reason: line);
        }
        for (final line in rule.misses) {
          expect(pattern.regExp.hasMatch(line), isFalse, reason: line);
        }
        if (!rule.required) expect(pattern.scope, rule.scope);
        expect(pattern.message, contains(rule.phrase), reason: rule.id);
        expect(
          [docType.description, sectionOfRule.description].join('\n'),
          contains(rule.phrase),
          reason: rule.id,
        );
      });
    }

    test('component_details is an optional section right after components', () {
      final architecture = prdCoreDocType(set, 'architecture');
      final ids = [for (final s in architecture.sections) s.id];
      expect(ids.indexOf('component_details'), ids.indexOf('components') + 1);
      final details = section('architecture', 'component_details');
      expect(details.header, 'Component details');
      expect(details.required, isFalse);
    });

    test(
      'the component diagram reads title, edge labels, and the Uses ban',
      () {
        final diagram = section('architecture', 'component_diagram').diagram!;
        expect((diagram.title, diagram.edgeLabels), (true, true));
        expect(diagram.bannedLabels, ['Uses']);
      },
    );

    test('the count, item field, required-when, and catalog keys sit on their '
        'sections', () {
      List<(int, String?)> sentences(String docType, String id) => [
        for (final s in section(docType, id).maxSentences!) (s.count, s.column),
      ];
      expect(sentences('architecture', 'components'), [(1, 'Responsibility')]);
      expect(sentences('domain', 'invariants'), [(1, null)]);
      expect(sentences('topic', 'rules'), [(1, null)]);
      expect(section('architecture', 'design_references').maxLines, 3);
      final fields = section('domain', 'invariants').itemFields!;
      expect([for (final f in fields) f.field], ['Enforcer', 'Consistency']);
      expect(fields.first.values, isNull);
      expect(fields.last.values, ['immediate', 'eventual']);
      final rule = section('domain', 'corrective_policies').requiredWhen!;
      expect(
        (rule.section, rule.field, rule.value),
        ('invariants', 'Consistency', 'eventual'),
      );
      expect(section('error', 'error_catalog').catalog!.column, 'Code');
    });

    test('no other spec section sets a guide-rule key', () {
      final found = <String>{
        for (final (docType, s) in specSections())
          if (s.maxSentences != null ||
              s.itemFields != null ||
              s.requiredWhen != null ||
              s.catalog != null ||
              s.diagram != null ||
              s.maxLines != null ||
              s.minLines != null ||
              s.itemCount != null ||
              s.namesCodes != null)
            '${docType.id}.${s.id}',
      };
      expect(found, {
        'architecture.component_diagram',
        'architecture.components',
        'architecture.design_references',
        'domain.invariants',
        'domain.corrective_policies',
        'topic.rules',
        'error.error_catalog',
      });
    });

    test('the record caps its characters at 60000 beside domain and '
        'architecture, and no other spec type sets a cap', () {
      for (final docType in set.docTypes) {
        if (docType.pack != 'software-tech') continue;
        expect(
          docType.lint.maxChars,
          {'domain', 'architecture', 'implementation'}.contains(docType.id)
              ? 60000
              : isNull,
          reason: docType.id,
        );
      }
    });
  });

  test(
    'the shipped prd-core pack is 1.8.0, so the guide-rule keys ride it',
    () {
      expect(shippedPackVersions()['prd-core'], '1.8.0');
    },
  );

  group('the prd-core guide-rule lint', () {
    late MergedSet set;
    setUpAll(() async {
      set = await resolvePrdCore();
    });

    MergedSection section(String docType, String id) =>
        sectionOf(prdCoreDocType(set, docType), id);

    PatternEntry entry(String docType, String sectionId, String id) => section(
      docType,
      sectionId,
    ).bannedPatterns!.singleWhere((p) => p.id == id);

    test('the section banned_patterns entries are exactly the guide-rule '
        'list, each on its section', () {
      final found = <String, List<String>>{
        for (final docType in set.docTypes)
          for (final s in docType.sections)
            if (s.bannedPatterns != null)
              '${docType.id}.${s.id}': [
                for (final p in s.bannedPatterns!) p.id,
              ],
      };
      expect(found, {
        'project.vision': ['quote_words', 'quote_language'],
        'project.goals': ['metric_number'],
        'feature.out_of_scope': ['out_of_scope_owner'],
        'user_story.acceptance_criteria': ['scenario_title'],
        'fr.statement': ['second_shall'],
        'fr.edge_cases': ['edge_case_arrow'],
        'nf.statement': ['second_shall', 'statement_number'],
        for (final category in _gnfrCategories)
          'gnfr.$category': ['second_shall', 'statement_number'],
      });
    });

    for (final rule in _guideRules) {
      test('${rule.docType}.${rule.section} ${rule.id}: fires on a broken '
          'line, passes a sound one, and cites its guide line', () {
        final sectionIds = rule.section == null
            ? _gnfrCategories
            : [rule.section!];
        for (final sectionId in sectionIds) {
          final docType = prdCoreDocType(set, rule.docType);
          final pattern = entry(rule.docType, sectionId, rule.id);
          for (final line in rule.hits) {
            expect(pattern.regExp.hasMatch(line), isTrue, reason: line);
          }
          for (final line in rule.misses) {
            expect(pattern.regExp.hasMatch(line), isFalse, reason: line);
          }
          expect(pattern.scope, rule.scope, reason: rule.id);
          expect(pattern.message, contains(rule.phrase), reason: rule.id);
          final guide = [
            docType.description,
            section(rule.docType, sectionId).description,
          ].join('\n');
          expect(guide, contains(rule.phrase), reason: rule.id);
        }
      });
    }

    test('a gnfr category reads its patterns on the Statement lines only', () {
      for (final category in _gnfrCategories) {
        expect(
          section('gnfr', category).linePrefix,
          '- **Statement:**',
          reason: category,
        );
      }
    });

    test('title_no_number is true on persona, anti_persona, feature, and '
        'journey, and unset on the others', () {
      const numbered = {'persona', 'anti_persona', 'feature', 'journey'};
      for (final docType in set.docTypes) {
        expect(
          docType.lint.titleNoNumber,
          numbered.contains(docType.id) ? isTrue : isNull,
          reason: docType.id,
        );
      }
    });

    test('the count keys sit on their sections', () {
      List<(int, String?)> sentences(String docType, String id) => [
        for (final s in section(docType, id).maxSentences!)
          (s.count, s.linePrefix),
      ];
      expect(sentences('project', 'vision'), [
        (1, '- **Why:**'),
        (1, '- **Problem:**'),
        (1, '- **Audience:**'),
      ]);
      expect(sentences('fr', 'statement'), [(1, null)]);
      final stories = section('user_story', 'acceptance_criteria').itemCount!;
      expect((stories.min, stories.max, stories.perSubsection), (3, 5, true));
      expect(
        [for (final p in stories.prefixes) (p.linePrefix, p.count)],
        [('- **When**', 1)],
      );
      final jobs = section('persona', 'jobs').itemCount!;
      expect((jobs.min, jobs.max, jobs.perSubsection), (3, 4, false));
      for (final docType in ['persona', 'anti_persona']) {
        final snapshot = section(docType, 'snapshot');
        expect((snapshot.minLines, snapshot.maxLines), (2, 4), reason: docType);
      }
    });

    test('no other section sets a count key', () {
      final found = <String>{
        for (final docType in set.docTypes)
          for (final s in docType.sections)
            if (s.maxSentences != null ||
                s.itemCount != null ||
                s.minLines != null ||
                s.maxLines != null)
              '${docType.id}.${s.id}',
      };
      expect(found, {
        'project.vision',
        'fr.statement',
        'user_story.acceptance_criteria',
        'persona.jobs',
        'persona.snapshot',
        'anti_persona.snapshot',
      });
    });

    test('names_codes is true on the fr edge cases and the story acceptance '
        'criteria, and set nowhere else', () {
      final found = <String>{
        for (final docType in set.docTypes)
          for (final s in docType.sections)
            if (s.namesCodes != null) '${docType.id}.${s.id}',
      };
      expect(found, {'fr.edge_cases', 'user_story.acceptance_criteria'});
      expect(section('fr', 'edge_cases').namesCodes, isTrue);
      expect(section('user_story', 'acceptance_criteria').namesCodes, isTrue);
    });

    test('diagram is an empty map on the feature flow, the fr behavior, and '
        'the features diagram, so only the quoting part reads', () {
      final found = <String>{
        for (final docType in set.docTypes)
          for (final s in docType.sections)
            if (s.diagram != null) '${docType.id}.${s.id}',
      };
      expect(found, {'feature.flow', 'fr.behavior', 'features.diagram'});
      for (final key in found) {
        final diagram = section(
          key.split('.').first,
          key.split('.').last,
        ).diagram!;
        expect(
          (diagram.title, diagram.edgeLabels),
          (false, false),
          reason: key,
        );
        expect(diagram.bannedLabels, isEmpty, reason: key);
      }
    });

    test('the fr tbr section bans TBD and the nf tbr section bans nothing', () {
      expect(section('fr', 'tbr').bannedWords, ['TBD']);
      expect(section('nf', 'tbr').bannedWords, isNull);
    });
  });

  test('template_packs/write_prd_docs_from_prd_core/'
      'write_shipped_writing_guides E05: the shipped feature type names the '
      'three size findings', () {
    final feature = utf8.decode(shippedPackFiles['prd-core/feature.yaml']!);
    for (final finding in [
      'chars_over_limit',
      'lines_over_limit',
      'item_over_limit',
    ]) {
      expect(feature, contains('`$finding`'));
    }
  });
}

const _gnfrCategories = <String>[
  'performance',
  'security',
  'reliability',
  'maintainability',
  'interface',
  'environment',
  'safety',
  'operability',
  'design_standards',
];

final class _GuideRule {
  const new(
    this.docType,
    this.section,
    this.id, {
    required this.phrase,
    required this.hits,
    required this.misses,
    this.scope = PatternScope.all,
    this.required = false,
  });

  final String docType;

  /// The section id, or null for each of the nine gnfr categories.
  final String? section;
  final String id;

  /// A phrase of the guide that the message repeats.
  final String phrase;
  final List<String> hits;
  final List<String> misses;
  final PatternScope scope;

  /// Whether the entry is a `required_patterns` entry.
  final bool required;
}

const _fifteenWords = 'w0 w1 w2 w3 w4 w5 w6 w7 w8 w9 w10 w11 w12 w13 w14';
const _sixteenWords = '$_fifteenWords w15';

const _guideRules = <_GuideRule>[
  _GuideRule(
    'project',
    'vision',
    'quote_words',
    phrase: 'keep each sentence to 15 words or fewer',
    hits: ['> en: $_sixteenWords', '> th: $_sixteenWords and more'],
    misses: ['> en: $_fifteenWords', '- **Why:** $_sixteenWords'],
  ),
  _GuideRule(
    'project',
    'vision',
    'quote_language',
    phrase: 'Use an ISO 639-1 code',
    hits: ['> eng: hello', '> EN: hello', '> e: hello', '> pt-BR: hello'],
    misses: [
      '> en: hello',
      '> th: สวัสดี',
      '- **Why:** a: b',
      '> Note this: x',
    ],
  ),
  _GuideRule(
    'project',
    'goals',
    'metric_number',
    phrase: 'a numeric metric with unit',
    hits: ['**Metric:** a fast tool', '**Metric:**', '- **Metric:** soon'],
    misses: ['**Metric:** at most 3 tool calls', '**Serves:** PV-02'],
  ),
  _GuideRule(
    'feature',
    'out_of_scope',
    'out_of_scope_owner',
    phrase: 'Write each line as `<thing> — <owning feature | not planned>`',
    hits: ['- Offline mode', '* Cloud sync'],
    misses: ['- Cloud sync — not planned', '- Export — f02_export'],
  ),
  _GuideRule(
    'user_story',
    'acceptance_criteria',
    'scenario_title',
    phrase: '### Scenario N — [happy|edge|error] <what differs>',
    hits: [
      '### Scenario 1 [happy] Login works',
      '### Scenario 1 — [odd] Login works',
      '### Scenario 1 — [happy]',
      '### Scenario — [happy] Login works',
      '### Scenario 1 - [happy] Login works',
    ],
    misses: [
      '### Scenario 1 — [happy] Login works',
      '### Scenario 12 — [error] Wrong password (BR-01)',
      '### Not a scenario',
    ],
  ),
  _GuideRule(
    'fr',
    'statement',
    'second_shall',
    phrase: 'one "shall"',
    scope: PatternScope.text,
    hits: ['The system shall save and shall print 10 files.'],
    misses: ['The system shall save 10 files.'],
  ),
  _GuideRule(
    'nf',
    'statement',
    'second_shall',
    phrase: 'one "shall"',
    scope: PatternScope.text,
    hits: ['The system shall save and shall print 10 files.'],
    misses: ['The system shall save 10 files.'],
  ),
  _GuideRule(
    'gnfr',
    null,
    'second_shall',
    phrase: 'one "shall"',
    scope: PatternScope.text,
    hits: ['- **Statement:** The product shall save and shall print 10 files.'],
    misses: ['- **Statement:** The product shall save 10 files.'],
  ),
  _GuideRule(
    'nf',
    'statement',
    'statement_number',
    phrase: 'a quantified value',
    hits: ['The system shall respond quickly.'],
    misses: ['The system shall respond within 2 s.', 'It is a note.'],
  ),
  _GuideRule(
    'gnfr',
    null,
    'statement_number',
    phrase: 'a quantified value',
    hits: ['- **Statement:** The product shall respond quickly.'],
    misses: ['- **Statement:** The product shall respond within 2 s.'],
  ),
  _GuideRule(
    'fr',
    'edge_cases',
    'edge_case_arrow',
    phrase: 'E01 — <trigger> → <response>',
    hits: ['1. E01 — A case with no arrow', '- E02 — A case with none'],
    misses: ['1. E01 — A case → what happens', '   a wrapped line'],
  ),
];

final _specGuideRules = <_GuideRule>[
  const _GuideRule(
    'architecture',
    'components',
    'table_only',
    phrase: 'Write no line but a table line',
    hits: [
      '- a bullet under the table',
      'Some prose',
      '  | indented row',
      '### Sub',
    ],
    misses: [
      '| Component | Responsibility |',
      '|---|---|',
      '',
      '## Components',
    ],
  ),
  const _GuideRule(
    'architecture',
    'concerns',
    'concern_ending',
    phrase:
        'End each line with `see <section or sibling doc>` or `N/A — <reason>`',
    hits: [
      '- Integration — handled elsewhere',
      'Errors: fine',
      '- Auth — N/A —',
    ],
    misses: [
      '- Integration — see `API.md`',
      '- Errors — N/A — no new code',
      '- Auth — see AUTH.md#roles',
      '',
      '## Concerns',
    ],
  ),
  const _GuideRule(
    'api',
    'operations',
    'operation_heading',
    phrase: 'alone with no FR label',
    hits: ['### `create` — FR-01', '### `create` FR-01', '### `create` (v2)'],
    misses: ['### `create`', '### `POST /items`', '#### `x` y', '- `x` y'],
  ),
  const _GuideRule(
    'auth',
    'scopes',
    'scope_form',
    phrase: 'write each scope as `<resource>:<action>`',
    hits: [
      '| read | read items | list |',
      '| `items` | read | list |',
      '| items.read | read | list |',
      '| | read | list |',
    ],
    misses: [
      '| `items:read` | read | list |',
      '| items:read | read | list |',
      '| Scope | Action | Required for |',
      '|---|---|---|',
      '| --- | --- | --- |',
      '| :---: | --- | --- |',
      'Default scope: items:read',
    ],
  ),
  const _GuideRule(
    'auth',
    'resource_matrix',
    'matrix_cell',
    phrase: '`yes`, `no`, `own` (the resource belongs to the caller), or `any`',
    hits: [
      '| /items | yes | maybe |',
      '| /items | GET | yes | Y |',
      '| /items | own | read |',
      '| /items | no | ✓ |',
    ],
    misses: [
      '| Resource | admin | user |',
      '|---|---|---|',
      '| /items | yes | no |',
      '| /items | | any |',
      '| /items | GET | own | |',
      '| /items | `yes` | `no` |',
      'Default: deny',
    ],
  ),
  const _GuideRule(
    'domain',
    'entities',
    'entity_kind',
    phrase: 'Write Kind as Aggregate root, Entity, Service, or Repository',
    hits: [
      '| Order | Thing | id | lines | | note |',
      '| Order | | id |',
      '| Order | aggregate root | id |',
    ],
    misses: [
      '| Entity | Kind | Identity |',
      '|---|---|---|',
      '| :---: | :---: | --- |',
      '| Order | Aggregate root | id |',
      '| Line | Entity | id |',
      '| Clock | Service | none |',
      '| Orders | Repository | id |',
    ],
  ),
  const _GuideRule(
    'domain',
    'invariants',
    'numbered_invariant',
    phrase: 'never a numbered item',
    hits: ['1. **INV-1** one rule', '12) The rule'],
    misses: ['- **INV-1** one rule', '  - **Enforcer:** order'],
  ),
  for (final (concern, id) in [
    ('Integration', 'concern_integration'),
    ('Errors', 'concern_errors'),
    ('Auth', 'concern_auth'),
    ('Lifecycle', 'concern_lifecycle'),
    ('Events', 'concern_events'),
    ('Rollout', 'concern_rollout'),
    ('Observability', 'concern_observability'),
  ])
    _GuideRule(
      'architecture',
      'concerns',
      id,
      phrase: concern,
      required: true,
      hits: [
        '- $concern — see `API.md`',
        '- **$concern:** N/A — none',
        '$concern — see x',
      ],
      misses: [
        '- ${concern}s — see x',
        '- The $concern — see x',
        '- ${concern}ation — see x',
      ],
    ),
];
