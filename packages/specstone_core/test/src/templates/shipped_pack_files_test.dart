import 'dart:convert';

import 'package:specstone_core/src/doc_model/path_pattern.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:specstone_core/src/templates/pack_manifest.dart';
import 'package:specstone_core/src/templates/shipped_pack_files.dart';
import 'package:test/test.dart';

import '../../helpers/prd_core.dart';
import '../../helpers/software_tech.dart';

const _guideLineMarker = 'guide line: ';

void main() {
  test('decodes base64 constants back to bytes', () {
    final files = decodeShippedPacks({
      'a/x.pdf': base64Encode([0xff, 0, 1]),
    });

    expect(files['a/x.pdf'], [0xff, 0, 1]);
  });

  test('the shipped pack files are decoded', () {
    expect(shippedPackFiles.keys, contains('prd-core/pack.yaml'));
  });

  test('shippedPackVersions reads the version each '
      'shipped pack.yaml carries', () {
    final versions = shippedPackVersions();
    expect(versions.keys, [
      'agent-skills',
      'marketing',
      'personal-branding',
      'prd-core',
      'software-design-system',
      'software-tech',
    ]);
    for (final MapEntry(:key, :value) in versions.entries) {
      final manifest = PackManifest.parse(
        utf8.decode(shippedPackFiles['$key/pack.yaml']!),
        file: 'packs/$key/pack.yaml',
      );
      expect(value, manifest.version.toString());
    }
  });

  group('the shipped software-tech pack', () {
    late MergedSet both;
    late MergedSet prdOnly;
    setUpAll(() async {
      both = await resolveSoftwareTech();
      prdOnly = await resolvePrdCore();
    });

    test('the pack writes no layer over a prd-core doc type, so a '
        'story and an FR carry no code-pointer field', () {
      final files = shippedPackFiles.keys
          .where(
            (k) =>
                k.startsWith('software-tech/') &&
                !k.startsWith('software-tech/patterns/'),
          )
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

    test('every software-tech doc type but decision is per target and no '
        'prd-core one is, so each reads specs/<target>/ with two targets', () {
      for (final docType in both.docTypes) {
        expect(
          docType.isPerTarget,
          softwareTechIds.contains(docType.id) && docType.id != 'decision',
          reason: docType.id,
        );
      }
      expect(
        PathPattern(prdCoreDocType(both, 'implementation').path!)
            .forTarget('jaspr')
            .source,
        '.specstone/records/jaspr/f{nn}_{slug}/IMPLEMENTATION.md',
      );
      expect(
        PathPattern(prdCoreDocType(both, 'tech_stack').path!)
            .forTarget('jaspr')
            .source,
        'specs/jaspr/TECH_STACK.md',
      );
    });

    test('a project that lists only prd-core gets no implementation '
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

    test('the implementation record holds the status and the code '
        'lines, each optional, and the one optional matrix section', () {
      final record = both.recordDocType!;
      expect(record.id, 'implementation');
      expect(record.isPerTarget, isTrue);
      expect(record.sections.map((s) => s.id), ['verification_matrix']);
      expect(record.sections.single.required, isFalse);
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
        FieldSpec(
          'covers',
          FieldType.outputRef,
          list: true,
          pointer: PointerKind.prefix,
        ),
      ]);
    });

    test('the other pointer fields keep their kind and requirement', () {
      expectOwnFields(prdCoreDocType(both, 'architecture'), const [
        FieldSpec('overrides', FieldType.string, list: true),
        FieldSpec('tasks', FieldType.taskRef, list: true),
      ]);
      expectOwnFields(prdCoreDocType(both, 'decision'), const [
        FieldSpec('superseded_by', FieldType.docRef, docTypes: ['decision']),
        FieldSpec('tasks', FieldType.taskRef, list: true),
      ]);
      expectOwnFields(prdCoreDocType(both, 'tech_stack'), const [
        FieldSpec('code', FieldType.string, list: true),
        FieldSpec('tasks', FieldType.taskRef, list: true),
      ]);
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
          'architecture.observability': ['log_channel_form'],
          'api.operations': ['operation_heading', 'why_line'],
          'integration.events': ['action_value'],
          'security.threats': ['stride_value', 'response_value'],
          'project_architecture.components': ['table_only'],
          'project_architecture.observability': ['log_channel_form'],
          'project_security.threats': ['stride_value', 'response_value'],
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
          'api.operations': ['errors_line', 'auth_line'],
          'integration.contract_per_system': ['endpoints_used'],
        },
      );
    });

    for (final rule in _specGuideRules) {
      test('${rule.docType}.${rule.section} ${rule.id}: fires on a broken '
          'line and passes a sound one', () {
        final sectionOfRule = section(rule.docType, rule.section!);
        final pattern = sectionOfRule.bannedPatterns!.singleWhere(
          (p) => p.id == rule.id,
        );
        for (final line in rule.hits) {
          expect(pattern.regExp.hasMatch(line), isTrue, reason: line);
        }
        for (final line in rule.misses) {
          expect(pattern.regExp.hasMatch(line), isFalse, reason: line);
        }
        expect(pattern.scope, rule.scope);
      });
    }

    test('the count, item field, required-when, and catalog keys sit on their '
        'sections', () {
      List<(int, String?)> sentences(String docType, String id) => [
        for (final s in section(docType, id).maxSentences!) (s.count, s.column),
      ];
      expect(sentences('architecture', 'components'), [(1, 'Responsibility')]);
      expect(sentences('api', 'errors'), [
        (1, 'Condition'),
        (1, 'Client action'),
      ]);
      expect(sentences('project_api', 'error_model'), [
        (1, 'Condition'),
        (1, 'Client action'),
      ]);
      expect(sentences('tech_stack', 'stack'), [(1, 'Why')]);
      expect(
        set.docTypes
            .where((t) => t.pack == 'software-tech')
            .expand((t) => t.sections)
            .where((s) => s.itemFields != null),
        isEmpty,
      );
      expect(
        set.docTypes
            .where((t) => t.pack == 'software-tech')
            .expand((t) => t.sections)
            .where((s) => s.requiredWhen != null),
        isEmpty,
      );
      expect(section('api', 'errors').catalog!.column, 'Code');
      expect(section('project_api', 'error_model').catalog!.column, 'Code');
    });

    test('the line key sits on its section', () {
      expect(section('security', 'enforcement').maxLines, 1);
      expect(section('project_security', 'enforcement').maxLines, 1);
      expect([
        for (final (docType, s) in specSections())
          if (s.id == 'design_references') docType.id,
      ], isEmpty);
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
              s.maxItemLines != null ||
              s.namesCodes != null)
            '${docType.id}.${s.id}',
      };
      expect(found, {
        'architecture.technical_diagram',
        'architecture.components',
        'security.enforcement',
        'tech_stack.stack',
        'api.errors',
        'project_architecture.technical_diagram',
        'project_architecture.components',
        'project_security.enforcement',
        'project_api.error_model',
        'project_api.conventions',
      });
    });

    test(
      'no shipped section but the architecture technical diagram sets names',
      () {
        expect(
          {
            for (final (docType, s) in specSections())
              if (s.diagram?.names ?? false) '${docType.id}.${s.id}',
          },
          {
            'architecture.technical_diagram',
            'project_architecture.technical_diagram',
          },
        );
      },
    );

    test(
      'each project spec doc type takes the caps of the type it extends',
      () {
        for (final MapEntry(key: id, value: base)
            in projectSpecDocBases.entries) {
          final project = prdCoreDocType(set, id).lint;
          final extended = prdCoreDocType(set, base).lint;
          expect(
            (project.maxLines, project.maxChars),
            (extended.maxLines, extended.maxChars),
            reason: id,
          );
        }
      },
    );
  });

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
      // A shared pattern joins a list after its local entries, and check sorts
      // its findings, so each section's entries compare as a set.
      final found = <String, Set<String>>{
        for (final docType in set.docTypes)
          for (final s in docType.sections)
            if (s.bannedPatterns != null)
              '${docType.id}.${s.id}': {
                for (final p in s.bannedPatterns!) p.id,
              },
      };
      expect(found, {
        'project.vision': {'quote_words', 'quote_language'},
        'goal.long_term': {'metric_number'},
        'goal.mid_term': {'metric_number'},
        'goal.short_term': {'metric_number'},
        'feature.out_of_scope': {'out_of_scope_owner'},
        'user_story.acceptance_criteria': {'scenario_title'},
        'fr.statement': {'second_shall', 'trace_outside_field'},
        'fr.edge_cases': {'edge_case_arrow', 'trace_outside_field'},
        'fr.rationale': {'trace_outside_field'},
        'glossary.terms': {'term_bullet_form'},
        'fr.verification': {'test_file_named'},
        'measurement.scope': {'history'},
        'measurement.method': {'history', 'method_numbered'},
        'measurement.baseline': {'history'},
        'measurement.open_causes': {'history'},
        'reference.summary': {'fact_locator'},
        'nf.statement': {
          'second_shall',
          'statement_number',
          'trace_outside_field',
        },
        for (final category in _gnfrCategories)
          'gnfr.$category': {
            'second_shall',
            'statement_number',
            'trace_outside_field',
          },
      });
    });

    test('fr holds exit_status once, at doc level, reading the raw line', () {
      // D6: Behavior and Input / Output reach it with no copy of their own.
      final doc = prdCoreDocType(
        set,
        'fr',
      ).lint.bannedPatterns!.where((p) => p.id == 'exit_status');

      expect(doc.map((p) => p.scope), [PatternScope.all]);
    });

    test('each section pattern message that names a guide line names one the '
        'doc type guide prints', () {
      var named = 0;
      for (final docType in set.docTypes) {
        final guide = docType.renderGuide();
        for (final s in docType.sections) {
          for (final p in s.bannedPatterns ?? const <PatternEntry>[]) {
            final at = p.message.indexOf(_guideLineMarker);
            if (at < 0) continue;
            named++;
            expect(
              guide,
              contains(p.message.substring(at + _guideLineMarker.length)),
              reason: '${docType.id}.${s.id} ${p.id}',
            );
          }
        }
      }
      expect(named, greaterThan(0));
    });

    for (final rule in _guideRules) {
      test('${rule.docType}.${rule.section} ${rule.id}: fires on a broken '
          'line and passes a sound one', () {
        final sectionIds = rule.section == null
            ? _gnfrCategories
            : [rule.section!];
        for (final sectionId in sectionIds) {
          final pattern = entry(rule.docType, sectionId, rule.id);
          for (final line in rule.hits) {
            expect(pattern.regExp.hasMatch(line), isTrue, reason: line);
          }
          for (final line in rule.misses) {
            expect(pattern.regExp.hasMatch(line), isFalse, reason: line);
          }
          expect(pattern.scope, rule.scope, reason: rule.id);
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
        [('- **When**', 1), ('- **Then**', 1)],
      );
      final jobs = section('persona', 'jobs').itemCount!;
      expect((jobs.min, jobs.max, jobs.perSubsection), (3, 4, false));
      for (final docType in ['persona', 'anti_persona']) {
        final snapshot = section(docType, 'snapshot');
        expect((snapshot.minLines, snapshot.maxLines), (2, 4), reason: docType);
      }
      final edgeCases = section('fr', 'edge_cases').itemCount!;
      expect(
        (
          edgeCases.min,
          edgeCases.max,
          edgeCases.perSubsection,
          edgeCases.waitsForOwner,
        ),
        (null, 8, false, true),
      );
      final rules = section('user_story', 'rules').itemCount!;
      expect((rules.min, rules.max), (2, null));
      final alternatives = section('persona', 'alternatives').itemCount!;
      expect((alternatives.min, alternatives.max), (1, null));
      expect(section('journey', 'goal').maxLines, 1);
      for (final (docType, id) in [
        ('feature', 'out_of_scope'),
        ('glossary', 'terms'),
        ('project', 'name'),
        ('project', 'roles'),
      ]) {
        expect(section(docType, id).maxItemLines, 1, reason: '$docType.$id');
      }
    });

    test('the story scenario cap is 6 and no other section sets one', () {
      expect(section('user_story', 'acceptance_criteria').maxSubsections, 6);
      final found = <String>{
        for (final docType in set.docTypes)
          for (final s in docType.sections)
            if (s.maxSubsections != null) '${docType.id}.${s.id}',
      };
      expect(found, {'user_story.acceptance_criteria'});
    });

    test('the five misuser sections are required and held only when '
        'anti_type is misuser, and no other section sets when_field', () {
      const misuserSections = [
        'motivations',
        'actions',
        'tools',
        'needs',
        'consequences',
      ];
      for (final id in misuserSections) {
        final s = section('anti_persona', id);
        expect(s.required, isTrue, reason: id);
        expect(s.whenField?.field, 'anti_type', reason: id);
        expect(s.whenField?.values, ['misuser'], reason: id);
      }
      final found = <String>{
        for (final docType in set.docTypes)
          for (final s in docType.sections)
            if (s.whenField != null) '${docType.id}.${s.id}',
      };
      expect(found, {for (final id in misuserSections) 'anti_persona.$id'});
    });

    test('no other section sets a count key', () {
      final found = <String>{
        for (final docType in set.docTypes)
          for (final s in docType.sections)
            if (s.maxSentences != null ||
                s.itemCount != null ||
                s.minLines != null ||
                s.maxLines != null ||
                s.maxItemLines != null)
              '${docType.id}.${s.id}',
      };
      expect(found, {
        'project.vision',
        'project.name',
        'project.roles',
        'fr.statement',
        'fr.edge_cases',
        'user_story.acceptance_criteria',
        'user_story.rules',
        'persona.jobs',
        'persona.snapshot',
        'persona.alternatives',
        'anti_persona.snapshot',
        'journey.goal',
        'feature.out_of_scope',
        'glossary.terms',
      });
    });

    test('names_codes is true on four fr and story sections, the nine gnfr '
        'categories, and nf.statement, and set nowhere else (D13)', () {
      final named = {
        'fr.statement',
        'fr.input_output',
        'fr.edge_cases',
        'user_story.acceptance_criteria',
        for (final category in _gnfrCategories) 'gnfr.$category',
        'nf.statement',
      };
      final found = <String>{
        for (final docType in set.docTypes)
          for (final s in docType.sections)
            if (s.namesCodes != null) '${docType.id}.${s.id}',
      };
      expect(found, named);
      for (final key in named) {
        final [docType, id] = key.split('.');
        expect(section(docType, id).namesCodes, isTrue, reason: key);
      }
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

    test('every prd-core diagram section reads names as false', () {
      for (final docType in set.docTypes) {
        for (final s in docType.sections) {
          if (s.diagram == null) continue;
          expect(s.diagram!.names, isFalse, reason: '${docType.id}.${s.id}');
        }
      }
    });

    test('the fr tbr section bans TBD and the nf tbr section bans nothing', () {
      expect(section('fr', 'tbr').bannedWords, ['TBD']);
      expect(section('nf', 'tbr').bannedWords, isNull);
    });
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
    required this.hits,
    required this.misses,
    this.scope = PatternScope.all,
  });

  final String docType;

  /// The section id, or null for each of the nine gnfr categories.
  final String? section;
  final String id;

  final List<String> hits;
  final List<String> misses;
  final PatternScope scope;
}

