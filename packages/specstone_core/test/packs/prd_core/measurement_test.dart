import 'package:specstone_core/src/index_query/bundle.dart';
import 'package:specstone_core/src/index_query/bundle_render.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/index_fixture.dart';
import '../../helpers/prd_core.dart';

const _docPath = 'measurements/grounding_cost/MEASUREMENT.md';
const _goalLink = '[Fewer resets](../../prds/PROJECT.md#pg-01--fewer-resets)';

String _measurement({
  String title = '# Grounding cost',
  String? baseline,
  String results =
      'Newest first. Met: at most 3 calls.\n\n'
      '| Date | Version | Run | Calls | Met |\n|---|---|---|---|---|\n',
  String method = '1. Run the task.\n2. Count the calls.\n',
  String openCauses = 'N/A\n',
}) =>
    '$title\n\n$_goalLink\n\n'
    '## Scope\n\n- One run per feature.\n\n'
    '## Method\n\n$method\n'
    '${baseline == null ? '' : '## Baseline\n\n$baseline\n'}'
    '## Results\n\n$results\n'
    '## Open causes\n\n$openCauses';

void main() {
  late MergedDocType measurement;
  setUpAll(() async {
    measurement = prdCoreDocType(await resolvePrdCore(), 'measurement');
  });

  test('measurement has its path, no parent, and the built-in fields '
      'alone', () {
    expect(measurement.path, 'measurements/{slug}/MEASUREMENT.md');
    expect(measurement.parent, isNull);
    expectOwnFields(measurement, const []);
  });

  test('measurement holds scope, method, baseline, results, and open '
      'causes in order, baseline alone optional', () {
    expectSections(measurement, const [
      SectionSpec('scope', 'Scope', required: true),
      SectionSpec('method', 'Method', required: true),
      SectionSpec('baseline', 'Baseline'),
      SectionSpec('results', 'Results', required: true),
      SectionSpec('open_causes', 'Open causes', required: true),
    ]);
  });

  test('scope is a summary section, results counts one summary row, and '
      'the doc is summarized for the project target', () {
    expect(sectionOf(measurement, 'scope').summary, isTrue);
    expect(sectionOf(measurement, 'results').summaryRowCount, 1);
    expect(measurement.summaryFor, ['project']);
    for (final id in ['method', 'baseline', 'open_causes']) {
      expect(sectionOf(measurement, id).summaryRowCount, isNull, reason: id);
    }
  });

  test('measurement titles with no number, carries the shared lint and '
      'pattern entries, caps at 400 lines, and cites no source', () {
    expectGuideShape(measurement, title: "# <the goal's short name>");
    expect(measurement.lint.titleNoNumber, isTrue);
    expect(measurement.lint.maxLines, 400);
    expect(
      [for (final pattern in measurement.lint.bannedPatterns!) pattern.id],
      ['doc_citation', 'history'],
    );
    expectNoNasaLint(measurement);
    expectSources(measurement, []);
  });

  test('the guide states the item shape: rule per ID, mechanics, and '
      'bound', () {
    expectItemShape(
      measurement,
      'Write one rule per ID; in a section with no IDs, one rule per item, '
      'with mechanics left to the spec docs.\n'
      'Keep a bound in the item it limits, never in the prose.',
    );
  });

  test('the guide states the log rule and the goal link', () {
    final guide = measurement.renderGuide();
    expect(
      guide,
      contains(
        'a run adds its row on top and never edits an '
        'older row',
      ),
    );
    expect(guide, contains("goal's `### PG-` heading"));
    expect(guide, contains('`**Metric:**` line links back'));
    expect(guide, contains('never restate it.'));
  });

  group('check', () {
    Future<List<String>> kindsAt(String text) async {
      final project = await writeCheckProject(extra: {'docs/$_docPath': text});
      return [
        for (final f in checkOf(project).findings)
          if (f.path == _docPath) f.kind.wire,
      ];
    }

    test('a title holding a digit is title_numbered', () async {
      expect(
        await kindsAt(_measurement(title: '# PG-01 grounding cost')),
        contains('title_numbered'),
      );
    });

    test('a measurement with no baseline has no finding', () async {
      expect(await kindsAt(_measurement()), isEmpty);
    });

    test('a baseline table beside a results table with no body row has no '
        'finding', () async {
      expect(
        await kindsAt(
          _measurement(
            baseline:
                '| Metric | Run | Value | Date | Source |\n'
                '|---|---|---|---|---|\n'
                '| Calls | 1 | 9 | 2026-11-01 | `README.md` |\n',
          ),
        ),
        isEmpty,
      );
    });

    test('a method written as prose and a results table with other '
        'columns have no finding', () async {
      expect(
        await kindsAt(
          _measurement(
            method: 'Run the task, then count the calls.\n',
            results:
                'Newest first. Met: at most 3 calls.\n\n'
                '| When | Tokens |\n|---|---|\n| 2026-11-15 | 120 |\n',
          ),
        ),
        isEmpty,
      );
    });
  });

  test('a bundle drops an open causes section that reads N/A', () async {
    final index = await indexWith({'docs/$_docPath': _measurement()});
    final text = answerContext(
      index,
      pickBundle(
        index,
        'grounding_cost',
        BundleMode.implement,
        noProject: false,
      ),
      label: 'grounding_cost',
      byCode: false,
    ).text;
    expect(text, contains('## Scope'));
    expect(text, isNot(contains('## Open causes')));
  });
}
