import 'package:specstone_core/src/index_query/bundle.dart';
import 'package:specstone_core/src/index_query/bundle_render.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/index_fixture.dart';
import '../../helpers/pattern_findings.dart';
import '../../helpers/prd_core.dart';

const _docPath = 'measurements/grounding_cost/MEASUREMENT.md';

String _measurement({
  String title = '# Grounding cost',
  String? baseline,
  String results =
      'Newest first. Met: at most 3 calls.\n\n'
      '| Date | Version | Run | Calls | Met |\n|---|---|---|---|---|\n',
  String method = '1. Run the task.\n2. Count the calls.\n',
  String openCauses = 'N/A\n',
}) =>
    '$title\n\n$measurementHeadLink\n\n'
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
      'the doc is summarized for the project and goal targets', () {
    expect(sectionOf(measurement, 'scope').summary, isTrue);
    expect(sectionOf(measurement, 'results').summaryRowCount, 1);
    expect(measurement.summaryFor, ['project', 'goal']);
    for (final id in ['method', 'baseline', 'open_causes']) {
      expect(sectionOf(measurement, id).summaryRowCount, isNull, reason: id);
    }
  });

  test('measurement titles with no number', () {
    expect(measurement.lint.titleNoNumber, isTrue);
  });

  test('the guide prints the log rule and the goal link, then the shared '
      'cite line', () {
    expect(measurement.sharedLines.map((l) => l.id), contains('cite_by_link'));
  });

  group('check', () {
    Future<List<String>> kindsAt(String text) async {
      final project = await writeCheckProject(extra: {'docs/$_docPath': text});
      return [
        for (final f in (await checkOf(project)).findings)
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

    test('a results table with other columns has no finding', () async {
      expect(
        await kindsAt(
          _measurement(
            results:
                'Newest first. Met: at most 3 calls.\n\n'
                '| When | Tokens |\n|---|---|\n| 2026-11-15 | 120 |\n',
          ),
        ),
        isEmpty,
      );
    });
  });

  group('the log rule', () {
    Future<List<String>> flagged(String pattern, String text) =>
        bannedLines({'docs/$_docPath': text}, _docPath, pattern);

    const historyLine = 'Previously a run took 9 calls.';

    test('history prose in Results is no finding, and the same prose in '
        'Scope, Method, Baseline, or Open causes is history', () async {
      expect(
        await flagged(
          'history',
          _measurement(
            results:
                'Newest first. Met: at most 3 calls.\n\n'
                '| Date | Version | Run | Calls | Met |\n'
                '|---|---|---|---|---|\n'
                '| 2026-11-15 | 1.3.0 | formerly run 2, no longer 9 | 3 | yes '
                '|\n$historyLine\n',
          ),
        ),
        isEmpty,
      );

      final text = _measurement(
        baseline:
            '| Metric | Run | Value | Date | Source |\n|---|---|---|---|---|\n'
            '| Calls | 1 | 9 | 2026-11-01 | formerly 12 |\n',
        openCauses: '$historyLine\n',
      ).replaceFirst('- One run per feature.', '- Formerly one run.');
      expect(await flagged('history', text), [
        '- Formerly one run.',
        '| Calls | 1 | 9 | 2026-11-01 | formerly 12 |',
        historyLine,
      ]);
      expect(
        await flagged(
          'history',
          _measurement(method: '1. Previously run the task.\n'),
        ),
        ['1. Previously run the task.'],
      );
    });

    test('a Method line not opening with a number is method_numbered, and a '
        'numbered step, a wrapped line, a blank line, the header, and a '
        'fenced line are not', () async {
      expect(
        await flagged(
          'method_numbered',
          _measurement(
            method:
                '1. Run the task.\n'
                '   then count the calls.\n'
                '2. Record the result:\n\n'
                '   - the count\n\n'
                '```sh\nspecstone check\n```\n'
                '10. Close the run.\n',
          ),
        ),
        isEmpty,
      );
      const loose = [
        'Run the task, then count the calls.',
        '- Run the task.',
        '`specstone check`, then count.',
        '| Step | Action |',
        '1.Run the task.',
      ];
      expect(
        await flagged(
          'method_numbered',
          _measurement(method: '1. Run the task.\n${loose.join('\n')}\n'),
        ),
        loose,
      );
    });

    test('method_numbered reads the Method section alone', () async {
      expect(
        await flagged(
          'method_numbered',
          _measurement(
            openCauses: 'The cache missed.\n',
            baseline:
                '| Metric | Run | Value | Date | Source |\n'
                '|---|---|---|---|---|\n| Calls | 1 | 9 | 2026-11-01 | a |\n',
          ),
        ),
        isEmpty,
      );
    });

    test('history sits on four sections and not on Results, and the doc '
        'level keeps doc_citation alone', () {
      expect(
        [for (final p in measurement.lint.bannedPatterns!) p.id],
        ['doc_citation'],
      );
      for (final section in measurement.sections) {
        expect(
          [
            for (final p in section.bannedPatterns ?? const <PatternEntry>[])
              p.id,
          ],
          switch (section.id) {
            'results' => isEmpty,
            'method' => ['history', 'method_numbered'],
            _ => ['history'],
          },
          reason: section.id,
        );
      }
    });

    test('the guide prints no present_truth line, and the log rule stays', () {
      expect(
        measurement.sharedLines.map((l) => l.id),
        isNot(contains('present_truth')),
      );
    });
  });

  test('a bundle drops an open causes section that reads N/A', () async {
    final index = await indexWith({'docs/$_docPath': _measurement()});
    final text = answerContext(
      index,
      pickBundle(
        index,
        ['grounding_cost'],
        BundleMode.implement,
        noProject: false,
      ),
      targets: ['grounding_cost'],
    ).text;
    expect(text, contains('## Scope'));
    expect(text, isNot(contains('## Open causes')));
  });
}
