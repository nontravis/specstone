import 'dart:convert';

import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/pack_manifest.dart';
import 'package:specstone_core/src/templates/shipped_pack_files.dart';
import 'package:specstone_core/src/templates/template_fault.dart';
import 'package:test/test.dart';

import '../../helpers/prd_core.dart';

void main() {
  group('prd-core manifest', () {
    test('f03/us06/fr01: prd-core ships at 1.3.0 with no extends', () {
      final bytes = shippedPackFiles['prd-core/pack.yaml'];
      expect(bytes, isNotNull);
      final manifest = PackManifest.parse(
        utf8.decode(bytes!),
        file: 'packs/prd-core/pack.yaml',
      );
      expect(manifest.name, 'prd-core');
      expect(manifest.version.toString(), '1.3.0');
      expect(manifest.extendsPack, isNull);
    });

    test('f03/us06/fr01: a project pinning the shipped prd-core resolves with '
        'no fault', () async {
      final set = await resolvePrdCore();
      expect(set.docTypes.every((d) => d.pack == 'prd-core'), isTrue);
    });
  });

  group('listedWordsIn', () {
    test('f03/us06/fr03: finds whole words and phrases in any case', () {
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

    test('f03/us06/fr03: a listed word inside a longer word is no hit', () {
      expect(
        listedWordsIn('Safety, usability, smaller, fastest, retcon'),
        isEmpty,
      );
    });
  });

  group('prd-core doc types', () {
    test('f03/us06/fr01, f03/us06/fr01/e01: a project listing only prd-core '
        'holds exactly the eleven doc types', () async {
      final set = await resolvePrdCore();
      expect(set.docTypes.map((d) => d.id), prdCoreIds);
      expect(set.docTypes.map((d) => d.pack), everyElement('prd-core'));
    });

    test('f03/us06/fr01/e03: a project that groups features overrides the '
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

    test('f03/us06/fr01/e04: a project adds Availability to gnfr as a project '
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

    test('f03/us06/fr03/e03: a plain Statement list over the shipped one is '
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

    test(
      'f03/us06/fr03/e03: a project writes its own doc-level list plain',
      () async {
        final set = await resolvePrdCore(
          templates: {'fr.yaml': 'lint:\n  banned_words: [simply]\n'},
        );
        expect(set.lookup('fr')!.lint.bannedWords, ['simply']);
      },
    );
  });

  group('expectOwnFields', () {
    test(
      'f03/us06/fr01: fails when an enum field lists other values',
      () async {
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
      },
    );

    test(
      'f03/us06/fr01: fails when a docRef field names other doc types',
      () async {
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
          ]),
          throwsA(isA<TestFailure>()),
        );
      },
    );
  });
}
