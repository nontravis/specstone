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

/// The packs of a project that writes design-system docs.
const softwareDesignSystemPacks = <String>[
  'prd-core',
  'software-tech',
  'software-design-system',
];

/// The `config.yaml` text pinning [softwareDesignSystemPacks] to the shipped
/// versions.
String softwareDesignSystemConfig() =>
    shippedPinsConfig(softwareDesignSystemPacks);

/// Resolves a temp project that pins the shipped `prd-core`, `software-tech`,
/// and `software-design-system`.
///
/// Calls `writeTree`, so call it from a test or `setUpAll`.
Future<MergedSet> resolveSoftwareDesignSystem() async {
  final project = await writeTree({
    '.specstone/config.yaml': softwareDesignSystemConfig(),
  });
  final home = await writeTree({});
  return TemplateResolver().resolve(
    workingDirectory: project,
    homeDirectory: home,
  );
}
