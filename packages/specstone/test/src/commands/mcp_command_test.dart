import 'dart:convert';
import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:dart_mcp/stdio.dart';
import 'package:test/test.dart';

import '../../helpers/built_cli.dart';
import '../../helpers/temp_tree.dart';

void main() {
  group('specstone mcp', () {
    late String exe;

    setUpAll(() async {
      exe = await buildSpecstone();
    });

    test('serves initialize and zero tools over stdio, then exits 0', () async {
      await _expectServesZeroTools(exe);
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('f03/us01/fr04/e04, f03/us05/fr01/e07, f03/us05/fr02/e03: mcp starts '
        'and initializes inside a project with a broken config', () async {
      final project = await writeTree({'.specstone/config.yaml': 'packs: [\n'});

      await _expectServesZeroTools(exe, workingDirectory: project.path);
    }, timeout: const Timeout(Duration(seconds: 60)));
  }, timeout: const Timeout(Duration(minutes: 5)));
}

/// Starts `specstone mcp` from the built binary [exe], initializes a client
/// against it, and expects zero tools and exit status 0.
Future<void> _expectServesZeroTools(
  String exe, {
  String? workingDirectory,
}) async {
  final process = await Process.start(exe, [
    'mcp',
  ], workingDirectory: workingDirectory);
  addTearDown(process.kill);
  final stderrLines = <String>[];
  process.stderr
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen(stderrLines.add);

  final received = <String>[];
  final client = MCPClient(Implementation(name: 'test', version: '0.0.0'));
  final server = client.connectServer(
    stdioChannel(input: process.stdout, output: process.stdin).changeStream(
      (lines) => lines.map((line) {
        received.add(line);
        return line;
      }),
    ),
  );

  final InitializeResult result;
  try {
    result = await server.initialize(
      InitializeRequest(
        protocolVersion: ProtocolVersion.latestSupported,
        capabilities: client.capabilities,
        clientInfo: client.implementation,
      ),
    );
  } on Object catch (error) {
    // The process died before answering; its exit status and stderr say why.
    final status = await process.exitCode.timeout(
      const Duration(seconds: 30),
      onTimeout: () => -1,
    );
    fail(
      'initialize failed: $error\n'
      'exit status: $status\n'
      'stderr: ${stderrLines.join('\n')}',
    );
  }
  server.notifyInitialized();
  final tools = await server.listTools(ListToolsRequest());
  await client.shutdown();

  expect(result.serverInfo.name, 'specstone');
  expect(tools.tools, isEmpty);
  expect(
    await process.exitCode.timeout(const Duration(seconds: 30)),
    0,
    reason: 'stderr: ${stderrLines.join('\n')}',
  );

  for (final line in received) {
    expect(
      jsonDecode(line),
      isA<Map<String, Object?>>().having((m) => m['jsonrpc'], 'jsonrpc', '2.0'),
    );
  }
}
