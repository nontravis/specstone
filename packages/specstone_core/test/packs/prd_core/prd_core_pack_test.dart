import 'dart:convert';

import 'package:specstone_core/src/setup_migration/migration_chain.dart';
import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/pack_manifest.dart';
import 'package:specstone_core/src/templates/pack_version.dart';
import 'package:specstone_core/src/templates/shipped_pack_files.dart';
import 'package:specstone_core/src/templates/template_fault.dart';
import 'package:test/test.dart';

import '../../helpers/prd_core.dart';

void main() {
  final shipped = shippedPackVersions()['prd-core']!;

  group('prd-core manifest', () {
    test('prd-core ships at 1.17.0 with no extends', () {
      final bytes = shippedPackFiles['prd-core/pack.yaml'];
      expect(bytes, isNotNull);
      final manifest = PackManifest.parse(
        utf8.decode(bytes!),
        file: 'packs/prd-core/pack.yaml',
      );
      expect(manifest.name, 'prd-core');
      expect(manifest.version.toString(), '1.17.0');
      expect(manifest.extendsPack, isNull);
    });

    test('prd-core lists no migration entry with an empty step list', () {
      final manifest = PackManifest.parse(
        utf8.decode(shippedPackFiles['prd-core/pack.yaml']!),
        file: 'packs/prd-core/pack.yaml',
      );
      expect(manifest.migrations.where((e) => e.steps.isEmpty), isEmpty);
    });

    test('a 1.7.0 or 1.9.0 pin upgrades to the shipped version with no '
        'step', () {
      final manifest = PackManifest.parse(
        utf8.decode(shippedPackFiles['prd-core/pack.yaml']!),
        file: 'packs/prd-core/pack.yaml',
      );
      for (final pin in ['1.7.0', '1.9.0']) {
        final upgrades = selectUpgrades(
          {
            'prd-core': PackVersion.parse(
              pin,
              file: 'config.yaml',
              key: 'packs.prd-core',
            ),
          },
          {'prd-core': manifest},
        );
        expect(upgrades.single.target.toString(), shipped, reason: pin);
        expect(upgrades.single.steps, isEmpty, reason: pin);
      }
    });

    for (final pin in ['1.10.0', '1.11.0', '1.12.0']) {
      test('a $pin pin takes the shipped pin alone, with no step', () {
        final manifest = PackManifest.parse(
          utf8.decode(shippedPackFiles['prd-core/pack.yaml']!),
          file: 'packs/prd-core/pack.yaml',
        );
        final upgrades = selectUpgrades(
          {
            'prd-core': PackVersion.parse(
              pin,
              file: 'config.yaml',
              key: 'packs.prd-core',
            ),
          },
          {'prd-core': manifest},
        );
        expect(upgrades.single.target.toString(), shipped);
        expect(upgrades.single.steps, isEmpty);
      });
    }

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
    test('only project, glossary, gnfr, and goal set bundle_refs', () async {
      final set = await resolvePrdCore();
      expect(
        {
          for (final d in set.docTypes)
            if (d.bundleRefs != null) d.id: d.bundleRefs,
        },
        {'project': true, 'glossary': true, 'gnfr': true, 'goal': true},
      );
    });

    test('prd-core carries fourteen doc types', () async {
      final set = await resolvePrdCore();
      expect(set.docTypes, hasLength(14));
    });

    test('f03/us06/fr01, f03/us06/fr01/e01: a project listing only prd-core '
        'holds exactly the fourteen doc types', () async {
      final set = await resolvePrdCore();
      expect(set.docTypes.map((d) => d.id), prdCoreIds);
      expect(set.docTypes.map((d) => d.pack), everyElement('prd-core'));
    });

    test('every prd-core doc type caps a doc at 400 lines and 20000 '
        'characters', () async {
      final set = await resolvePrdCore();
      for (final docType in set.docTypes) {
        expect(docType.lint.maxLines, 400, reason: docType.id);
        expect(docType.lint.maxChars, 20000, reason: docType.id);
      }
    });

    test('Set the shared lint and sources: '
        'only glossary sets max_item_chars, so every other prd-core doc type '
        'takes the default', () async {
      final set = await resolvePrdCore();
      for (final docType in set.docTypes) {
        expect(
          docType.lint.maxItemChars,
          docType.id == 'glossary' ? 300 : isNull,
          reason: docType.id,
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

    test('f03/us06/fr03/e03, f03/us02/fr03/e08: a project changes the fr '
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
}
