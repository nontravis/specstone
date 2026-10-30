import 'dart:convert';
import 'dart:io';

import 'package:specstone/src/command_runner.dart';
import 'package:specstone_core/specstone_core.dart';
import 'package:test/test.dart';

import '../../../../specstone_core/test/helpers/shipped_pins.dart';
import '../../helpers/temp_tree.dart';

const _configPath = '.specstone/config.yaml';
const _guideUsage = 'Usage: specstone guide [type] [--json]';
final String _bothPacks = shippedPinsConfig();
final String _prdCoreOnly = shippedPinsConfig(['prd-core']);
final String _softwareTechOnly = shippedPinsConfig(['software-tech']);
const _nineteenIds =
    'anti_persona\napi\narchitecture\nauth\ndomain\nerror\nfeature\nfeatures\n'
    'fr\ngnfr\nintegration\njourney\nnf\npersona\nproject\nreference\n'
    'tech_stack\ntopic\nuser_story\n';
const _softwareTechIds = <String>[
  'api',
  'architecture',
  'auth',
  'domain',
  'error',
  'integration',
  'tech_stack',
  'topic',
];

/// The ids of the `Map` entries of [list], read from key [key].
List<Object?> _idsOf(Object? list, [String key = 'id']) => [
  for (final entry in list! as List<Object?>)
    (entry! as Map<String, Object?>)[key],
];

