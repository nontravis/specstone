import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:specstone_core/src/templates/models/merged_field.dart'
    show FieldType;
import 'package:specstone_core/src/templates/models/reference_entry.dart';
import 'package:specstone_core/src/templates/shipped_pack_files.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/cold_node.dart';
import '../../helpers/prd_core.dart';
import '../../helpers/software_tech.dart';

/// The `fr` shared lines software-tech adds on top of the prd-core guide.
const _softwareTechFrLines = {'wire_fact_home', 'mechanism_home'};

void main() {
  useColdHostNode();

  late MergedSet both;
  late MergedSet prdOnly;
  setUpAll(() async {
    both = await resolveSoftwareTech();
    prdOnly = await resolvePrdCore();
  });

  for (final id in ['user_story', 'fr']) {
    test('with software-tech, $id keeps '
        'the prd-core guide, path, parent, sections, lint, and sources', () {
      final merged = prdCoreDocType(both, id);
      final base = prdCoreDocType(prdOnly, id);
      expect(merged.description, base.description);
      expect(
        [
          for (final l in merged.sharedLines)
            if (id != 'fr' || !_softwareTechFrLines.contains(l.id))
              (l.id, l.text),
        ],
        [for (final l in base.sharedLines) (l.id, l.text)],
      );
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
      expect(merged.files, base.files);
    });
  }

  test('a project listing only prd-core has no '
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

  test('the pack writes no layer over nf or any other prd-core '
      'doc type', () {
    final files = shippedPackFiles.keys
        .where(
          (k) =>
              k.startsWith('software-tech/') &&
              !k.startsWith('software-tech/patterns/') &&
              !k.startsWith('software-tech/frozen/'),
        )
        .toList();
    expect(
      files,
      unorderedEquals([
        'software-tech/pack.yaml',
        for (final id in softwareTechIds) 'software-tech/$id.yaml',
      ]),
    );
    expect(
      prdCoreDocType(both, 'nf').fields.map((f) => f.id),
      prdCoreDocType(prdOnly, 'nf').fields.map((f) => f.id),
    );
  });
  test('a 50001-character ARCHITECTURE.md gets '
      'chars_over_limit, limit 50000, actual 50001', () async {
    // A draft takes no approval stamp, so the count stays exact.
    const draftMark = 'draft: true\n';
    const draft = '---\n$draftMark---\n\n';
    // The count leaves the draft mark out, so the file holds its length more.
    const counted = 50001 + draftMark.length - draft.length;
    // The index counts the laid-out text: a blank line under the title and
    // a final line break.
    const title = '# Login architecture\n';
    const docPath = 'docs/specs/f01_login/ARCHITECTURE.md';
    final report = await checkOf(
      await writeCheckProject(
        extra: {docPath: '$draft$title${'x' * (counted - title.length - 2)}'},
      ),
    );

    final finding = report.findings.singleWhere(
      (f) => f.kind == FindingKind.charsOverLimit,
    );
    expect(finding.path, docPath.substring('docs/'.length));
    expect(
      finding.toJson(),
      allOf(containsPair('limit', 50000), containsPair('actual', 50001)),
    );
  });
}
