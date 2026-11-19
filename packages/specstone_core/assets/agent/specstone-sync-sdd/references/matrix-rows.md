**Matrix rows** (step 4.5). First read the mode, the top-level `verification_coverage` of `.specstone/config.yaml`:
off (absent, null, or `false`), `fr` (`true` or `fr`), or `edge_case`. Off and `fr` read per-FR rows,
``- <item>: `<literal>`[, `<literal>` ...][ <fingerprint>]``; `edge_case` reads per-edge-case rows,
``- <item> <edge case>: `<literal>`[ <fingerprint>]``. A skip row holds `skipped: <reason>` after its label.

A row finding sits on a line of a record's `verification_matrix` section: a `matrix_test_unresolved` finding, a
`suspect` or `unconfirmed` one with `waitsFor` `agent`, or, under `edge_case`, a per-FR row's `matrix_row_malformed`
(`per-FR row under verification_coverage edge_case`). The finding's `line` is the row; a `matrix_test_unresolved`
finding also holds the `item` key and the `name` key, the literal that does not resolve. One with `waitsFor` `owner`
is not in your list: its FR is a pending draft, or it is a per-edge-case row under off or `fr`, which only the Owner's
`specstone migrate` folds. Leave that row as written.

Compare no code and run no `context --code` read. Re-read the row's upstream block and its tests, in a file the item's
`tests` lines name. The block is the FR's contract under `fr`
(`specstone get <feature>/<item>#statement <feature>/<item>#input_output <feature>/<item>#edge_cases`) and its edge
case under `edge_case` (`specstone get <feature>/<item>#edge_cases`); under off a row has none. Then write the row
through
`specstone set implementation:<feature>#verification_matrix --target <name> --base <hash> --replace`, stdin holding
`==> old <==`, the old row, `==> new <==`, then the new row; the hash is the `base` of
`specstone get implementation:<feature>#verification_matrix`. That write marks no draft. To remove a row, send the row and
a blank line as the old passage and nothing after `==> new <==`.

- **`matrix_test_unresolved`, the test in the same file under a new name:** rewrite that literal to the test's current
  first literal; the row keeps its fingerprint.
- **The test in another file the item's `tests` lines name:** rewrite that literal. Under off or `fr` the row keeps its
  fingerprint; under `edge_case` write it with no fingerprint.
- **The test in none of those files:** leave the row as written and list it as waiting for its implementer.
- **Under `edge_case` alone, a `suspect` row whose test proves a split ID of its edge case instead:** rewrite its edge
  case ID to the lowest split ID the test proves, keep its literal, drop its fingerprint, then stamp it; remove the row
  instead when a row of that item, ID, and literal stands. A test that also proves the row's own edge case keeps the
  row, restamped. List each other split ID the test proves as waiting for its implementer. Under `fr` a split moves no
  row: the FR's row is stamped or reported as below.
- **Under `edge_case`, a per-FR row's `matrix_row_malformed`:** re-read the FR's edge cases and each literal's test.
  Write one row ``- <item> <edge case>: `<literal>` ``, with no fingerprint, per edge case each literal's test proves.
  Report a literal whose test proves none of them under `Mismatches:` with the row, the FR, and the literal. Once each
  literal is placed or reported, remove the per-FR row.
- **Tests that prove none of what changed** (the FR's contract under `fr`, its edge case under `edge_case`): write and
  stamp nothing, so the row stays as written; report it under `Mismatches:` with the row, its FR or edge case, and its
  literals, and list it as waiting for its implementer.

Stamp a row by the `--replace` write above, never `set --stamp`, which stamps code links only. Under off, stamp no
row. Under `fr` or `edge_case`, run `specstone check --out "<folder>/reports/check.sync.<XXXXXX>.txt"`
and stamp: each row you wrote with no fingerprint, each `suspect` row, and each `unconfirmed` row with `waitsFor`
`agent` ends in its finding's `fingerprint`, found by searching that file and written the same way, but only when the
re-read showed its tests still prove its upstream block. Never stamp a row whose FR carries `draft: true`, its
`waitsFor` `owner`; list it as waiting for its FR's approval. Run `check` again, searching its file, until no
`waitsFor` `agent` row finding is left on a row you wrote or stamped.

Name a waiting row by its item, its edge case under `edge_case`, and its literals. Write no row for a new test: its
implementer writes it.
