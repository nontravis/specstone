import 'dart:io';

import 'package:dart_mcp/stdio.dart';
import 'package:specstone/src/commands/specstone_command.dart';
import 'package:specstone/src/mcp/specstone_mcp_server.dart';

/// Runs the Specstone MCP server over stdio until the client disconnects.
class McpCommand extends SpecstoneCommand {
  @override
  String get name => 'mcp';

  @override
  String get description => 'Run the Specstone MCP server over stdio.';

  @override
  bool get takesArguments => false;

  @override
  Future<int> run() async {
    final server = SpecstoneMcpServer(
      stdioChannel(input: stdin, output: stdout),
    );
    await server.done;
    return 0;
  }
}
