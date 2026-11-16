import 'dart:convert';
import 'dart:io';

import 'package:specstone/src/command_runner.dart';
import 'package:specstone_core/specstone_core.dart';
import 'package:test/test.dart';

import '../../../../specstone_core/test/helpers/shipped_pins.dart';
import '../../helpers/temp_tree.dart';

const _configPath = '.specstone/config.yaml';
const _guideUsage = 'Usage: specstone guide [type …] [--json]';
const _prdCoreIds = <String>[
  'anti_persona',
  'feature',
  'features',
  'fr',
  'glossary',
  'gnfr',
  'goal',
  'journey',
  'measurement',
  'nf',
  'persona',
  'project',
  'reference',
  'user_story',
];

const _citeRule =
    'Cite a rule another doc owns by a link to the item that holds it, '
    'never restate it.';

const _capLine =
    'Each sentence holds 25 words or fewer (Korean 17), or 100 characters in '
    'a script with no spaces (Japanese 60, Chinese 45).';

const _nestLine =
    'Keep one rule in each item, and put several conditions in a nested '
    'list. A one-sentence paragraph with no ID moves its detail to the '
    'section of the same doc that owns it, never into a sub-list.';

const _endLine = "Put a cite or an ownership note at the item's end.";

const _exampleLine =
    'Give a non-obvious rule one example inside its item, as a `such as` '
    'clause or one "For example," sentence, within the sentence\'s cap.';

const _orderLine =
    'State the condition first, then the rule, one clause chain per '
    'sentence; split a sentence whose clauses nest.';

/// The five readability lines every prd-core description carries.
const _readabilityLines = <String>[
  _capLine,
  _nestLine,
  _endLine,
  _exampleLine,
  _orderLine,
];

/// The `software-tech` doc type ids (US-07 FR-01).
const _softwareTechIds = <String>[
  'tech_stack',
  'topic',
  'architecture',
  'domain',
  'api',
  'integration',
  'error',
  'auth',
  'implementation',
  'project_architecture',
  'project_domain',
  'project_api',
  'project_integration',
  'project_error',
  'project_auth',
];

/// The `guide` listing of [ids]: sorted, each followed by a newline.
String _listOf(List<String> ids) =>
    (List.of(ids)..sort()).map((id) => '$id\n').join();

/// True when an ancestor of the system temp folder holds a project config.
bool _tempHasConfigAncestor() {
  Directory? dir = Directory.systemTemp.absolute;
  while (dir != null) {
    if (File.fromUri(dir.uri.resolve(_configPath)).existsSync()) return true;
    final parent = dir.parent;
    dir = parent.path == dir.path ? null : parent;
  }
  return false;
}

