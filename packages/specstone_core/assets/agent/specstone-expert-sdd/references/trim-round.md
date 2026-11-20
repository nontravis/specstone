# Run a bootstrap round that trims

The main session's steps for a `specstone-bootstrap-prd` or `specstone-bootstrap-spec` round with a trim batch, a batch
holding a `retrim_due` finding or an FR trimmed past a cap. The skill that points here says when each step runs and
which skill's batch takes a handed line.

## Audit the round

Once the round's reports are shown, dispatch one fresh `specstone-sdd-engineer` as the skill's step 2 does, with
`mode: audit`, every draft of the round as its targets, `trims:` the round's bootstrap reports, `check:` the latest
check file, and `report:` `<folder>/reports/sdd-engineer.audit.<XXXXXX>.md`, a new name per audit.

## Fix and audit again

Send the audit's findings to a bootstrap engineer as a fix batch, dispatched as the skill's step 2 does, with
`batch:` the finding lines. Then dispatch a fresh audit, never a resumed one, of each draft whose hash changed. Run two
such rounds at most; a finding still left waits for the Owner.

## Approve

Follow `specstone-expert-sdd`'s "Get the drafts approved" with `--audit` per audit report of the round, oldest first,
in place of `--no-audit`: the trim-round case its item 1 names. A trim draft the call still asks goes to Owner
confirmation like any other.

## Handed lines

Each `Citers outside:` and `Spec moves:` line of the round's reports starts another round, in the batch of the feature
folder that holds its doc, sent with that batch's `batch:`. A record's matrix row goes to that feature's spec batch.

## Sync after the run

When the run approved a trim and the project's `verification_coverage` is `fr` or `edge_case`, end the run by
following `specstone-sync-sdd` on the trimmed features. With the setting absent or `false`, no sync follows.
