// The expected texts are plan literals kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:collection';
import 'dart:convert';

import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/check_report.dart';
import 'package:specstone_core/src/consistency_check/diagram_rules.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/cold_node.dart';
import '../../helpers/index_fixture.dart';
import '../../helpers/target_fixture.dart';

const Set<FindingKind> _diagramKinds = {
  FindingKind.diagramTitleMissing,
  FindingKind.diagramEdgeUnlabeled,
  FindingKind.diagramLabelUnquoted,
  FindingKind.diagramNameUnknown,
  FindingKind.diagramActorMismatch,
};

/// The architecture doc with [block] as its technical diagram.
///
/// The block's opening fence sits on line 10 and its first line on line 11.
String _diagramDoc(String block) =>
    '---\ncovers:\n  - app/lib/\n---\n\n# Login architecture\n\n'
    '## Technical diagram\n\n$block\n\n## Components\n\n'
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

Future<CheckReport> _checkArchitecture(String block) async => checkOf(
  await writeCheckProject(
    extra: {
      'docs/$loginArchitecture': _diagramDoc(block),
      _namesLayerPath: _noNamesLayer,
    },
    unstamped: {'docs/$loginArchitecture'},
  ),
);

Future<CheckReport> _checkFlow(String block) =>
    _check(_flowDoc(block), loginFeature);

const _namesLayerPath = '.specstone/templates/architecture.yaml';

/// The layer whose technical diagram section sets the `names` rule.
const _namesLayer = '''
sections:
  - id: technical_diagram
    lint:
      diagram:
        title: true
        edge_labels: true
        banned_labels: [Uses]
        names: true
''';

/// The layer whose technical diagram section sets every rule but `names`.
const _noNamesLayer = '''
sections:
  - id: technical_diagram
    lint:
      diagram:
        title: true
        edge_labels: true
        banned_labels: [Uses]
        names: false
''';

/// A titled flowchart block of [lines]; its first line sits on file line 15 of
/// [_diagramDoc].
String _flow(String lines) =>
    '```mermaid\n---\ntitle: T\n---\nflowchart TD\n$lines\n```';

/// A titled sequence block of [lines]; its first line sits on file line 15 of
/// [_diagramDoc].
String _sequence(String lines) =>
    '```mermaid\n---\ntitle: T\n---\nsequenceDiagram\n$lines\n```';

/// The architecture doc with [block], its section setting the `names` rule.
Future<CheckReport> _checkNames(
  String block, {
  Map<String, String> extra = const {},
}) async => checkOf(
  await writeCheckProject(
    extra: {
      'docs/$loginArchitecture': _diagramDoc(block),
      _namesLayerPath: _namesLayer,
      ...extra,
    },
    unstamped: {'docs/$loginArchitecture'},
  ),
);

/// A doc whose one [section] table holds one row per name in [column].
String _tableDoc(String section, String column, List<String> names) =>
    '---\n---\n\n# Table\n\n## $section\n\n| $column | Notes |\n|---|---|\n'
    '${names.map((name) => '| $name | x |').join('\n')}\n';

/// A project architecture doc holding a Components and an External systems
/// table.
String _projectArchitectureDoc({
  required List<String> components,
  required List<String> systems,
}) =>
    '---\n---\n\n# Architecture\n\n## Components\n\n'
    '| Component | Notes |\n|---|---|\n'
    '${components.map((name) => '| $name | x |').join('\n')}\n\n'
    '## External systems\n\n| System | Notes |\n|---|---|\n'
    '${systems.map((name) => '| $name | x |').join('\n')}\n';

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

/// Sections that fail on any read, standing for a doc no rule may read.
final class _UnreadSections extends ListBase<IndexedSection> {
  @override
  int get length => throw StateError('the doc was read');

  @override
  set length(int newLength) => throw UnsupportedError('read only');

  @override
  IndexedSection operator [](int index) => throw StateError('the doc was read');

  @override
  void operator []=(int index, IndexedSection value) =>
      throw UnsupportedError('read only');
}

