import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:test/test.dart';

import '../../helpers/prd_core.dart';

const _templates = {
  'name':
      '- **Human:** <Human-readable project name>\n'
      '- **Code:** `<snake_case_code_name>`',
  'vision':
      '### PV-01 — <short name>\n'
      '> en: <one sentence of 15 words or fewer>\n'
      '- **Why:** <one sentence>\n'
      '- **Problem:** <one sentence>\n'
      '- **Audience:** <one sentence>',
  'goals':
      '### PG-01 — <short name>\n'
      '- **Serves:** PV-01\n'
      '- **Statement:** <goal statement>\n'
      '- **Metric:** <numeric target with unit>\n'
      '- **By:** <date or milestone>',
  'roles': '- `<RoleName>` — <one-line definition>',
  'out_of_scope': '- <thing the project will NOT do>',
  'glossary': '- **<Term>** — <one-line definition tying to a concrete entity>',
};

void main() {
  late MergedDocType project;
  setUpAll(() async {
    project = prdCoreDocType(await resolvePrdCore(), 'project');
  });

  test('project sits at prds/PROJECT.md with no parent, an '
      'owner field, and six sections', () {
    expect(project.path, 'prds/PROJECT.md');
    expect(project.parent, isNull);
    expectOwnFields(project, const [
      FieldSpec('owner', FieldType.string, required: true),
    ]);
    expectStatusValues(project, ['planned', 'implemented', 'deprecated']);
    expectSections(project, const [
      SectionSpec('name', 'Project name', required: true),
      SectionSpec('vision', 'Project vision', prefixId: 'PV-', required: true),
      SectionSpec('goals', 'Project goals', prefixId: 'PG-'),
      SectionSpec('roles', 'Role', required: true),
      SectionSpec('out_of_scope', 'Out-of-scope', required: true),
      SectionSpec('glossary', 'Domain glossary'),
    ]);
  });

  test('the status field gives the three meanings', () {
    expect(
      fieldOf(project, 'status').description,
      allOf(
        contains('no feature is in use'),
        contains('at least one feature is in use'),
        contains('still usable and being retired'),
      ),
    );
  });

  test('f03/us06/fr02, f03/us06/fr02/e01, f03/us06/fr03, '
      'f03/us06/fr03/e01, f03/us06/fr03/e04: titled # Project context, '
      'a short English guide, 400 lines, no NASA list', () {
    expectGuideShape(project, title: '# Project context');
    expectNoNasaLint(project);
    expectSources(project, []);
  });

  test('the templates carry the quote line and the '
      'English labels', () {
    for (final MapEntry(:key, :value) in _templates.entries) {
      expect(sectionOf(project, key).template, value, reason: key);
    }
  });

  test('project joins every bundle mode and marks roles, '
      'out_of_scope, and glossary query', () async {
    final project = prdCoreDocType(await resolvePrdCore(), 'project');
    expect(project.bundle, ['query', 'implement', 'design']);
    expect(
      [
        for (final s in project.sections)
          if (s.query == true) s.id,
      ],
      ['roles', 'out_of_scope', 'glossary'],
    );
  });

  test('Write the shipped writing guides '
      'E07: the guide states the item shape: rule per ID, bound, '
      'mechanics, and trace', () {
    expectItemShape(
      project,
      'Write one rule per `PV-*` or `PG-*` ID, '
      'and leave mechanics to the spec docs.\n'
      "Keep a goal's bound in its own `- **Metric:**` and "
      '`- **By:**` lines, and its trace in its `- **Serves:**` '
      'line.',
    );
  });

  test('the guides keep measured numbers out of PROJECT and ask for a '
      'general Problem and a linked measurement', () {
    expectItemShape(
      project,
      "PROJECT holds no measured number; a vision's evidence goes to the "
      'Baseline of the measurement of a goal that serves it.',
    );
    expect(
      sectionOf(project, 'vision').description,
      contains('with Problem in general words.'),
    );
    final goals = sectionOf(project, 'goals').description!;
    expect(
      goals,
      allOf(
        contains('pass bound and its unit, and names no other project'),
        contains('no scope item, and no baseline number'),
        contains("link the goal's measurement"),
      ),
    );
    expect(goals.split('\n').length, lessThanOrEqualTo(5));
  });

  group('metric lint', () {
    late Map<String, RegExp> lint;
    setUpAll(() {
      lint = {
        for (final p in sectionOf(project, 'goals').bannedPatterns!)
          p.id: p.regExp,
      };
    });

    test('metric_measurement hits a bare and a bullet Metric line that '
        'links no measurement', () {
      final pattern = lint['metric_measurement']!;
      for (final line in [
        '**Metric:** at most 3 tool calls',
        '- **Metric:** at most 3 tool calls',
        '- **Metric:** at most 3 calls, [bench](../benchmarks/README.md)',
        '- **Metric:** 3 calls, [bench](../x/NOTMEASUREMENT.md)',
        '- **Metric:** 3 calls, [bench](../x/MEASUREMENT.md.bak)',
        '- **Metric:** 3 calls, MEASUREMENT.md',
      ]) {
        expect(pattern.hasMatch(line), isTrue, reason: line);
      }
    });

    test('metric_measurement misses a Metric line that links a '
        'MEASUREMENT.md, with or without an anchor, and other lines', () {
      final pattern = lint['metric_measurement']!;
      for (final line in [
        '- **Metric:** 3 calls, [m](../../measurements/x/MEASUREMENT.md)',
        '**Metric:** 3 calls, [m](../../measurements/x/MEASUREMENT.md#results)',
        '- **Metric:** 3 calls, [m](MEASUREMENT.md)',
        '- **Serves:** PV-02',
      ]) {
        expect(pattern.hasMatch(line), isFalse, reason: line);
      }
    });

    test('metric_number still hits a digit-free Metric line', () {
      final pattern = lint['metric_number']!;
      expect(pattern.hasMatch('- **Metric:** a fast tool'), isTrue);
      expect(pattern.hasMatch('**Metric:** 3 calls'), isFalse);
    });
  });
}
