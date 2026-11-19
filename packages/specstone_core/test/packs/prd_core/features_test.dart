import 'package:specstone_core/src/templates/layer_source.dart'
    show packManifestName;
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/shipped_pack_files.dart';
import 'package:test/test.dart';

import '../../helpers/prd_core.dart';

const prdCorePack = 'prd-core';

void main() {
  late MergedDocType features;
  setUpAll(() async {
    features = prdCoreDocType(await resolvePrdCore(), 'features');
  });

  test('features sits at prds/FEATURES.md with no parent, no '
      'own field, and three sections', () {
    expect(features.path, 'prds/FEATURES.md');
    expect(features.parent, isNull);
    expectOwnFields(features, const []);
    expectStatusValues(features, ['planned', 'implemented', 'deprecated']);
    expectSections(features, const [
      SectionSpec('features', 'Features', required: true),
      SectionSpec('diagram', 'System interaction diagram', required: true),
      SectionSpec('systems', 'Systems', required: true),
    ]);
  });

  test('features lists the feature_catalog generator', () {
    expect(features.listedGenerators, ['feature_catalog']);
  });

  test('the description gives the fixed title and names its three '
      'sections', () {
    expect(features.description, contains('`# Feature map`'));
    expect(features.description, contains('feature catalog'));
    expect(features.description, contains('diagram'));
    expect(features.description, contains('Systems table'));
  });

  test('the description states no number a lint key holds', () {
    expect(features.description, isNot(contains('three sections')));
  });

  test('every prd-core doc type sets the shared 400-line and 20000-char '
      'lint caps', () async {
    final set = await resolvePrdCore();
    final shipped = [
      for (final key in shippedPackFiles.keys)
        if (key.split('/') case [prdCorePack, final file]
            when file != packManifestName && file.endsWith('.yaml'))
          key,
    ];
    expect(shipped, isNotEmpty);
    expect(set.docTypes, hasLength(shipped.length));
    for (final docType in set.docTypes) {
      expect(docType.lint.maxLines, 400, reason: docType.id);
      expect(docType.lint.maxChars, 20000, reason: docType.id);
    }
  });

  test('the Features section holds a generated block with no template', () {
    final section = sectionOf(features, 'features');
    expect(section.description, contains('generated block'));
    expect(section.description, contains('never written by hand'));
    expect(section.template, isNull);
  });
}
