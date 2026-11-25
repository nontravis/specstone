// The doc texts and parser messages are plan literals kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/consistency_check/check_report.dart';
import 'package:specstone_core/src/consistency_check/check_run.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/consistency_check/mermaid_node_run.dart';
import 'package:specstone_core/src/consistency_check/mermaid_parse_rules.dart';
import 'package:specstone_core/src/index_query/index_store.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/index_fixture.dart';
import '../../helpers/posix_modes.dart';

const _parsing = 'sequenceDiagram\n  A->>B: ok';
const _refused = 'sequenceDiagram\n  A->>B: ok\n  A->>B: x;y';
const _refusedRaw =
    "Parse error on line 3:\n...ok  A->>B: x;y\n----------------------^\nExpecting 'TXT', got 'NEWLINE'";
const _refusedLine =
    "Parse error on line 3: ...ok A->>B: x;y ----------------------^ Expecting 'TXT', got 'NEWLINE'";

/// A refused sequence diagram whose error names block line 3.
const _refusedAnswer = _Answer(
  diagram: 'sequence',
  parses: false,
  message: _refusedRaw,
  line: 3,
);

/// The architecture doc with [block] as its technical diagram.
///
/// The block's opening fence sits on line 10.
String _architectureWith(String block) =>
    '---\ncovers:\n  - app/lib/\n---\n\n# Login architecture\n\n'
    '## Technical diagram\n\n```mermaid\n$block\n```\n\n## Components\n\n'
    '| Component | Responsibility |\n|---|---|\n| Sign-in page | Takes the form |\n';

/// The feature doc with [block] as its feature flow.
///
/// The block's opening fence sits on line 28.
String _featureWith(String block) =>
    '---\nvision:\n  - PV-01\ngoals:\n  - PG-01\n---\n\n# Login\n\n'
    '## Problem\n\nUsers forget passwords.\n\n## Benefit hypothesis\n\n'
    'Fewer resets.\n\n## Success measures\n\nResets per week.\n\n'
    '## Current alternatives\n\nEmail links.\n\n## Feature flow\n\n'
    '```mermaid\n$block\n```\n\n## Out-of-scope\n\n- Social sign-in — not planned\n';

Future<Directory> _project({String? architecture, String? feature}) =>
    writeCheckProject(
      extra: {
        if (architecture != null)
          'docs/$loginArchitecture': _architectureWith(architecture),
        if (feature != null) 'docs/$loginFeature': _featureWith(feature),
      },
      unstamped: {'docs/$loginArchitecture', 'docs/$loginFeature'},
    );

Future<CheckReport> _check(
  Directory project,
  MermaidNodeRun runner, {
  String? docPath,
}) async {
  final session = openSession(project);
  try {
    return await runCheck(session, docPath: docPath, mermaidRunner: runner);
  } finally {
    session.close();
  }
}

/// Returns `<path>:<line> <diagram key> | <message>` per parse finding.
List<String> _parseFindings(CheckReport report) => [
  for (final f in report.findings)
    if (f.kind == FindingKind.diagramParseFailed)
      '${f.path}:${f.line} ${f.keys['diagram'] ?? '-'} | ${f.message}',
];

List<String> _mermaidWarnings(CheckReport report) => [
  for (final w in report.warnings)
    if (w.startsWith('Mermaid parse')) w,
];

