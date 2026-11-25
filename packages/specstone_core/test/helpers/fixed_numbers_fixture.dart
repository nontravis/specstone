/// The DocPath of the first fixture decision.
const firstDecision = 'specs/decisions/d01_adopt_sqlite.md';

/// The DocPath of the second fixture decision.
const secondDecision = 'specs/decisions/d02_use_wal.md';

/// The project layer of a numbered doc type whose numbers never change.
///
/// It has no parent and no `per_target` key, so a doc lives in the one
/// `specs/decisions/` folder whatever the code targets.
const decisionLayerFile = '.specstone/templates/decision.yaml';

/// The text of [decisionLayerFile].
const decisionLayer =
    'id: decision\n'
    'description: A fixture decision\n'
    'path: specs/decisions/d{nn}_{slug}.md\n'
    'fixed_numbers: true\n';

/// Returns the files that add the fixture `decision` type and its first two
/// docs to a project.
Map<String, String> decisionFiles() => {
  decisionLayerFile: decisionLayer,
  'docs/$firstDecision': '# Adopt SQLite\n',
  'docs/$secondDecision': '# Use WAL\n',
};
