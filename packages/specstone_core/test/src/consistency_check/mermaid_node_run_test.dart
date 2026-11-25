import 'dart:io';

import 'package:specstone_core/src/consistency_check/mermaid_node_run.dart';
import 'package:test/test.dart';

import '../../helpers/cold_node.dart';

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
      timeout: const Duration(seconds: 5),
    ).parse(_blocks);

    expect(outcome.skipReason, 'node timed out after 5 s');
    expect(outcome.answered.keys, ['h0', 'h1']);
    expect(outcome.answered['h0']!.parses, isTrue);
    expect(outcome.answered['h0']!.diagram, 'sequence');
    expect(outcome.answered['h1']!.parses, isFalse);
    expect(outcome.answered['h1']!.message, 'boom');
    expect(outcome.answered['h1']!.blockLine, 2);
    expect(outcome.answered['h1']!.blockHash, 'h1');
  });

  test(
    'with no timeout given a hang is cut after 10 s and the child is killed',
    () async {
      final beat = File.fromUri(temp.uri.resolve('beat.txt'))..createSync();
      final stopwatch = Stopwatch()..start();

      final outcome = await MermaidNodeRun(
        start: fake("""
$_twoResultLines
  final beat = File(r'${beat.path}');
  while (true) {
    beat.writeAsStringSync('x', mode: FileMode.append, flush: true);
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
"""),
      ).parse(_blocks);
      stopwatch.stop();

      expect(outcome.skipReason, 'node timed out after 10 s');
      expect(
        stopwatch.elapsed,
        greaterThanOrEqualTo(const Duration(seconds: 10)),
      );
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 20)));
      expect(outcome.answered.keys, ['h0', 'h1']);
      final sizeAtReturn = beat.lengthSync();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(beat.lengthSync(), sizeAtReturn);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test('a hang mid-line drops the cut line and keeps the whole ones', () async {
    final outcome = await MermaidNodeRun(
      start: fake('''
  stdout.writeln('{"i":0,"diagram":"sequence","parses":true}');
  stdout.write('{"i":1,"diagr');
  await stdout.flush();
  await Future<void>.delayed(const Duration(minutes: 5));
'''),
      timeout: const Duration(seconds: 5),
    ).parse(_blocks);

    expect(outcome.skipReason, 'node timed out after 5 s');
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
    for (final body in ['  exit(1);', '']) {
      final outcome = await MermaidNodeRun(start: fake(body)).parse(_blocks);

      expect(outcome.answered, isEmpty, reason: 'body: "$body"');
      expect(outcome.skipReason, isNotNull, reason: 'body: "$body"');
    }
  });

  test('blocks sharing a hash go in once and both resolve', () async {
    final outcome =
        await MermaidNodeRun(
          start: fake(
            '''  stdout.writeln('{"i":0,"diagram":"sequence","parses":true}');''',
          ),
        ).parse(const [
          PendingBlock(hash: 'same', text: 'sequenceDiagram\n  A->>B: ok'),
          PendingBlock(hash: 'same', text: 'sequenceDiagram\n  A->>B: ok'),
        ]);

    expect(outcome.skipReason, isNull);
    expect(outcome.answered.keys, ['same']);
  });

  test('no block starts no process and gives no reason', () async {
    var starts = 0;
    final outcome = await MermaidNodeRun(
      start: (_) {
        starts++;
        throw const ProcessException('node', []);
      },
    ).parse(const []);

    expect(starts, 0);
    expect(outcome.answered, isEmpty);
    expect(outcome.skipReason, isNull);
  });

  test(
    'another start failure gives a one-line failed-to-start reason',
    () async {
      final outcome = await MermaidNodeRun(
        start: (_) => throw const ProcessException(
          'node',
          [],
          'permission\n  denied\n',
          13,
        ),
      ).parse(_blocks);

      expect(outcome.answered, isEmpty);
      expect(outcome.skipReason, 'node failed to start: permission denied');
    },
  );

  test('invalid UTF-8 on stdout drops every answer', () async {
    final outcome = await MermaidNodeRun(
      start: fake('''
  stdout.writeln('{"i":0,"diagram":"sequence","parses":true}');
  stdout.add([0xff, 0xfe, 0x0a]);
'''),
    ).parse(_blocks);

    expect(outcome.answered, isEmpty);
    expect(outcome.skipReason, 'node wrote output that is not a parse result');
  });

  test('a line whose parses is not a bool drops every answer', () async {
    final outcome = await MermaidNodeRun(
      start: fake('''
  stdout.writeln('{"i":0,"diagram":"sequence","parses":true}');
  stdout.writeln('{"i":1,"diagram":"sequence","parses":"yes"}');
'''),
    ).parse(_blocks);

    expect(outcome.answered, isEmpty);
    expect(outcome.skipReason, 'node wrote output that is not a parse result');
  });

  test('real node answers one good and one bad block with no reason', () async {
    await warmNode();
    final outcome = await MermaidNodeRun(timeout: coldHostNodeTimeout)
        .parse(_blocks);

    expect(outcome.skipReason, isNull);
    expect(outcome.answered['h0']!.parses, isTrue);
    expect(outcome.answered['h0']!.diagram, 'sequence');
    expect(outcome.answered['h1']!.parses, isFalse);
    expect(outcome.answered['h1']!.blockLine, 2);
    expect(outcome.answered['h1']!.message, isNotEmpty);
  }, timeout: const Timeout(Duration(seconds: 60)));
}
