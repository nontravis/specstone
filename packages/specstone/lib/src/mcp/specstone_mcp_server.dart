import 'package:dart_mcp/server.dart';
import 'package:specstone_core/specstone_core.dart';

/// The Specstone MCP server, served over stdio.
///
/// Registers no tools yet; `tools/list` answers empty until a later task
/// registers them.
base class SpecstoneMcpServer extends MCPServer with ToolsSupport {
  new(super.channel)
    : super.fromStreamChannel(
        implementation: Implementation(
          name: 'specstone',
          version: specstoneVersion,
        ),
      );
}
