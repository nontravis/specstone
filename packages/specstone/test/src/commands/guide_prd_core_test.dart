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
  'gnfr',
  'journey',
  'nf',
  'persona',
  'project',
  'reference',
  'user_story',
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

    test('f03/us06/s1, f03/us06/fr01/e01: guide lists the eleven prd-core doc '
        'types and no other', () async {
      final runner = await runnerIn(await prdCoreProject());
      expect(await runner.run(['guide']), 0);
      expect(out.toString(), _listOf(_prdCoreIds));
      expect(err.toString(), isEmpty);
    });

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

    test('f03/us01/fr02: guide fr lists the statement banned words after the '
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

    test('template_packs/write_prd_docs_from_prd_core/write_shipped_writing_guides '
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

    test('f04/us03/fr01: guide fr --json describes the three traced_from '
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

    test('f03/us06/fr03: guide fr ends with the NASA source', () async {
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

    test('f03/us06/fr03/e01: guide journey prints no sources', () async {
      final runner = await runnerIn(await prdCoreProject());
      expect(await runner.run(['guide', 'journey']), 0);
      expect(out.toString(), isNot(contains('Guide sources:')));
    });

    test(
      'f03/us06/fr01/e02: with --json the refusal is doc_type_unknown',
      () async {
        final runner = await runnerIn(await prdCoreProject());
        expect(await runner.run(['guide', 'project_document', '--json']), 64);
        final error = (jsonDecode(err.toString()) as Map)['error'] as Map;
        expect(error['code'], 'doc_type_unknown');
        expect(out.toString(), isEmpty);
      },
    );
  });
}
