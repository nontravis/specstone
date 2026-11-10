# Confirm traced links

The steps of `specstone:expert-sdd`'s rule 4.

When you write an FR (`fr`), an nf (`nf`), or an API row (`api`), record its `confirmed` entries: run
`specstone check <target>` to print each link it traces, its upstream block, then its fingerprint; read the block,
then write the entries with `specstone set <target> --field confirmed --base <hash>`. Take `<hash>` from
`bases.fields.confirmed` in `specstone get <target> --json`, never from a fingerprint `check` prints.

A `suspect` link's upstream block moved on since the entry was recorded: re-read it and confirm again the same way.
Your approval request to the Owner then says what changed upstream.
