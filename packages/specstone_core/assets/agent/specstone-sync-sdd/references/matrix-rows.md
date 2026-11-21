**Matrix rows** (step 4.5).

- Mode: top-level `verification_coverage` of `.specstone/config.yaml`: off (absent, null, `false`), `fr` (`true`, `fr`), or `edge_case`.
- Off and `fr` read per-FR rows, ``- <item>: `<literal>`[, `<literal>` ...][ <fingerprint>]``; `edge_case` per-edge-case rows, ``- <item> <edge case>: `<literal>`[ <fingerprint>]``.
- A skip row holds `skipped: <reason>` after its label.
- Row finding, on a record's `verification_matrix` line: `matrix_test_unresolved`, `suspect` or `unconfirmed` with `waitsFor` `agent`, or, under `edge_case`, a per-FR row's `matrix_row_malformed`.
- Its `line` is the row; `matrix_test_unresolved` also holds `item` and `name`, the unresolved literal.
- Leave a `waitsFor` `owner` row as written: a pending FR draft, or a per-edge-case row under off or `fr`, which only the Owner's `specstone migrate` folds.

## Re-read, then write

- Compare no code, run no `context --code`; re-read the upstream block and its tests in files the item's `tests` lines name.
- Block: under `fr` the FR's contract (`specstone get <feature>/<item>#statement <feature>/<item>#input_output <feature>/<item>#edge_cases`), under `edge_case` its edge case (`specstone get <feature>/<item>#edge_cases`), under off none.
- Write by `specstone set implementation:<feature>#verification_matrix --target <name> --base <hash> --replace`, stdin `==> old <==`, old row, `==> new <==`, new row.
- Hash: `base` of `specstone get implementation:<feature>#verification_matrix`; the write marks no draft.
- Remove a row: the row and a blank line as old passage, nothing after `==> new <==`.

## By case

- **`matrix_test_unresolved`, test renamed in its file:** rewrite the literal to the test's current first literal; keep the fingerprint.
- **Test in another `tests` file of the item:** rewrite the literal; off or `fr` keep the fingerprint, `edge_case` drop it.
- **Test in none:** leave the row; list it waiting for its implementer.
- **`edge_case` alone, a `suspect` row whose test proves a split ID instead:** rewrite its ID to the lowest proven split ID, keep the literal, drop the fingerprint, stamp; remove it if a row of that item, ID, and literal stands.
- A test also proving the row's own edge case keeps it, restamped; list other proven split IDs waiting for the implementer.
- Under `fr` a split moves no row: stamp or report the FR's row as below.
- **`edge_case`, a per-FR row's `matrix_row_malformed`:** re-read the FR's edge cases and each literal's test; write one row ``- <item> <edge case>: `<literal>` ``, no fingerprint, per proven edge case.
- A literal proving none: report under `Mismatches:` with row, FR, literal; once each literal is placed or reported, remove the per-FR row.
- **Tests proving none of the change** (FR contract under `fr`, edge case under `edge_case`): write and stamp nothing; report under `Mismatches:` with row, FR or edge case, literals; list it waiting for its implementer.

## Stamp

- Stamp a row by the `--replace` write, never `set --stamp` (code links only); under off, stamp no row.
- Under `fr` or `edge_case`, run `specstone check --out "<folder>/reports/check.sync.<XXXXXX>.txt"`; end each row you wrote unstamped, each `suspect` row, and each `waitsFor` `agent` `unconfirmed` row in its finding's `fingerprint`, by the same write.
- Stamp only when the re-read showed its tests still prove the block.
- Never stamp a row whose FR is `draft: true`; list it waiting for the FR's approval.
- Rerun `check` until no `waitsFor` `agent` row finding is left on a row you wrote or stamped.
- Name a waiting row by item, edge case under `edge_case`, and literals.
- Write no row for a new test; its implementer does.
