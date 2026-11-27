# Write a doc through the CLI

Rules 2 and 3 of `specstone-expert-sdd`.

## Writes (rule 2)

- Each write leaves a draft, a pointer write (`implements`, `covers`) excepted; never remove `draft: true`.
- Take bases from `specstone get <type>:<name> --json` (`docs[0].bases.title`, `docs[0].bases.sections.<key>`,
  `docs[0].bases.fields.<id>`); each write prints the new one.
- Pipe text to `specstone set <type>:<name>#<key> --base <hash>`, with `--field <id>` or `--title` for `#<key>`.
- A passage: `--replace` with `==> old <==`, the passage, `==> new <==`, the new one.
- Omit a section body's `## ` line; give a list field its whole list; empty text drops the section or key.
- Text between the title and the first `##` is `#_lead`.
- Exit 75 `base_mismatch`: read again, merge, retry.
- Quote a node label holding `(`, `)`, `[`, `]`, `{`, or `}`; write `"` in it as `#quot;`.

## Guide (rule 3)

- One call naming several types, or this run's saved guide, counts.

## Code target (rule 2)

- With two or more code targets, `new`, `get`, `set` (`confirmed` too), `structure <doc>`, and `refs <owner>` take the
  loading surface's `--target`, never an Owner question; `approve` and `delete` take none.

## Feature record (rule 2)

- Write a feature's record at `<doc type>:<name>` from its bundle naming line `<name> (<doc type>)`, the line whose
  path sits under `.specstone/records/`, never at a type of your own, since the feature's other spec docs share its
  name.
- With no saved bundle holding that naming line, first run one `specstone context <story> --for implement --out` on a
  story of that feature, with the code target the write takes.

## Feature patterns (rule 2)

- For a new feature, pick its patterns with `specstone guide --pattern`; cover each checklist item or list it as a
  skip line in Out-of-scope.
