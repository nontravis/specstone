// Label literals are built from parts so this file holds no number label.

import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';

const _file = 'USER_STORY.md';
const _name = 'consistency_check/find_broken_pointers/report_number_labels';

/// The body line of the login feature that the tests replace.
const _line = 'Users forget passwords.';

/// The file line of [_line] in the login feature.
const _lineNumber = 13;

String f(int n) => 'F-$n';
String us(int n) => 'US-$n';
String fr(int n) => 'FR-$n';
String path(String first, String second) => '$first/$second';

Future<List<Finding>> labelFindings(Map<String, String> extra) async {
  final report = checkOf(await writeCheckProject(extra: extra));
  return [
    for (final finding in report.findings)
      if (finding.kind == FindingKind.numberLabel) finding,
  ];
}

Future<List<Finding>> labelsInFeature(String replacement) =>
    labelFindings(doc(loginFeature, _line, replacement));

void main() {
  test('$_name E01: a paragraph citing an FR by three labels gives one '
      'finding naming them as written', () async {
    final run = '${f(2)} ${us(3)} ${fr(4)}';
    final findings = await labelsInFeature('Cite $run for the rule.');
    expect(findings, hasLength(1));
    final finding = findings.single;
    expect(finding.path, loginFeature);
    expect(finding.line, _lineNumber);
    expect(finding.keys, {'label': run});
    expect(
      finding.message,
      '$run is a number label; cite the doc by its name, '
      'such as `<feature>/<story>`',
    );
    expect(finding.toJson(), containsPair('label', run));
  });

  test('$_name E02: a table cell holding a folder path whose story folder '
      'has no slug gives one finding', () async {
    final cell = path('us03', 'fr04_check_password');
    final findings = await labelsInFeature(
      '| Cite | Path |\n|---|---|\n| row | `$cell` |',
    );
    expect(findings, hasLength(1));
    expect(findings.single.line, _lineNumber + 2);
    expect(findings.single.keys, {'label': cell});
  });

  test(
    '$_name E03: a path whose every folder carries its slug gives none',
    () async {
      final findings = await labelsInFeature(
        'See prds/features/f02_document_writing/us03_approve_drafts/$_file '
        'and ../us03_approve_drafts/$_file.',
      );
      expect(findings, isEmpty);
    },
  );

  test('$_name E04: an item ID or a goal ID gives none', () async {
    final findings = await labelsInFeature(
      'INV-6, RULE-12, E05, S3, BR-01, PV-02, NFR-P03 are IDs.',
    );
    expect(findings, isEmpty);
  });

  test('$_name E05: a label in a mermaid block gives one finding', () async {
    final findings = await labelsInFeature(
      '```mermaid\nflowchart LR\n  A[get command, ${f(5)} CLI entry]\n```',
    );
    expect(findings, hasLength(1));
    expect(findings.single.line, _lineNumber + 2);
    expect(findings.single.keys, {'label': f(5)});
  });

  test('$_name E05: a label in another fenced block gives none', () async {
    final findings = await labelsInFeature(
      '```dart\nconst a = "${f(5)}";\n```\n\n~~~\n${us(1)} ${fr(2)}\n~~~',
    );
    expect(findings, isEmpty);
  });

  test('$_name E05: a label in a frontmatter value gives none', () async {
    final findings = await labelFindings(
      edit(loginFr, [
        ('verify_method: test', 'verify_method: test\nnote: ${f(5)}'),
      ]),
    );
    expect(findings, isEmpty);
  });

  test('$_name E06: a label followed by an item ID gives one finding for '
      'the label', () async {
    final findings = await labelsInFeature('${f(2)} INV-6 holds.');
    expect(findings, hasLength(1));
    expect(findings.single.keys, {'label': f(2)});
  });

  test('$_name E07: a doc outside the checked folders gets no check', () async {
    final findings = await labelFindings({
      'docs/plans/p.md': '# Plan\n\nCite ${f(1)} ${us(2)} ${fr(3)}.\n',
    });
    expect(findings, isEmpty);
  });

  test('$_name E08: a partial label that resolves to no doc gives one '
      'finding as any label does', () async {
    final findings = await labelsInFeature('Cite ${fr(9)} here.');
    expect(findings, hasLength(1));
    expect(findings.single.keys, {'label': fr(9)});
  });

  test('$_name E09: UTF-8, UTF-16, and x-FR-12 give none, a bracket, a space, '
      'or a comma before a label gives one', () async {
    final none = await labelsInFeature(
      'UTF-8 and `UTF-16` and x-${fr(12)} here.',
    );
    expect(none, isEmpty);
    final some = await labelsInFeature('Cite (${f(1)}), ${us(2)} here.');
    expect(some.map((f) => f.keys['label']), [f(1), us(2)]);
  });

  test('$_name: a placeholder label gives none', () async {
    final findings = await labelsInFeature(
      'Cite F-<nn> US-<nn> FR-<nn> or f<nn>/us<nn>/fr<nn>.',
    );
    expect(findings, isEmpty);
  });

  test(
    '$_name: a label in a link destination gives none, the link text one',
    () async {
      final findings = await labelsInFeature(
        '[${us(1)} ${fr(2)}](../${path('us01', 'fr02')}.md)',
      );
      expect(findings.map((f) => f.keys['label']), ['${us(1)} ${fr(2)}']);
    },
  );

  test('$_name: a doc-scope run reports the same finding', () async {
    final project = await writeCheckProject(
      extra: doc(loginFeature, _line, 'Cite ${f(1)}.'),
    );
    final report = checkOf(project, docPath: loginFeature);
    expect(spots(report, FindingKind.numberLabel), [
      '$loginFeature:$_lineNumber: number_label',
    ]);
  });
}
