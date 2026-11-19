# Traced and cited links

The steps of `specstone-expert-sdd`'s rule 4, and what rule 7's cite links do.

Each `check` here saves to its own file: `<role>` is your caller's role, `<folder>` and `XXXXXX` the project gate's.
Search it for the target's lines, never read it whole.

## Traced links (rule 4)

When you write an FR (`fr`), an nf (`nf`), or an API row (`api`), record its `confirmed` entries: run
`specstone check <target> --out "<folder>/reports/check.<role>.<XXXXXX>.txt"` to save each link it traces, its upstream
block, then its fingerprint; read the block, then write the entries with
`specstone set <target> --field confirmed --base <hash>`. Take `<hash>` from `bases.fields.confirmed` in
`specstone get <target> --json`, never from a fingerprint `check` prints.

A `suspect` link's upstream block moved on since the entry was recorded: re-read it and confirm again the same way.
Your approval request to the Owner then says what changed upstream.
Under the `auto` mode, the approved list of `approve-mode.md` names the upstream change.

## Override lines (rule 4)

With each `Overrides:` line you write in a spec doc, record its `overrides` entry: one per overridden item, written
`<doc type>:<name>#<ID> <fingerprint>`. Run
`specstone check <target> --out "<folder>/reports/check.<role>.<XXXXXX>.txt"` to save each fingerprint, then write the
entries with `specstone set <target> --field overrides --base <hash>`, as you write `confirmed` entries. Take `<hash>`
from `bases.fields.overrides` in `specstone get <target> --json`. Until the entry matches, `check` reports the line
`unconfirmed`; in a draft the line stays `unconfirmed` even when the entry matches, and waits for the Owner's approval.

## Cited links (rule 7)

`specstone refs <owner>` lists each doc that cites it by a link, and `specstone context` follows the link, but a
citation pins no hash: it never turns `suspect` when the owner changes, and takes no `confirmed` entry.