const _fifteenWords = 'w0 w1 w2 w3 w4 w5 w6 w7 w8 w9 w10 w11 w12 w13 w14';
const _sixteenWords = '$_fifteenWords w15';

const _guideRules = <_GuideRule>[
  _GuideRule(
    'project',
    'vision',
    'quote_words',
    hits: ['> en: $_sixteenWords', '> th: $_sixteenWords and more'],
    misses: ['> en: $_fifteenWords', '- **Why:** $_sixteenWords'],
  ),
  _GuideRule(
    'project',
    'vision',
    'quote_language',
    hits: ['> eng: hello', '> EN: hello', '> e: hello', '> pt-BR: hello'],
    misses: [
      '> en: hello',
      '> th: สวัสดี',
      '- **Why:** a: b',
      '> Note this: x',
    ],
  ),
  _GuideRule(
    'goal',
    'long_term',
    'metric_number',
    hits: ['**Metric:** a fast tool', '**Metric:**', '- **Metric:** soon'],
    misses: ['**Metric:** at most 3 tool calls', '**Serves:** PV-02'],
  ),
  _GuideRule(
    'goal',
    'mid_term',
    'metric_number',
    hits: ['**Metric:** a fast tool', '**Metric:**', '- **Metric:** soon'],
    misses: ['**Metric:** at most 3 tool calls', '**Serves:** PV-02'],
  ),
  _GuideRule(
    'goal',
    'short_term',
    'metric_number',
    hits: ['**Metric:** a fast tool', '**Metric:**', '- **Metric:** soon'],
    misses: ['**Metric:** at most 3 tool calls', '**Serves:** PV-02'],
  ),
  _GuideRule(
    'feature',
    'out_of_scope',
    'out_of_scope_owner',
    hits: ['- Offline mode', '* Cloud sync'],
    misses: ['- Cloud sync — not planned', '- Export — f02_export'],
  ),
  _GuideRule(
    'user_story',
    'acceptance_criteria',
    'scenario_title',
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
    scope: PatternScope.text,
    hits: ['The system shall save and shall print 10 files.'],
    misses: ['The system shall save 10 files.'],
  ),
  _GuideRule(
    'nf',
    'statement',
    'second_shall',
    scope: PatternScope.text,
    hits: ['The system shall save and shall print 10 files.'],
    misses: ['The system shall save 10 files.'],
  ),
  _GuideRule(
    'gnfr',
    null,
    'second_shall',
    scope: PatternScope.text,
    hits: ['- **Statement:** The product shall save and shall print 10 files.'],
    misses: ['- **Statement:** The product shall save 10 files.'],
  ),
  _GuideRule(
    'nf',
    'statement',
    'statement_number',
    hits: ['The system shall respond quickly.'],
    misses: ['The system shall respond within 2 s.', 'It is a note.'],
  ),
  _GuideRule(
    'gnfr',
    null,
    'statement_number',
    hits: ['- **Statement:** The product shall respond quickly.'],
    misses: ['- **Statement:** The product shall respond within 2 s.'],
  ),
  _GuideRule(
    'fr',
    'edge_cases',
    'edge_case_arrow',
    hits: ['1. E01 — A case with no arrow', '- E02 — A case with none'],
    misses: ['1. E01 — A case → what happens', '   a wrapped line'],
  ),
  _GuideRule(
    'fr',
    'verification',
    'test_file_named',
    hits: [
      'Run `test/x_test.dart`.',
      'Run `tests/fixtures/a.json`.',
      'Run `packages/app/test/`.',
      'Read `test/README` first.',
      '- **Pass criteria:** login_test.dart passes.',
      'See login.test.ts and login.spec.js.',
    ],
    misses: [
      'Test: a wrong password is refused.',
      '- **Level:** unit/integration',
      'Level: test/analysis, per the test method.',
      'Level: test/analysis/inspection',
      'Level: analysis/test/demonstration.',
      'A test-driven check of the latest sign-in.',
    ],
  ),
];

