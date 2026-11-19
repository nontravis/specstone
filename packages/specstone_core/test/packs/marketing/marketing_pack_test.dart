import 'dart:convert';

import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/consistency_check/readability_rules.dart';
import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:specstone_core/src/templates/pack_manifest.dart';
import 'package:specstone_core/src/templates/shipped_pack_files.dart';
import 'package:specstone_core/src/templates/template_fault.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/marketing.dart';
import '../../helpers/prd_core.dart';
import '../../helpers/shipped_pins.dart';
import '../../helpers/software_tech.dart';
import '../../helpers/temp_tree.dart';

const _resultsDoc = 'specs/f01_login/results/RESULTS.md';
const _positioningDoc = 'specs/marketing/POSITIONING.md';
const _packs = ['prd-core', 'software-tech', 'marketing'];

const _storedStatement =
    "The docs hold the stable facts and the campaign plan; the project's own "
    'skills write the content outside the docs.';
const _learningStatement = 'A learning edits the doc it corrects.';
const _measurementsStatement =
    "A campaign's results never go under `measurements/`, which keeps the "
    "project goals' measurements alone.";

/// One expected marketing doc type: its path, parent, and sections.
final class _DocTypeSpec {
  const new(this.path, this.parent, this.sections);

  final String path;
  final String? parent;
  final List<SectionSpec> sections;
}

const _docTypes = <String, _DocTypeSpec>{
  'positioning': _DocTypeSpec('specs/marketing/POSITIONING.md', null, [
    SectionSpec('competitive_alternatives', 'Competitive alternatives'),
    SectionSpec('unique_attributes', 'Unique attributes'),
    SectionSpec('value', 'Value'),
    SectionSpec('best_fit_customers', 'Best fit customers'),
    SectionSpec('market_category', 'Market category'),
  ]),
  'messaging': _DocTypeSpec('specs/marketing/MESSAGING.md', null, [
    SectionSpec('core_message', 'Core message'),
    SectionSpec('pillars', 'Pillars'),
    SectionSpec('per_audience', 'Per audience'),
  ]),
  'voice': _DocTypeSpec('specs/marketing/VOICE.md', null, [
    SectionSpec('tone', 'Tone'),
    SectionSpec('words', 'Words'),
  ]),
  'audience': _DocTypeSpec('specs/marketing/AUDIENCE.md', null, [
    SectionSpec('segments', 'Segments'),
  ]),
  'lifecycle': _DocTypeSpec('specs/marketing/LIFECYCLE.md', null, [
    SectionSpec('stages', 'Stages'),
    SectionSpec('triggers', 'Triggers'),
  ]),
  'content_pillars': _DocTypeSpec('specs/marketing/CONTENT_PILLARS.md', null, [
    SectionSpec('themes', 'Themes'),
  ]),
  'loyalty': _DocTypeSpec('specs/marketing/LOYALTY.md', null, [
    SectionSpec('retention', 'Retention'),
    SectionSpec('rewards', 'Rewards'),
  ]),
  'channel': _DocTypeSpec('specs/marketing/channels/{slug}.md', null, [
    SectionSpec('audience', 'Audience'),
    SectionSpec('format', 'Format'),
    SectionSpec('cadence', 'Cadence'),
    SectionSpec('measures', 'Measures'),
  ]),
  'competitor': _DocTypeSpec('specs/marketing/competitors/{slug}.md', null, [
    SectionSpec('offer', 'Offer'),
    SectionSpec('position', 'Position'),
    SectionSpec('gaps', 'Gaps'),
  ]),
  'campaign': _DocTypeSpec('specs/f{nn}_{slug}/CAMPAIGN.md', 'feature', [
    SectionSpec('plan', 'Plan'),
  ]),
  'campaign_results': _DocTypeSpec(
    'specs/f{nn}_{slug}/results/RESULTS.md',
    'campaign',
    [
      SectionSpec('funnel', 'Funnel', required: true),
      SectionSpec('channels', 'Channels', required: true),
      SectionSpec('spend', 'Spend', required: true),
    ],
  ),
};

/// Checks [text] at [path] in a project that lists the marketing packs.
Future<List<String>> _findings(
  String path,
  String text, {
  FindingKind? kind,
  Map<String, String> extra = const {},
}) async {
  final project = await writeCheckProject(
    extra: {
      '.specstone/config.yaml': shippedPinsConfig(_packs),
      'docs/$path': text,
      ...extra,
    },
  );
  return spots(await checkOf(project, docPath: path), kind);
}

