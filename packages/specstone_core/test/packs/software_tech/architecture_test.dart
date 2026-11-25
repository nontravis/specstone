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
    expect(
      lines.singleWhere((l) => l.contains('Deployment view')),
      allOf(contains('`subgraph`'), contains('protocol'), contains('no Why')),
    );
    expect(
      lines.singleWhere((l) => l.contains('Sequence view')),
      contains('`sequenceDiagram`'),
    );
    expect(
      lines.join('\n'),
      allOf(
        contains('`title:`'),
        contains('12 boxes or 12 messages'),
        contains('`classDef`'),
        contains('`stateDiagram-v2`'),
      ),
    );
  });

  test(
    'deployment leaves the links between runtime nodes to the deployment view',
    () async {
      final set = await resolveSoftwareTech();

      for (final id in ['architecture', 'project_architecture']) {
        expect(
          sectionOf(prdCoreDocType(set, id), 'deployment').description,
          allOf(
            contains('Write no link between runtime nodes'),
            contains('the Deployment view draws them'),
          ),
          reason: id,
        );
      }
    },
  );

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
      expect(
        lines.first,
        allOf(contains('in the order below'), contains('any view may repeat')),
        reason: id,
      );
      expect(lines.join('\n'), contains('`feature:` mention'), reason: id);
    }
  });

  test('the technical diagram description shows the box label form and the quote escape', () async {
    final set = await resolveSoftwareTech();

    for (final id in ['architecture', 'project_architecture']) {
      expect(
        sectionOf(prdCoreDocType(set, id), 'technical_diagram').description,
        allOf(
          contains('Type every box as `Name (technology)`'),
          contains('`A["Formatter (Dart)"]`'),
          contains('`#quot;`'),
        ),
        reason: id,
      );
    }
  });

  test('the section descriptions state no number a lint key holds', () {
    expect(
      sectionOf(architecture, 'components').description,
      isNot(contains('one sentence')),
    );
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

  test('architecture and project_architecture descriptions forbid design '
      'rationale', () async {
    final set = await resolveSoftwareTech();

    for (final id in ['architecture', 'project_architecture']) {
      expect(
        prdCoreDocType(set, id).description?.split('\n'),
        contains(
          "Write no design rationale here; a decision's why goes in its "
          '`decision` doc, linked from here.',
        ),
        reason: id,
      );
    }
  });

  test('the technical diagram description sends a flow explanation to its FR or a decision doc', () async {
    final set = await resolveSoftwareTech();

    for (final id in ['architecture', 'project_architecture']) {
      final text = sectionOf(
        prdCoreDocType(set, id),
        'technical_diagram',
      ).description!;
      expect(
        text,
        contains(
          "put a flow's explanation in the FR it serves when users see it, "
          'else in a `decision` doc',
        ),
        reason: id,
      );
      expect(text, isNot(contains('Zoom-in')), reason: id);
    }
  });

  test('components states a role never an FR behavior and a row for every diagram box', () {
    final text = sectionOf(architecture, 'components').description!;

    expect(
      text,
      allOf(
        contains('every box of the Component view is a row'),
        contains(
          'Write a role in Responsibility, never a behavior an FR states',
        ),
        contains('Write no line but a table line'),
      ),
    );
    expect(text.split('\n'), hasLength(lessThanOrEqualTo(5)));
  });

  test('deployment holds one row per component with a one-clause Why and no decision rationale', () async {
    final set = await resolveSoftwareTech();

    for (final id in ['architecture', 'project_architecture']) {
      expect(
        sectionOf(prdCoreDocType(set, id), 'deployment').description,
        allOf(
          contains('one row per component'),
          contains('a one-clause Why on each row'),
          contains('why it runs there, no design decision'),
        ),
        reason: id,
      );
    }
  });

  test('the architecture description says a feature writes the doc for a container, a store, or a flow of three components', () {
    expect(
      architecture.description,
      contains(
        'Write this doc only when the feature adds or changes a container or '
        'a store, or when a flow crosses three or more components.',
      ),
    );
  });

  test('the architecture description says a SECURITY may cite it by a section link', () {
    expect(
      architecture.description,
      contains(
        "A feature's SECURITY may cite this doc by a section link, such as "
        '`[architecture:rendering](ARCHITECTURE.md#technical-diagram)`.',
      ),
    );
  });

  test('components names four columns and no file list', () {
    final components = sectionOf(architecture, 'components');

    expect(
      components.description,
      allOf(
        contains('the columns Component, Responsibility, Tech, Owns.'),
        isNot(contains('Code path')),
        contains('Write no file, folder, or command list'),
      ),
    );
  });
}