final _specGuideRules = <_GuideRule>[
  const _GuideRule(
    'architecture',
    'components',
    'table_only',
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
      'Overrides: [INV-1](../DOMAIN.md#invariants) — slower, because it caches',
      '- Overrides: [INV-1](../DOMAIN.md#invariants) — slower, because it caches',
    ],
  ),
  const _GuideRule(
    'architecture',
    'observability',
    'log_channel_form',
    hits: ['- audit log: sign-in', '- audit-log', '- audit-log - '],
    misses: [
      '- audit-log - sign-in, sign-out',
      '- `audit` - sign-in',
      '| Signal | SLI |',
      '',
      '## Observability',
      'A plain line',
      '- Overrides: [INV-1](../DOMAIN.md#invariants) — slower, because it caches',
    ],
  ),
  const _GuideRule(
    'api',
    'operations',
    'why_line',
    hits: ['**Why:** users wait', '- **Why:** users wait'],
    misses: ['**Errors:** none', 'Why users wait', '', '## Operations'],
  ),
  const _GuideRule(
    'integration',
    'events',
    'action_value',
    hits: [
      '| mail.sent | mail | publish | schema | id | v1 |',
      '| mail.sent | mail |  | schema | id | v1 |',
      '| mail.sent | mail | Send | schema | id | v1 |',
    ],
    misses: [
      '| mail.sent | mail | send | schema | id | v1 |',
      '| mail.sent | mail | `receive` | schema | id | v1 |',
      '| Event type | Channel | Action | Payload schema |',
      '|---|---|---|---|',
      '',
    ],
  ),
  const _GuideRule(
    'api',
    'operations',
    'operation_heading',
    hits: ['### `create` — FR-01', '### `create` FR-01', '### `create` (v2)'],
    misses: ['### `create`', '### `POST /items`', '#### `x` y', '- `x` y'],
  ),
  const _GuideRule(
    'security',
    'threats',
    'stride_value',
    hits: [
      '| Login form | Spoof | A forged session | mitigate | low | `t` |',
      '| Login form |  | A forged session | mitigate | low | `t` |',
      '| Login form | spoofing | A forged session | mitigate | low | `t` |',
    ],
    misses: [
      '| Login form | Spoofing | A forged session | mitigate | low | `t` |',
      '| Store | Information disclosure | A leak | accept | low | none |',
      '| Element | STRIDE | Threat | Response | Residual risk | Proved by |',
      '|---|---|---|---|---|---|',
      '',
    ],
  ),
  const _GuideRule(
    'security',
    'threats',
    'response_value',
    hits: [
      '| Login form | Spoofing | A forged session | ignore | low | `t` |',
      '| Login form | Spoofing | A forged session |  | low | `t` |',
      '| Login form | Spoofing | A forged session | Mitigate | low | `t` |',
    ],
    misses: [
      '| Login form | Spoofing | A forged session | mitigate | low | `t` |',
      '| Store | Tampering | A rewrite | transfer | low | none |',
      '| Element | STRIDE | Threat | Response | Residual risk | Proved by |',
      '|---|---|---|---|---|---|',
      '',
    ],
  ),
];