void main() {
  late MergedSet set;

  setUpAll(() async => set = await resolveMarketing());

  group('manifest', () {
    test('marketing ships at 1.0.0 and extends prd-core', () {
      final bytes = shippedPackFiles['marketing/pack.yaml'];
      expect(bytes, isNotNull);
      final manifest = PackManifest.parse(
        utf8.decode(bytes!),
        file: 'packs/marketing/pack.yaml',
      );
      expect(manifest.name, 'marketing');
      expect(manifest.version.toString(), '1.0.0');
      expect(manifest.extendsPack, 'prd-core');
    });

    test('outside its patterns folder the pack holds the manifest and the '
        'doc type files of marketingIds only', () {
      expect(
        shippedPackFiles.keys.where(
          (k) =>
              k.startsWith('marketing/') &&
              !k.startsWith('marketing/patterns/'),
        ),
        unorderedEquals([
          'marketing/pack.yaml',
          for (final id in marketingIds) 'marketing/$id.yaml',
        ]),
      );
      for (final id in prdCoreIds) {
        expect(shippedPackFiles.containsKey('marketing/$id.yaml'), isFalse);
      }
    });

    test('a project that lists prd-core and marketing resolves with no '
        'extends_target_unknown', () async {
      final project = await writeTree({
        '.specstone/config.yaml': shippedPinsConfig(['prd-core', 'marketing']),
      });
      final home = await writeTree({});

      final merged = TemplateResolver().resolve(
        workingDirectory: project,
        homeDirectory: home,
      );

      expect(merged.lookup('campaign')?.pack, 'marketing');
    });

    test('a project that lists marketing without prd-core is '
        'prd_core_missing', () async {
      final project = await writeTree({
        '.specstone/config.yaml': shippedPinsConfig(['marketing']),
      });
      final home = await writeTree({});
      expect(
        () => TemplateResolver().resolve(
          workingDirectory: project,
          homeDirectory: home,
        ),
        throwsA(
          isA<TemplateFault>().having(
            (f) => f.code,
            'code',
            FaultCode.prdCoreMissing,
          ),
        ),
      );
    });

    test('a pin one version below fails as pack_pin_older naming the shipped '
        'version', () async {
      final project = await writeTree({
        '.specstone/config.yaml':
            'packs:\n  prd-core: ${shippedPackVersions()['prd-core']}\n'
            '  marketing: 0.9.0\n',
      });
      final home = await writeTree({});
      expect(
        () => TemplateResolver().resolve(
          workingDirectory: project,
          homeDirectory: home,
        ),
        throwsA(
          isA<TemplateFault>()
              .having((f) => f.code, 'code', FaultCode.packPinOlder)
              .having((f) => f.message, 'message', contains('1.0.0')),
        ),
      );
    });
  });

  group('merged set', () {
    test('lists the eleven marketing doc types beside the prd-core ones', () {
      expect(marketingIds, hasLength(11));
      expect(
        set.docTypes.map((d) => d.id).toList(),
        [...prdCoreIds, ...marketingIds]..sort(),
      );
      for (final id in marketingIds) {
        expect(prdCoreDocType(set, id).pack, 'marketing', reason: id);
      }
    });

    test('lists with software-tech too and refuses no id', () async {
      final both = await resolveMarketing(_packs);
      expect(
        both.docTypes.map((d) => d.id).toList(),
        [...prdCoreIds, ...softwareTechIds, ...marketingIds]..sort(),
      );
    });

    test('is absent from a project that lists prd-core alone', () async {
      final without = await resolvePrdCore();
      for (final id in marketingIds) {
        expect(without.lookup(id), isNull, reason: id);
      }
    });
  });

  group('doc types', () {
    test('each loads at its path with its parent', () {
      expect([..._docTypes.keys]..sort(), marketingIds);
      for (final MapEntry(key: id, value: spec) in _docTypes.entries) {
        final docType = prdCoreDocType(set, id);
        expect(docType.path, spec.path, reason: id);
        expect(docType.parent, spec.parent, reason: id);
      }
    });

    test('each holds the sections of its row, in order, with the required '
        'flags', () {
      for (final MapEntry(key: id, value: spec) in _docTypes.entries) {
        expectSections(prdCoreDocType(set, id), spec.sections);
      }
    });

    test('no guide carries a shared readability line', () {
      for (final id in marketingIds) {
        final description = prdCoreDocType(set, id).description;
        expect(description, isNot(contains(citeNoteGuideLine)), reason: id);
      }
    });

    test('none sets per_target', () {
      for (final id in marketingIds) {
        expect(prdCoreDocType(set, id).isPerTarget, isFalse, reason: id);
      }
    });

    test('only campaign carries an own field, covers, optional with '
        'pointer prefix and root project', () {
      for (final id in marketingIds.where((i) => i != 'campaign')) {
        expectOwnFields(prdCoreDocType(set, id), const []);
      }
      final campaign = prdCoreDocType(set, 'campaign');
      expectOwnFields(campaign, const [
        FieldSpec(
          'covers',
          FieldType.outputRef,
          list: true,
          pointer: PointerKind.prefix,
        ),
      ]);
      expect(fieldOf(campaign, 'covers').root, PointerRoot.project);
    });

    test('every description holds the two guide statements on one line each, '
        'and campaign_results the measurements one', () {
      for (final id in marketingIds) {
        final lines = prdCoreDocType(set, id).description!.split('\n');
        expect(
          lines.where((l) => l == _storedStatement),
          hasLength(1),
          reason: id,
        );
        expect(
          lines.where((l) => l == _learningStatement),
          hasLength(1),
          reason: id,
        );
        expect(
          lines.where((l) => l == _measurementsStatement),
          hasLength(id == 'campaign_results' ? 1 : 0),
          reason: id,
        );
      }
    });

    test('campaign asks for no code_root setting', () {
      final campaign = prdCoreDocType(set, 'campaign');
      expect(campaign.description, isNot(contains('code_root')));
      expect(
        fieldOf(campaign, 'covers').description,
        isNot(contains('code_root')),
      );
      expect(fieldOf(campaign, 'covers').description, contains('project root'));
    });

    test('every path starts under specs/ and overlaps no other pack path', () {
      final others = [
        for (final d in set.docTypes)
          if (d.pack != 'marketing') ...d.paths,
      ];
      for (final id in marketingIds) {
        final path = prdCoreDocType(set, id).path!;
        expect(path, startsWith('specs/'), reason: id);
        expect(others, isNot(contains(path)), reason: id);
      }
    });

    test('each guide cites at least one reference entry', () {
      for (final id in marketingIds) {
        expect(prdCoreDocType(set, id).reference, isNotEmpty, reason: id);
      }
    });
  });

  group('check', () {
    test('a campaign with no covers gives no finding', () async {
      expect(await _findings(campaignDocPath, campaignDocText()), isEmpty);
    });

    test('a campaign outside a feature folder is untyped', () async {
      const loose = 'specs/CAMPAIGN.md';
      expect(
        await _findings(loose, campaignDocText(), kind: FindingKind.untypedDoc),
        ['$loose:1: untyped_doc'],
      );
    });

    test('a results doc linking a CSV that does not exist is '
        'link_target_missing', () async {
      expect(
        await _findings(
          _resultsDoc,
          '# Launch results\n\n## Funnel\n\n[funnel](funnel.csv)\n\n'
          '## Channels\n\nEmail.\n\n## Spend\n\nNone.\n',
          kind: FindingKind.linkTargetMissing,
          extra: {'docs/$campaignDocPath': campaignDocText()},
        ),
        [startsWith('$_resultsDoc:')],
      );
    });

    test(
      'a results doc linking a CSV in its folder gives no finding',
      () async {
        expect(
          await _findings(
            _resultsDoc,
            '# Launch results\n\n## Funnel\n\n[funnel](funnel.csv)\n\n'
            '## Channels\n\nEmail.\n\n## Spend\n\nNone.\n',
            extra: {
              'docs/$campaignDocPath': campaignDocText(),
              'docs/specs/f01_login/results/funnel.csv': 'stage,count\n',
            },
          ),
          isEmpty,
        );
      },
    );

    test('a positioning doc with no Value section gives no finding', () async {
      expect(
        await _findings(
          _positioningDoc,
          '# Positioning\n\n## Market category\n\nLogin tools.\n',
        ),
        isEmpty,
      );
    });
  });
}
