import 'dart:convert';

import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:specstone_core/src/templates/pack_manifest.dart';
import 'package:specstone_core/src/templates/shipped_pack_files.dart';
import 'package:specstone_core/src/templates/template_fault.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/marketing.dart';
import '../../helpers/pattern_findings.dart';
import '../../helpers/prd_core.dart';
import '../../helpers/sentence_case.dart';
import '../../helpers/shared_lines.dart';
import '../../helpers/shipped_pins.dart';
import '../../helpers/software_tech.dart';
import '../../helpers/temp_tree.dart';
import '../../helpers/yaml_key_line.dart';

const _resultsDoc = 'specs/f01_login/results/RESULTS.md';
const _positioningDoc = 'specs/marketing/POSITIONING.md';
const _packs = ['prd-core', 'software-tech', 'marketing'];

/// The ids of the shared lines each guide prints, in print order: the
/// `prd-core` lines that reach every doc type, then the pack's own lines.
const _sharedLineIds = <String>[
  ...everyTypeSharedLineIds,
  'stable_facts_and_plan',
  'learning_edits_doc',
];

PackManifest _manifest() => PackManifest.parse(
  utf8.decode(shippedPackFiles['marketing/pack.yaml']!),
  file: 'packs/marketing/pack.yaml',
);

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
    test(
      'marketing ships at 1.5.0 with no migrations and extends prd-core',
      () {
        final bytes = shippedPackFiles['marketing/pack.yaml'];
        expect(bytes, isNotNull);
        final manifest = PackManifest.parse(
          utf8.decode(bytes!),
          file: 'packs/marketing/pack.yaml',
        );
        expect(manifest.name, 'marketing');
        expect(manifest.version.toString(), '1.5.0');
        expect(manifest.migrations, isEmpty);
        expect(manifest.extendsPack, 'prd-core');
      },
    );

    test('marketing declares one leftover home for the old '
        'competitor file', () {
      final entries = _manifest().leftoverHomes;

      expect(entries, hasLength(1));
      final entry = entries.single;
      expect(entry.path, 'specs/marketing/competitors/{slug}.md');
      expect(entry.sectionId, isNull);
      expect(entry.docTypes, isEmpty);
      expect(entry.to, ['competitor']);
    });

    test('ships stable_facts_and_plan, then learning_edits_doc, each naming '
        'the ten doc types, and no shared field', () {
      final shared = _manifest().shared;
      expect(
        [for (final l in shared.lines) (l.id, l.disabled)],
        [('stable_facts_and_plan', false), ('learning_edits_doc', false)],
      );
      for (final line in shared.lines) {
        expect(line.forDocTypes, marketingIds, reason: line.id);
      }
      expect(shared.fields, isEmpty);
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
          'marketing/competitor.yaml',
          for (final id in marketingIds) 'marketing/$id.yaml',
        ]),
      );
      for (final id in prdCoreIds.where((id) => id != 'competitor')) {
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

    test('an older marketing pin points at the shipped version', () async {
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
              .having((f) => f.message, 'message', contains('1.5.0')),
        ),
      );
    });
  });

  group('lint entries', () {
    const draft = '---\ndraft: true\n---\n\n';
    const noLink = [
      '- Parents of toddlers',
      '* Retired teachers, no persona yet',
      '1. Weekend gardeners',
      '2) A link-like [text] and (parens)',
    ];
    const linked = [
      '- [Parents](../prds/personas/parents.md) of toddlers',
      '- Gardeners, see [persona](../prds/personas/gardener.md)',
      '1. [Teachers](../prds/personas/teacher.md#needs)',
      '| Segment | Persona |',
      '  and a wrapped line of the item above',
    ];

    test('each doc type but the three placeholder-titled ones holds its title '
        'in the title key and its description states none', () {
      const placeholderTitled = {'channel', 'campaign', 'campaign_results'};
      for (final id in marketingIds) {
        final type = prdCoreDocType(set, id);
        if (placeholderTitled.contains(id)) {
          expect(type.title, isNull, reason: id);
        } else {
          expect(type.title, sentenceCase(id), reason: id);
        }
      }
    });

    test('every doc type titles with no number, so each sets '
        'lint.title_no_number', () {
      for (final id in marketingIds) {
        expect(prdCoreDocType(set, id).lint.titleNoNumber, isTrue, reason: id);
      }
    });

    test('a doc title holding a digit is title_numbered', () async {
      expect(
        await _findings(
          _positioningDoc,
          '$draft# Positioning 2\n\n## Value\n\nOne line.\n',
          kind: FindingKind.titleNumbered,
        ),
        hasLength(1),
      );
    });

    test('a segment item with no link is segment_link, and a linked item, a '
        'table line, a wrapped line, a fenced line, and a blank line give '
        'none', () async {
      const path = 'specs/marketing/AUDIENCE.md';
      final lines = await bannedLines(
        {
          '.specstone/config.yaml': shippedPinsConfig(_packs),
          'docs/$path':
              '$draft# Audience\n\n## Segments\n\n${linked.join('\n')}\n\n'
              '```\n- Fenced item\n```\n\n${noLink.join('\n')}\n',
        },
        path,
        'segment_link',
      );
      expect(lines, noLink);
    });

    test('the message reads the guide line', () {
      final entry = sectionOf(
        prdCoreDocType(set, 'audience'),
        'segments',
      ).bannedPatterns!.singleWhere((e) => e.id == 'segment_link');
      expect(
        entry.message,
        "segment item has no link; guide line: Link each segment's `persona` "
        'doc',
      );
    });
  });

  group('merged set', () {
    test('lists the ten marketing doc types beside the prd-core ones', () {
      expect(marketingIds, hasLength(10));
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

    test('guide campaign prints the five prd-core lines, then '
        'stable_facts_and_plan and learning_edits_doc, and no code_root '
        'line', () {
      final campaign = prdCoreDocType(set, 'campaign');
      expect(campaign.sharedLines.map((l) => l.id), _sharedLineIds);
      final guide = campaign.renderGuide();
      final starts = [
        for (final line in campaign.sharedLines) guide.indexOf(line.text),
      ];
      expect(starts, everyElement(isNonNegative));
      expect(starts, [...starts]..sort());
      expect(guide, isNot(contains('code_root')));
    });

    test('each guide prints the prd-core lines, then the two marketing '
        'lines', () {
      for (final id in marketingIds) {
        final type = prdCoreDocType(set, id);
        expect(type.sharedLines.map((l) => l.id), _sharedLineIds, reason: id);
        final guide = type.renderGuide();
        for (final line in type.sharedLines) {
          expect(guide, contains(line.text), reason: id);
        }
      }
    });

    test('no description restates a shared line that reaches its doc '
        'type', () {
      for (final id in marketingIds) {
        final type = prdCoreDocType(set, id);
        for (final description in descriptionsOf(type)) {
          for (final line in type.sharedLines) {
            expect(description ?? '', isNot(contains(line.text)), reason: id);
          }
        }
      }
    });

    test('no description or template holds a YAML key line', () {
      for (final id in marketingIds) {
        final type = prdCoreDocType(set, id);
        final texts = [
          ...descriptionsOf(type),
          for (final section in type.sections) section.template,
        ];
        for (final text in texts) {
          expectNoYamlKeyLine(text, reason: id);
        }
      }
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

  group('competitor layer', () {
    test('the competitor layer adds its section after lessons and keeps the '
        'prd-core path', () async {
      final base = prdCoreDocType(await resolvePrdCore(), 'competitor');
      final layered = prdCoreDocType(set, 'competitor');

      expect(layered.pack, 'prd-core');
      expect(layered.path, 'prds/competitors/{slug}/COMPETITOR.md');
      expect(layered.path, base.path);
      expect(layered.description, base.description);
      expectSections(layered, [
        ...base.sections.map(
          (s) => SectionSpec(
            s.id,
            s.header,
            prefixId: s.prefixId,
            required: s.required,
          ),
        ),
        const SectionSpec('offer', 'Offer'),
      ]);
      expect(base.sections.map((s) => s.id).last, 'lessons');
      expect(sectionOf(layered, 'offer').description, isNotEmpty);
    });

    test('an old marketing competitor doc is untyped_doc on the current '
        'marketing pin', () async {
      const old = 'specs/marketing/competitors/acme.md';

      expect(
        await _findings(
          old,
          '# Acme\n\n## Offer\n\nA sync tool.\n',
          kind: FindingKind.untypedDoc,
        ),
        ['$old:1: untyped_doc'],
      );
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
