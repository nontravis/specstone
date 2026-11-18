import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';

import 'shipped_pins.dart';
import 'temp_tree.dart';

/// The `software-design-system` doc type ids, in code point order.
const softwareDesignSystemIds = <String>[
  'accessibility',
  'color',
  'component',
  'component_group',
  'content',
  'contributing',
  'discovery',
  'elevation',
  'guidelines',
  'icon',
  'layout',
  'motion',
  'setup',
  'shape',
  'spacing',
  'theme',
  'tokens',
  'typography',
  'ui_pattern',
];

/// Resolves a temp project that pins the shipped `prd-core`, `software-tech`,
/// and `software-design-system`.
///
/// Each [templates] entry lands at `.specstone/templates/<key>`. Calls
/// `writeTree`, so call it from a test or `setUpAll`.
Future<MergedSet> resolveSoftwareDesignSystem({
  Map<String, String> templates = const {},
}) async {
  final project = await writeTree({
    '.specstone/config.yaml': shippedPinsConfig([
      'prd-core',
      'software-tech',
      'software-design-system',
    ]),
    for (final MapEntry(:key, :value) in templates.entries)
      '.specstone/templates/$key': value,
  });
  final home = await writeTree({});
  return TemplateResolver().resolve(
    workingDirectory: project,
    homeDirectory: home,
  );
}
