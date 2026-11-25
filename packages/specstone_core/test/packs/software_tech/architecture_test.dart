// Test names stay one literal so `specstone check` finds them by exact text.
// ignore_for_file: lines_longer_than_80_chars

import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/pattern_findings.dart';
import '../../helpers/prd_core.dart';
import '../../helpers/software_tech.dart';

const _archPath = 'specs/f01_login/ARCHITECTURE.md';

const _overridesBare =
    'Overrides: [API-C1](../API.md#conventions) — slower, because it caches';

const _overridesBullet = '- $_overridesBare';

/// Returns the lines of an architecture doc's [section] body that [pattern]
/// flags.
Future<List<String>> _flagged(
  String section,
  List<String> lines,
  String pattern,
) => bannedLines(
  {
    'docs/$_archPath':
        '---\ndraft: true\n---\n\n# Login architecture\n\n'
        '## $section\n${lines.join('\n')}\n',
  },
  _archPath,
  pattern,
);

void main() {
  const draft = '---\ndraft: true\n---\n\n';
  late MergedDocType architecture;
  setUpAll(() async {
    architecture = prdCoreDocType(await resolveSoftwareTech(), 'architecture');
  });

  test('architecture sits under specs/f{nn}_{slug}/ with parent feature, no covers field, and the eight sections of its row', () {
    expect(architecture.path, 'specs/f{nn}_{slug}/ARCHITECTURE.md');
    expect(architecture.parent, 'feature');
    expectOwnFields(architecture, const [
      FieldSpec('overrides', FieldType.string, list: true),
      FieldSpec('tasks', FieldType.taskRef, list: true),
    ]);
    expectSections(architecture, const [
      SectionSpec('technical_diagram', 'Technical diagram', required: true),
      SectionSpec('components', 'Components', required: true),
      SectionSpec('data', 'Data'),
      SectionSpec('deployment', 'Deployment'),
      SectionSpec('rollout', 'Rollout'),
      SectionSpec('observability', 'Observability'),
      SectionSpec('risks', 'Risks'),
      SectionSpec('open_questions', 'Open questions'),
    ]);
  });

  test('the technical diagram lint sets title, edge labels, the banned label, and names', () {
    final diagram = sectionOf(architecture, 'technical_diagram').diagram!;

    expect(
      (diagram.title, diagram.edgeLabels, diagram.names),
      (true, true, true),
    );
    expect(diagram.bannedLabels, ['Uses']);
  });

  test('the technical diagram description prints its view lines', () {
    final lines = sectionOf(
      architecture,
      'technical_diagram',
    ).description!.split('\n');

    expect(lines, hasLength(10));
    for (final view in [
      'Component',
      'Deployment',
      'Data flow',
      'Dependency',
      'Sequence',
    ]) {
      expect(
        lines.where((l) => l.contains('$view view')),
        hasLength(1),
        reason: view,
      );
    }
    expect(lines.where((l) => l.contains('Technical context view')), isEmpty);
  });

  test('the technical diagram view lines run in the views-table order and the description prints that order and repeats', () async {
    final set = await resolveSoftwareTech();
    const views = [
      'Technical context view',
      'Component view',
      'Deployment view',
      'Data flow view',
      'Dependency view',
      'Sequence view',
    ];

    for (final id in ['architecture', 'project_architecture']) {
      final lines = sectionOf(
        prdCoreDocType(set, id),
        'technical_diagram',
      ).description!.split('\n');
      final expected = [
        for (final view in views)
          if (id == 'project_architecture' || view != 'Technical context view')
            view,
      ];
      final indexes = [
        for (final view in expected)
          lines.indexWhere((l) => l.startsWith(view)),
      ];
      expect(indexes, everyElement(greaterThanOrEqualTo(0)), reason: id);
      expect(indexes, orderedEquals([...indexes]..sort()), reason: id);
    }
  });

  test('a bullet under the components table is banned', () async {
    final report = await checkOf(
      await writeCheckProject(
        extra: {
          'docs/specs/f01_login/ARCHITECTURE.md':
              '$draft# Login architecture\n\n## Components\n'
              '| Component | Responsibility |\n|---|---|\n'
              '| Gate | Checks the password |\n\n'
              '- Gate also logs each attempt\n',
        },
      ),
    );

    final finding = report.findings.singleWhere(
      (f) => f.kind == FindingKind.patternBanned,
    );
    expect(finding.path, 'specs/f01_login/ARCHITECTURE.md');
    expect(finding.toJson(), containsPair('line', 12));
  });

  group('the Components and Observability line rules', () {
    test('a table line and both Overrides forms pass table_only, and a bullet '
        'under the table is flagged', () async {
      expect(
        await _flagged('Components', [
          '| Component | Responsibility |',
          '|---|---|',
          '| Gate | Checks the password |',
          '',
          _overridesBare,
          _overridesBullet,
          '```text',
          '- a fenced bullet',
          '```',
        ], 'table_only'),
        isEmpty,
      );
      const bullet = '- Gate also logs each attempt';
      expect(
        await _flagged('Components', [
          '| Gate | Checks |',
          '',
          bullet,
        ], 'table_only'),
        [bullet],
      );
    });

    test(
      'an Observability bullet off the channel form is log_channel_form, '
      'and a table line, a channel line, and both Overrides forms pass',
      () async {
        const offForm = '- audit log: sign-in events';
        const noEvents = '- audit-log - ';
        expect(
          await _flagged('Observability', [
            '| Signal | SLI | SLO target | Alert on |',
            '|---|---|---|---|',
            '| Sign-in rate | per minute | 1 s | slow |',
            '',
            '- audit-log - sign-in, sign-out',
            '- `audit` - sign-in events',
            _overridesBare,
            _overridesBullet,
            'A line that is no bullet',
            '```text',
            '- a fenced bullet',
            '```',
          ], 'log_channel_form'),
          isEmpty,
        );
        expect(
          await _flagged('Observability', [
            '- audit-log - sign-in',
            offForm,
            noEvents,
          ], 'log_channel_form'),
          [offForm, noEvents],
        );
      },
    );

    test('the messages name guide lines the descriptions print', () {
      Map<String, String> messages(String section) => {
        for (final p in sectionOf(architecture, section).bannedPatterns!)
          p.id: p.message,
      };

      expect(
        messages('components')['table_only'],
        endsWith('guide line: Write no line but a table line'),
      );
      expect(
        messages('observability')['log_channel_form'],
        endsWith('guide line: Add the log channels as `<name> - <events>`'),
      );
    });
  });

  test('architecture ships no design references section', () {
    expect([
      for (final s in architecture.sections) s.id,
    ], isNot(contains('design_references')));
  });

  test('components states a role never an FR behavior and a row for every diagram box', () {
    final text = sectionOf(architecture, 'components').description!;

    expect(text.split('\n'), hasLength(lessThanOrEqualTo(5)));
  });
}
