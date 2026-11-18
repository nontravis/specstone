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

/// The path under `docs/` of the `campaign` doc the check tests write.
const campaignDocPath = 'specs/f01_login/CAMPAIGN.md';

/// Returns a `campaign` doc covering [covers]; no `covers` field when empty.
String campaignDocText([List<String> covers = const []]) {
  final coversField = covers.isEmpty
      ? ''
      : 'covers:\n${[for (final c in covers) '  - $c\n'].join()}';
  return '---\n$coversField---\n\n# Launch\n\n## Plan\n\nLaunch the product.\n';
}
