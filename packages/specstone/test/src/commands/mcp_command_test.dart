import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:dart_mcp/stdio.dart';
import 'package:test/test.dart';

void main() {
  group('specstone mcp', () {
    test('serves initialize and zero tools over stdio, then exits 0', () async {
      final process = await Process.start(Platform.resolvedExecutable, [
        'run',
        'bin/specstone.dart',
        'mcp',
      ]);
      addTearDown(process.kill);
      final client = MCPClient(Implementation(name: 'test', version: '0.0.0'));
      final server = client.connectServer(
        stdioChannel(input: process.stdout, output: process.stdin),
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
      expect(await process.exitCode.timeout(const Duration(seconds: 30)), 0);
    });
  });
}
