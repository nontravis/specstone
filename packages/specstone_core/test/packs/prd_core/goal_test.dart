import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:test/test.dart';

import '../../helpers/prd_core.dart';

const _goalTemplate =
    '### PG-01 — <short name>\n'
    '- **Serves:** PV-01\n'
    '- **Statement:** <goal statement>\n'
    '- **Metric:** <numeric target with unit>\n'
    '- **By:** <date or milestone>';

const _horizonIds = ['long_term', 'mid_term', 'short_term'];

void main() {
  late MergedDocType goal;
  setUpAll(() async {
    goal = prdCoreDocType(await resolvePrdCore(), 'goal');
  });

  test('goal loads at its path with its three sections', () {
    expect(goal.path, 'prds/GOAL.md');
    expect(goal.parent, isNull);
    expectOwnFields(goal, const []);
    expect(goal.bundle, ['implement', 'design']);
    expect(goal.bundleRefs, isTrue);
    expectSections(goal, const [
      SectionSpec('long_term', 'Long-term goals', prefixId: 'PG-'),
      SectionSpec('mid_term', 'Mid-term goals', prefixId: 'PG-'),
      SectionSpec('short_term', 'Short-term goals', prefixId: 'PG-'),
    ]);
    for (final id in _horizonIds) {
      final section = sectionOf(goal, id);
      expect(section.skeleton, isTrue, reason: id);
      expect(section.query, isNull, reason: id);
      expect(section.summary, isNull, reason: id);
      expect(section.template, _goalTemplate, reason: id);
    }
  });

  test('every section carries the metric_number entry', () {
    for (final id in _horizonIds) {
      final entries = sectionOf(goal, id).bannedPatterns!;
      expect([for (final p in entries) p.id], ['metric_number'], reason: id);
      final pattern = entries.single;
      expect(pattern.message, contains('numeric metric with unit'));
      expect(pattern.regExp.hasMatch('- **Metric:** a fast tool'), isTrue);
      expect(pattern.regExp.hasMatch('**Metric:** 3 calls'), isFalse);
    }
  });

  test('goal is titled # Project goals, caps at 400 lines, and carries the '
      'doc_citation and history entries with no word list or source', () {
    expectGuideShape(goal, title: '# Project goals');
    expectNoNasaLint(goal);
    expectSources(goal, []);
    expect(
      [for (final pattern in goal.lint.bannedPatterns!) pattern.id],
      ['doc_citation', 'history'],
    );
  });

  test('the description states the goal rules and the item shape', () {
    expectItemShape(
      goal,
      'Write one rule per `PG-*` ID, and leave mechanics to the spec docs.\n'
      'Cite a rule another doc owns by a link to the item that holds it, '
      'never restate it.',
    );
    final description = goal.description!;
    for (final rule in const [
      "next number above the doc's highest `PG-` ID",
      "moves its block to that horizon's section, its ID kept",
      'deleted from the goal doc together with its measurement',
      'leaves out `**By:**`',
      "links the goal's measurement",
    ]) {
      expect(description, contains(rule));
    }
  });
}
