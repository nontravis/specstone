import 'package:dart_mcp/client.dart';
import 'package:specstone/src/mcp/specstone_mcp_server.dart';
import 'package:specstone_core/specstone_core.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';

void main() {
  group('SpecstoneMcpServer', () {
    late MCPClient client;
    late ServerConnection server;

    setUp(() {
      final channel = StreamChannelController<String>();
      SpecstoneMcpServer(channel.local);
      client = MCPClient(Implementation(name: 'test', version: '0.0.0'));
      server = client.connectServer(channel.foreign);
    });

    tearDown(() => client.shutdown());

    test('completes initialize and lists zero tools', () async {
      final result = await server.initialize(
        InitializeRequest(
          protocolVersion: ProtocolVersion.latestSupported,
          capabilities: client.capabilities,
          clientInfo: client.implementation,
        ),
      );
      server.notifyInitialized();
      final tools = await server.listTools(ListToolsRequest());

      expect(result.serverInfo.name, 'specstone');
      expect(result.serverInfo.version, specstoneVersion);
      expect(result.capabilities.tools, isNotNull);
      expect(tools.tools, isEmpty);
    });
  });
}
