# Run a bootstrap round that trims

Main's steps for a `specstone-bootstrap-prd` or `specstone-bootstrap-spec` round with a trim batch, a `retrim_due`
or `code_blocks_over_limit` finding, an FR trimmed past a cap, or a handed line.

## Audit the round

- Apply each keep plan file a report names with one `specstone move --plan-file "<file>"`, no Owner ok, before the
  audit.
- Once the round's reports are shown, dispatch one fresh `specstone-sdd-auditor` as the skill's step 2 does,
  `job: trim-audit`, every draft of the round its `targets:`, `trims:` the round's bootstrap reports, and `report:`
  `<folder>/reports/sdd-auditor.audit.<XXXXXX>.md`, a new name per audit.
- Send the audit's `Findings:` items into the fix loop of `fix-loop.md`, each writer the bootstrap engineer of the batch
  that wrote the draft it names.

## Approve

- Once the fix loop ends, follow `approve.md` with `--audit` per audit report of the round, in place of `--no-audit`.
- A trim draft the call still asks goes to Owner confirmation.

## Handed lines

- Each `Citers outside:` line of the round's reports starts another round, sent with its batch's `batch:`.
- Each `Outside the drafts:` item of the trim audit goes to the next round as a `Citers outside:` line, and
  `approve.md` names its lead name on a `Queued:` line.
- So does each item the fix loop hands on, an `Outside the round:` item or a finding on a doc outside every writer's
  drafts: as a `Citers outside:` line it makes its batch a trim batch, with its own trim audit and loop.
- A `Citers outside:` line goes to its doc's feature folder batch, else the rest batch; a record's matrix row to that
  feature's spec batch.
- A line whose batch the other bootstrap skill runs waits on that skill.

## Before you stop

- List each waiting handed line under `Waits on specstone-bootstrap-spec:` or `Waits on specstone-bootstrap-prd:`,
  with the report that names it; that skill's next round sends it with the batch Handed lines give.
- A run that approved a trim, with `verification_coverage` `fr` or `edge_case`: end by following
  `specstone-sync-sdd` on the trimmed features; absent or `false`, no sync.
