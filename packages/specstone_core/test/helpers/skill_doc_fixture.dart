import 'shipped_pins.dart';

/// The DocPath of the fixture skill doc.
const skillDoc = 'specs/skills/review.md';

/// The fixture skill's `SKILL.md`, as a path from the project root.
const skillFile = '.claude/skills/review/SKILL.md';

/// The text of the fixture skill's `SKILL.md`.
const skillText = '# Review\n\nReview the diff.\n';

/// The `config.yaml` text pinning the check fixture's packs and
/// `agent-skills`.
String skillPinsConfig() =>
    shippedPinsConfig(['prd-core', 'software-tech', 'agent-skills']);

/// Returns the fixture skill doc, keyed by its path from the project root,
/// its `covers:` holding one line per entry of [covers].
Map<String, String> skillDocFile(List<String> covers) => {
  'docs/$skillDoc':
      '---\noutput: .claude/skills/review/\ncovers:\n'
      '${[for (final entry in covers) '  - $entry\n'].join()}---\n\n'
      '# review\n\n## Purpose\n\nReviews a diff.\n\n'
      '## When to use\n\n- A diff to review.\n\n'
      '## Sources\n\n- [Login](../../prds/features/f01_login/FEATURE.md)\n',
};
