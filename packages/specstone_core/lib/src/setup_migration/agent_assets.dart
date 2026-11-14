import 'dart:convert';

import 'package:specstone_core/src/setup_migration/agent_text.g.dart';

/// One embedded skill or agent file: its `path` under `assets/agent/`, with
/// `/` separators, and its LF `text`.
typedef AgentAsset = ({String path, String text});

/// Returns every embedded skill and agent file, sorted by path.
List<AgentAsset> shippedAgentAssets() {
  final paths = agentAssetsBase64.keys.toList()..sort();
  return [
    for (final path in paths)
      (path: path, text: utf8.decode(base64Decode(agentAssetsBase64[path]!))),
  ];
}
