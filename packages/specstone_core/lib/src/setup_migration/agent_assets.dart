import 'dart:convert';

import 'package:specstone_core/src/setup_migration/agent_text.g.dart';
import 'package:specstone_core/src/setup_migration/models/agent_asset.dart';

/// Returns every embedded skill and agent file, sorted by path.
List<AgentAsset> shippedAgentAssets() {
  final paths = agentAssetsBase64.keys.toList()..sort();
  return [
    for (final path in paths)
      AgentAsset(
        path: path,
        text: utf8.decode(base64Decode(agentAssetsBase64[path]!)),
      ),
  ];
}
