# Fix a doc over its size limit

This covers the three size findings `specstone check` raises: `chars_over_limit`, `lines_over_limit`, and
`item_over_limit`. Cite a size only as `specstone structure <doc>` or `specstone check` prints it, never a count of
your own. Never cut meaning to pass a size.

## The order

1. **Layout.** Every write lays its doc out. A size finding still listed after your last write to that doc takes the
   next step.
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
- `item_over_limit`: the item takes its doc type's item shape in a bootstrap pass the Owner schedules.
