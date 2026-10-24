import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:specstone_core/src/templates/reference_entry.dart';
import 'package:specstone_core/src/templates/shipped_pack_files.dart';
import 'package:test/test.dart';

import '../../helpers/prd_core.dart';
import '../../helpers/software_tech.dart';

void main() {
  late MergedSet both;
  late MergedSet prdOnly;
  setUpAll(() async {
    both = await resolveSoftwareTech();
    prdOnly = await resolvePrdCore();
  });

  for (final id in ['user_story', 'fr']) {
    test('f03/us07/fr01, f03/us07/fr02/e09, f03/us07/fr03/e02: the $id layer '
        'writes the implements field and nothing else', () {
      final layer = shippedLayer(id, pack: 'software-tech');
      expect(layer.id, isNull);
      expect(layer.description, isNull);
      expect(layer.path, isNull);
      expect(layer.writesParent, isFalse);
      expect(layer.extendsId, isNull);
      expect(layer.sections, isEmpty);
      expect(layer.lint, isNull);
      expect(layer.reference, isNull);
      expect(layer.fields.map((f) => f.id), ['implements']);
    });

    test(
      'f03/us07/s4, f03/us07/fr01, f03/us07/fr01/e07: with software-tech, '
      '$id adds one optional exact implements list after the prd-core fields',
      () {
        final merged = prdCoreDocType(both, id);
        final base = prdCoreDocType(prdOnly, id);
        expect(merged.fields.map((f) => f.id), [
          ...base.fields.map((f) => f.id),
          'implements',
        ]);
        final implements = fieldOf(merged, 'implements');
        expect(implements.type, FieldType.outputRef);
        expect(implements.list, isTrue);
        expect(implements.required, isFalse);
        expect(implements.pointer, PointerKind.exact);
        expect(
          implements.description,
          allOf(contains('`path[:Symbol]`'), contains('project root')),
        );
      },
    );

    test('f03/us07/fr02/e09, f03/us07/fr03/e02: with software-tech, $id keeps '
        'the prd-core guide, path, parent, sections, lint, and sources', () {
      final merged = prdCoreDocType(both, id);
      final base = prdCoreDocType(prdOnly, id);
      expect(merged.description, base.description);
      expect(merged.path, base.path);
      expect(merged.parent, base.parent);
      expect(merged.extendsId, base.extendsId);
      expect(
        [for (final s in merged.sections) s.toJson()],
        [for (final s in base.sections) s.toJson()],
      );
      expect(merged.lint.toJson(), base.lint.toJson());
      expect(
        [for (final r in merged.reference ?? <ReferenceEntry>[]) r.toJson()],
        [for (final r in base.reference ?? <ReferenceEntry>[]) r.toJson()],
      );
      expect(merged.pack, 'prd-core');
      expect(merged.files, [...base.files, 'packs/software-tech/$id.yaml']);
    });
  }

  test('f03/us07/s5, f03/us07/fr01/e02: a project listing only prd-core has no '
      'field that points at code and no spec doc type', () {
    for (final docType in prdOnly.docTypes) {
      expect(
        docType.fields.where((f) => f.type == FieldType.outputRef),
        isEmpty,
        reason: docType.id,
      );
    }
    for (final id in softwareTechIds) {
      expect(prdOnly.lookup(id), isNull, reason: id);
    }
  });

  test('f03/us07/fr01: the pack writes no layer over nf or any other prd-core '
      'doc type', () {
    final files = shippedPackFiles.keys
        .where((k) => k.startsWith('software-tech/'))
        .toList();
    expect(
      files,
      unorderedEquals([
        'software-tech/pack.yaml',
        for (final id in softwareTechIds) 'software-tech/$id.yaml',
        'software-tech/user_story.yaml',
        'software-tech/fr.yaml',
      ]),
    );
    expect(
      prdCoreDocType(both, 'nf').fields.map((f) => f.id),
      prdCoreDocType(prdOnly, 'nf').fields.map((f) => f.id),
    );
  });
}
