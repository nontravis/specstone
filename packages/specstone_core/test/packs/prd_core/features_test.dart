import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/templates/layer_source.dart'
    show packManifestName;
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/shipped_pack_files.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart' as check;
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

  test('the description names its three sections, and the fixed title sits in '
      'the title key', () {
    expect(features.title, 'Feature map');
  });

  test('features takes its own line and character caps, every other prd-core '
      'doc type the shared ones', () async {
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
      final isFeatures = docType.id == 'features';
      expect(docType.lint.maxLines, isFeatures ? 150 : 400, reason: docType.id);
      expect(
        docType.lint.maxChars,
        isFeatures ? 10000 : 20000,
        reason: docType.id,
      );
    }
  });

  test('the Features section holds a generated block with no template', () {
    final section = sectionOf(features, 'features');
    expect(section.template, isNull);
  });

  test('a features doc at its line and character caps gives no size '
      'finding', () async {
    const path = 'prds/FEATURES.md';
    const head = '# Feature map\n\n';
    // An unstamped doc carries no approval mark, and blank-separated
    // paragraphs stay as written, so the counts stay exact.
    Future<Set<FindingKind>> sizeKinds({
      required int lines,
      required int chars,
    }) async {
      final filler = lines - 1;
      final room = chars - head.length - 1 - 2 * (filler - 1);
      final paragraphs = [
        for (var i = 0; i < filler; i++)
          'x' * (room ~/ filler + (i < room % filler ? 1 : 0)),
      ];
      final text = '$head${paragraphs.join('\n\n')}\n';
      expect(text.length, chars);
      final report = await check.checkOf(
        await check.writeCheckProject(
          extra: {'docs/$path': text},
          unstamped: {'docs/$path'},
        ),
      );
      return {
        for (final f in report.findings)
          if (f.path == path &&
              (f.kind == FindingKind.linesOverLimit ||
                  f.kind == FindingKind.charsOverLimit))
            f.kind,
      };
    }

    expect(await sizeKinds(lines: 150, chars: 10000), isEmpty);
    expect(await sizeKinds(lines: 151, chars: 10000), {
      FindingKind.linesOverLimit,
    });
    expect(await sizeKinds(lines: 150, chars: 10001), {
      FindingKind.charsOverLimit,
    });
  });
}
