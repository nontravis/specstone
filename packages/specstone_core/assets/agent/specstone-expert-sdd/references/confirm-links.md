# Traced and cited links

The steps of `specstone-expert-sdd`'s rule 4, and what rule 7's cite links do.

## Traced links (rule 4)

When you write an FR (`fr`), an nf (`nf`), or an API row (`api`), record its `confirmed` entries: run
`specstone check <target>` to print each link it traces, its upstream block, then its fingerprint; read the block,
then write the entries with `specstone set <target> --field confirmed --base <hash>`. Take `<hash>` from
`bases.fields.confirmed` in `specstone get <target> --json`, never from a fingerprint `check` prints.

A `suspect` link's upstream block moved on since the entry was recorded: re-read it and confirm again the same way.
Your approval request to the Owner then says what changed upstream.
Under the `auto` mode, the approved list of `approve-mode.md` names the upstream change.

## Cited links (rule 7)

`specstone refs <owner>` lists each doc that cites it by a link, and `specstone context` follows the link, but a
citation pins no hash: it never turns `suspect` when the owner changes, and takes no `confirmed` entry.
