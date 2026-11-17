import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/pattern_entry.dart';
import 'package:test/test.dart';

import '../../helpers/prd_core.dart';

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
    }
  });

  test('every section carries the metric_number entry', () {
    for (final id in _horizonIds) {
      final entries = sectionOf(goal, id).bannedPatterns!;
      expect([for (final p in entries) p.id], ['metric_number'], reason: id);
      final pattern = entries.single;
      expect(pattern.scope, PatternScope.all, reason: id);
      expect(pattern.regExp.hasMatch('- **Metric:** a fast tool'), isTrue);
      expect(pattern.regExp.hasMatch('**Metric:** 3 calls'), isFalse);
    }
  });
}