void main() {
  group('specstone guide with the shipped prd-core pack', () {
    late StringBuffer out;
    late StringBuffer err;

    setUp(() {
      out = StringBuffer();
      err = StringBuffer();
    });

    Future<SpecstoneCommandRunner> runnerIn(Directory working) async =>
        SpecstoneCommandRunner(
          out: out,
          err: err,
          templates: TemplateResolver(),
          workingDirectory: working,
          homeDirectory: await writeTree({}),
        );

    Future<Directory> prdCoreProject() => writeTree({
      _configPath: shippedPinsConfig(['prd-core']),
    });

    test(
      'f03/us06/s1, f03/us06/fr01/e01: guide lists the fourteen prd-core doc '
      'types and no other',
      () async {
        final runner = await runnerIn(await prdCoreProject());
        expect(await runner.run(['guide']), 0);
        expect(out.toString(), _listOf(_prdCoreIds));
        expect(err.toString(), isEmpty);
      },
    );

    test(
      'f03/us01/s5, f03/us01/fr04/e01: outside a project guide lists every '
      'shipped doc type',
      () async {
        final runner = await runnerIn(await writeTree({}));
        expect(await runner.run(['guide']), 0);
        expect(out.toString(), _listOf([..._prdCoreIds, ..._softwareTechIds]));
      },
      skip: _tempHasConfigAncestor()
          ? 'an ancestor of the system temp folder holds $_configPath'
          : false,
    );

    test('f03/us06/s2, f03/us06/fr02: guide user_story prints the title form, '
        'then each section header and description in order', () async {
      final runner = await runnerIn(await prdCoreProject());
      expect(await runner.run(['guide', 'user_story']), 0);
      final guide = out.toString();
      expect(guide, isNot(startsWith('#')));
      final title = guide.indexOf('# <Name>');
      final at = [
        '## Use Case\n\nWrite: As a <Role>',
        '## Rules\n\nWrite it when the story has two or more rules',
        '## Acceptance Criteria\n\nTitle each scenario',
        '## Open questions\n\nOptional. Record each example',
      ].map(guide.indexOf).toList();
      expect(title, greaterThan(0));
      expect(at, everyElement(greaterThan(title)));
      expect(at, orderedEquals(List.of(at)..sort()));
    });

    test('guide fr lists the statement banned words after the '
        'description that names them, and shows the verification '
        'template', () async {
      final runner = await runnerIn(await prdCoreProject());
      expect(await runner.run(['guide', 'fr']), 0);
      final guide = out.toString();
      expect(
        guide,
        contains(
          'and the other listed words.\n\n'
          'Banned words: `flexible`, `easy`, `sufficient`,',
        ),
      );
      expect(guide, contains('`etc.`, `and/or`, `but not limited to`\n\n'));
      expect(
        guide,
        contains(
          'Never write results here; evidence belongs to the verification '
          'matrix.\n\n'
          'Template:\n```markdown\n'
          '- **Pass criteria:** <what shows the requirement holds>\n'
          '  - <one condition, when the criteria are long>\n'
          '- **Level:** <level>\n```\n',
        ),
      );
      expect(err.toString(), isEmpty);
    });

    test('Write the shipped writing guides '
        'E06: guide fr prints the item shape', () async {
      final runner = await runnerIn(await prdCoreProject());
      expect(await runner.run(['guide', 'fr']), 0);
      expect(
        out.toString(),
        allOf(
          contains('with a quantified value kept in it, such as `within 2 s`.'),
          contains('leave mechanics to the spec docs'),
          contains('Write one Edge cases item per case;'),
          contains('with what happens then.'),
          contains('Keep the trace in `traced_from` alone'),
        ),
      );
      expect(err.toString(), isEmpty);
    });

    test('guide fr shows a long Verification as one Pass criteria line with '
        'a nested bullet per condition, and names no test file', () async {
      final runner = await runnerIn(await prdCoreProject());
      expect(await runner.run(['guide', 'fr']), 0);
      expect(
        out.toString(),
        allOf(
          contains(
            'Write a long Verification as one `- **Pass criteria:**` line '
            'with one nested bullet per condition.\n',
          ),
          contains(
            "Name no test file here; each target's record names the tests "
            'that prove the FR.\n',
          ),
        ),
      );
      expect(err.toString(), isEmpty);
    });

    test('guide user_story caps a story at 6 scenarios, and guide fr names no '
        'test file', () async {
      final runner = await runnerIn(await prdCoreProject());
      expect(await runner.run(['guide', 'user_story']), 0);
      expect(
        out.toString(),
        allOf(
          contains(
            'Split a story that needs more than 6 scenarios, along business '
            'behavior and never along technical layers.\n',
          ),
          isNot(contains('five or six')),
        ),
      );
      out.clear();
      expect(await runner.run(['guide', 'fr', '--json']), 0);
      final json = jsonDecode(out.toString()) as Map<String, Object?>;
      final verification = (json['sections']! as List)
          .cast<Map<String, Object?>>()
          .firstWhere((s) => s['id'] == 'verification');
      final patterns =
          ((verification['lint']! as Map)['bannedPatterns']! as List)
              .cast<Map<String, Object?>>();
      expect(patterns.map((p) => p['id']), ['test_file_named']);
      expect(patterns.single['message'], contains('Name no test file here'));
      expect(verification['description'], contains('Name no test file here'));
    });

    test('guide fr and guide user_story ask for no ID order', () async {
      final runner = await runnerIn(await prdCoreProject());
      expect(await runner.run(['guide', 'fr']), 0);
      final fr = out.toString();
      expect(fr, contains('Write each as `E01 — <trigger> → <response>`.\n'));
      expect(fr, isNot(contains('numbered in order')));
      out.clear();
      expect(await runner.run(['guide', 'user_story']), 0);
      final story = out.toString();
      expect(story, contains('Write each rule as `**BR-NN** — <rule>`.\n'));
      expect(story, isNot(contains('number the rules in order')));
    });

    test('guide project --json prints a guide-rule entry whose message names '
        'its guide line', () async {
      final runner = await runnerIn(await prdCoreProject());
      expect(await runner.run(['guide', 'project', '--json']), 0);
      final json = jsonDecode(out.toString()) as Map<String, Object?>;
      final vision = (json['sections']! as List)
          .cast<Map<String, Object?>>()
          .firstWhere((s) => s['id'] == 'vision');
      final patterns = ((vision['lint']! as Map)['bannedPatterns']! as List)
          .cast<Map<String, Object?>>();
      expect(patterns.map((p) => p['id']), ['quote_words', 'quote_language']);
      expect(
        patterns.first['message'],
        contains('keep each sentence to 15 words or fewer'),
      );
      expect(
        vision['description'],
        contains('keep each sentence to 15 words or fewer'),
      );
    });

    test('f03/us06/s3, f03/us06/fr01: guide fr --json gives the prds path, '
        'the parent, the fields, and the sections', () async {
      final runner = await runnerIn(await prdCoreProject());
      expect(await runner.run(['guide', 'fr', '--json']), 0);
      final json = jsonDecode(out.toString()) as Map<String, Object?>;
      expect(
        json['path'],
        'prds/features/f{nn}_{slug}/us{nn}_{slug}/fr{nn}_{slug}.md',
      );
      expect(json['parent'], 'user_story');
      expect((json['fields']! as List).map((f) => (f as Map)['id']), [
        'slug',
        'status',
        'draft',
        'approved',
        'reference',
        'traced_from',
        'verify_method',
        'owner',
        'confirmed',
      ]);
      expect((json['sections']! as List).map((s) => (s as Map)['id']), [
        'statement',
        'input_output',
        'behavior',
        'edge_cases',
        'rationale',
        'verification',
        'tbr',
      ]);
    });

    test('guide fr --json describes the three traced_from '
        'forms', () async {
      final runner = await runnerIn(await prdCoreProject());
      expect(await runner.run(['guide', 'fr', '--json']), 0);
      final json = jsonDecode(out.toString()) as Map<String, Object?>;
      final tracedFrom = (json['fields']! as List)
          .cast<Map<String, Object?>>()
          .firstWhere((f) => f['id'] == 'traced_from');
      expect(
        tracedFrom['description'],
        allOf(
          contains('`S<N>`'),
          contains('`<story Name>#S<N>`'),
          contains('sibling story'),
          contains('`self-derived`'),
        ),
      );
    });

    test('f03/us06/s3, f03/us06/fr01: guide feature --json gives the prds '
        'path and no parent', () async {
      final runner = await runnerIn(await prdCoreProject());
      expect(await runner.run(['guide', 'feature', '--json']), 0);
      final json = jsonDecode(out.toString()) as Map<String, Object?>;
      expect(json['path'], 'prds/features/f{nn}_{slug}/FEATURE.md');
      expect(json.containsKey('parent'), isFalse);
      expect([
        for (final field
            in (json['fields']! as List).cast<Map<String, Object?>>())
          field['id'],
      ], contains('patterns'));
    });

    test('f03/us06/s4, f03/us06/fr03: guide fr --json gives the NASA word '
        'list and the NASA handbook', () async {
      final runner = await runnerIn(await prdCoreProject());
      expect(await runner.run(['guide', 'fr', '--json']), 0);
      final json = jsonDecode(out.toString()) as Map<String, Object?>;
      expect((json['lint']! as Map).containsKey('bannedWords'), isFalse);
      final statement = (json['sections']! as List)
          .cast<Map<String, Object?>>()
          .firstWhere((s) => s['id'] == 'statement');
      final words = (statement['lint']! as Map)['bannedWords']! as List;
      expect(words, hasLength(29));
      expect(words.first, 'flexible');
      expect(words.last, 'but not limited to');
      expect(json['reference'], [
        {
          'title': 'NASA Systems Engineering Handbook, NASA SP-2016-6105 Rev2',
          'url': 'https://www.nasa.gov/reference/systems-engineering-handbook/',
          'locator': 'Appendix C and section 4.2',
        },
      ]);
    });

    test('f03/us06/s5, f03/us06/fr01/e02: a generic project document type is '
        'refused with the usage', () async {
      final runner = await runnerIn(await prdCoreProject());
      expect(await runner.run(['guide', 'project_document']), 64);
      expect(
        err.toString(),
        contains(
          'Could not find a doc type named "project_document".\n\n'
          '$_guideUsage',
        ),
      );
      expect(out.toString(), isEmpty);
    });

    test('guide fr ends with the NASA source', () async {
      final runner = await runnerIn(await prdCoreProject());
      expect(await runner.run(['guide', 'fr']), 0);
      expect(
        out.toString(),
        endsWith(
          '\n\nGuide sources:\n'
          '- NASA Systems Engineering Handbook, NASA SP-2016-6105 Rev2, '
          'Appendix C and section 4.2: '
          'https://www.nasa.gov/reference/systems-engineering-handbook/\n',
        ),
      );
      expect(err.toString(), isEmpty);
    });

    test('every prd-core guide says to cite a rule another '
        'doc owns by a link to its item, never restate it', () async {
      final runner = await runnerIn(await prdCoreProject());
      for (final id in _prdCoreIds) {
        out.clear();
        expect(await runner.run(['guide', id]), 0, reason: id);
        expect(out.toString(), contains(_citeRule), reason: id);
      }
    });

    test(
      'every prd-core description carries the five readability lines',
      () async {
        final runner = await runnerIn(await prdCoreProject());
        for (final id in _prdCoreIds) {
          out.clear();
          expect(await runner.run(['guide', id, '--json']), 0, reason: id);
          final json = jsonDecode(out.toString()) as Map<String, Object?>;
          final description = json['description']! as String;
          expect(
            description.split('\n'),
            containsAll(_readabilityLines),
            reason: id,
          );
          for (final section
              in (json['sections']! as List).cast<Map<String, Object?>>()) {
            final text = section['description'] as String? ?? '';
            for (final line in _readabilityLines) {
              expect(text, isNot(contains(line)), reason: id);
            }
          }
        }
      },
    );

    test('fr edge cases template shows the calibration shape', () async {
      final runner = await runnerIn(await prdCoreProject());
      expect(await runner.run(['guide', 'fr', '--json']), 0);
      final json = jsonDecode(out.toString()) as Map<String, Object?>;
      final edgeCases = (json['sections']! as List)
          .cast<Map<String, Object?>>()
          .firstWhere((s) => s['id'] == 'edge_cases');
      expect(
        edgeCases['template'],
        '1. E01 — <trigger> → <response>\n'
        '2. E02 — <lead> → <response>\n'
        '   <more response, one sentence per line, with no blank line>\n'
        '   - <trigger>\n'
        '   - <trigger>',
      );
      final description = edgeCases['description']! as String;
      expect(description.split('\n').length, lessThanOrEqualTo(5));
      expect(
        description,
        contains(
          'For several triggers, keep the `→` in the lead and join the '
          'response as indented lines, with no blank line.\n'
          'List the triggers as nested items.',
        ),
      );
    });

    test('fr statement and project vision carry item_count', () async {
      final runner = await runnerIn(await prdCoreProject());
      Future<Map<String, Object?>> itemCount(String type, String id) async {
        out.clear();
        expect(await runner.run(['guide', type, '--json']), 0);
        final json = jsonDecode(out.toString()) as Map<String, Object?>;
        final section = (json['sections']! as List)
            .cast<Map<String, Object?>>()
            .firstWhere((s) => s['id'] == id);
        return (section['lint']! as Map)['itemCount']! as Map<String, Object?>;
      }

      expect(await itemCount('fr', 'statement'), {
        'max': 1,
        'perSubsection': false,
        'prefixes': <Object?>[],
      });
      expect(await itemCount('project', 'vision'), {
        'max': 3,
        'perSubsection': true,
        'prefixes': [
          {'linePrefix': '- **Why:**', 'count': 1},
          {'linePrefix': '- **Problem:**', 'count': 1},
          {'linePrefix': '- **Audience:**', 'count': 1},
        ],
      });
    });

    test('guide journey prints no sources', () async {
      final runner = await runnerIn(await prdCoreProject());
      expect(await runner.run(['guide', 'journey']), 0);
      expect(out.toString(), isNot(contains('Guide sources:')));
    });

    test('guide measurement prints the description, then the five sections '
        'in order', () async {
      final runner = await runnerIn(await prdCoreProject());
      expect(await runner.run(['guide', 'measurement']), 0);
      final guide = out.toString();
      final description = guide.indexOf('A measurement: the evidence');
      final logRule = guide.indexOf('never edits an older row');
      final at = [
        '## Scope',
        '## Method',
        '## Baseline',
        '## Results',
        '## Open causes',
      ].map(guide.indexOf).toList();
      expect(description, 0);
      expect(logRule, greaterThan(description));
      expect(at.first, greaterThan(logRule));
      expect(at, orderedEquals(List.of(at)..sort()));
      expect(at, everyElement(isNonNegative));
      expect(guide, isNot(contains('Guide sources:')));
      expect(err.toString(), isEmpty);
    });

    test('guide goal prints the goal rules and the fixed title', () async {
      final runner = await runnerIn(await prdCoreProject());
      expect(await runner.run(['guide', 'goal']), 0);
      final guide = out.toString();
      final title = guide.indexOf('# Project goals');
      final rule = guide.indexOf('deleted from the goal doc');
      final at = [
        '## Long-term goals',
        '## Mid-term goals',
        '## Short-term goals',
      ].map(guide.indexOf).toList();
      expect(title, isNonNegative);
      expect(rule, greaterThan(title));
      expect(at.first, greaterThan(rule));
      expect(at, orderedEquals(List.of(at)..sort()));
      expect(at, everyElement(isNonNegative));
      expect(guide, isNot(contains('Guide sources:')));
      expect(err.toString(), isEmpty);
    });

    test('guide glossary prints the glossary rules, then the terms section '
        'with its template', () async {
      final runner = await runnerIn(await prdCoreProject());
      expect(await runner.run(['guide', 'glossary']), 0);
      final guide = out.toString();
      final title = guide.indexOf('# Domain glossary');
      final rule = guide.indexOf('A project has exactly one glossary doc.');
      final cap = guide.indexOf('Keep each entry to 300 characters or fewer;');
      final terms = guide.indexOf('## Terms');
      final template = guide.indexOf(
        '- **<Term>** — <one-line definition tying to a concrete entity>',
      );
      expect(guide, isNot(startsWith('#')));
      expect(title, isNonNegative);
      expect(rule, greaterThan(title));
      expect(cap, greaterThan(rule));
      expect(terms, greaterThan(cap));
      expect(template, greaterThan(terms));
      expect(guide, contains('Cite a rule another doc owns by a link'));
      expect(guide, isNot(contains('Guide sources:')));
      expect(err.toString(), isEmpty);
    });

    test('with --json the refusal is doc_type_unknown', () async {
      final runner = await runnerIn(await prdCoreProject());
      expect(await runner.run(['guide', 'project_document', '--json']), 64);
      final error = (jsonDecode(err.toString()) as Map)['error'] as Map;
      expect(error['code'], 'doc_type_unknown');
      expect(out.toString(), isEmpty);
    });
  });
}
