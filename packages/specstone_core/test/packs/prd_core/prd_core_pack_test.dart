import 'dart:convert';

import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/consistency_check/readability_rules.dart';
import 'package:specstone_core/src/setup_migration/migration_chain.dart';
import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/pack_manifest.dart';
import 'package:specstone_core/src/templates/pack_migration.dart';
import 'package:specstone_core/src/templates/pack_version.dart';
import 'package:specstone_core/src/templates/shipped_pack_files.dart';
import 'package:specstone_core/src/templates/template_fault.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/prd_core.dart';

/// The shared lines `prd-core` ships, by id, in file order.
const _sharedLines = <String, String>{
  'present_truth': 'State the present truth; history lives in git.',
  'one_rule_per_item': _oneRuleLine,
  'cite_at_item_end': citeNoteGuideLine,
  'one_example': _exampleLine,
  'condition_first': _conditionLine,
  'cite_by_link': _citeLine,
};

/// The doc types whose lint holds the `history` pattern.
const _historyIds = [
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
  'user_story',
];

const _citeLine =
    'Cite a rule another doc owns by a link to its item, never restate it.';

const _oneRuleLine =
    'Keep one rule in each item, and put several conditions in a nested list. '
    'Move the detail of a one-sentence paragraph with no ID to the section of '
    'the same doc that owns it, never into a sub-list.';

const _exampleLine =
    'Give a non-obvious rule one example inside its item, as a `such as` '
    'clause or one "For example," sentence, within the sentence\'s cap.';

const _conditionLine =
    'State the condition first, then the rule, one clause chain per sentence; '
    'split a sentence whose clauses nest.';

/// The doc types whose guide holds a banned word list at neither level.
const _noWordListIds = [
  'project',
  'features',
  'persona',
  'anti_persona',
  'reference',
  'feature',
  'user_story',
  'journey',
  'measurement',
  'goal',
  'glossary',
];

/// The doc types that carry no `reference:` entry.
const _noReferenceIds = [
  'project',
  'features',
  'reference',
  'journey',
  'measurement',
  'goal',
  'glossary',
];

/// The readability bar lines the guide prints, as short fragments.
const _barFragments = [
  'put several conditions in a nested list',
  "Put a cite or an ownership note at the item's end",
  'one example inside its item',
  'State the condition first, then the rule',
];

