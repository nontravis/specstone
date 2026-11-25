**Matrix rows** (procedure step 2).

- Mode: top-level `verification_coverage` of `.specstone/config.yaml`: off (absent, null, `false`), `fr` (`true`, `fr`), or `edge_case`.
- Off and `fr` read per-FR rows, ``- <item>: `<literal>`[, `<literal>` ...][ <fingerprint>]``; `edge_case` per-edge-case rows, ``- <item> <edge case>: `<literal>`[ <fingerprint>]``.
- The group file prints each row to judge with its FR's current contract text, each literal with its test file and line, and the FR or edge-case fingerprint a `match` line copies.
- Judge from it and the tests at those lines; compare no code.
- Leave a `waitsFor` `owner` row as written: a pending FR draft, or a per-edge-case row under off or `fr`, which only the Owner's `specstone migrate` folds.

## Lines

- Write a row by `row <record> <item>[ <edge case>]: <sign><literal>[ <sign><literal>]…`: `+` adds a literal and `-` removes one, each `<literal>` in one code span, copied from the test file as it stands, its first literal when the name is split, interpolations kept; it holds no fingerprint.
- Stamp a row by `match <record> <item>[ <edge case>] <fingerprint>`; for a row a `row` line writes, put its `match` line after that `row` line, with the fingerprint the group file prints for the row's FR or edge case.
- Stamp only when its tests still prove the upstream block: under `fr` the FR's contract, under `edge_case` its edge case; under off, stamp no row.
- Never stamp a row whose FR is `draft: true`; list it waiting for the FR's approval.
- Write no row for a new test; its implementer does.

## By case

- **Declared row**, a pre-filled `match` line: keep it, with no re-read.
- **`suspect` row whose tests prove its block:** replace its `?` with `match`.
- **Tests proving none of the change:** replace its `?` with `mismatch <record> <item>[ <edge case>]: <point>`, naming its literals; list it waiting for its implementer.
- **`matrix_test_unresolved`, test renamed or moved into a file the item's `tests` lines name:** keep or edit the pre-filled `row` line; off or `fr` keep the row's fingerprint, and under `edge_case` a `match` line follows it.
- **Test in no such file:** delete the pre-filled `row` line; list the row waiting for its implementer.
- **`edge_case` alone, a `suspect` row whose test proves a split ID instead:** in place of its `?` line, write `row <record> <item> <edge case>: -<literal>`, then `row <record> <item> <split ID>: +<literal>` for the lowest proven split ID and its `match` line; when a row of that split ID and literal stands, only the `-` line.
- A test also proving the row's own edge case keeps it, stamped by `match`; list other proven split IDs waiting for the implementer.
- Under `fr`, a split moves no row: stamp or report the FR's row as above.
- **`edge_case`, a per-FR row's `matrix_row_malformed`:** read the FR's edge cases the group file prints and each literal's test; per edge case a literal's test proves, write `row <record> <item> <edge case>: +<literal>` and its `match` line.
- A literal proving none: a `mismatch` line naming row, FR, and literal; once each literal is placed or reported, one `row <record> <item>: -<literal> …` line removes the per-FR row.
- Name a waiting row by item, edge case under `edge_case`, and literals.
