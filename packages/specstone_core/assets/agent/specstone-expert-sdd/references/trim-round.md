# Run a bootstrap round that trims

Main's steps for a `specstone-bootstrap-prd` or `specstone-bootstrap-spec` round with a trim batch, a `retrim_due`
finding, an FR trimmed past a cap, or a handed line.

## Audit the round

- Once the round's reports are shown, dispatch one fresh `specstone-sdd-auditor` as the skill's step 2 does, every
  draft of the round its targets, `trims:` the round's bootstrap reports, no `check:`, and `report:`
  `<folder>/reports/sdd-auditor.audit.<XXXXXX>.md`, a new name per audit.

## Fix and audit again

- Send the audit's findings to a bootstrap engineer as one fix batch, dispatched as step 2 does, `batch:` the finding
  lines.
- Then dispatch a fresh audit, never a resumed one, of each draft whose hash changed.
- Run one such round; each line of that re-audit waits for the Owner.

## Approve

- Follow `specstone-expert-sdd`'s "Get the drafts approved" with `--audit` per audit report of the round, oldest
  first, in place of `--no-audit`.
- A trim draft the call still asks goes to Owner confirmation.

## Handed lines

- Each `Citers outside:` and `Spec moves:` line of the round's reports starts another round, sent with its batch's
  `batch:`.
- A `Citers outside:` line goes to its doc's feature folder batch, else the rest batch; a record's matrix row to that
  feature's spec batch.
- A `Spec moves:` line names a feature folder, not a doc: it goes to that folder's spec batch.
- A line whose batch the other bootstrap skill runs waits on that skill.

## Before you stop

- List each waiting handed line under `Waits on specstone-bootstrap-spec:` or `Waits on specstone-bootstrap-prd:`,
  with the report that names it; that skill's next round sends it with the batch Handed lines give.
- A run that approved a trim, with `verification_coverage` `fr` or `edge_case`: end by following
  `specstone-sync-sdd` on the trimmed features; absent or `false`, no sync.
