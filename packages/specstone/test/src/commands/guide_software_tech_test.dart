import 'dart:convert';
import 'dart:io';

import 'package:specstone/src/command_runner.dart';
import 'package:specstone_core/specstone_core.dart';
import 'package:test/test.dart';

import '../../../../specstone_core/test/helpers/shipped_pins.dart';
import '../../helpers/temp_tree.dart';

const _configPath = '.specstone/config.yaml';
const _guideUsage = 'Usage: specstone guide [type …] [--json]';
final String _bothPacks = shippedPinsConfig();
final String _prdCoreOnly = shippedPinsConfig(['prd-core']);
final String _softwareTechOnly = shippedPinsConfig(['software-tech']);
const _twentyIds =
    'anti_persona\napi\narchitecture\nauth\ndomain\nerror\nfeature\nfeatures\n'
    'fr\ngnfr\nimplementation\nintegration\njourney\nnf\npersona\nproject\n'
    'reference\ntech_stack\ntopic\nuser_story\n';
const _softwareTechIds = <String>[
  'api',
  'architecture',
  'auth',
  'domain',
  'error',
  'implementation',
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
        'the nine software-tech doc types and no other', () async {
      final runner = await runnerFor(_bothPacks);
      expect(await runner.run(['guide']), 0);
      expect(out.toString(), _twentyIds);
      expect(err.toString(), isEmpty);
    });

    test('f03/us07/s1, f03/us07/fr02: guide --json names software-tech as '
        'the pack of the nine, each with a one-line summary', () async {
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

    test('template_packs/write_spec_docs_from_software_tech/'
        'ship_software_tech_pack: guide domain prints Known limits right '
        'after Invariants', () async {
      final runner = await runnerFor(_bothPacks);
      expect(await runner.run(['guide', 'domain']), 0);
      final guide = out.toString();
      final invariants = guide.indexOf('## Invariants\n\n');
      final knownLimits = guide.indexOf('## Known limits\n\n');
      final lifecycle = guide.indexOf('## Lifecycle\n\n');
      expect(invariants, greaterThan(0));
      expect(knownLimits, greaterThan(invariants));
      expect(lifecycle, greaterThan(knownLimits));
      expect(err.toString(), isEmpty);
    });

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

    test('f03/us07/s4, f03/us07/fr01/e08: guide fr --json holds the prd-core '
        'fields and no field that points at code', () async {
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
      ]);
      for (final field in fields.cast<Map<String, Object?>>()) {
        expect(field['type'], isNot('output_ref'), reason: '${field['id']}');
        expect(field.containsKey('pointer'), isFalse, reason: '${field['id']}');
      }
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

    test('f03/us07/s4, f03/us07/fr01/e07: guide implementation --json gives '
        'the path, the parent feature, and the two record fields, each code '
        'entry an exact pointer', () async {
      final runner = await runnerFor(_bothPacks);
      expect(await runner.run(['guide', 'implementation', '--json']), 0);
      final json = jsonDecode(out.toString()) as Map<String, Object?>;
      expect(json['path'], 'specs/f{nn}_{slug}/IMPLEMENTATION.md');
      expect(json['parent'], 'feature');
      expect(json['perTarget'], isTrue);
      final fields = (json['fields']! as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(_idsOf(fields), [
        'slug',
        'status',
        'draft',
        'approved',
        'reference',
        'statuses',
        'implements',
      ]);
      final statuses = fields.singleWhere((f) => f['id'] == 'statuses');
      expect(statuses['type'], 'record_status');
      expect(statuses['list'], isTrue);
      expect(statuses.containsKey('required'), isFalse);
      final implements = fields.singleWhere((f) => f['id'] == 'implements');
      expect(implements['type'], 'output_ref');
      expect(implements['list'], isTrue);
      expect(implements['pointer'], 'item_exact');
      expect(
        implements['description'],
        contains(
          "relative to the code root of the doc's target "
          '(`.specstone/config.yaml`, else the project root)',
        ),
      );
      expect(json['sections'], isEmpty);
    });

    test('f03/us07/fr02/e01, e02: each spec guide titles its doc with the '
        'feature name and no number, the tech stack and a topic by their own '
        'forms', () async {
      const titles = {
        'architecture': '`# <Feature name> architecture`',
        'domain': '`# <Feature name> domain`',
        'api': '`# <Feature name> API`',
        'integration': '`# <Feature name> integrations`',
        'error': '`# <Feature name> errors`',
        'auth': '`# <Feature name> auth`',
        'implementation': '`# <Feature name> implementation`',
        'topic': '`# <Topic name>`',
        'tech_stack': '`# Tech stack`',
      };
      final runner = await runnerFor(_bothPacks);
      for (final MapEntry(key: id, value: title) in titles.entries) {
        out.clear();
        expect(await runner.run(['guide', id]), 0, reason: id);
        expect(out.toString(), contains(title), reason: id);
        expect(out.toString(), contains('no number'), reason: id);
      }
      expect(err.toString(), isEmpty);
    });

    test('f03/us07/fr02/e03: each spec guide says a spec doc never writes '
        "status:, and names the target's record as the home of whether code "
        'exists', () async {
      final runner = await runnerFor(_bothPacks);
      for (final id in _softwareTechIds) {
        out.clear();
        expect(await runner.run(['guide', id]), 0, reason: id);
        expect(out.toString(), contains('Never write `status:`'), reason: id);
        expect(
          out.toString(),
          contains(
            "lives in that target's record, its `implementation` docs, only",
          ),
          reason: id,
        );
        expect(out.toString(), isNot(contains('FR `status`')), reason: id);
      }
      expect(err.toString(), isEmpty);
    });

    test('f03/us07/fr02/e04: each guide states its line target, and the '
        "record's is one line per entry under the 400-line cap", () async {
      const targets = {
        'tech_stack': 'about 80 lines',
        'architecture': 'under 150 lines',
        'domain': 'about 150 to 200 lines',
        'api': 'about 150 to 200 lines',
        'integration': 'about 150 to 200 lines',
        'error': 'about 150 to 200 lines',
        'auth': 'about 150 to 200 lines',
        'topic': 'about 150 to 200 lines',
        'implementation':
            'one line per entry in `statuses` and one per code path in '
            '`implements`, under the 400-line cap',
      };
      final runner = await runnerFor(_bothPacks);
      for (final MapEntry(key: id, value: target) in targets.entries) {
        out.clear();
        expect(await runner.run(['guide', id]), 0, reason: id);
        expect(out.toString(), contains(target), reason: id);
      }
    });

    test('f03/us07/fr02/e11: each guide states its item shape, one rule per '
        'ID', () async {
      const shapes = {
        'tech_stack': 'one Stack row per slot',
        'architecture': 'one Components row per component',
        'domain': 'one bullet per invariant',
        'api': 'one `###` per operation',
        'integration': 'one `###` per system',
        'error': 'one catalog row per code',
        'auth': 'one matrix row per resource and operation',
        'topic': 'one bullet per rule',
        'implementation': 'one entry per story and FR',
      };
      final runner = await runnerFor(_bothPacks);
      for (final MapEntry(key: id, value: shape) in shapes.entries) {
        out.clear();
        expect(await runner.run(['guide', id]), 0, reason: id);
        expect(out.toString(), contains('Write one rule per ID: $shape'));
      }
    });

    test('f03/us07/fr02/e14: the implementation guide names the record as '
        'the one home of status and code paths, a missing line as planned, '
        'and a skip with a reason and no code path', () async {
      final runner = await runnerFor(_bothPacks);
      expect(await runner.run(['guide', 'implementation']), 0);
      final guide = out.toString();
      expect(
        guide,
        contains(
          "The record is the one home of each story's and FR's status and "
          'code paths in its target',
        ),
      );
      expect(
        guide,
        contains(
          'an item with no `statuses` line, outside every skip, is `planned`, '
          'code paths or not',
        ),
      );
      expect(
        guide,
        contains(
          'A `skipped` entry carries a one-line reason and no code path; a '
          'skip on the feature or on a story covers everything below it',
        ),
      );
      expect(guide, isNot(contains('## ')));
    });

    test('f03/us07/fr02/e15: the architecture and tech stack guides name '
        "the target's record as the holder of status and code paths, and "
        "covers and code as the target's own code", () async {
      final runner = await runnerFor(_bothPacks);
      expect(await runner.run(['guide', 'architecture']), 0);
      expect(
        out.toString(),
        contains(
          "The target's record holds each story's and FR's status and code "
          "paths; `covers` names the target's own code only.",
        ),
      );
      out.clear();
      expect(await runner.run(['guide', 'tech_stack']), 0);
      expect(
        out.toString(),
        contains(
          "The target's record holds each story's and FR's status and code "
          "paths; `code` names the target's own code only.",
        ),
      );
    });

    test('f03/us07/fr03 E04, f03/us07/fr03: guide implementation ends with '
        'its four sources, and carries the 400-line cap and no banned '
        'word', () async {
      final runner = await runnerFor(_bothPacks);
      expect(await runner.run(['guide', 'implementation', '--json']), 0);
      final json = jsonDecode(out.toString()) as Map<String, Object?>;
      final lint = json['lint']! as Map<String, Object?>;
      expect(lint['maxLines'], 400);
      expect(lint.containsKey('maxItemChars'), isFalse);
      expect(lint.containsKey('bannedWords'), isFalse);
      final reference = (json['reference']! as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(_idsOf(reference, 'title'), [
        'OpenFastTrace, Terminology',
        'Sphinx-CodeLinks, Source tracing directive',
        'Doorstop, Item reference',
        'MDN browser-compat-data, Compat data schema',
      ]);
      for (final entry in reference) {
        expect(entry['url'], isNotEmpty);
        expect(entry['locator'], isNotEmpty);
      }
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

    test('template_packs/write_spec_docs_from_software_tech/'
        'write_spec_writing_guides E10: guide api states the one operation '
        'heading shape', () async {
      final runner = await runnerFor(_bothPacks);
      expect(await runner.run(['guide', 'api']), 0);
      expect(
        out.toString(),
        contains('Write one `###` per operation, headed `` `<operation>` ``'),
      );
      expect(out.toString(), isNot(contains('FR-<NN>')));
      expect(err.toString(), isEmpty);
    });

    test('template_packs/write_spec_docs_from_software_tech/'
        'write_spec_writing_guides E10: guide api --json carries the same '
        'heading shape in the operations section', () async {
      final runner = await runnerFor(_bothPacks);
      expect(await runner.run(['guide', 'api', '--json']), 0);
      final json = jsonDecode(out.toString()) as Map<String, Object?>;
      final operations = (json['sections']! as List<Object?>)
          .cast<Map<String, Object?>>()
          .singleWhere((section) => section['id'] == 'operations');
      final description = operations['description']! as String;
      expect(
        description,
        contains('Write one `###` per operation, headed `` `<operation>` ``'),
      );
      expect(description, isNot(contains('FR-<NN>')));
    });

    test('f03/us01/fr02: guide api ends with its four sources as '
        'written', () async {
      final runner = await runnerFor(_bothPacks);
      expect(await runner.run(['guide', 'api']), 0);
      expect(
        out.toString(),
        endsWith(
          '\n\nGuide sources:\n'
          '- OpenAPI Specification 3.2.1, Operation Object (operationId); '
          'Working with Examples: https://spec.openapis.org/oas/v3.2.1.html\n'
          '- Google AIP-121, Resource-oriented design, Guidance: '
          'https://google.aip.dev/121\n'
          '- Google AIP-180, Backwards compatibility, Guidance (source, wire, '
          'semantic compatibility): https://google.aip.dev/180\n'
          '- Microsoft Azure REST API Guidelines, Exactly Once Behavior; '
          'Handling Errors: '
          'https://github.com/microsoft/api-guidelines/blob/'
          'vNext/azure/Guidelines.md\n',
        ),
      );
      expect(err.toString(), isEmpty);
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
