import 'dart:convert';

import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/doc_model/path_pattern.dart';
import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:specstone_core/src/templates/pack_manifest.dart';
import 'package:specstone_core/src/templates/pattern_entry.dart';
import 'package:specstone_core/src/templates/shipped_pack_files.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/prd_core.dart';
import '../../helpers/software_tech.dart';

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

    test('each doc type takes the path and the parent of the Output '
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
        'implementation': (
          '.specstone/records/f{nn}_{slug}/IMPLEMENTATION.md',
          'feature',
        ),
        'project_architecture': ('specs/ARCHITECTURE.md', null),
        'project_domain': ('specs/DOMAIN.md', null),
        'project_api': ('specs/API.md', null),
        'project_integration': ('specs/INTEGRATION.md', null),
        'project_error': ('specs/ERROR.md', null),
        'project_auth': ('specs/AUTH.md', null),
      };
      expect(outputTable.keys, unorderedEquals(softwareTechIds));
      for (final MapEntry(key: id, value: (path, parent))
          in outputTable.entries) {
        final docType = prdCoreDocType(both, id);
        expect(docType.path, path, reason: id);
        expect(docType.parent, parent, reason: id);
      }
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

    test('every software-tech doc type is per target and no '
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
      ]);
    });

    test('the other pointer fields keep their kind and requirement', () {
      expectOwnFields(prdCoreDocType(both, 'architecture'), const [
        FieldSpec(
          'covers',
          FieldType.outputRef,
          list: true,
          required: true,
          pointer: PointerKind.prefix,
        ),
        FieldSpec('overrides', FieldType.string, list: true),
        FieldSpec('tasks', FieldType.taskRef, list: true),
      ]);
      expectOwnFields(prdCoreDocType(both, 'topic'), const [
        FieldSpec(
          'covers',
          FieldType.outputRef,
          list: true,
          required: true,
          pointer: PointerKind.prefix,
        ),
        FieldSpec('overrides', FieldType.string, list: true),
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
          'architecture.concerns': ['concern_ending'],
          'api.operations': ['operation_heading'],
          'topic.interface': ['interface_pointer'],
          'auth.scopes': ['scope_form'],
          'auth.resource_matrix': ['matrix_cell'],
          'domain.entities': ['entity_kind'],
          'domain.invariants': ['numbered_invariant'],
          'project_architecture.components': ['table_only'],
          'project_architecture.concerns': ['concern_ending'],
          'project_auth.scopes': ['scope_form'],
          'project_auth.resource_matrix': ['matrix_cell'],
          'project_domain.entities': ['entity_kind'],
          'project_domain.invariants': ['numbered_invariant'],
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
          'api.operations': ['response_success', 'response_error'],
          for (final id in ['architecture', 'project_architecture'])
            '$id.concerns': [
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
          'line and passes a sound one', () {
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
      });
    }

    test('the topic interface limits its pointer rule to the `- ` lines, and '
        'each api operation needs both response examples per subsection', () {
      expect(section('topic', 'interface').linePrefix, '- ');
      for (final id in ['response_success', 'response_error']) {
        final entry = section(
          'api',
          'operations',
        ).requiredPatterns!.singleWhere((p) => p.id == id);
        expect(entry.perSubsection, isTrue, reason: id);
      }
    });

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
      final fields = section('domain', 'invariants').itemFields!;
      expect(
        [for (final f in fields) f.field],
        ['Enforcer', 'Consistency', 'Corrective policy'],
      );
      expect(fields.first.values, isNull);
      expect(fields[1].values, ['immediate', 'eventual']);
      expect(fields.last.values, isNull);
      expect(fields.last.when!.field, 'Consistency');
      expect(fields.last.when!.value, 'eventual');
      expect(
        set.docTypes
            .where((t) => t.pack == 'software-tech')
            .expand((t) => t.sections)
            .where((s) => s.requiredWhen != null),
        isEmpty,
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
        'domain.invariants',
        'topic.rules',
        'error.error_catalog',
        'project_architecture.component_diagram',
        'project_architecture.components',
        'project_domain.invariants',
        'project_error.error_catalog',
        'project_api.conventions',
      });
    });

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

  group('the shipped api and topic lint entries under check', () {
    const operation = '### `signIn`\n\nSigns the Agent in.\n\n';
    const success = '**Response example — success**\n\n';
    const failure = '**Response example — error**\n\n';

    String api(String operations) =>
        '---\nconfirmed:\n  - email_login/check_password '
        '${fingerprintFor('\n$checkPasswordStatement')}\n---\n\n# Login API\n\n'
        '## FR trace\n\n| FR | Operation |\n|---|---|\n'
        '| email_login/check_password | `signIn` |\n\n'
        '## Operations\n\n$operations';

    Future<List<String>> apiSpots(String operations) async => spots(
      await checkOf(
        await writeCheckProject(
          extra: {'docs/$loginApi': api(operations)},
          unstamped: {'docs/$loginApi'},
        ),
      ),
      FindingKind.patternMissing,
    );

    test('an operation with no error example is pattern_missing at its '
        'heading, and one with both examples passes', () async {
      final text = api('$operation$success');
      final headingLine = text
          .substring(0, text.indexOf('### `signIn`'))
          .split('\n')
          .length;

      expect(await apiSpots('$operation$success'), [
        '$loginApi:$headingLine: pattern_missing',
      ]);
      expect(await apiSpots('$operation$success$failure'), isEmpty);
    });

    test('each operation needs its own examples, so a second operation with '
        'none is reported alone', () async {
      const first = '$operation$success$failure';
      final text = api('$first### `lock`\n\nLocks it.\n');
      final lockLine = text
          .substring(0, text.indexOf('### `lock`'))
          .split('\n')
          .length;

      expect(await apiSpots('$first### `lock`\n\nLocks it.\n'), [
        '$loginApi:$lockLine: pattern_missing',
        '$loginApi:$lockLine: pattern_missing',
      ]);
    });

    test('a topic interface item not opening with a path:Symbol code span is '
        'reported at its line', () async {
      const topicPath = 'docs/specs/topics/sign_in.md';
      String topic(String item) =>
          '---\ncovers:\n  - app/lib/\n---\n\n# Sign in\n\n'
          '## Purpose\n\nSigns in.\n\n## Scope\n\nThe sign-in code.\n\n'
          '## Used by\n\n| Feature | What it uses |\n|---|---|\n'
          '| login | all |\n\n## Interface\n\n$item\n';
      Future<List<String>> bannedIn(String item) async => spots(
        await checkOf(
          await writeCheckProject(
            extra: {topicPath: topic(item)},
            unstamped: {topicPath},
          ),
        ),
        FindingKind.patternBanned,
      );
      final lines = topic('- A bare item').split('\n');
      final itemLine = lines.indexOf('- A bare item') + 1;

      expect(await bannedIn('- A bare item'), [
        'specs/topics/sign_in.md:$itemLine: pattern_banned',
      ]);
      expect(
        await bannedIn('- `app/lib/login.dart:SignInPage` — the page'),
        isEmpty,
      );
    });
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
        'goal.long_term': ['metric_number'],
        'goal.mid_term': ['metric_number'],
        'goal.short_term': ['metric_number'],
        'feature.out_of_scope': ['out_of_scope_owner'],
        'user_story.acceptance_criteria': ['scenario_title'],
        'fr.statement': ['second_shall'],
        'fr.edge_cases': ['edge_case_arrow'],
        'fr.verification': ['test_file_named'],
        'nf.statement': ['second_shall', 'statement_number'],
        for (final category in _gnfrCategories)
          'gnfr.$category': ['second_shall', 'statement_number'],
      });
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

    test('title_no_number is true on persona, anti_persona, feature, '
        'journey, and measurement, and unset on the others', () {
      const numbered = {
        'persona',
        'anti_persona',
        'feature',
        'journey',
        'measurement',
      };
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
    this.required = false,
  });

  final String docType;

  /// The section id, or null for each of the nine gnfr categories.
  final String? section;
  final String id;

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
    ],
  ),
  const _GuideRule(
    'architecture',
    'concerns',
    'concern_ending',
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
    hits: ['### `create` — FR-01', '### `create` FR-01', '### `create` (v2)'],
    misses: ['### `create`', '### `POST /items`', '#### `x` y', '- `x` y'],
  ),
  const _GuideRule(
    'topic',
    'interface',
    'interface_pointer',
    hits: [
      '- A public entry point',
      '- `lib/src/a.dart` Symbol',
      '- lib/src/a.dart:Symbol',
      '- `Symbol` in lib/src/a.dart:Symbol',
    ],
    misses: [
      '- `lib/src/a.dart:Symbol` — opens a file',
      '- `lib/src/a.dart:Symbol.method`',
      '  - nested note',
    ],
  ),
  const _GuideRule(
    'api',
    'operations',
    'response_success',
    required: true,
    hits: [
      '**Response example — success**',
      '**Response example — success** x',
    ],
    misses: ['**Response example — error**', 'Response example — success'],
  ),
  const _GuideRule(
    'api',
    'operations',
    'response_error',
    required: true,
    hits: ['**Response example — error**', '**Response example — error** x'],
    misses: ['**Response example — success**', 'Response example — error'],
  ),
  const _GuideRule(
    'auth',
    'scopes',
    'scope_form',
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
    hits: [
      '| /items | yes | maybe |',
      '| /items | GET | maybe | yes |',
      '| /items | GET | yes | Y |',
      '| /items | own | read |',
      '| /items | no | ✓ |',
      '| /items | GET | own | |',
    ],
    // A bad cell before the first good one is caught; a good row passes.
    misses: [
      '| Resource | admin | user |',
      '|---|---|---|',
      '| /items | yes | no |',
      '| /items | | any |',
      '| /items | no | any |',
      '| /items | `yes` | `no` |',
      '| :---: | --- | --- |',
      'Default: deny',
    ],
  ),
  const _GuideRule(
    'domain',
    'entities',
    'entity_kind',
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
