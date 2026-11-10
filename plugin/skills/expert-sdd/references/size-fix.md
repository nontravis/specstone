# Fix a doc over its size limit

This covers the three size findings `specstone check` raises, `chars_over_limit`, `lines_over_limit`, and
`item_over_limit`, under `specstone:expert-sdd`'s rule 5.

## The order

Answer each `chars_over_limit` or `lines_over_limit` finding once in your report, though `check` tags it
`(waits for the Owner)`: a split proposal, or why none applies. Give `item_over_limit` neither; the last section
covers it.

1. **Layout.** Every write lays its doc out. A size finding `check` still lists takes the next step; `check` counts
   the laid-out doc.
2. **Split.** `chars_over_limit` or `lines_over_limit` on a feature of 4 stories or more: propose a sub-feature
   split, as below. `item_over_limit` skips this step: a split never shrinks one item.
3. **Text to its home.** After an approved split, the next round fills each new feature draft and moves each spec
   doc's text to its sub-feature's spec doc. Without a split, text moves only as the Owner picks.

## The split proposal

Group the feature's stories into sub-features by the placement questions `specstone guide feature` prints: at least 2
sub-features of at least 2 stories each. Name each sub-feature's slug and its stories, then the ready commands in run
order, one `new` per sub-feature, then one `move` per sub-feature:

```
specstone new feature --parent <feature> --slug <slug>
specstone move <story> … --under <sub-feature>
```

Run none of them before the Owner's ok, and then in that order. A dispatched agent runs none: its report holds them
for the main session. A split the Owner turns down leaves nothing to delete.

## No split applies

Say why in your report and leave the finding as it is: it waits for the Owner.

- A feature of fewer than 4 stories, since a split needs at least 2 sub-features of at least 2 stories each, and a
  feature holds stories or sub-features, never both; or a top doc, such as `gnfr`: the Owner picks text moved to its
  home or the doc type's limit raised in the project's templates.

## An item over its limit

Only a bootstrap run the Owner started naming `item_over_limit` fixes it; a dispatched agent sees the name in
`batch:`. That run rewrites the item in its doc type's item shape, as `specstone guide <type>` gives it:

- one rule per ID: each rule split off takes the next free ID of its section;
- a bound stays in its rule;
- its mechanics, known limits, and trace move to the homes the guide names;
- no statement is dropped.

Anywhere else, leave the finding as it is: it waits for the Owner. A bootstrap report lists it under
`Waits on the Owner:` until a run names `item_over_limit`.
