import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/pattern_findings.dart';
import '../../helpers/prd_core.dart';

const _doc = 'prds/competitors/acme/COMPETITOR.md';

const _frontmatter =
    '---\nsource: https://acme.example\nchecked: 2026-11-01\nkind: direct\n'
    '---\n\n';

const _takeBullet = '- **Take:** adopt\n';
const _appliesBullet =
    '- **Applies to:** [Login](../../features/f01_login/FEATURE.md)\n';
const _fromBullet = '- **From:** Fast onboarding\n';

/// Returns a competitor doc whose one lesson holds [bullets].
String _docWith({
  String bullets = '$_takeBullet$_appliesBullet$_fromBullet',
  String title = 'Acme',
}) =>
    '$_frontmatter# $title\n\n## Summary\n\nAcme sells a sync tool.\n\n'
    '## Strengths\n\n- Fast onboarding (`references/readme.txt`).\n\n'
    '## Weaknesses\n\n- No offline mode (acme.example/pricing).\n\n'
    '## Lessons\n\n### CL-01 — Adopt the quick start\n\n$bullets';

Future<List<Finding>> _findingsOf(
  Map<String, String> extra, {
  bool unfiltered = false,
}) async {
  final report = await checkOf(await writeCheckProject(extra: extra));
  return [
    for (final f in report.findings)
      if (unfiltered || f.path.contains('competitor')) f,
  ];
}

void main() {
  late MergedDocType competitor;
  setUpAll(() async {
    competitor = prdCoreDocType(await resolvePrdCore(), 'competitor');
  });

  test('competitor loads at its folder path with no parent and its own '
      'fields', () {
    expect(competitor.path, 'prds/competitors/{slug}/COMPETITOR.md');
    expect(competitor.parent, isNull);
    expectOwnFields(competitor, const [
      FieldSpec('source', FieldType.string, required: true),
      FieldSpec('checked', FieldType.date, required: true),
      FieldSpec('version', FieldType.string),
      FieldSpec(
        'kind',
        FieldType.enumType,
        required: true,
        enumValues: ['direct', 'indirect', 'substitute'],
      ),
      FieldSpec('files', FieldType.string, list: true),
    ]);
    expectStatusValues(competitor, ['current', 'retired']);
    expect(competitor.bundle, isNull);
    expect(competitor.bundleRefs, isNull);
    for (final section in competitor.sections) {
      expect(section.query, isNull, reason: section.id);
      expect(section.summary, isNull, reason: section.id);
    }
  });

  test('competitor holds its five sections in order, lessons taking the CL '
      'prefix', () {
    expectSections(competitor, const [
      SectionSpec('summary', 'Summary', required: true),
      SectionSpec('strengths', 'Strengths', required: true),
      SectionSpec('weaknesses', 'Weaknesses', required: true),
      SectionSpec('compared_with_us', 'Compared with us'),
      SectionSpec('lessons', 'Lessons', prefixId: 'CL-', required: true),
    ]);
  });

  group('a lesson missing a bullet', () {
    const heading = 'CL-01 — Adopt the quick start';

    test('a lesson missing any of its three bullets is pattern_missing for '
        'that bullet', () async {
      final cases = {
        'take_line': '$_appliesBullet$_fromBullet',
        'applies_to_line': '$_takeBullet$_fromBullet',
        'from_line': '$_takeBullet$_appliesBullet',
      };
      for (final MapEntry(:key, :value) in cases.entries) {
        expect(
          await missingPatterns({'docs/$_doc': _docWith(bullets: value)}, _doc),
          ['$key @ $heading'],
          reason: key,
        );
      }
      expect(await missingPatterns({'docs/$_doc': _docWith()}, _doc), isEmpty);
    });

    test('an Applies to line whose link sits in a code span is '
        'pattern_missing applies_to_line', () async {
      Future<List<String>> missing(String link) => missingPatterns({
        'docs/$_doc': _docWith(
          bullets: '$_takeBullet- **Applies to:** $link\n$_fromBullet',
        ),
      }, _doc);

      expect(
        await missing('[Login](../../features/f01_login/FEATURE.md)'),
        isEmpty,
      );
      expect(await missing('`[Login](../../features/f01_login/FEATURE.md)`'), [
        'applies_to_line @ $heading',
      ]);
    });

    test('each bullet message names its guide line, which the guide '
        'prints', () {
      final entries = sectionOf(competitor, 'lessons').requiredPatterns!;
      expect(
        [for (final e in entries) e.id],
        ['take_line', 'applies_to_line', 'from_line'],
      );
      final guide = competitor.renderGuide();
      for (final entry in entries) {
        expect(entry.perSubsection, isTrue, reason: entry.id);
        expect(entry.message, contains('guide line: '), reason: entry.id);
        expect(
          guide,
          contains(entry.message.split('guide line: ').last),
          reason: entry.id,
        );
      }
    });
  });

  test('a project with no competitor doc gets no competitor finding', () async {
    expect(await _findingsOf(const {}, unfiltered: true), isEmpty);
  });

  test('a valid competitor doc gives no finding', () async {
    expect(await _findingsOf({'docs/$_doc': _docWith()}), isEmpty);
  });

  test('an md evidence file under references is untyped_doc', () async {
    const evidence = 'prds/competitors/acme/references/readme.md';
    final found = await _findingsOf({
      'docs/$_doc': _docWith(),
      'docs/$evidence': '# Saved README\n',
    });

    expect(
      [
        for (final f in found)
          if (f.kind == FindingKind.untypedDoc) f.path,
      ],
      [evidence],
    );
    expect([
      for (final f in found)
        if (f.path == _doc) f.kind,
    ], isEmpty);
  });

  test('two competitor docs each numbering a lesson CL-01 give no id '
      'finding', () async {
    const other = 'prds/competitors/globex/COMPETITOR.md';
    final found = await _findingsOf({
      'docs/$_doc': _docWith(),
      'docs/$other': _docWith(title: 'Globex'),
    });

    expect(found, isEmpty);
  });

  test('competitor cites its two sources and carries the doc-level lint '
      'every prd-core type takes', () {
    final lint = competitor.lint;
    expect(lint.titleNoNumber, isTrue);
    expect(lint.maxLines, 400);
    expect(lint.maxChars, 20000);
    expect(
      [for (final p in lint.bannedPatterns!) p.id],
      ['doc_citation', 'history'],
    );
    expect(lint.bannedWords, isNull);
    expect(lint.maxItemChars, isNull);
    expect(competitor.sharedLines.map((l) => l.id), contains('present_truth'));
  });

  test('competitor description titles the doc with its own name and states '
      'both item-shape lines', () {
    final guide = competitor.renderGuide();
    final shape = guide.indexOf('Write one rule per ID');
    for (final id in [
      'one_rule_per_item',
      'cite_at_item_end',
      'one_example',
      'condition_first',
      'cite_by_link',
    ]) {
      final line = competitor.sharedLines.singleWhere((l) => l.id == id);
      expect(guide.indexOf(line.text), greaterThan(shape), reason: id);
    }
  });
}
