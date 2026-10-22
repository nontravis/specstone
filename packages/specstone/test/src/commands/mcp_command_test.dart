import 'dart:convert';
import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:dart_mcp/stdio.dart';
import 'package:test/test.dart';

import '../../helpers/package_root.dart';

void main() {
  group('specstone mcp', () {
    test('serves initialize and zero tools over stdio, then exits 0', () async {
      final process = await Process.start(Platform.resolvedExecutable, [
        'run',
        packageRoot().uri.resolve('bin/specstone.dart').toFilePath(),
        'mcp',
      ]);
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

      final result = await server.initialize(
        InitializeRequest(
          protocolVersion: ProtocolVersion.latestSupported,
          capabilities: client.capabilities,
          clientInfo: client.implementation,
        ),
      );
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
          isA<Map<String, Object?>>().having(
            (m) => m['jsonrpc'],
            'jsonrpc',
            '2.0',
          ),
        );
      }
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}
