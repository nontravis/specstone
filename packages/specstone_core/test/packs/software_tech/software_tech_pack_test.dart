import 'dart:convert';

import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:specstone_core/src/templates/pack_manifest.dart';
import 'package:specstone_core/src/templates/shipped_pack_files.dart';
import 'package:specstone_core/src/templates/template_fault.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';

import '../../helpers/prd_core.dart';
import '../../helpers/shipped_pins.dart';
import '../../helpers/software_tech.dart';
import '../../helpers/temp_tree.dart';

void main() {
  group('software-tech manifest', () {
    test('software-tech ships at 1.7.0 and extends prd-core', () {
      final bytes = shippedPackFiles['software-tech/pack.yaml'];
      expect(bytes, isNotNull);
      final manifest = PackManifest.parse(
        utf8.decode(bytes!),
        file: 'packs/software-tech/pack.yaml',
      );
      expect(manifest.name, 'software-tech');
      expect(manifest.version.toString(), '1.7.0');
      expect(manifest.extendsPack, 'prd-core');
    });

    test('a project pinning both packs resolves with no fault', () {
      expect(resolveSoftwareTech(), completes);
    });

    test('software-tech listed without prd-core is '
        'prd_core_missing', () async {
      final project = await writeTree({
        '.specstone/config.yaml': shippedPinsConfig(['software-tech']),
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
  });

  group('software-tech set', () {
    late MergedSet set;

    setUpAll(() async {
      set = await resolveSoftwareTech();
    });

    test('the set holds the eleven prd-core and the nine '
        'software-tech doc types', () {
      expect(
        set.docTypes.map((d) => d.id).toList(),
        [...prdCoreIds, ...softwareTechIds]..sort(),
      );
      for (final id in softwareTechIds) {
        expect(prdCoreDocType(set, id).pack, 'software-tech', reason: id);
      }
      for (final id in prdCoreIds) {
        expect(prdCoreDocType(set, id).pack, 'prd-core', reason: id);
      }
    });

    test('every spec doc path starts specs/, and the seven '
        'per-feature doc types take parent feature', () {
      const perFeature = <String, String>{
        'architecture': 'ARCHITECTURE',
        'domain': 'DOMAIN',
        'api': 'API',
        'integration': 'INTEGRATION',
        'error': 'ERROR',
        'auth': 'AUTH',
        'implementation': 'IMPLEMENTATION',
      };
      for (final MapEntry(:key, :value) in perFeature.entries) {
        final docType = prdCoreDocType(set, key);
        expect(docType.path, 'specs/f{nn}_{slug}/$value.md', reason: key);
        expect(docType.parent, 'feature', reason: key);
      }
      for (final id in softwareTechIds) {
        expect(prdCoreDocType(set, id).path, startsWith('specs/'), reason: id);
      }
    });

    test('no doc type is a spec index', () {
      expect(set.lookup('index'), isNull);
      for (final docType in set.docTypes) {
        expect(
          docType.path ?? '',
          isNot(endsWith('INDEX.md')),
          reason: docType.id,
        );
      }
    });

    test('rollout, observability, and events are optional '
        'sections, not doc types', () {
      for (final id in ['rollout', 'observability', 'events']) {
        expect(set.lookup(id), isNull, reason: id);
      }
      final architecture = prdCoreDocType(set, 'architecture');
      final integration = prdCoreDocType(set, 'integration');
      expect(sectionOf(architecture, 'rollout').required, isFalse);
      expect(sectionOf(architecture, 'observability').required, isFalse);
      expect(sectionOf(integration, 'events').required, isFalse);
    });

    test('only architecture and topic carry covers', () {
      for (final docType in set.docTypes) {
        expect(
          docType.fields.any((f) => f.id == 'covers'),
          docType.id == 'architecture' || docType.id == 'topic',
          reason: docType.id,
        );
      }
    });

    test('f03/us07/fr03, f03/us07/fr03/e01: no spec doc type carries a word '
        'list at either level', () {
      for (final id in softwareTechIds) {
        final docType = prdCoreDocType(set, id);
        expect(docType.lint.bannedWords, isNull, reason: id);
        for (final section in docType.sections) {
          expect(section.bannedWords, isNull, reason: '$id.${section.id}');
        }
      }
    });

    test('template_packs/write_spec_docs_from_software_tech/'
        'set_spec_lint_and_sources: no software-tech doc type sets '
        'max_item_chars, so each takes the default', () {
      for (final id in softwareTechIds) {
        expect(prdCoreDocType(set, id).lint.maxItemChars, isNull, reason: id);
      }
    });

    test('template_packs/write_spec_docs_from_software_tech/'
        'write_spec_writing_guides: every section description stays within '
        'five lines', () {
      for (final id in softwareTechIds) {
        for (final section in prdCoreDocType(set, id).sections) {
          final lines = const LineSplitter().convert(section.description ?? '');
          expect(
            lines.length,
            lessThanOrEqualTo(5),
            reason: '$id.${section.id}',
          );
        }
      }
    });

    test('f03/us06/fr01, f03/us07/fr01: no other doc type sets bundle, and no '
        'other section sets query', () {
      expect(
        [
          for (final t in set.docTypes)
            if (t.bundle != null) t.id,
        ],
        ['gnfr', 'project', 'tech_stack'],
      );
      expect(
        {
          for (final t in set.docTypes)
            for (final s in t.sections)
              if (s.query != null) t.id,
        },
        {'feature', 'project'},
      );
    });

    test('f03/us05/fr01, f03/us07/fr01: every code path field is read from '
        'the code root, which the config sets', () {
      final codePathFields = [
        for (final docType in set.docTypes)
          for (final field in docType.fields)
            if (field.type == FieldType.outputRef || field.id == 'code')
              (docType.id, field),
      ];

      expect(codePathFields.map((e) => '${e.$1}.${e.$2.id}'), [
        'architecture.covers',
        'implementation.implements',
        'implementation.tests',
        'tech_stack.code',
        'topic.covers',
      ]);
      for (final (docTypeId, field) in codePathFields) {
        expect(
          field.description,
          allOf(
            contains(
              "relative to the code root of the doc's target "
              '(`.specstone/config.yaml`, else the project root)',
            ),
            isNot(contains('relative to the project root')),
          ),
          reason: '$docTypeId.${field.id}',
        );
      }
    });
  });
}