void main() {
  test('a refused block is one finding at its fence line plus the named block line, keyed by the diagram', () async {
    final node = _FakeNode({_refused: _refusedAnswer});
    final project = await _project(architecture: _refused);

    final report = await _check(project, node.runner);

    expect(_parseFindings(report), [
      '$loginArchitecture:13 sequence | $_refusedLine',
    ]);
    final finding = report.findings.singleWhere(
      (f) => f.kind == FindingKind.diagramParseFailed,
    );
    expect(finding.waitsFor, WaitsFor.agent);
    expect(finding.keys, {'diagram': 'sequence'});
  });

  test('a refused block whose type the parser misses holds no key', () async {
    final node = _FakeNode({
      'nonsense': const _Answer(parses: false, message: 'No diagram type'),
    });
    final project = await _project(architecture: 'nonsense');

    final report = await _check(project, node.runner);

    final finding = report.findings.singleWhere(
      (f) => f.kind == FindingKind.diagramParseFailed,
    );
    expect(finding.keys, isEmpty);
  });

  test('an error that names no line sits at the opening fence', () async {
    final node = _FakeNode({
      _refused: const _Answer(
        diagram: 'sequence',
        parses: false,
        message: 'Lexer error',
      ),
    });
    final project = await _project(architecture: _refused);

    final report = await _check(project, node.runner);

    expect(_parseFindings(report), [
      '$loginArchitecture:10 sequence | Lexer error',
    ]);
  });

  test('a block that parses gives no finding, and no warning prints', () async {
    final node = _FakeNode({});
    final project = await _project(architecture: _parsing);

    final report = await _check(project, node.runner);

    expect(_parseFindings(report), isEmpty);
    expect(report.warnings, isEmpty);
    expect(node.sent, [
      [_parsing],
    ]);
  });

  test('with no node an unstored block gives no finding and stores nothing, while a stored block reports', () async {
    final project = await _project(architecture: _refused, feature: _parsing);
    await _check(project, _FakeNode({_refused: _refusedAnswer}).runner);
    File.fromUri(project.uri.resolve('docs/$loginFeature'))
        .writeAsStringSync(_featureWith(_refused.replaceAll('x;y', 'p;q')));
    final missing = MermaidNodeRun(
      start: (_) => throw const ProcessException('node', [], 'none', 2),
    );

    final report = await _check(project, missing);

    expect(_parseFindings(report), [
      '$loginArchitecture:13 sequence | $_refusedLine',
    ]);
    expect(_mermaidWarnings(report), ['Mermaid parse skipped: node not found']);
    final next = _FakeNode({});
    await _check(project, next.runner);
    expect(next.sent, [
      [_refused.replaceAll('x;y', 'p;q')],
    ]);
  });

  test('a second run with every row stored starts no process, prints no warning, and reports from the rows', () async {
    final project = await _project(architecture: _refused);
    await _check(project, _FakeNode({_refused: _refusedAnswer}).runner);
    final second = _FakeNode({});

    final report = await _check(project, second.runner);

    expect(second.starts, 0);
    expect(report.warnings, isEmpty);
    expect(_parseFindings(report), [
      '$loginArchitecture:13 sequence | $_refusedLine',
    ]);
  });

  test('an edited block parses again', () async {
    final project = await _project(architecture: _parsing);
    await _check(project, _FakeNode({}).runner);
    File.fromUri(project.uri.resolve('docs/$loginArchitecture'))
        .writeAsStringSync(_architectureWith(_refused));
    final next = _FakeNode({_refused: _refusedAnswer});

    final report = await _check(project, next.runner);

    expect(next.sent, [
      [_refused],
    ]);
    expect(_parseFindings(report), hasLength(1));
  });

  test('after the index is deleted every block parses again', () async {
    final project = await _project(architecture: _parsing, feature: _refused);
    await _check(project, _FakeNode({_refused: _refusedAnswer}).runner);
    for (final suffix in ['', '-wal', '-shm']) {
      final file = File.fromUri(project.uri.resolve('$indexFilePath$suffix'));
      if (file.existsSync()) file.deleteSync();
    }
    final next = _FakeNode({_refused: _refusedAnswer});

    await _check(project, next.runner);

    expect(next.sent.single, unorderedEquals([_parsing, _refused]));
  });

  test('a mermaid block in an untyped markdown file is not read', () async {
    final project = await writeCheckProject(
      extra: {
        'docs/$loginArchitecture': _architectureWith(_parsing),
        'docs/notes.md': '# Notes\n\n```mermaid\n$_refused\n```\n',
      },
      unstamped: {'docs/$loginArchitecture'},
    );
    final node = _FakeNode({_refused: _refusedAnswer});

    final report = await _check(project, node.runner);

    expect(node.sent, [
      [_parsing],
    ]);
    expect(_parseFindings(report), isEmpty);
  });

  test(
    'stored results of another parser are not used, so the block parses again',
    () async {
      final project = await _project(architecture: _refused);
      await _check(project, _FakeNode({_refused: _refusedAnswer}).runner);
      sqlite3.open(File.fromUri(project.uri.resolve(indexFilePath)).path)
        ..execute("UPDATE diagram_parses SET parser_hash = 'an older parser'")
        ..close();
      final next = _FakeNode({_refused: _refusedAnswer});

      final report = await _check(project, next.runner);

      expect(next.sent, [
        [_refused],
      ]);
      expect(_parseFindings(report), [
        '$loginArchitecture:13 sequence | $_refusedLine',
      ]);
    },
  );

  test('after the index is rebuilt in full every block parses again', () async {
    final project = await _project(architecture: _parsing, feature: _refused);
    await _check(project, _FakeNode({_refused: _refusedAnswer}).runner);
    sqlite3.open(File.fromUri(project.uri.resolve(indexFilePath)).path)
      ..execute('UPDATE meta SET layout = layout - 1')
      ..close();
    final next = _FakeNode({_refused: _refusedAnswer});

    await _check(project, next.runner);

    expect(next.sent.single, unorderedEquals([_parsing, _refused]));
  });

  test('a node label with an unquoted bracket gives the parse finding and the label finding', () async {
    const block = 'flowchart TD\nA[Save (draft)] -->|reads| B[Index]';
    final node = _FakeNode({
      block: const _Answer(
        diagram: 'flowchart-v2',
        parses: false,
        message: 'Parse error on line 2:\nA[Save (draft)]',
        line: 2,
      ),
    });
    final project = await _project(architecture: block);

    final report = await _check(project, node.runner);

    expect(
      [
        for (final f in report.findings)
          if (f.kind == FindingKind.diagramParseFailed ||
              f.kind == FindingKind.diagramLabelUnquoted)
            '${f.line} ${f.kind.wire}',
      ],
      unorderedEquals(['12 diagram_parse_failed', '12 diagram_label_unquoted']),
    );
  });

  test('a write met by a held lock still returns the findings, stores nothing, and warns with the code', () async {
    final project = await _project(architecture: _refused);
    final session = openSession(
      project,
      busyTimeout: const Duration(milliseconds: 100),
    );
    final holder = sqlite3.open(
      File.fromUri(project.uri.resolve(indexFilePath)).path,
    )..execute('BEGIN IMMEDIATE');
    final CheckReport report;
    try {
      report = await runCheck(
        session,
        mermaidRunner: _FakeNode({_refused: _refusedAnswer}).runner,
      );
    } finally {
      holder
        ..execute('ROLLBACK')
        ..close();
      session.close();
    }

    expect(_parseFindings(report), [
      '$loginArchitecture:13 sequence | $_refusedLine',
    ]);
    expect(_mermaidWarnings(report), [
      'Mermaid parse results not stored: index_busy',
    ]);
    final next = _FakeNode({_refused: _refusedAnswer});
    await _check(project, next.runner);
    expect(next.sent, [
      [_refused],
    ]);
  });

  test('a partial answer reports and stores the answered block, warns once, and leaves the other unstored', () async {
    final project = await _project(architecture: _refused, feature: _parsing);
    final node = _FakeNode(
      {_refused: _refusedAnswer},
      hangOn: {_parsing},
      timeout: const Duration(seconds: 1),
    );

    final report = await _check(project, node.runner);

    expect(_parseFindings(report), [
      '$loginArchitecture:13 sequence | $_refusedLine',
    ]);
    expect(_mermaidWarnings(report), [
      'Mermaid parse skipped: node timed out after 1 s',
    ]);
    final next = _FakeNode({});
    final rerun = await _check(project, next.runner);
    expect(next.sent, [
      [_parsing],
    ]);
    expect(_parseFindings(rerun), [
      '$loginArchitecture:13 sequence | $_refusedLine',
    ]);
  });

  test(
    'a write refused as index_not_writable still returns the findings and warns with the code',
    skip: unreadablePathSkipReason(),
    () async {
      final project = await _project(architecture: _refused);
      openSession(project).close();
      final index = File.fromUri(project.uri.resolve(indexFilePath));
      Process.runSync('chmod', ['444', index.path]);
      addTearDown(() => Process.runSync('chmod', ['644', index.path]));

      final report = await _check(
        project,
        _FakeNode({_refused: _refusedAnswer}).runner,
      );

      expect(_parseFindings(report), [
        '$loginArchitecture:13 sequence | $_refusedLine',
      ]);
      expect(_mermaidWarnings(report), [
        'Mermaid parse results not stored: index_not_writable',
      ]);
    },
  );

  test("a run on one doc sends only that doc's blocks", () async {
    final project = await _project(architecture: _refused, feature: _parsing);
    final node = _FakeNode({_refused: _refusedAnswer});

    final report = await _check(
      project,
      node.runner,
      docPath: loginArchitecture,
    );

    expect(node.sent, [
      [_refused],
    ]);
    expect(_parseFindings(report), hasLength(1));
  });

  test(
    'two docs holding one block text send it once and get one finding each',
    () async {
      final project = await _project(architecture: _refused, feature: _refused);
      final node = _FakeNode({_refused: _refusedAnswer});

      final report = await _check(project, node.runner);

      expect(node.starts, 1);
      expect(node.sent, [
        [_refused],
      ]);
      expect(
        _parseFindings(report),
        unorderedEquals([
          '$loginArchitecture:13 sequence | $_refusedLine',
          '$loginFeature:31 sequence | $_refusedLine',
        ]),
      );
    },
  );

  group('oneLineMessage', () {
    test('a jison error reads on one line', () {
      expect(
        oneLineMessage(
          "Parse error on line 2:\n...equenceDiagramA->>B\n----------------------^\nExpecting 'TXT', got 'NEWLINE'",
        ),
        "Parse error on line 2: ...equenceDiagramA->>B ----------------------^ Expecting 'TXT', got 'NEWLINE'",
      );
    });

    test('a Langium error loses its trailing space', () {
      expect(
        oneLineMessage(
          'Parsing failed: Lexer error on line 2, column 9: unexpected character: ->x<- at offset: 12, skipped 1 characters. ',
        ),
        'Parsing failed: Lexer error on line 2, column 9: unexpected character: ->x<- at offset: 12, skipped 1 characters.',
      );
    });

    test('runs of spaces, tabs, and CRLF breaks become one space', () {
      expect(oneLineMessage('  a \t b\r\n\r\nc  '), 'a b c');
    });
  });
}

