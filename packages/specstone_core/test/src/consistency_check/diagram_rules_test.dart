// The expected texts are plan literals kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'package:specstone_core/src/consistency_check/check_report.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';

const Set<FindingKind> _diagramKinds = {
  FindingKind.diagramTitleMissing,
  FindingKind.diagramEdgeUnlabeled,
  FindingKind.diagramLabelUnquoted,
};

/// The architecture doc with [block] as its component diagram.
///
/// The block's opening fence sits on line 10 and its first line on line 11.
String _diagramDoc(String block) =>
    '---\ncovers:\n  - app/lib/\n---\n\n# Login architecture\n\n'
    '## Component diagram\n\n$block\n\n## Components\n\n'
    '| Component | Responsibility |\n|---|---|\n| Sign-in page | Takes the form |\n';

/// The feature doc with [block] as its feature flow, a section whose guide
/// sets the quoting rule alone.
///
/// The block's opening fence sits on line 28 and its first line on line 29.
String _flowDoc(String block) =>
    '---\nvision:\n  - PV-01\ngoals:\n  - PG-01\n---\n\n# Login\n\n'
    '## Problem\n\nUsers forget passwords.\n\n## Benefit hypothesis\n\n'
    'Fewer resets.\n\n## Success measures\n\nResets per week.\n\n'
    '## Current alternatives\n\nEmail links.\n\n## Feature flow\n\n'
    '$block\n\n## Out-of-scope\n\n- Social sign-in — not planned\n';

Future<CheckReport> _checkArchitecture(String block) =>
    _check(_diagramDoc(block), loginArchitecture);

Future<CheckReport> _checkFlow(String block) =>
    _check(_flowDoc(block), loginFeature);

Future<CheckReport> _check(String doc, String docPath) async => checkOf(
  await writeCheckProject(
    extra: {'docs/$docPath': doc},
    unstamped: {'docs/$docPath'},
  ),
);

/// Returns `<line> <kind> <keys>` per diagram finding, findings order.
List<String> _found(CheckReport report) => [
  for (final f in report.findings.where((f) => _diagramKinds.contains(f.kind)))
    '${f.line} ${f.kind.wire} ${f.keys.isEmpty ? '' : f.keys.values.join(' ')}'
        .trimRight(),
];

void main() {
  test('a titled block whose edges carry labels gives no finding', () async {
    final report = await _checkArchitecture(
      '```mermaid\n---\ntitle: Sign-in\n---\nflowchart TD\n'
      'A[CLI] -->|reads, SQLite| B[Index]\n```',
    );

    expect(_found(report), isEmpty);
  });

  test('an edge with no label is one finding at its own line', () async {
    final report = await _checkArchitecture(
      '```mermaid\nflowchart TD\nA --> B\n```',
    );

    expect(
      _found(report).singleWhere((f) => f.contains('edge_unlabeled')),
      '12 diagram_edge_unlabeled A --> B',
    );
  });

  test('an edge labeled with a banned word is an unlabeled edge', () async {
    final report = await _checkArchitecture(
      '```mermaid\nflowchart TD\nA -- Uses --> B\n```',
    );

    expect(
      _found(report).singleWhere((f) => f.contains('edge_unlabeled')),
      '12 diagram_edge_unlabeled A --> B',
    );
  });

  test('a node label holding an unquoted bracket is one finding keyed by the '
      'node', () async {
    final report = await _checkArchitecture(
      '```mermaid\nflowchart TD\nA[Save (draft)] -->|reads| B[Index]\n```',
    );

    expect(
      _found(report).singleWhere((f) => f.contains('label_unquoted')),
      '12 diagram_label_unquoted A',
    );
  });

  test('a quoted node label gives no finding', () async {
    final report = await _checkArchitecture(
      '```mermaid\nflowchart TD\nA["Save (draft)"] -->|reads| B[Index]\n```',
    );

    expect(_found(report).where((f) => f.contains('label_unquoted')), isEmpty);
  });

  test(
    'a block without front matter misses its title at the opening fence',
    () async {
      final report = await _checkArchitecture(
        '```mermaid\nflowchart TD\nA -->|reads| B[Index]\n```',
      );

      expect(
        _found(report).singleWhere((f) => f.contains('title_missing')),
        '10 diagram_title_missing',
      );
    },
  );

  test('a block in a section whose guide sets no title needs none', () async {
    final report = await _checkFlow(
      '```mermaid\nflowchart TD\nA -->|reads| B[Index]\n```',
    );

    expect(_found(report).where((f) => f.contains('title_missing')), isEmpty);
  });

  test('a sequenceDiagram block is not read', () async {
    final report = await _checkArchitecture(
      '```mermaid\nsequenceDiagram\nA --> B\n```',
    );

    expect(_found(report), isEmpty);
  });

  test('a flowchart block in a section whose guide sets no diagram key is '
      'not read', () async {
    final report = await _check(
      '---\nconfirmed:\n  - email_login/check_password '
      '${fingerprintFor(checkPasswordStatement)}\n---\n\n# Login API\n\n'
      '## Operations\n\n```mermaid\nflowchart TD\nA --> B\n```\n\n'
      '### signIn\n\nSigns the Agent in.\n',
      loginApi,
    );

    expect(_found(report), isEmpty);
  });

  test('two unlabeled edges on two lines give two findings at their lines', () async {
    final report = await _checkArchitecture(
      '```mermaid\nflowchart TD\nA --> B\nB -->|reads| C[Index]\nC --> A\n```',
    );

    expect(_found(report).where((f) => f.contains('edge_unlabeled')), [
      '12 diagram_edge_unlabeled A --> B',
      '14 diagram_edge_unlabeled C --> A',
    ]);
  });

  test('a chain on one line gives one finding per edge at that line', () async {
    final report = await _checkArchitecture(
      '```mermaid\nflowchart TD\nA --> B --> C\n```',
    );

    expect(_found(report).where((f) => f.contains('edge_unlabeled')), [
      '12 diagram_edge_unlabeled A --> B',
      '12 diagram_edge_unlabeled B --> C',
    ]);
  });

  test('two nodes with unquoted brackets on one line give two findings told '
      'apart by the node key', () async {
    final report = await _checkArchitecture(
      '```mermaid\nflowchart TD\nA[Save (draft)] -->|reads| B[Load (draft)]\n```',
    );

    expect(_found(report).where((f) => f.contains('label_unquoted')), [
      '12 diagram_label_unquoted A',
      '12 diagram_label_unquoted B',
    ]);
  });

  test('subgraph, classDef, style, and click lines give no finding', () async {
    final report = await _checkArchitecture(
      '```mermaid\n---\ntitle: Sign-in\n---\nflowchart TD\n'
      'subgraph inner[A group (open)]\n'
      'classDef c1 fill:#f9f9f9,stroke:#333,stroke-width:1px\n'
      'style A fill:#f9f9f9,stroke:#333,stroke-width:1px\n'
      'click A "/docs" "tooltip (open)"\n'
      'end\n'
      'A -->|reads| B[Index]\n```',
    );

    expect(_found(report), isEmpty);
  });

  test('an unlabeled edge inside a subgraph is still a finding', () async {
    final report = await _checkArchitecture(
      '```mermaid\nflowchart TD\nsubgraph inner[A group]\nA --> B\nend\n```',
    );

    expect(
      _found(report).singleWhere((f) => f.contains('edge_unlabeled')),
      '13 diagram_edge_unlabeled A --> B',
    );
  });
}
