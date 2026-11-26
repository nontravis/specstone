// Label literals are built from parts so this file holds no number label.

import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/cold_node.dart';
import '../../helpers/shipped_pins.dart';

const _file = 'USER_STORY.md';

/// The body line of the login feature that the tests replace.
const _line = 'Users forget passwords.';

/// The file line of [_line] in the login feature.
const _lineNumber = 14;

String f(int n) => 'F-$n';
String us(int n) => 'US-$n';
String fr(int n) => 'FR-$n';
String path(String first, String second) => '$first/$second';
String fo(int n) => 'FO-$n';

Future<List<Finding>> labelFindings(Map<String, String> extra) async {
  final report = await checkOf(await writeCheckProject(extra: extra));
  return [
    for (final finding in report.findings)
      if (finding.kind == FindingKind.numberLabel) finding,
  ];
}

Future<List<Finding>> labelsInFeature(String replacement) =>
    labelFindings(doc(loginFeature, _line, replacement));

Future<List<Finding>> labelsWithPrefixes(
  List<String> prefixes,
  String replacement,
) => labelFindings({
  ...doc(loginFeature, _line, replacement),
  '.specstone/config.yaml':
      '${shippedPinsConfig()}number_label_prefixes: [${prefixes.join(', ')}]\n',
});

