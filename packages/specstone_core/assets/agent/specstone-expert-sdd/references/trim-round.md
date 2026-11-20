# Run a bootstrap round that trims

The main session's steps for a `specstone-bootstrap-prd` or `specstone-bootstrap-spec` round with a trim batch, a batch
holding a `retrim_due` finding, an FR trimmed past a cap, or a handed line (Handed lines). The skill that points here
says when each step runs and which skill's batch takes a handed line.

## Audit the round

Once the round's reports are shown, dispatch one fresh `specstone-sdd-auditor` as the skill's step 2 does, with every
draft of the round as its targets, `trims:` the round's bootstrap reports, no `check:`, since every check file
predates some write of the round, and `report:` `<folder>/reports/sdd-auditor.audit.<XXXXXX>.md`, a new name per
audit.

## Fix and audit again

Send the audit's findings to a bootstrap engineer as one fix batch, dispatched as the skill's step 2 does, with
`batch:` the finding lines. Then dispatch a fresh audit, never a resumed one, of each draft whose hash changed. Run
one such round; each line of that re-audit waits for the Owner.

## Approve

Follow `specstone-expert-sdd`'s "Get the drafts approved" with `--audit` per audit report of the round, oldest first,
in place of `--no-audit`: the trim-round case its item 1 names. A trim draft the call still asks goes to Owner
confirmation like any other.

## Handed lines

Each `Citers outside:` and `Spec moves:` line of the round's reports starts another round, sent with its batch's
`batch:`. A `Citers outside:` line goes to the batch of the doc it names: its feature folder's, else the rest batch. A
record's matrix row goes to that feature's spec batch. A `Spec moves:` line names a feature folder, not a doc: it goes
to that folder's spec batch. A line whose batch the other bootstrap skill runs waits on that skill.

## Before you stop

List each handed line still waiting under `Waits on specstone-bootstrap-spec:` or
`Waits on specstone-bootstrap-prd:`, the skill it waits on, with the report that names it. That skill's next round
sends each line with the batch Handed lines give.

When the run approved a trim and the project's `verification_coverage` is `fr` or `edge_case`, end the run by
following `specstone-sync-sdd` on the trimmed features. With the setting absent or `false`, no sync follows.
