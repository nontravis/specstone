import 'dart:io';

import 'package:specstone_core/src/consistency_check/mermaid_node_run.dart';
import 'package:test/test.dart';

/// The Node parse timeout for a suite that needs real Node answers: under the
/// 30 s test timeout, so a slow parse fails with its skip reason.
const coldHostNodeTimeout = Duration(seconds: 25);

/// Starts `node` once and waits for it to exit, so the host's cold first start
/// lands here, not in a timed parse; a host without `node` is left as it is.
Future<void> warmNode() async {
  try {
    await Process.run('node', ['-e', '0']);
  } on ProcessException {
    // A missing node is a case the suite's own tests cover.
  }
}

/// Warms `node` before the suite and gives every runner it builds without a
/// timeout [coldHostNodeTimeout], restoring the shipped default after.
void useColdHostNode() {
  final shipped = MermaidNodeRun.defaultTimeout;
  setUpAll(() async {
    MermaidNodeRun.defaultTimeout = coldHostNodeTimeout;
    await warmNode();
  });
  tearDownAll(() => MermaidNodeRun.defaultTimeout = shipped);
}
