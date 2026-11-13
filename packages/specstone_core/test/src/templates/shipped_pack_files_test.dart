import 'dart:convert';

import 'package:specstone_core/src/doc_model/path_pattern.dart';
import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:specstone_core/src/templates/pack_manifest.dart';
import 'package:specstone_core/src/templates/pack_migration.dart';
import 'package:specstone_core/src/templates/shipped_pack_files.dart';
import 'package:test/test.dart';

import '../../helpers/prd_core.dart';
import '../../helpers/software_tech.dart';

void main() {
  test('f03/us03/fr03/e08: decodes base64 constants back to bytes', () {
    final files = decodeShippedPacks({
      'a/x.pdf': base64Encode([0xff, 0, 1]),
    });

    expect(files['a/x.pdf'], [0xff, 0, 1]);
  });

  test('f03/us03/fr03/e08: the shipped pack files are decoded', () {
    expect(shippedPackFiles.keys, contains('prd-core/pack.yaml'));
  });

  test(
    'f03/us06/fr01, f03/us07/fr01: shippedPackVersions reads the version each '
    'shipped pack.yaml carries',
    () {
      final versions = shippedPackVersions();
      expect(versions.keys, ['prd-core', 'software-tech']);
      for (final MapEntry(:key, :value) in versions.entries) {
        final manifest = PackManifest.parse(
          utf8.decode(shippedPackFiles['$key/pack.yaml']!),
          file: 'packs/$key/pack.yaml',
        );
        expect(value, manifest.version.toString());
      }
    },
  );

  test('template_packs/write_spec_docs_from_software_tech/ship_software_tech_pack: '
      'the shipped software-tech pack is 1.5.0', () {
    expect(shippedPackVersions()['software-tech'], '1.5.0');
  });

  group('template_packs/write_spec_docs_from_software_tech/'
      'ship_software_tech_pack', () {
    late MergedSet both;
    late MergedSet prdOnly;
    setUpAll(() async {
      both = await resolveSoftwareTech();
      prdOnly = await resolvePrdCore();
    });

    test('E01: the merged set holds the eleven prd-core and the nine '
        'software-tech doc types, the record among them', () {
      expect(
        both.docTypes.map((d) => d.id).toList(),
        [...prdCoreIds, ...softwareTechIds]..sort(),
      );
      expect(softwareTechIds, hasLength(9));
      expect(softwareTechIds, contains('implementation'));
      for (final id in softwareTechIds) {
        expect(prdCoreDocType(both, id).pack, 'software-tech', reason: id);
      }
    });

    test('S1, E01: each doc type takes the path and the parent of the Output '
        'table', () {
      const outputTable = <String, (String, String?)>{
        'tech_stack': ('specs/TECH_STACK.md', null),
        'architecture': ('specs/f{nn}_{slug}/ARCHITECTURE.md', 'feature'),
        'domain': ('specs/f{nn}_{slug}/DOMAIN.md', 'feature'),
        'api': ('specs/f{nn}_{slug}/API.md', 'feature'),
        'integration': ('specs/f{nn}_{slug}/INTEGRATION.md', 'feature'),
        'error': ('specs/f{nn}_{slug}/ERROR.md', 'feature'),
        'auth': ('specs/f{nn}_{slug}/AUTH.md', 'feature'),
        'topic': ('specs/topics/{slug}.md', null),
        'implementation': ('specs/f{nn}_{slug}/IMPLEMENTATION.md', 'feature'),
      };
      expect(outputTable.keys, unorderedEquals(softwareTechIds));
      for (final MapEntry(key: id, value: (path, parent))
          in outputTable.entries) {
        final docType = prdCoreDocType(both, id);
        expect(docType.path, path, reason: id);
        expect(docType.parent, parent, reason: id);
      }
    });

    test('S4, E08: the pack writes no layer over a prd-core doc type, so a '
        'story and an FR carry no code-pointer field', () {
      final files = shippedPackFiles.keys
          .where((k) => k.startsWith('software-tech/'))
          .toList();
      expect(
        files,
        unorderedEquals([
          'software-tech/pack.yaml',
          for (final id in softwareTechIds) 'software-tech/$id.yaml',
        ]),
      );
      for (final id in ['user_story', 'fr']) {
        final merged = prdCoreDocType(both, id);
        expect(
          merged.fields.map((f) => f.id),
          prdCoreDocType(prdOnly, id).fields.map((f) => f.id),
          reason: id,
        );
        expect(
          merged.fields.where((f) => f.type == FieldType.outputRef),
          isEmpty,
          reason: id,
        );
      }
    });

    test('E09, E01: every software-tech doc type is per target and no '
        'prd-core one is, so each reads specs/<target>/ with two targets', () {
      for (final docType in both.docTypes) {
        expect(
          docType.isPerTarget,
          softwareTechIds.contains(docType.id),
          reason: docType.id,
        );
      }
      expect(
        PathPattern(prdCoreDocType(both, 'implementation').path!)
            .forTarget('jaspr')
            .source,
        'specs/jaspr/f{nn}_{slug}/IMPLEMENTATION.md',
      );
      expect(
        PathPattern(prdCoreDocType(both, 'tech_stack').path!)
            .forTarget('jaspr')
            .source,
        'specs/jaspr/TECH_STACK.md',
      );
    });

    test('E02: a project that lists only prd-core gets no implementation '
        'doc type and no record doc type', () {
      expect(prdOnly.lookup('implementation'), isNull);
      expect(prdOnly.recordDocType, isNull);
      for (final id in ['user_story', 'fr']) {
        expect(
          prdCoreDocType(prdOnly, id).fields.map((f) => f.id),
          contains('status'),
          reason: id,
        );
      }
    });

    test('E07: the implementation record holds the status and the code '
        'lines, each optional, and no section', () {
      final record = both.recordDocType!;
      expect(record.id, 'implementation');
      expect(record.isPerTarget, isTrue);
      expect(record.sections, isEmpty);
      expectOwnFields(record, const [
        FieldSpec('statuses', FieldType.recordStatus, list: true),
        FieldSpec(
          'implements',
          FieldType.outputRef,
          list: true,
          pointer: PointerKind.itemExact,
        ),
      ]);
      expect(
        fieldOf(record, 'implements').description,
        contains(
          "relative to the code root of the doc's target "
          '(`.specstone/config.yaml`, else the project root)',
        ),
      );
    });

    test('E07: the other pointer fields keep their kind and requirement', () {
      expectOwnFields(prdCoreDocType(both, 'architecture'), const [
        FieldSpec(
          'covers',
          FieldType.outputRef,
          list: true,
          required: true,
          pointer: PointerKind.prefix,
        ),
      ]);
      expectOwnFields(prdCoreDocType(both, 'topic'), const [
        FieldSpec(
          'covers',
          FieldType.outputRef,
          list: true,
          required: true,
          pointer: PointerKind.prefix,
        ),
      ]);
      expectOwnFields(prdCoreDocType(both, 'tech_stack'), const [
        FieldSpec('code', FieldType.string, list: true),
      ]);
    });

    test('S1: the pack carries the one migrations entry from 1.4.0, a '
        'move_to_record step', () {
      final manifest = PackManifest.parse(
        utf8.decode(shippedPackFiles['software-tech/pack.yaml']!),
        file: 'packs/software-tech/pack.yaml',
      );
      expect(manifest.migrations, hasLength(1));
      final entry = manifest.migrations.single;
      expect(entry.from.toString(), '1.4.0');
      final step = entry.steps.single as MoveToRecord;
      expect(step.docTypes, ['user_story', 'fr']);
      expect(step.fields, ['status', 'implements']);
      expect(step.to, 'implementation');
    });
  });

  test('template_packs/write_prd_docs_from_prd_core/ship_prd_core_pack: '
      'the shipped prd-core pack is 1.7.0, so the guide text rides it', () {
    expect(shippedPackVersions()['prd-core'], '1.7.0');
  });

  test('template_packs/write_prd_docs_from_prd_core/'
      'write_shipped_writing_guides E05: the shipped feature type names the '
      'three size findings', () {
    final feature = utf8.decode(shippedPackFiles['prd-core/feature.yaml']!);
    for (final finding in [
      'chars_over_limit',
      'lines_over_limit',
      'item_over_limit',
    ]) {
      expect(feature, contains('`$finding`'));
    }
  });
}
