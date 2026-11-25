import 'dart:io';

import 'shipped_pins.dart';
import 'temp_tree.dart';

/// The DocPath of the grouped top feature `kitchen/recipes`.
const kitchenRecipes = 'prds/features/kitchen/f01_recipes/FEATURE.md';

/// The DocPath of the grouped top feature `kitchen/menus`.
const kitchenMenus = 'prds/features/kitchen/f02_menus/FEATURE.md';

/// The DocPath of the story `kitchen/recipes/add_dish`.
const kitchenAddDish =
    'prds/features/kitchen/f01_recipes/us01_add_dish/USER_STORY.md';

/// The DocPath of the architecture doc of `kitchen/recipes`.
const kitchenRecipesArchitecture = 'specs/kitchen/f01_recipes/ARCHITECTURE.md';

/// The doc types the stratum-ui project puts under a group folder: the PRD
/// ones on `prds/features/{slug}/f{nn}_{slug}/…`, the spec ones on
/// `specs/{slug}/f{nn}_{slug}/<FILE>.md`.
const _groupedPaths = {
  'feature': 'prds/features/{slug}/f{nn}_{slug}/FEATURE.md',
  'user_story': 'prds/features/{slug}/f{nn}_{slug}/us{nn}_{slug}/USER_STORY.md',
  'fr': 'prds/features/{slug}/f{nn}_{slug}/us{nn}_{slug}/fr{nn}_{slug}.md',
  'nf': 'prds/features/{slug}/f{nn}_{slug}/us{nn}_{slug}/nf{nn}_{slug}.md',
  'architecture': 'specs/{slug}/f{nn}_{slug}/ARCHITECTURE.md',
  'api': 'specs/{slug}/f{nn}_{slug}/API.md',
  'security': 'specs/{slug}/f{nn}_{slug}/SECURITY.md',
  'integration': 'specs/{slug}/f{nn}_{slug}/INTEGRATION.md',
  'implementation': 'specs/{slug}/f{nn}_{slug}/IMPLEMENTATION.md',
};

/// Returns the docs of the grouped project, keyed by path from the project
/// root: `kitchen/f01_recipes` with the story `us01_add_dish` and an
/// architecture doc, and `kitchen/f02_menus`.
Map<String, String> groupedFiles() => {
  '.specstone/config.yaml': shippedPinsConfig(),
  for (final MapEntry(:key, :value) in _groupedPaths.entries)
    '.specstone/templates/$key.yaml': 'path: $value\n',
  'docs/$kitchenRecipes': '# Recipes\n',
  'docs/$kitchenMenus': '# Menus\n',
  'docs/$kitchenAddDish': '# Add a dish\n',
  'docs/$kitchenRecipesArchitecture': '# Recipes architecture\n',
};

/// Writes the grouped project under a new temp folder.
///
/// A key in [extra] replaces or adds a file.
Future<Directory> writeGroupedProject({Map<String, String> extra = const {}}) =>
    writeTree({...groupedFiles(), ...extra});
