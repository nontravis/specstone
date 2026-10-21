import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dart_mcp/stdio.dart';
import 'package:specstone/src/mcp/specstone_mcp_server.dart';

/// Runs the Specstone MCP server over stdio until the client disconnects.
class McpCommand extends Command<int> {
  @override
  String get name => 'mcp';

  @override
  String get description => 'Run the Specstone MCP server over stdio.';

  @override
  Future<int> run() async {
    final server = SpecstoneMcpServer(
      stdioChannel(input: stdin, output: stdout),
    );
    await server.done;
    return 0;
  }
}
