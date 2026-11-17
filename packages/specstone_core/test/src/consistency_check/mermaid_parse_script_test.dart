import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/consistency_check/mermaid_parser.dart';
import 'package:test/test.dart';

/// A worked example: the block text and the result the parse script gives.
final class _Case {
  const new(
    this.text, {
    required this.parses,
    required this.diagram,
    this.line,
    this.message,
  });

  final String text;
  final bool parses;
  final String? diagram;
  final int? line;
  final String? message;
}

const _badMessage = '  A->>B: x;y';

const _cases = {
  'a message with a semicolon on the third line': _Case(
    'sequenceDiagram\n  A->>B: ok\n$_badMessage',
    parses: false,
    diagram: 'sequence',
    line: 3,
  ),
  'a comment line before the error': _Case(
    'sequenceDiagram\n%% a note\nA->>B: ok\nA->>B: x;y',
    parses: false,
    diagram: 'sequence',
    line: 4,
  ),
  'an error that names no line': _Case(
    'not a diagram',
    parses: false,
    diagram: null,
  ),
  'a block that parses': _Case(
    'sequenceDiagram\n  A->>B: ok',
    parses: true,
    diagram: 'sequence',
  ),
  'a front matter and a blank line before the diagram': _Case(
    '---\ntitle: x\n---\n\nsequenceDiagram\n  A->>B: ok\n$_badMessage',
    parses: false,
    diagram: 'sequence',
    line: 7,
  ),
  'a mid-block init line': _Case(
    'sequenceDiagram\n%%{init: {"theme": "dark"}}%%\n  A->>B: ok\n'
    '$_badMessage',
    parses: false,
    diagram: 'sequence',
    line: 4,
  ),
  'a bare comment mark line': _Case(
    'sequenceDiagram\nA->>B: ok\n%%\nA->>B: x;y',
    parses: false,
    diagram: 'sequence',
    line: 4,
  ),
  'a blank line before a comment line': _Case(
    'sequenceDiagram\nA->>B: ok\n\n%% note\nA->>B: x;y',
    parses: false,
    diagram: 'sequence',
    line: 5,
  ),
  'a comment line before the diagram type': _Case(
    '%% note\nsequenceDiagram\nA->>B: ok\nA->>B: x;y',
    parses: false,
    diagram: 'sequence',
    line: 4,
  ),
  'a jison parser error': _Case(
    'sequenceDiagram\nA->>B',
    parses: false,
    diagram: 'sequence',
    line: 2,
    message:
        'Parse error on line 2: ...equenceDiagramA->>B '
        "----------------------^ Expecting 'TXT', got 'NEWLINE'",
  ),
  'a Langium parser error': _Case(
    'pie\n"a" : 1 x',
    parses: false,
    diagram: 'pie',
    line: 2,
    message:
        'Parsing failed: Lexer error on line 2, column 9: unexpected '
        'character: ->x<- at offset: 12, skipped 1 characters.',
  ),
  'an error naming two lines': _Case(
    'pie\n"a" ^: 1\n"b" : 2\n"c"',
    parses: false,
    diagram: 'pie',
    line: 2,
  ),
};

/// Each whitespace run made one space, and the ends trimmed.
String _oneLine(String text) => text.replaceAll(RegExp(r'\s+'), ' ').trim();

/// The result lines one `node` run prints, and the time the run took.
final class _Run {
  const new(this.lines, this.elapsed);

  final List<Map<String, Object?>> lines;
  final Duration elapsed;
}

Future<_Run> _parse(List<String> blocks) async {
  final watch = Stopwatch()..start();
  final process = await Process.start('node', ['-e', mermaidParseScript]);
  final stdoutText = process.stdout.transform(utf8.decoder).join();
  final stderrText = process.stderr.transform(utf8.decoder).join();
  process.stdin
    ..write(patchedMermaidBundle())
    ..write('\n')
    ..write(
      jsonEncode([
        for (final (index, text) in blocks.indexed) {'i': index, 'text': text},
      ]),
    );
  await process.stdin.close();
  final exitCode = await process.exitCode;
  watch.stop();
  final out = await stdoutText;
  expect(exitCode, 0, reason: await stderrText);
  return _Run([
    for (final line in const LineSplitter().convert(out))
      jsonDecode(line) as Map<String, Object?>,
  ], watch.elapsed);
}

void main() {
  late _Run run;

  setUpAll(() async {
    run = await _parse([for (final c in _cases.values) c.text]);
  });

  test('prints one line per block, in input order, under 5 s', () {
    expect(run.lines.map((line) => line['i']), [
      for (var i = 0; i < _cases.length; i++) i,
    ]);
    expect(run.elapsed, lessThan(const Duration(seconds: 5)));
  });

  for (final (index, MapEntry(key: name, value: c)) in _cases.entries.indexed) {
    test('$name gives its parse result, diagram, and block line', () {
      final line = run.lines[index];

      expect(line['parses'], c.parses);
      expect(line['diagram'], c.diagram);
      if (c.parses) {
        expect(line.containsKey('message'), isFalse);
        return;
      }
      expect(line['line'], c.line);
      expect(line['message'], isA<String>());
      if (c.message case final message?) {
        expect(_oneLine(line['message']! as String), message);
      }
    });
  }

  test('an empty block list prints nothing', () async {
    final empty = await _parse(const []);

    expect(empty.lines, isEmpty);
  });
}