void main() {
  group('prd-core manifest', () {
    test('prd-core ships at 1.18.0 with no extends', () {
      final bytes = shippedPackFiles['prd-core/pack.yaml'];
      expect(bytes, isNotNull);
      final manifest = PackManifest.parse(
        utf8.decode(bytes!),
        file: 'packs/prd-core/pack.yaml',
      );
      expect(manifest.name, 'prd-core');
      expect(manifest.version.toString(), '1.18.0');
      expect(manifest.extendsPack, isNull);
      final upgrade = _upgradeFrom('1.7.0', manifest);
      expect(upgrade.target.toString(), '1.18.0');
      expect(
        [for (final s in upgrade.steps) (s.from.toString(), s.step.kind)],
        [('1.7.0', 'strip_shared_copies')],
      );
    });

    test('a pin past the strip entry gets the pin change only', () {
      final upgrade = _upgradeFrom('1.17.0', _prdCoreManifest());
      expect(upgrade.target.toString(), '1.18.0');
      expect(upgrade.steps, isEmpty);
    });

    test('prd-core lists one migration entry, from 1.7.0, holding the one '
        'strip step', () {
      final migrations = _prdCoreManifest().migrations;
      expect(migrations.map((e) => e.from.toString()), ['1.7.0']);
      expect(migrations.single.steps.single, isA<StripSharedCopies>());
    });

    test('prd-core ships its shared lines in order with their reach and no '
        'shared field', () {
      final shared = _prdCoreManifest().shared;
      expect({for (final l in shared.lines) l.id: l.text}, _sharedLines);
      expect(shared.lines.map((l) => l.id), _sharedLines.keys);
      expect(
        {for (final l in shared.lines) l.id: l.forDocTypes},
        {
          for (final id in _sharedLines.keys)
            id: id == 'present_truth' ? _historyIds : null,
        },
      );
      expect(shared.fields, isEmpty);
    });

    test('a project pinning the shipped prd-core resolves with '
        'no fault', () async {
      final set = await resolvePrdCore();
      expect(set.docTypes.every((d) => d.pack == 'prd-core'), isTrue);
    });
  });

  group('listedWordsIn', () {
    test('finds whole words and phrases in any case', () {
      expect(listedWordsIn('This is Fast, etc. and/or Light-Weight.'), [
        'fast',
        'light-weight',
        'this',
        'etc.',
        'and/or',
      ]);
      expect(listedWordsIn('When required, but not limited to X'), [
        'when required',
        'but not limited to',
      ]);
    });

    test('a listed word inside a longer word is no hit', () {
      expect(
        listedWordsIn('Safety, usability, smaller, fastest, retcon'),
        isEmpty,
      );
    });
  });

  group('prd-core doc types', () {
    test('each section the pack file gives a template keeps it, and no '
        'description holds a YAML key', () async {
      final set = await resolvePrdCore();
      final blockKey = RegExp(r'\b[a-z_]+: \|');
      for (final docType in set.docTypes) {
        final file = loadYaml(
          utf8.decode(shippedPackFiles['prd-core/${docType.id}.yaml']!),
        ) as YamlMap;
        final sections = (file['sections'] as YamlList?)?.nodes ?? [];
        for (final node in sections) {
          final raw = node as YamlMap;
          if (!raw.containsKey('template')) continue;
          final id = raw['id'] as String;
          expect(
            sectionOf(docType, id).template,
            isNotNull,
            reason: '${docType.id} $id',
          );
        }
        final texts = [
          docType.description,
          for (final field in docType.fields) field.description,
          for (final section in docType.sections) section.description,
        ];
        for (final text in texts) {
          expect(text ?? '', isNot(contains(blockKey)), reason: docType.id);
        }
      }
    });

    test('only project, glossary, gnfr, and goal set bundle_refs', () async {
      final set = await resolvePrdCore();
      expect(
        {
          for (final d in set.docTypes)
            if (d.bundleRefs == true) d.id,
        },
        {'project', 'glossary', 'gnfr', 'goal'},
      );
    });

    test('a project listing only prd-core '
        'holds exactly the fourteen doc types', () async {
      final set = await resolvePrdCore();
      expect(set.docTypes.map((d) => d.id), prdCoreIds);
      expect(set.docTypes.map((d) => d.pack), everyElement('prd-core'));
    });

    test('only the feature summary field carries a lint', () async {
      final set = await resolvePrdCore();
      expect(
        [
          for (final d in set.docTypes)
            for (final f in d.fields)
              if (f.lint != null) '${d.id}.${f.id}',
        ],
        ['feature.summary'],
      );
    });

    test(
      'no description states the sentence length a lint key holds',
      () async {
        final set = await resolvePrdCore();
        for (final docType in set.docTypes) {
          expect(
            docType.description,
            isNot(contains('Each sentence holds')),
            reason: docType.id,
          );
        }
      },
    );

    test('no description holds a shared line, and each guide prints the '
        'shared lines that reach it', () async {
      final set = await resolvePrdCore();
      for (final docType in set.docTypes) {
        final texts = [
          docType.description,
          for (final field in docType.fields) field.description,
          for (final section in docType.sections) section.description,
        ];
        for (final line in _sharedLines.values) {
          for (final text in texts) {
            expect(text ?? '', isNot(contains(line)), reason: docType.id);
          }
        }
        expect(docType.sharedLines.map((l) => l.id), [
          for (final id in _sharedLines.keys)
            if (id != 'present_truth' || _historyIds.contains(docType.id)) id,
        ], reason: docType.id);
      }
    });

    test('each doc type flags a doc over its own line and character '
        'caps', () async {
      final set = await resolvePrdCore();
      // A draft takes no approval stamp, so the counts stay exact.
      const draft = '---\ndraft: true\n---\n\n# Probe\n\n';
      for (final docType in set.docTypes) {
        final path = docType.path!
            .replaceAll('{nn}', '07')
            .replaceAll('{slug}', 'probe');
        Future<Set<FindingKind>> kindsOf(String body) async {
          final report = await checkOf(
            await writeCheckProject(
              extra: {'docs/$path': '$draft$body\n'},
              unstamped: {'docs/$path'},
            ),
          );
          return {
            for (final f in report.findings)
              if (f.path == path) f.kind,
          };
        }

        final lines = List.filled(docType.lint.maxLines! + 1, 'x').join('\n');
        final chars = 'x' * (docType.lint.maxChars! + 1);
        expect(
          await kindsOf(lines),
          contains(FindingKind.linesOverLimit),
          reason: '${docType.id} lines',
        );
        expect(
          await kindsOf(chars),
          contains(FindingKind.charsOverLimit),
          reason: '${docType.id} chars',
        );
      }
    });

    test('a project that groups features overrides the '
        'four paths in its layer', () async {
      const story = 'prds/features/{slug}/f{nn}_{slug}/us{nn}_{slug}';
      final set = await resolvePrdCore(
        templates: {
          'feature.yaml':
              'path: prds/features/{slug}/f{nn}_{slug}/FEATURE.md\n',
          'user_story.yaml': 'path: $story/USER_STORY.md\n',
          'fr.yaml': 'path: $story/fr{nn}_{slug}.md\n',
          'nf.yaml': 'path: $story/nf{nn}_{slug}.md\n',
        },
      );
      expect(
        set.lookup('feature')!.path,
        'prds/features/{slug}/f{nn}_{slug}/FEATURE.md',
      );
      expect(set.lookup('user_story')!.path, '$story/USER_STORY.md');
      expect(set.lookup('fr')!.path, '$story/fr{nn}_{slug}.md');
      expect(set.lookup('nf')!.path, '$story/nf{nn}_{slug}.md');
      expect(set.lookup('fr')!.parent, 'user_story');
    });

    test('a project adds Availability to gnfr as a project '
        'section', () async {
      final set = await resolvePrdCore(
        templates: {
          'gnfr.yaml':
              'sections:\n'
              '  - id: availability\n'
              '    header: Availability\n'
              '    prefix_id: NFR-A\n'
              '    required: true\n'
              '    after: reliability\n',
        },
      );
      final gnfr = set.lookup('gnfr')!;
      expect(gnfr.sections.map((s) => s.id).take(5), [
        'performance',
        'security',
        'reliability',
        'availability',
        'maintainability',
      ]);
      expect(sectionOf(gnfr, 'availability').prefixId, 'NFR-A');
    });

    test('a project changes the fr '
        'Statement list with add and remove', () async {
      final set = await resolvePrdCore(
        templates: {
          'fr.yaml':
              'sections:\n  - id: statement\n    lint:\n      banned_words:\n'
              '        add: [simply]\n        remove: [etc.]\n',
        },
      );
      expect(sectionOf(set.lookup('fr')!, 'statement').bannedWords, [
        ...nasaBannedWords.where((w) => w != 'etc.'),
        'simply',
      ]);
      expect(set.lookup('fr')!.lint.bannedWords, isNull);
    });

    test('a plain Statement list over the shipped one is '
        'list_override_needs_add_remove', () async {
      await expectLater(
        resolvePrdCore(
          templates: {
            'fr.yaml':
                'sections:\n  - id: statement\n    lint:\n'
                '      banned_words: [simply]\n',
          },
        ),
        throwsA(
          isA<TemplateFault>().having(
            (f) => f.code,
            'code',
            FaultCode.listOverrideNeedsAddRemove,
          ),
        ),
      );
    });

    test('a project writes its own doc-level list plain', () async {
      final set = await resolvePrdCore(
        templates: {'fr.yaml': 'lint:\n  banned_words: [simply]\n'},
      );
      expect(set.lookup('fr')!.lint.bannedWords, ['simply']);
    });
  });

  group('expectOwnFields', () {
    test('fails when an enum field lists other values', () async {
      final anti = prdCoreDocType(await resolvePrdCore(), 'anti_persona');
      expect(
        () => expectOwnFields(anti, const [
          FieldSpec(
            'anti_type',
            FieldType.enumType,
            required: true,
            enumValues: ['misuser', 'other'],
          ),
          FieldSpec(
            'basis',
            FieldType.enumType,
            required: true,
            enumValues: ['proto', 'qualitative', 'statistical'],
          ),
          FieldSpec('reviewed', FieldType.date),
        ]),
        throwsA(isA<TestFailure>()),
      );
    });

    test('fails when a docRef field names other doc types', () async {
      final feature = prdCoreDocType(await resolvePrdCore(), 'feature');
      expect(
        () => expectOwnFields(feature, const [
          FieldSpec('vision', FieldType.string, list: true),
          FieldSpec('goals', FieldType.string, list: true),
          FieldSpec(
            'persona',
            FieldType.docRef,
            list: true,
            docTypes: ['anti_persona'],
          ),
          FieldSpec('system', FieldType.string),
          FieldSpec(
            'depends_on',
            FieldType.docRef,
            list: true,
            docTypes: ['feature'],
          ),
        ]),
        throwsA(isA<TestFailure>()),
      );
    });
  });

  group('prd-core shared lint and sources', () {
    test('eleven doc types carry no banned word list at either level and '
        'seven carry no reference entry', () async {
      final set = await resolvePrdCore();
      for (final id in _noWordListIds) {
        final docType = prdCoreDocType(set, id);
        expect(docType.lint.bannedWords, isNull, reason: id);
        for (final section in docType.sections) {
          expect(section.bannedWords, isNull, reason: '$id ${section.id}');
        }
      }
      for (final id in _noReferenceIds) {
        expect(prdCoreDocType(set, id).reference ?? [], isEmpty, reason: id);
      }
    });

    test('the built-in reference field of every doc type carries no '
        'doc_types limit', () async {
      final set = await resolvePrdCore();
      for (final docType in set.docTypes) {
        expect(
          fieldOf(docType, 'reference').docTypes,
          isNull,
          reason: docType.id,
        );
      }
    });
  });

  group('prd-core pack contents', () {
    test('a project adds its own project-level doc type and the pack '
        'defines no generic one', () async {
      final set = await resolvePrdCore(
        templates: {
          'runbook.yaml':
              'id: runbook\ndescription: A runbook.\n'
              'path: prds/runbooks/{slug}/RUNBOOK.md\n'
              'sections:\n  - id: steps\n    header: Steps\n',
        },
      );
      expect(set.lookup('runbook'), isNotNull);
      for (final generic in ['document', 'doc', 'note', 'spec']) {
        expect(set.lookup(generic), isNull, reason: generic);
      }
    });

    test('the shipped gnfr categories keep their prefix ids after a project '
        'adds one', () async {
      final shipped = prdCoreDocType(await resolvePrdCore(), 'gnfr');
      final added = prdCoreDocType(
        await resolvePrdCore(
          templates: {
            'gnfr.yaml':
                'sections:\n  - id: availability\n    header: Availability\n'
                '    prefix_id: NFR-A\n    after: reliability\n',
          },
        ),
        'gnfr',
      );
      for (final section in shipped.sections) {
        expect(sectionOf(added, section.id).prefixId, section.prefixId);
      }
    });

    test('a pin at 1.7.0 or 1.9.0 takes steps that change no goal doc', () {
      final manifest = _prdCoreManifest();
      for (final pin in ['1.7.0', '1.9.0']) {
        expect(
          _upgradeFrom(
            pin,
            manifest,
          ).steps.where((s) => s.step.touches('goal')),
          isEmpty,
          reason: pin,
        );
      }
    });
  });

  group('prd-core writing guides', () {
    test('project, goal, glossary, features, and gnfr descriptions give '
        'their fixed titles', () async {
      final set = await resolvePrdCore();
      const titles = {
        'project': '# Project context',
        'goal': '# Project goals',
        'glossary': '# Domain glossary',
        'features': '# Feature map',
        'gnfr': '# Project-wide non-functional requirements',
      };
      for (final MapEntry(key: id, value: title) in titles.entries) {
        expect(
          prdCoreDocType(set, id).description,
          contains('Title it `$title`'),
          reason: id,
        );
      }
    });

    test('persona, anti_persona, reference, feature, user_story, fr, and nf '
        'descriptions title the doc by its own name', () async {
      final set = await resolvePrdCore();
      final byName = RegExp('Title it `# <[^>]+>`');
      for (final id in [
        'persona',
        'anti_persona',
        'reference',
        'feature',
        'user_story',
        'fr',
        'nf',
      ]) {
        expect(
          byName.hasMatch(prdCoreDocType(set, id).description!),
          isTrue,
          reason: id,
        );
      }
      expect(prdCoreDocType(set, 'fr').description, contains('`# <Name>`'));
      expect(
        prdCoreDocType(set, 'persona').description,
        contains('`# <archetype title>`'),
      );
    });

    test('gnfr, fr, and nf descriptions name the other -ly and -ize word '
        'classes', () async {
      final set = await resolvePrdCore();
      for (final id in ['gnfr', 'fr', 'nf']) {
        expect(
          prdCoreDocType(set, id).description,
          contains('-ly and -ize words beyond the banned list'),
          reason: id,
        );
      }
    });

    test('every other description states one rule per ID and its guide prints '
        'the readability bar', () async {
      final set = await resolvePrdCore();
      final perId = RegExp(r'one rule per (?:`[\w-]+\*` )?ID');
      for (final docType in set.docTypes) {
        if (docType.id == 'fr' || docType.id == 'glossary') continue;
        expect(
          perId.hasMatch(docType.description!),
          isTrue,
          reason: docType.id,
        );
        for (final fragment in _barFragments) {
          expect(docType.renderGuide(), contains(fragment), reason: docType.id);
        }
      }
    });

    test('id-less section types state one rule per item under the '
        'readability bar', () async {
      final set = await resolvePrdCore();
      for (final id in [
        'anti_persona',
        'feature',
        'features',
        'glossary',
        'journey',
        'persona',
        'reference',
      ]) {
        final guide = prdCoreDocType(set, id).renderGuide();
        final rule = guide.indexOf('one rule per item');
        expect(rule, isNonNegative, reason: id);
        for (final fragment in _barFragments) {
          expect(
            guide.indexOf(fragment),
            greaterThan(rule),
            reason: '$id $fragment',
          );
        }
      }
    });

    test('every guide says a rule another doc owns is cited by a link, never '
        'restated', () async {
      final set = await resolvePrdCore();
      for (final docType in set.docTypes) {
        expect(
          docType.renderGuide(),
          contains('by a link to its item, never restate it'),
          reason: docType.id,
        );
      }
    });

    test('the fr edge_cases and user_story rules descriptions ask for no ID '
        'order', () async {
      final set = await resolvePrdCore();
      final edge = sectionOf(prdCoreDocType(set, 'fr'), 'edge_cases');
      final rules = sectionOf(prdCoreDocType(set, 'user_story'), 'rules');
      expect(edge.description, contains('`E01 — <trigger> → <response>`'));
      expect(rules.description, contains('`**BR-NN** — <rule>`'));
      for (final text in [edge.description!, rules.description!]) {
        expect(text, isNot(matches(RegExp('in order|numbered'))));
      }
    });

    test('every guide prints the readability bar and no section description '
        'holds it', () async {
      final set = await resolvePrdCore();
      for (final docType in set.docTypes) {
        for (final fragment in _barFragments) {
          expect(docType.renderGuide(), contains(fragment), reason: docType.id);
          for (final section in docType.sections) {
            expect(
              section.description ?? '',
              isNot(contains(fragment)),
              reason: '${docType.id} ${section.id}',
            );
          }
        }
      }
    });
  });
}

PackManifest _prdCoreManifest() => PackManifest.parse(
  utf8.decode(shippedPackFiles['prd-core/pack.yaml']!),
  file: 'packs/prd-core/pack.yaml',
);

/// The one upgrade of a project that pins `prd-core` at [pin].
PackUpgrade _upgradeFrom(String pin, PackManifest manifest) => selectUpgrades(
  {'prd-core': PackVersion.parse(pin, file: 'config', key: 'prd-core')},
  {'prd-core': manifest},
).single;