/// What the fake Node answers for one block text.
final class _Answer {
  const new({this.diagram, required this.parses, this.message, this.line});

  final String? diagram;
  final bool parses;
  final String? message;
  final int? line;
}

/// A Node stand-in: counts starts, records the block texts each start got,
/// and answers each text from its answers, else as a parsing sequence.
///
/// A text in [hangOn] gets no line, and the process then runs until the
/// runner's [timeout] kills it.
final class _FakeNode {
  new(this._answers, {this.hangOn = const {}, this.timeout});

  final Map<String, _Answer> _answers;
  final Set<String> hangOn;
  final Duration? timeout;

  /// How many processes the runner started.
  int starts = 0;

  /// The block texts each start received, in input order.
  final List<List<String>> sent = [];

  MermaidNodeRun get runner => MermaidNodeRun(start: _start, timeout: timeout);

  Future<Process> _start(List<String> arguments) async {
    starts++;
    final input = StreamController<List<int>>();
    final output = StreamController<List<int>>();
    final exit = Completer<int>();
    unawaited(_answer(input.stream, output, exit));
    return _FakeProcess(IOSink(input), output.stream, exit.future, () {
      if (!output.isClosed) unawaited(output.close());
      if (!exit.isCompleted) exit.complete(_killedStatus);
    });
  }