/// Runs the diagram rules on the login architecture with the
/// project architecture doc swapped for one whose sections fail on any read.
Future<List<Finding>> _findingsWithUnreadableProject(
  Map<String, String> extra,
) async {
  final session = openSession(
    await writeCheckProject(
      extra: {
        'docs/specs/ARCHITECTURE.md': _tableDoc('Components', 'Component', [
          'Engine',
        ]),
        ...extra,
      },
      unstamped: {'docs/$loginArchitecture'},
    ),
  );
  addTearDown(session.close);
  final real = session.index.docs.singleWhere(
    (doc) => doc.docPath == 'specs/ARCHITECTURE.md',
  );
  final content = session.index.contentOf(real);
  final unread = DocContent(
    readText: () => content.text,
    head: content.head,
    sections: _UnreadSections(),
    links: content.links,
    lineFacts: content.lineFacts,
    readBannedMatches: () => const [],
    readItemFacts: () => content.itemFacts,
  );
  final context = CheckContext(session, contents: {real.docPath: unread});
  final login = session.index.docs.singleWhere(
    (doc) => doc.docPath == loginArchitecture,
  );
  return checkDiagrams(context, login).toList();
}

void main() {
  useColdHostNode();

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

  test(
    'an edge ending in an x head with no label is one finding at its own line',
    () async {
      final report = await _checkArchitecture(
        '```mermaid\nflowchart TD\nA --x B\n```',
      );

      expect(
        _found(report).singleWhere((f) => f.contains('edge_unlabeled')),
        '12 diagram_edge_unlabeled A --> B',
      );
    },
  );

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

  test(
    'a sequenceDiagram block takes the title rule and no edge rule',
    () async {
      final report = await _checkArchitecture(
        '```mermaid\nsequenceDiagram\nA --> B\nC[Save (draft)] --> D\n```',
      );

      expect(_found(report), ['10 diagram_title_missing']);
    },
  );

  test('a stateDiagram-v2 block is not read', () async {
    final report = await _checkArchitecture(
      '```mermaid\nstateDiagram-v2\n[*] --> Idle\nIdle --> Busy\n```',
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

  test('subgraph, classDef, style, and click lines give no finding while a '
      'titled block still has its edge read', () async {
    final report = await _checkArchitecture(
      '```mermaid\n---\ntitle: Sign-in\n---\nflowchart TD\n'
      'subgraph inner[A group (open)]\n'
      'classDef c1 fill:#f9f9f9,stroke:#333,stroke-width:1px\n'
      'style A fill:#f9f9f9,stroke:#333,stroke-width:1px\n'
      'click A "/docs" "tooltip (open)"\n'
      'end\n'
      'A --> B\n```',
    );

    expect(_found(report), ['20 diagram_edge_unlabeled A --> B']);
  });

  test('a titled block is read: its unlabeled edge is a finding', () async {
    final report = await _checkArchitecture(
      '```mermaid\n---\ntitle: Sign-in\n---\nflowchart TD\nA --> B\n```',
    );

    expect(_found(report), ['15 diagram_edge_unlabeled A --> B']);
  });

  test('a block whose front matter holds no title misses its title', () async {
    final report = await _checkArchitecture(
      '```mermaid\n---\nconfig: x\n---\nflowchart TD\n'
      'A -->|reads| B\n```',
    );

    expect(_found(report), ['10 diagram_title_missing']);
  });

  test('an arrow or label with no node after it gives no finding and no '
      'crash', () async {
    final report = await _checkArchitecture(
      '```mermaid\n---\ntitle: T\n---\nflowchart TD\n'
      'A -->\nA -->|reads|\nA ...\n```',
    );

    expect(_found(report), isEmpty);
  });

  test('pair-delimited shapes and comment lines give no finding', () async {
    final report = await _checkArchitecture(
      '```mermaid\n---\ntitle: T\n---\nflowchart TD\n'
      'DB[(Database)] -->|reads| A((Start))\n'
      'S([Stop]) -->|reads| B[[Sub]]\n'
      'H{{Hex}} -->|reads| C(((Ring)))\n'
      '%% X --> Y\n```',
    );

    expect(_found(report), isEmpty);
  });

  test('a bare two-dash run with no closing arrow is no edge', () async {
    final report = await _checkArchitecture(
      '```mermaid\n---\ntitle: T\n---\nflowchart TD\nA -- B\n```',
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

  test(
    'a box name no source holds is diagram_name_unknown at its line',
    () async {
      final report = await _checkNames(
        _flow('A[Sign-in page] -->|reads, SQL| B[Ghost]'),
      );

      expect(_found(report), ['15 diagram_name_unknown Ghost']);
    },
  );

  test(
    'a quoted box label with a technology part matches the component table',
    () async {
      final report = await _checkNames(
        _flow('A["Sign-in page (Dart)"] -->|reads, SQL| B[Sign-in page]'),
      );

      expect(_found(report), isEmpty);
    },
  );

  test('a node with no label and an undeclared participant take their ID as the name', () async {
    final flow = await _checkNames(
      _flow('A[Sign-in page] -->|reads, SQL| Ghost'),
    );
    final sequence = await _checkNames(
      _sequence('participant S as Sign-in page\nS->>Phantom: asks'),
    );

    expect(_found(flow), ['15 diagram_name_unknown Ghost']);
    expect(_found(sequence), ['16 diagram_name_unknown Phantom']);
  });

  test('a name from the project architecture, a feature mention, an integration system, or the Systems table matches', () async {
    final report = await _checkNames(
      _flow(
        'A[Engine] -->|reads, SQL| B[feature:shop Cart]\n'
        'B -->|reads, SQL| C[feature:shop]\n'
        'C -->|sends, SMTP| D[Mailer]\n'
        'D -->|charges, REST| E[Stripe]\n'
        'E -->|reads, REST| F[Billing site]',
      ),
      extra: {
        'docs/specs/ARCHITECTURE.md': _projectArchitectureDoc(
          components: ['Engine'],
          systems: ['Stripe'],
        ),
        'docs/specs/f02_shop/ARCHITECTURE.md': _tableDoc(
          'Components',
          'Component',
          ['Cart'],
        ),
        'docs/specs/f01_login/INTEGRATION.md': _tableDoc(
          'External systems',
          'System',
          ['Mailer'],
        ),
        'docs/prds/FEATURES.md': _tableDoc('Systems', 'System', [
          'Billing site',
        ]),
      },
    );

    expect(_found(report), isEmpty);
  });

  test(
    'a feature mention whose feature has no such component is unknown',
    () async {
      final report = await _checkNames(
        _flow('A[feature:shop Wagon] -->|reads, SQL| B[Sign-in page]'),
        extra: {
          'docs/specs/f02_shop/ARCHITECTURE.md': _tableDoc(
            'Components',
            'Component',
            ['Cart'],
          ),
        },
      );

      expect(_found(report), ['15 diagram_name_unknown feature:shop Wagon']);
    },
  );

  test('a name repeated in one block is one finding', () async {
    final report = await _checkNames(
      _flow(
        'A[Ghost] -->|reads, SQL| B[Sign-in page]\n'
        'B -->|reads, SQL| C[Ghost]',
      ),
    );

    expect(_found(report), ['15 diagram_name_unknown Ghost']);
  });

  test('an actor whose name is no role is diagram_actor_mismatch', () async {
    final report = await _checkNames(
      _sequence(
        'actor Intruder\nactor Agent\nparticipant S as Sign-in page\n'
        'Agent->>S: signs in',
      ),
    );

    expect(_found(report), ['15 diagram_actor_mismatch Intruder']);
  });

  test('a participant or box named for a role is one diagram_actor_mismatch and no unknown name', () async {
    final sequence = await _checkNames(
      _sequence(
        'participant Owner\nparticipant S as Sign-in page\nOwner->>S: signs in',
      ),
    );
    final flow = await _checkNames(
      _flow('A[Owner] -->|reads, SQL| B[Sign-in page]'),
    );

    expect(_found(sequence), ['15 diagram_actor_mismatch Owner']);
    expect(_found(flow), ['15 diagram_actor_mismatch Owner']);
  });

  test('a role named by a box tells the fix a flowchart can take, a role named by a participant tells it to draw an actor', () async {
    final sequence = await _checkNames(
      _sequence(
        'participant Owner\nparticipant S as Sign-in page\nOwner->>S: signs in',
      ),
    );
    final flow = await _checkNames(
      _flow('A[Owner] -->|reads, SQL| B[Sign-in page]'),
    );

    expect(
      sequence.findings
          .singleWhere((f) => f.kind == FindingKind.diagramActorMismatch)
          .message,
      'Owner names a role, so draw it as an actor',
    );
    expect(
      flow.findings
          .singleWhere((f) => f.kind == FindingKind.diagramActorMismatch)
          .message,
      'Owner names a role; a box never does, draw the role as a sequence '
      '`actor` or leave it out',
    );
  });

  test('a participant id Mermaid accepts beyond letters and digits is held to the sources by its label, else by its id', () async {
    final hyphenated = await _checkNames(
      _sequence(
        'participant api-gw as Gateway\nparticipant S as Sign-in page\n'
        'api-gw->>S: asks',
      ),
    );
    final spaced = await _checkNames(
      _sequence(
        'participant Specstone CLI\nparticipant S as Sign-in page\n'
        'Specstone CLI->>S: asks',
      ),
    );
    final undeclared = await _checkNames(
      _sequence('participant S as Sign-in page\nS->>api-gw: asks'),
    );
    final matching = await _checkNames(
      _sequence(
        'participant api-gw as Sign-in page\nparticipant Specstone CLI as Engine'
        '\napi-gw->>Specstone CLI: asks',
      ),
      extra: {
        'docs/specs/ARCHITECTURE.md': _tableDoc('Components', 'Component', [
          'Engine',
        ]),
      },
    );

    expect(_found(hyphenated), ['15 diagram_name_unknown Gateway']);
    expect(_found(spaced), ['15 diagram_name_unknown Specstone CLI']);
    expect(_found(undeclared), ['16 diagram_name_unknown api-gw']);
    expect(_found(matching), isEmpty);
  });

  test('a section whose diagram key sets no names reads no name', () async {
    final flow = await _checkArchitecture(
      _flow('A[Ghost] -->|reads, SQL| B[Sign-in page]'),
    );
    final sequence = await _checkArchitecture(
      _sequence('actor Intruder\nIntruder->>Phantom: asks'),
    );

    expect(_found(flow), isEmpty);
    expect(_found(sequence), isEmpty);
  });

  test('with two targets a name matches the project architecture of its own target only', () async {
    final project = await writeTwinProject(
      extra: {
        '.specstone/templates/architecture.yaml': _namesLayer,
        'docs/specs/flutter/ARCHITECTURE.md': _tableDoc(
          'Components',
          'Component',
          ['FlutterOnly'],
        ),
        'docs/specs/jaspr/ARCHITECTURE.md': _tableDoc(
          'Components',
          'Component',
          ['JasprOnly'],
        ),
        'docs/$flutterArchitecture': _diagramDoc(
          _flow('A[FlutterOnly] -->|reads, SQL| B[JasprOnly]'),
        ),
        'docs/$jasprArchitecture': _diagramDoc(
          _flow('A[JasprOnly] -->|reads, SQL| B[FlutterOnly]'),
        ),
      },
    );
    final report = await checkOf(project);

    expect(
      [
        for (final f in report.findings)
          if (f.kind == FindingKind.diagramNameUnknown)
            '${f.path}:${f.line} ${f.keys['label']}',
      ],
      unorderedEquals([
        '$flutterArchitecture:15 JasprOnly',
        '$jasprArchitecture:15 FlutterOnly',
      ]),
    );
  });

  test('with two targets an external system matches the project architecture of its own target only', () async {
    final project = await writeTwinProject(
      extra: {
        '.specstone/templates/architecture.yaml': _namesLayer,
        'docs/specs/flutter/ARCHITECTURE.md': _projectArchitectureDoc(
          components: ['Engine'],
          systems: ['FlutterStripe'],
        ),
        'docs/specs/jaspr/ARCHITECTURE.md': _projectArchitectureDoc(
          components: ['Engine'],
          systems: ['JasprStripe'],
        ),
        'docs/$flutterArchitecture': _diagramDoc(
          _flow('A[FlutterStripe] -->|reads, SQL| B[JasprStripe]'),
        ),
        'docs/$jasprArchitecture': _diagramDoc(
          _flow('A[JasprStripe] -->|reads, SQL| B[FlutterStripe]'),
        ),
      },
    );
    final report = await checkOf(project);

    expect(
      [
        for (final f in report.findings)
          if (f.kind == FindingKind.diagramNameUnknown)
            '${f.path}:${f.line} ${f.keys['label']}',
      ],
      unorderedEquals([
        '$flutterArchitecture:15 JasprStripe',
        '$jasprArchitecture:15 FlutterStripe',
      ]),
    );
  });

  test(
    'a name finding keeps the doc name and carries the diagram name as label',
    () async {
      final report = await _checkNames(
        _flow('A[Sign-in page] -->|reads, SQL| B[Ghost]'),
      );
      final json = jsonDecode(
        jsonEncode(
          report.findings
              .singleWhere((f) => f.kind == FindingKind.diagramNameUnknown)
              .toJson(),
        ),
      ) as Map<String, Object?>;

      expect(json['name'], 'login');
      expect(json['label'], 'Ghost');
    },
  );

  test('a node first drawn bare and labeled on a later line takes its label at that line', () async {
    final report = await _checkNames(
      _flow(
        'A[Sign-in page] -->|reads, SQL| B\n'
        'B[Ghost] -->|reads, SQL| A',
      ),
    );

    expect(_found(report), ['16 diagram_name_unknown Ghost']);
  });

  test(
    'a feature mention whose feature has no architecture doc matches nothing',
    () async {
      final report = await _checkNames(
        _flow('A[feature:ghost] -->|reads, SQL| B[feature:ghost Cart]'),
      );

      expect(
        _found(report),
        unorderedEquals([
          '15 diagram_name_unknown feature:ghost',
          '15 diagram_name_unknown feature:ghost Cart',
        ]),
      );
    },
  );

  test('a section whose diagram key sets no names reads no other doc, and one that sets names reads it', () async {
    final unnamed = _flow('A[Ghost] -->|reads, SQL| B[Sign-in page]');
    final without = await _findingsWithUnreadableProject({
      'docs/$loginArchitecture': _diagramDoc(unnamed),
      _namesLayerPath: _noNamesLayer,
    });
    final withNames = _findingsWithUnreadableProject({
      'docs/$loginArchitecture': _diagramDoc(unnamed),
      _namesLayerPath: _namesLayer,
    });

    expect(without, isEmpty);
    await expectLater(withNames, throwsA(isA<StateError>()));
  });

  test('an actor with no role name drawn is diagram_actor_mismatch when the roles section holds no role', () async {
    final report = await _checkNames(
      _sequence(
        'actor Intruder\nparticipant S as Sign-in page\nIntruder->>S: asks',
      ),
      extra: edit(projectDoc, [
        (
          '- `Agent` — the coding agent that writes the docs.\n'
              '- `Owner` — the person who approves them.\n',
          'None yet.\n',
        ),
      ]),
    );

    expect(_found(report), ['15 diagram_actor_mismatch Intruder']);
  });

  test('an arrow head x or o is part of its edge, not a name', () async {
    final report = await _checkNames(
      _flow(
        'A[Sign-in page] --x|reads, SQL| B[Sign-in page]\n'
        'B --o|reads, SQL| C[Sign-in page]\n'
        'C x--x|reads, SQL| D[Sign-in page]\n'
        'D o--o|reads, SQL| E[Sign-in page]',
      ),
    );

    expect(_found(report), isEmpty);
  });
}
