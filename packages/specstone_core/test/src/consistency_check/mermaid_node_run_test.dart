import 'dart:io';

import 'package:specstone_core/src/consistency_check/mermaid_node_run.dart';
import 'package:test/test.dart';

const _blocks = [
  PendingBlock(hash: 'h0', text: 'sequenceDiagram\n  A->>B: ok'),
  PendingBlock(hash: 'h1', text: 'sequenceDiagram\n  A->>B: x;y'),
];

const _twoResultLines = '''
  stdout.writeln('{"i":0,"diagram":"sequence","parses":true}');
  stdout.writeln(
    '{"i":1,"diagram":"sequence","parses":false,"message":"boom","line":2}',
  );
''';

void main() {
  late Directory temp;
  var fakeCount = 0;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('mermaid_node_run_test');
  });

  tearDown(() {
    temp.deleteSync(recursive: true);
  });

  /// A start function that runs a Dart script holding [body] as `main`.
  Future<Process> Function(List<String>) fake(String body) {
    final script = File.fromUri(temp.uri.resolve('fake_${fakeCount++}.dart'))
      ..writeAsStringSync(
        "import 'dart:io';\n\nFuture<void> main() async {\n"
        '$body\n  await stdout.flush();\n}\n',
      );
    return (_) => Process.start(Platform.resolvedExecutable, [script.path]);
  }

  test(
    'a missing executable gives no answers and the not-found reason',
    () async {
      final outcome = await MermaidNodeRun(
        start: (_) => throw const ProcessException('node', [], 'none', 2),
      ).parse(_blocks);

      expect(outcome.answered, isEmpty);
      expect(outcome.skipReason, 'node not found');
    },
  );

  test('a hang keeps the answered blocks and names the timeout', () async {
    final outcome = await MermaidNodeRun(
      start: fake('''
$_twoResultLines
  await stdout.flush();
  await Future<void>.delayed(const Duration(minutes: 5));
'''),
      timeout: const Duration(seconds: 2),
    ).parse(_blocks);

    expect(outcome.skipReason, 'node timed out after 2 s');
    expect(outcome.answered.keys, ['h0', 'h1']);
    expect(outcome.answered['h0']!.parses, isTrue);
    expect(outcome.answered['h0']!.diagram, 'sequence');
    expect(outcome.answered['h1']!.parses, isFalse);
    expect(outcome.answered['h1']!.message, 'boom');
    expect(outcome.answered['h1']!.blockLine, 2);
    expect(outcome.answered['h1']!.blockHash, 'h1');
  });

  test('a hang mid-line drops the cut line and keeps the whole ones', () async {
    final outcome = await MermaidNodeRun(
      start: fake('''
  stdout.writeln('{"i":0,"diagram":"sequence","parses":true}');
  stdout.write('{"i":1,"diagr');
  await stdout.flush();
  await Future<void>.delayed(const Duration(minutes: 5));
'''),
      timeout: const Duration(seconds: 2),
    ).parse(_blocks);

    expect(outcome.skipReason, 'node timed out after 2 s');
    expect(outcome.answered.keys, ['h0']);
  });

  test(
    'a non-zero exit drops every answer and names status and stderr',
    () async {
      final outcome = await MermaidNodeRun(
        start: fake('''
$_twoResultLines
  stderr.writeln('first problem');
  stderr.writeln('second problem');
  exit(1);
'''),
      ).parse(_blocks);

      expect(outcome.answered, isEmpty);
      expect(outcome.skipReason, 'node exited with status 1: first problem');
    },
  );

  test('a non-zero exit with no stderr names the status only', () async {
    final outcome = await MermaidNodeRun(start: fake('  exit(3);'))
        .parse(_blocks);

    expect(outcome.answered, isEmpty);
    expect(outcome.skipReason, 'node exited with status 3');
  });

  test('a non-JSON line drops every answer and gives a reason', () async {
    final outcome = await MermaidNodeRun(
      start: fake('''
  stdout.writeln('{"i":0,"diagram":"sequence","parses":true}');
  stdout.writeln('not json');
'''),
    ).parse(_blocks);

    expect(outcome.answered, isEmpty);
    expect(outcome.skipReason, 'node wrote output that is not a parse result');
  });

  test('a result line for an unknown block drops every answer', () async {
    final outcome = await MermaidNodeRun(
      start: fake('''
  stdout.writeln('{"i":0,"diagram":"sequence","parses":true}');
  stdout.writeln('{"i":7,"diagram":"sequence","parses":true}');
'''),
    ).parse(_blocks);

    expect(outcome.answered, isEmpty);
    expect(outcome.skipReason, 'node wrote output that is not a parse result');
  });

  test('a clean exit with a block unanswered drops every answer', () async {
    final outcome = await MermaidNodeRun(
      start: fake(
        '''  stdout.writeln('{"i":0,"diagram":"sequence","parses":true}');''',
      ),
    ).parse(_blocks);

    expect(outcome.answered, isEmpty);
    expect(outcome.skipReason, 'node wrote output that is not a parse result');
  });

  test('a child that exits before reading stdin throws nothing', () async {
    final outcome = await MermaidNodeRun(start: fake('  exit(1);'))
        .parse(_blocks);

    expect(outcome.answered, isEmpty);
    expect(outcome.skipReason, isNotNull);
  });

  test('a child that exits 0 before reading stdin throws nothing', () async {
    final outcome = await MermaidNodeRun(start: fake('')).parse(_blocks);

    expect(outcome.answered, isEmpty);
    expect(outcome.skipReason, isNotNull);
  });

  test('real node answers one good and one bad block with no reason', () async {
    final outcome = await MermaidNodeRun().parse(_blocks);

    expect(outcome.skipReason, isNull);
    expect(outcome.answered['h0']!.parses, isTrue);
    expect(outcome.answered['h0']!.diagram, 'sequence');
    expect(outcome.answered['h1']!.parses, isFalse);
    expect(outcome.answered['h1']!.blockLine, 2);
    expect(outcome.answered['h1']!.message, isNotEmpty);
  }, timeout: const Timeout(Duration(seconds: 60)));
}