  Future<void> _answer(
    Stream<List<int>> stdin,
    StreamController<List<int>> stdout,
    Completer<int> exit,
  ) async {
    final text = utf8.decode(await stdin.expand((chunk) => chunk).toList());
    final blocks = jsonDecode(text.substring(text.lastIndexOf('\n') + 1));
    final texts = <String>[];
    for (final block in blocks as List<Object?>) {
      if (block case {'i': final int i, 'text': final String body}) {
        texts.add(body);
        if (!hangOn.contains(body)) stdout.add(_resultLine(i, body));
      }
    }
    sent.add(texts);
    if (texts.any(hangOn.contains)) return;
    await stdout.close();
    exit.complete(0);
  }

  List<int> _resultLine(int i, String body) {
    final answer =
        _answers[body] ?? const _Answer(diagram: 'sequence', parses: true);
    final line = jsonEncode({
      'i': i,
      'diagram': answer.diagram,
      'parses': answer.parses,
      'message': ?answer.message,
      'line': ?answer.line,
    });
    return utf8.encode('$line\n');
  }
}

/// The exit status the fake reports after a kill.
const _killedStatus = -9;

/// A child process whose pipes the fake Node drives.
final class _FakeProcess implements Process {
  new(this.stdin, this.stdout, this.exitCode, this._onKill);

  @override
  final IOSink stdin;

  @override
  final Stream<List<int>> stdout;

  @override
  final Future<int> exitCode;

  final void Function() _onKill;

  @override
  Stream<List<int>> get stderr => const Stream.empty();

  @override
  int get pid => 0;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    _onKill();
    return true;
  }
}
