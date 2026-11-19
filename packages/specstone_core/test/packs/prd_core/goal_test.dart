import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/document_writing/new_doc.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/pattern_entry.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart' as check;
import '../../helpers/prd_core.dart';
import '../../helpers/write_fixture.dart' as write;

const _horizonIds = ['long_term', 'mid_term', 'short_term'];

const _citeFragment = 'by a link to its item, never restate it';

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

  test('the guide prints the goal rules, then the shared cite line', () {
    final guide = goal.renderGuide();
    final cite = guide.indexOf(_citeFragment);
    for (final rule in [
      'A goal that changes horizon moves its block',
      'A goal met or dropped is deleted',
    ]) {
      expect(guide.indexOf(rule), allOf(isNonNegative, lessThan(cite)));
    }
    expect(goal.description, isNot(contains(_citeFragment)));
    expect(goal.sharedLines.map((l) => l.id), contains('cite_by_link'));
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

  group('a project holding the shipped goal doc', () {
    // One goal block: heading, blank, Serves, text, blank.
    String block(String id, String serves) =>
        '### $id — Goal $id\n\n**Serves:** $serves\nText.\n\n';

    Map<String, String> goals({
      String long = '',
      String mid = '',
      String short = '',
    }) {
      final text =
          '# Project goals\n\n## Long-term goals\n\n$long'
          '## Mid-term goals\n\n$mid## Short-term goals\n\n$short';
      return {'docs/${check.goalDoc}': '${text.trimRight()}\n'};
    }

    Future<List<Finding>> findingsOf(
      Map<String, String> extra, {
      FindingKind? kind,
      Set<String> without = const {},
    }) async {
      final report = await check.checkOf(
        await check.writeCheckProject(extra: extra, without: without),
      );
      return [
        for (final f in report.findings)
          if (kind == null || f.kind == kind) f,
      ];
    }

    test('new on the shipped type with no text writes the three headers and '
        'no goal', () async {
      final root = await write.writeWriteProject();

      write.writeIn(root, (s) => answerNew(s, docTypeId: 'goal'));

      final text = write.readDoc(root, check.goalDoc);
      expect(
        text,
        '---\ndraft: true\n---\n\n# goal\n\n## Long-term goals\n\n'
        '## Mid-term goals\n\n## Short-term goals\n',
      );
    });

    test(
      'a goal doc whose three sections hold no goal gives no finding',
      () async {
        final found = await findingsOf(goals());

        expect(found.where((f) => f.path == check.goalDoc), isEmpty);
      },
    );

    test('a goal moved to another horizon keeps its ID, takes that horizon '
        'Serves rule, and leaves each goals key as it is', () async {
      final keys = check.edit(check.loginFeature, [
        ('  - PG-01\n', '  - PG-01\n  - PG-02\n'),
      ]);
      final before = await findingsOf({
        ...keys,
        ...goals(long: block('PG-01', 'PV-01'), mid: block('PG-02', 'PG-01')),
      });
      expect(
        before.where(
          (f) =>
              f.kind == FindingKind.goalServesHorizon ||
              f.kind == FindingKind.visionGoalUnresolved,
        ),
        isEmpty,
      );

      final after = await findingsOf({
        ...keys,
        ...goals(long: block('PG-01', 'PV-01') + block('PG-02', 'PG-01')),
      });

      expect(
        [
          for (final f in after)
            if (f.kind == FindingKind.goalServesHorizon)
              (f.toJson()['goal'], f.toJson()['id']),
        ],
        [('PG-02', 'PG-01')],
      );
      expect(
        after.where((f) => f.kind == FindingKind.visionGoalUnresolved),
        isEmpty,
      );
    });

    test('a lettered goal after PG-07 names PG-08 whichever section it sits '
        'in', () async {
      final seven = block('PG-07', 'PV-01');
      final lettered = block('PG-01a', 'PV-01');
      final sections = [
        goals(long: lettered, mid: seven),
        goals(mid: lettered, short: seven),
        goals(short: lettered, long: seven),
      ];

      for (final extra in sections) {
        final found = await findingsOf(extra, kind: FindingKind.itemIdLettered);
        expect(
          [for (final f in found) (f.toJson()['id'], f.toJson()['next'])],
          [('PG-01a', 'PG-08')],
        );
      }
    });

    test('a goal deleted with its measurement leaves its Serves line and '
        'goals key unresolved and its heading link anchor missing', () async {
      final extra = {
        ...goals(mid: block('PG-02', 'PG-01')),
        ...check.edit(check.loginFeature, [
          (
            'Users forget passwords.',
            'See [Fewer resets](../../GOAL.md#pg-01--fewer-resets).',
          ),
        ]),
      };

      final found = await findingsOf(
        extra,
        without: {'docs/${check.measurementDoc}'},
      );

      expect(
        [
          for (final f in found)
            if (f.kind == FindingKind.visionGoalUnresolved)
              (f.path, f.toJson()['id']),
        ],
        unorderedEquals([
          (check.goalDoc, 'PG-01'),
          (check.loginFeature, 'PG-01'),
          (check.loginStory, 'PG-01'),
        ]),
      );
      expect(
        [
          for (final f in found)
            if (f.kind == FindingKind.linkAnchorMissing) f.path,
        ],
        [check.loginFeature],
      );
    });

    test('a long-term goal with no By line gives no finding', () async {
      final found = await findingsOf(
        goals(
          long:
              '### PG-01 — Fewer resets\n\n**Serves:** PV-01\n'
              'Halve the password resets.\n\n',
        ),
      );

      expect(found.where((f) => f.path == check.goalDoc), isEmpty);
    });
  });
}