void main() {
  useColdHostNode();

  test('a paragraph citing an FR by three labels gives one '
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

  test('a folder path followed by an item ID or scenario segment '
      'gives one finding for the path', () async {
    final cell = path(path('f03', 'us02'), 'fr04');
    final findings = await labelsInFeature('Cite ${path(cell, 'e09')} here.');

    expect(findings, hasLength(1));
    expect(findings.single.keys, {'label': cell});
  });

  test('a folder path followed by a numbered folder gives one '
      'finding for the path', () async {
    final cell = path('us03', 'fr04');
    final findings = await labelsInFeature('Cite ${path(cell, 'nf02')} here.');

    expect(findings, hasLength(1));
    expect(findings.single.keys, {'label': cell});
  });

  test('a table cell holding a folder path whose story folder '
      'has no slug, outside a code span, gives one finding', () async {
    final cell = path('us03', 'fr04_check_password');
    final findings = await labelsInFeature(
      '| Cite | Path |\n|---|---|\n| row | $cell |',
    );
    expect(findings, hasLength(1));
    expect(findings.single.line, _lineNumber + 2);
    expect(findings.single.keys, {'label': cell});
  });

  test('a path whose every folder carries its slug gives none', () async {
    final findings = await labelsInFeature(
      'See prds/features/f02_document_writing/us03_approve_drafts/$_file '
      'and ../us03_approve_drafts/$_file.',
    );
    expect(findings, isEmpty);
  });

  test('an item ID or a goal ID gives none', () async {
    final findings = await labelsInFeature(
      'INV-6, RULE-12, E05, S3, BR-01, PV-02, NFR-P03 are IDs.',
    );
    expect(findings, isEmpty);
  });

  test('a label in a mermaid block gives one finding', () async {
    final findings = await labelsInFeature(
      '```mermaid\nflowchart LR\n  A[get command, ${f(5)} CLI entry]\n```',
    );
    expect(findings, hasLength(1));
    expect(findings.single.line, _lineNumber + 2);
    expect(findings.single.keys, {'label': f(5)});
  });

  test('a label in another fenced block gives none', () async {
    final findings = await labelsInFeature(
      '```dart\nconst a = "${f(5)}";\n```\n\n~~~\n${us(1)} ${fr(2)}\n~~~',
    );
    expect(findings, isEmpty);
  });

  test('a label in a frontmatter value gives none', () async {
    final findings = await labelFindings(
      edit(loginFr, [
        ('verify_method: test', 'verify_method: test\nnote: ${f(5)}'),
      ]),
    );
    expect(findings, isEmpty);
  });

  test('a label followed by an item ID gives one finding for '
      'the label', () async {
    final findings = await labelsInFeature('${f(2)} INV-6 holds.');
    expect(findings, hasLength(1));
    expect(findings.single.keys, {'label': f(2)});
  });

  test('a doc outside the checked folders gets no check', () async {
    final findings = await labelFindings({
      'docs/plans/p.md': '# Plan\n\nCite ${f(1)} ${us(2)} ${fr(3)}.\n',
    });
    expect(findings, isEmpty);
  });

  test('UTF-8, UTF-16, and x-FR-12 give none, a bracket, a space, '
      'or a comma before a label gives one', () async {
    final noneTexts = [
      'UTF-8 and `UTF-16` and x-${fr(12)} here.',
      'Files are UTF-16 here, not UTF-8, and x-${fr(12)} stays.',
    ];
    for (final text in noneTexts) {
      expect(await labelsInFeature(text), isEmpty, reason: text);
    }
    final some = await labelsInFeature('Cite (${f(1)}), ${us(2)} here.');
    expect(some.map((f) => f.keys['label']), [f(1), us(2)]);
  });

  test(
    'a label inside a code span gives none, one outside gives one',
    () async {
      final cell = path(path('f03', 'us02'), 'fr04');
      final findings = await labelsInFeature(
        'Cite `$cell` and `x ${f(1)} y` then $cell here.',
      );
      expect(findings, hasLength(1));
      expect(findings.single.line, _lineNumber);
      expect(findings.single.keys, {'label': cell});
    },
  );

  test('plain-text story and FR labels give one finding keyed by both labels '
      'as written', () async {
    final labels = [
      '${us(7)} ${fr(8)}',
      // A partial label that resolves to no doc reads as any label does.
      fr(9),
    ];
    for (final run in labels) {
      final findings = await labelsInFeature('Cite $run for the rule.');

      expect(findings, hasLength(1), reason: run);
      expect(findings.single.line, _lineNumber);
      expect(findings.single.keys, {'label': run});
    }
  });

  test('a placeholder label gives none', () async {
    final findings = await labelsInFeature(
      'Cite F-<nn> US-<nn> FR-<nn> or f<nn>/us<nn>/fr<nn>.',
    );
    expect(findings, isEmpty);
  });

  test('a label in a link destination gives none, the link text one', () async {
    final findings = await labelsInFeature(
      '[${us(1)} ${fr(2)}](../${path('us01', 'fr02')}.md)',
    );
    expect(findings.map((f) => f.keys['label']), ['${us(1)} ${fr(2)}']);
  });

  test('a listed prefix gives one number_label', () async {
    final findings = await labelsWithPrefixes(['FO-'], 'see ${fo(12)}');

    expect(findings, hasLength(1));
    expect(findings.single.line, _lineNumber);
    expect(findings.single.keys, {'label': fo(12)});
    expect(
      findings.single.message,
      '${fo(12)} is a number label; cite the doc by its name, '
      'such as `<feature>/<story>`',
    );
  });

  test('a listed prefix run that holds a built-in label is one '
      'finding', () async {
    final run = '${fo(12)} ${us(3)}';
    final listed = await labelsWithPrefixes(['FO-'], 'see $run');
    expect(listed, hasLength(1));
    expect(listed.single.keys, {'label': run});

    final unlisted = await labelsInFeature('see $run');
    expect(unlisted, hasLength(1));
    expect(unlisted.single.keys, {'label': us(3)});
  });

  test(
    'a run keeps its listed parts when an unlisted token joins it',
    () async {
      final one = await labelsWithPrefixes(['FO-'], 'see ${fo(12)} UTF-8');
      expect(one.map((f) => f.keys['label']), [fo(12)]);

      final two = await labelsWithPrefixes([
        'FO-',
      ], 'see ${fo(1)} UTF-8 ${fo(2)} ${us(3)}');
      expect(two.map((f) => f.keys['label']), [fo(1), '${fo(2)} ${us(3)}']);
    },
  );

  test('a listed prefix run of four labels gives two findings, none loses '
      'a built-in part', () async {
    final findings = await labelsWithPrefixes([
      'FO-',
    ], 'see ${fo(1)} ${f(2)} ${us(3)} ${fr(4)}');

    expect(findings.map((f) => f.keys['label']), [
      '${fo(1)} ${f(2)} ${us(3)}',
      fr(4),
    ]);
  });

  test('an unlisted prefix gives none', () async {
    expect(await labelsInFeature('see ${fo(12)}'), isEmpty);
    expect(await labelsWithPrefixes(['UTF-'], 'see ${fo(12)}'), isEmpty);
    expect(await labelsWithPrefixes(['FO-'], 'UTF-8 stays.'), isEmpty);
  });

  test('a doc-scope run reports the same finding', () async {
    final project = await writeCheckProject(
      extra: doc(loginFeature, _line, 'Cite ${f(1)}.'),
    );
    final report = await checkOf(project, docPath: loginFeature);
    expect(spots(report, FindingKind.numberLabel), [
      '$loginFeature:$_lineNumber: number_label',
    ]);
  });
}
