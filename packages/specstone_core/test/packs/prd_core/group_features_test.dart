import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart' as check;
import '../../helpers/prd_core.dart';

/// The project-layer files that put the feature tree under [levels] group
/// folders, keyed by file name under `.specstone/templates/`.
Map<String, String> _groupedLayers(int levels) {
  final groups = '{slug}/' * levels;
  final story = 'prds/features/${groups}f{nn}_{slug}/us{nn}_{slug}';
  return {
    'feature.yaml': 'path: prds/features/${groups}f{nn}_{slug}/FEATURE.md\n',
    'user_story.yaml': 'path: $story/USER_STORY.md\n',
    'fr.yaml': 'path: $story/fr{nn}_{slug}.md\n',
    'nf.yaml': 'path: $story/nf{nn}_{slug}.md\n',
  };
}

Future<MergedDocType> _groupFeatures({int levels = 0}) async => prdCoreDocType(
  await resolvePrdCore(templates: levels == 0 ? {} : _groupedLayers(levels)),
  'group_features',
);

void main() {
  late MergedDocType groupFeatures;
  setUpAll(() async {
    groupFeatures = await _groupFeatures();
  });

  test('group_features carries one required Features section, the group '
      'catalog generator, and the shared caps', () {
    expect(groupFeatures.path, isNull);
    expect(groupFeatures.parent, isNull);
    expectOwnFields(groupFeatures, const []);
    expectStatusValues(groupFeatures, ['planned', 'implemented', 'deprecated']);
    expectSections(groupFeatures, const [
      SectionSpec('features', 'Features', required: true),
    ]);
    expect(groupFeatures.listedGenerators, ['group_feature_catalog']);
    expect(groupFeatures.lint.maxLines, 400);
    expect(groupFeatures.lint.maxChars, 20000);
    expect(groupFeatures.bundle, isNull);
    expect(groupFeatures.bundleRefs, isNull);
    expect(groupFeatures.summaryFor, isNull);
  });

  test('group_features titles from its folder name, so a title with a digit '
      'holds no titleNumbered finding where the features doc would', () async {
    const groupPath = 'prds/features/form2/FEATURES.md';
    const mapPath = 'prds/FEATURES.md';
    final report = await check.checkOf(
      await check.writeCheckProject(
        extra: {
          for (final MapEntry(:key, :value) in _groupedLayers(1).entries)
            '.specstone/templates/$key': value,
          'docs/$groupPath': '# form2 features\n\n## Features\n',
          'docs/$mapPath': '# Feature map 2\n\n## Features\n',
        },
        unstamped: {'docs/$groupPath', 'docs/$mapPath'},
      ),
    );

    Set<FindingKind> kindsAt(String path) => {
      for (final finding in report.findings)
        if (finding.path == path) finding.kind,
    };
    expect(groupFeatures.lint.titleNoNumber, isFalse);
    expect(kindsAt(mapPath), contains(FindingKind.titleNumbered));
    expect(kindsAt(groupPath), isNot(contains(FindingKind.titleNumbered)));
  });

  test('group_features derives one FEATURES.md path per group level and none '
      'when ungrouped', () async {
    expect((await _groupFeatures(levels: 1)).paths, [
      'prds/features/{slug}/FEATURES.md',
    ]);
    expect((await _groupFeatures(levels: 2)).paths, [
      'prds/features/{slug}/FEATURES.md',
      'prds/features/{slug}/{slug}/FEATURES.md',
    ]);
    expect(groupFeatures.paths, isEmpty);
  });

  test('a group doc filled to the shared caps has no size finding, and one '
      'line or character more has one', () async {
    const path = 'prds/features/kitchen/FEATURES.md';
    const head = '# kitchen features\n\n';
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
          extra: {
            for (final MapEntry(:key, :value) in _groupedLayers(1).entries)
              '.specstone/templates/$key': value,
            'docs/$path': text,
          },
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

    expect(await sizeKinds(lines: 400, chars: 20000), isEmpty);
    expect(await sizeKinds(lines: 401, chars: 20000), {
      FindingKind.linesOverLimit,
    });
    expect(await sizeKinds(lines: 400, chars: 20001), {
      FindingKind.charsOverLimit,
    });
  });

  test('group_features sets no title key and its description titles the doc '
      'by its group folder name', () {
    expect(groupFeatures.title, isNull);
    expect(
      groupFeatures.description,
      contains('Title it `# <group folder name> features`'),
    );
  });

  test('group_features states one rule per item with no IDs and no '
      'one-rule-per-ID line', () async {
    final lines = groupFeatures.description!.split('\n');
    expect(
      lines.where((l) => l.startsWith('Write one rule per item')),
      hasLength(1),
    );
    expect(lines.where((l) => l.contains('one rule per ID')), isEmpty);
    final other = prdCoreDocType(await resolvePrdCore(), 'feature');
    expect(other.description, contains('one rule per ID'));
  });

  test('the group Features section holds a generated block with no '
      'template', () {
    final section = sectionOf(groupFeatures, 'features');
    expect(section.template, isNull);
    expect(section.description, contains('generated block'));
    expect(section.description, contains('never written by hand'));
  });
}
