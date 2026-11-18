import 'dart:io';

import 'package:specstone_core/src/rendering/docs_project.dart';
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';

import 'shipped_pins.dart';
import 'temp_tree.dart';

/// The packs of a project whose skill docs take design-system docs.
const skillProjectPacks = <String>[
  'prd-core',
  'software-tech',
  'software-design-system',
  'agent-skills',
];

/// A temp project on [skillProjectPacks], opened for rendering.
final class SkillProject {
  new(this.root, this.project);

  /// The project root as written.
  final Directory root;

  /// The project opened with the shipped packs.
  final DocsProject project;

  /// Returns the file at [path], `/`-separated from the project root.
  File file(String path) => File('${root.path}/$path');

  /// Returns the text of the file at [path].
  String read(String path) => file(path).readAsStringSync();

  /// Resolves [path] as `format` does; null takes the docs root.
  Target target([String? path]) => project.resolveTarget(
    path,
    workingDirectory: root,
    defaultsToDocsRoot: true,
    includeRecordsRoot: true,
  );
}

/// Writes [files] into a temp project on [skillProjectPacks] and opens it.
///
/// Calls `writeTree`, so call it from a test.
Future<SkillProject> openSkillProject(Map<String, String> files) async {
  final root = await writeTree({
    '.specstone/config.yaml': shippedPinsConfig(skillProjectPacks),
    ...files,
  });
  return SkillProject(
    root,
    DocsProject.open(
      templates: TemplateResolver(),
      workingDirectory: root,
      homeDirectory: null,
    ),
  );
}

/// Returns a skill doc with [output] whose Sources section lists [sources],
/// each a markdown link.
String skillDocText({
  String output = '.claude/skills/review/',
  List<String> sources = const [],
}) =>
    '---\noutput: $output\ncovers:\n  - ${output}SKILL.md\n---\n\n'
    '# review\n\n## Purpose\n\nReviews the UI.\n\n'
    '## Sources\n\n${[for (final source in sources) '- $source\n'].join()}';

/// Resolves a temp project that pins the shipped `prd-core` and
/// `agent-skills`, plus any other shipped pack in [extraPacks].
///
/// Each [templates] entry lands at `.specstone/templates/<key>`. Calls
/// `writeTree`, so call it from a test or `setUpAll`.
Future<MergedSet> resolveAgentSkills({
  List<String> extraPacks = const [],
  Map<String, String> templates = const {},
}) async {
  final project = await writeTree({
    '.specstone/config.yaml': shippedPinsConfig([
      'prd-core',
      ...extraPacks,
      'agent-skills',
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
