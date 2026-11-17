**Matrix rows** (step 4.5). A row finding is a `matrix_test_unresolved` finding, or a `suspect` or `unconfirmed` one with
`waitsFor` `agent`, on a line of a record's `verification_matrix` section. The finding's `line` is the row, and its text names the item,
the edge case, and the literal; a `matrix_test_unresolved` finding also holds the `item` and `name` keys. One with
`waitsFor` `owner` is not in your list: its FR is a pending draft.

Compare no code and run no `context --code` read. Re-read the row's edge case
(`specstone get <feature>/<item>#edge_cases`) and its test, in a file the item's `tests` lines name, then write the row
through
`specstone set implementation:<feature>#verification_matrix --target <name> --base <hash> --replace`, stdin holding
`==> old <==`, the old row, `==> new <==`, then the new row; the hash is the `base` of
`specstone get implementation:<feature>#verification_matrix`. That write marks no draft. To remove a row, send the row and
a blank line as the old passage and nothing after `==> new <==`.

- **`matrix_test_unresolved`, the test in the same file under a new name:** rewrite the literal to the test's current
  first literal; the row keeps its fingerprint.
- **The test in another file the item's `tests` lines name:** write the new literal and no fingerprint.
- **The test in none of those files:** leave the row as written and list it as waiting for its implementer.
- **A `suspect` row whose test proves a split ID of its edge case instead:** rewrite its edge case ID to the lowest split
  ID the test proves, keep its literal, drop its fingerprint, then stamp it; remove the row instead when a row of that
  item, ID, and literal stands. A test that also proves the row's own edge case keeps the row, restamped. List each
  other split ID the test proves as waiting for its implementer.
- **A test that proves none of the row's edge case:** write and stamp nothing; report the row under `Mismatches:` with
  the row, its edge case, and its literal, and list it as waiting for its implementer.

Then run `specstone check` and stamp: each row you wrote with no fingerprint, each `suspect` row, and each `unconfirmed`
row with `waitsFor` `agent` ends in its finding's `fingerprint`, written the same way, but only when the re-read showed
its test still proves its edge case. Never stamp a row whose `waitsFor` is `owner`; list it as waiting for its FR's
approval. Run `check` again until no `waitsFor` `agent` row finding is left on a row you wrote or stamped.

Name a waiting row by its item, edge case, and literal. Write no row for a test a change adds or moves: its implementer
writes it.