void main() {
  group('specstone guide with the shipped software-tech pack', () {
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

    Future<SpecstoneCommandRunner> runnerFor(String packs) async =>
        runnerIn(await writeTree({_configPath: packs}));

    test('f03/us07/s1, f03/us07/fr01/e01: guide lists the eleven prd-core and '
        'the eight software-tech doc types and no other', () async {
      final runner = await runnerFor(_bothPacks);
      expect(await runner.run(['guide']), 0);
      expect(out.toString(), _nineteenIds);
      expect(err.toString(), isEmpty);
    });

    test('f03/us07/s1, f03/us07/fr02: guide --json names software-tech as '
        'the pack of the eight, each with a one-line summary', () async {
      final runner = await runnerFor(_bothPacks);
      expect(await runner.run(['guide', '--json']), 0);
      final entries = (jsonDecode(out.toString()) as List<Object?>)
          .cast<Map<String, Object?>>();
      final fromSoftwareTech = entries
          .where((e) => e['pack'] == 'software-tech')
          .toList();
      expect(fromSoftwareTech.map((e) => e['id']), _softwareTechIds);
      for (final entry in fromSoftwareTech) {
        final description = entry['description']! as String;
        expect(description, isNotEmpty, reason: '${entry['id']}');
        expect(description, endsWith('.'), reason: '${entry['id']}');
        expect(description, isNot(startsWith('#')), reason: '${entry['id']}');
      }
      final fr = entries.singleWhere((e) => e['id'] == 'fr');
      expect(fr['pack'], 'prd-core');
      expect(err.toString(), isEmpty);
    });

    test(
      'f03/us07/s2, f03/us07/fr02/e01: guide architecture prints the '
      'title form, then each section header and description in order',
      () async {
        final runner = await runnerFor(_bothPacks);
        expect(await runner.run(['guide', 'architecture']), 0);
        final guide = out.toString();
        expect(guide, isNot(startsWith('#')));
        expect(guide, contains('no number'));
        final title = guide.indexOf('# <Feature name> architecture');
        final at = [
          '## Component diagram\n\n',
          '## Components\n\n',
          '## Interaction\n\n',
          '## Deployment\n\n',
          '## Rollout\n\n',
          '## Observability\n\n',
          '## Concerns\n\n',
          '## Design references\n\n',
          '## Open questions\n\n',
        ].map(guide.indexOf).toList();
        expect(title, greaterThan(0));
        expect(at, everyElement(greaterThan(title)));
        expect(at, orderedEquals(List.of(at)..sort()));
        expect(at.toSet(), hasLength(at.length));
        expect(err.toString(), isEmpty);
      },
    );

    test('f03/us07/s3, f03/us07/fr01: guide architecture --json gives the '
        'specs path, the parent feature, covers, and the sections', () async {
      final runner = await runnerFor(_bothPacks);
      expect(await runner.run(['guide', 'architecture', '--json']), 0);
      final json = jsonDecode(out.toString()) as Map<String, Object?>;
      expect(json['path'], 'specs/f{nn}_{slug}/ARCHITECTURE.md');
      expect(json['parent'], 'feature');
      final fields = json['fields']! as List<Object?>;
      expect(_idsOf(fields), [
        'slug',
        'status',
        'draft',
        'approved',
        'reference',
        'covers',
      ]);
      final covers = fields.cast<Map<String, Object?>>().singleWhere(
        (f) => f['id'] == 'covers',
      );
      expect(covers['type'], 'output_ref');
      expect(covers['list'], isTrue);
      expect(covers['required'], isTrue);
      expect(covers['pointer'], 'prefix');
      expect(_idsOf(json['sections']), [
        'component_diagram',
        'components',
        'interaction',
        'deployment',
        'rollout',
        'observability',
        'concerns',
        'design_references',
        'open_questions',
      ]);
    });

    test('f03/us07/s4, f03/us01/fr03: guide fr --json adds one optional '
        'exact implements field to the prd-core fields', () async {
      final runner = await runnerFor(_bothPacks);
      expect(await runner.run(['guide', 'fr', '--json']), 0);
      final json = jsonDecode(out.toString()) as Map<String, Object?>;
      final fields = json['fields']! as List<Object?>;
      expect(_idsOf(fields), [
        'slug',
        'status',
        'draft',
        'approved',
        'reference',
        'traced_from',
        'verify_method',
        'owner',
        'confirmed',
        'implements',
      ]);
      final implements = fields.last! as Map<String, Object?>;
      expect(implements.keys, ['id', 'type', 'list', 'pointer', 'description']);
      expect(implements['type'], 'output_ref');
      expect(implements['list'], isTrue);
      expect(implements['pointer'], 'exact');
      expect(_idsOf(json['sections']), [
        'statement',
        'input_output',
        'behavior',
        'edge_cases',
        'rationale',
        'verification',
        'tbr',
      ]);
    });

    test('f03/us07/s5, f03/us07/fr01/e02: with only prd-core, guide fr '
        '--json has no field that points at code', () async {
      final runner = await runnerFor(_prdCoreOnly);
      expect(await runner.run(['guide', 'fr', '--json']), 0);
      final json = jsonDecode(out.toString()) as Map<String, Object?>;
      final fields = (json['fields']! as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(fields, isNotEmpty);
      for (final field in fields) {
        expect(field['type'], isNot('output_ref'), reason: '${field['id']}');
        expect(field.containsKey('pointer'), isFalse, reason: '${field['id']}');
      }
    });

    test('f03/us07/s6, f03/us07/fr01/e02: with only prd-core, guide '
        'architecture is refused with the usage', () async {
      final runner = await runnerFor(_prdCoreOnly);
      expect(await runner.run(['guide', 'architecture']), 64);
      expect(
        err.toString(),
        contains(
          'Could not find a doc type named "architecture".\n\n$_guideUsage',
        ),
      );
      expect(out.toString(), isEmpty);
    });

    test('f03/us07/fr01/e02: with only prd-core and --json the refusal is '
        'doc_type_unknown', () async {
      final runner = await runnerFor(_prdCoreOnly);
      expect(await runner.run(['guide', 'architecture', '--json']), 64);
      final error =
          (jsonDecode(err.toString()) as Map<String, Object?>)['error']!
              as Map<String, Object?>;
      expect(error['code'], 'doc_type_unknown');
      expect(out.toString(), isEmpty);
    });

    test('f03/us07/fr01/e03: software-tech without prd-core is '
        'prd_core_missing', () async {
      final runner = await runnerFor(_softwareTechOnly);
      expect(await runner.run(['guide', '--json']), 78);
      final error =
          (jsonDecode(err.toString()) as Map<String, Object?>)['error']!
              as Map<String, Object?>;
      expect(error['code'], 'prd_core_missing');
      expect(out.toString(), isEmpty);
    });

    test('f03/us07/fr01/e04: a spec index doc type is refused with the '
        'usage', () async {
      final runner = await runnerFor(_bothPacks);
      expect(await runner.run(['guide', 'index']), 64);
      expect(
        err.toString(),
        contains('Could not find a doc type named "index".\n\n$_guideUsage'),
      );
      expect(out.toString(), isEmpty);
    });
  });
}
