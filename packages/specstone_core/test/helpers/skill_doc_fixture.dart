import 'shipped_pins.dart';

/// The DocPath of the fixture skill doc.
const skillDoc = 'specs/skills/review.md';

/// The fixture skill's `SKILL.md`, as a path from the project root.
const skillFile = '.claude/skills/review/SKILL.md';

/// The text of the fixture skill's `SKILL.md`.
const skillText = '# Review\n\nReview the diff.\n';

/// The DocPath of the fixture agent doc.
const agentDoc = 'specs/agents/reviewer.md';

/// The fixture agent's file, as a path from the project root.
const agentFile = '.claude/agents/reviewer.md';

/// The text of the fixture agent's file.
const agentText = '# Reviewer\n\nReview the diff.\n';

/// The `config.yaml` text pinning the check fixture's packs and
/// `agent-skills`.
String skillPinsConfig() =>
    shippedPinsConfig(['prd-core', 'software-tech', 'agent-skills']);

/// Returns the fixture skill doc, keyed by its path from the project root,
/// its `covers:` holding one line per entry of [covers].
Map<String, String> skillDocFile(List<String> covers) => {
  'docs/$skillDoc':
      '---\ncovers:\n'
      '${[for (final entry in covers) '  - $entry\n'].join()}---\n\n'
      '# review\n\n## Purpose\n\nReviews a diff.\n\n'
      '## When to use\n\n- A diff to review.\n\n'
      '## Boundaries\n\n- Never edits the diff.\n\n'
      '## Acceptance\n\n- A diff with one fault: the report names it.\n',
};

/// Returns the fixture agent doc, keyed by its path from the project root,
/// its `covers:` holding one line per entry of [covers].
Map<String, String> agentDocFile(List<String> covers) => {
  'docs/$agentDoc':
      '---\ncovers:\n'
      '${[for (final entry in covers) '  - $entry\n'].join()}---\n\n'
      '# reviewer\n\n## Role\n\nReviews a diff.\n\n'
      '## Dispatch trigger\n\n- A diff to review.\n\n'
      '## Brief inputs\n\n- The diff, required.\n\n'
      '## Report shape\n\n- A list of faults.\n\n'
      '## Boundaries\n\n- Read-only outside the report file.\n\n'
      '## Acceptance\n\n- A diff with one fault: the report names it.\n',
};
