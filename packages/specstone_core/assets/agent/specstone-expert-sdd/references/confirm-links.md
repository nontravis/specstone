# Traced and cited links

Rule 4 and rule 7 of `specstone-expert-sdd`. Save each `check` here to its own file, searched, never read whole:
`<role>` your caller's role, `<folder>` and `XXXXXX` the project gate's.

## Traced links (rule 4)

- Writing a doc whose type carries the `confirmed` field, which `specstone guide <type> --json` shows: run
  `specstone check <target> --out "<folder>/reports/check.<role>.<XXXXXX>.txt"` to save each traced link's upstream
  block and fingerprint.
- Read the block, then write the `confirmed` entries with `specstone set <target> --field confirmed --base <hash>`.
- Take `<hash>` from `bases.fields.confirmed` of `specstone get <target> --json`, never from a `check` fingerprint.
- A `suspect` link: re-read its upstream block and confirm again the same way.
- Say in the approval request what changed upstream; under `auto`, the approved list names it.

## Override lines (rule 4)

- Record one `overrides` entry per item each `Overrides:` line overrides: `<doc type>:<name>#<ID> <fingerprint>`.
- Run the same `check --out` for each fingerprint, then write
  `specstone set <target> --field overrides --base <hash>`, `<hash>` from `bases.fields.overrides` of
  `specstone get <target> --json`.
- Until the entry matches, `check` reports the line `unconfirmed`; in a draft it stays `unconfirmed` and waits for the
  Owner's approval.

## Cited links (rule 7)

- Link form: `[<ID>](<path>#<section heading anchor>)`.
- `check` reports an old cite form as `cite_unlinked`, a link to an item its section lacks as `link_item_missing`.
- A citation pins no hash: it never turns `suspect` and takes no `confirmed` entry; `specstone refs <owner>` lists
  its citers.
