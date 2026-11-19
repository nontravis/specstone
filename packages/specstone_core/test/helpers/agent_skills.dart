import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';

import 'shipped_pins.dart';
import 'temp_tree.dart';

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
