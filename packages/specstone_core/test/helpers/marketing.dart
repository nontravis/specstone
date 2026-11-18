import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';

import 'shipped_pins.dart';
import 'temp_tree.dart';

/// The `marketing` doc type ids, in code point order.
const marketingIds = <String>[
  'audience',
  'campaign',
  'campaign_results',
  'channel',
  'competitor',
  'content_pillars',
  'lifecycle',
  'loyalty',
  'messaging',
  'positioning',
  'voice',
];

/// Resolves a temp project that pins the shipped [packs].
///
/// Calls `writeTree`, so call it from a test or `setUpAll`.
Future<MergedSet> resolveMarketing([
  List<String> packs = const ['prd-core', 'marketing'],
]) async {
  final project = await writeTree({
    '.specstone/config.yaml': shippedPinsConfig(packs),
  });
  final home = await writeTree({});
  return TemplateResolver().resolve(
    workingDirectory: project,
    homeDirectory: home,
  );
}
