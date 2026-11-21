# Fix a doc over its size limit

## The order

- Answer each `chars_over_limit`, `lines_over_limit`, `subsections_over_limit`, and FR edge-case
  `item_count_out_of_range` once in your report, though tagged `(waits for the Owner)`: a split proposal, or why none.
- Give `item_over_limit` neither: `An item over its limit` covers it.
- A `bundle_over_limit` or `subsections_over_limit` skips steps 1 to 4: its own section, then step 5 per moved item.

1. **Layout.** Every write lays its doc out; a size finding `check` still lists takes the next step.
2. **Trim.** An `item_count_out_of_range` on an FR's edge cases, or a `chars_over_limit` on an FR: trim its edge
   cases by `trim.md` first; what stays over takes the new FRs of `A finding that names items to move`.
3. **Split.** `chars_over_limit` or `lines_over_limit` on a feature of 4 stories or more: propose a sub-feature split;
   `item_over_limit` skips this step.
4. **Text to its home.** After an approved split, the next round fills each new feature draft and moves each spec
   doc's text to its sub-feature's spec doc; without a split, text moves only as the Owner picks.
5. **A moved item.** A `prefix_id` section item or a scenario: one ready `specstone move <doc>#<ID> … --under <doc>`
   or `specstone move <story>#S<N> … --under <story>`, which rewrites each citer.
   - A keyed item, or a new ID split off in one doc: in the same pass run `specstone refs <old item's doc>`, repoint
     each citer of the moved part to the new item's link, and keep each other citer.

## The split proposal

- Group the feature's stories by the placement questions `specstone guide feature` prints: at least 2 sub-features of
  at least 2 stories each.
- Name each sub-feature's slug and stories, then the ready commands in run order: one `new` per sub-feature, its
  `move` lines, then the two extra `move` lines:

```
specstone new feature --parent <feature> --slug <slug>
specstone move <story> … --under <sub-feature>
specstone move feature:<x> … --under <feature>
specstone move <story>#S<N> … --under <story>
```

- Use the `move feature` line for a feature that exists, the scenario line for a story past its scenario cap.
- Run none before the Owner's ok, then in that order; a dispatched agent runs none and reports them.
- A split the Owner turns down leaves nothing to delete.

## A finding that names items to move

A size finding with `candidates` or `split`, or an FR still over a cap after step 2, takes this route; run its
commands as the split's.

- `candidates`, in place of `No split applies`: one `specstone move <doc>#<ID> … --under <doc>` per sub-feature, to
  that sub-feature's doc of the same type; the Owner approves the drafts.
- `split`: the sub-feature split above; when it cannot be formed, the finding keeps `No split applies`.
- An FR still over a cap, in place of `No split applies`: one `specstone new fr --parent <story> --slug <slug>` per
  new FR in the same story, then one `specstone move <fr>#<edge case ID> … --under <new fr>` per new FR.

## A story past its scenario cap

- Cut or merge no scenario: propose new stories in its feature, `specstone new user_story --parent <feature> --slug
  <slug>` each, then the split proposal's scenario `move` line per new story.

## No split applies

- Say why in your report and leave the finding: it waits for the Owner.
- A feature of fewer than 4 stories, or a top doc such as the gnfr doc: the Owner picks text moved to its home or the
  doc type's limit raised in the project's templates.

## A bundle over its limit

- The size is the design read-first file of the finding's `doc`, so no layout shrinks it; a story never takes a
  sub-feature split.
- Propose the fix by the `doc` key with ready commands, run none before the Owner's ok; answer it once; it waits.
- `doc` a story: split it into two stories in its feature, one `specstone new user_story --parent <feature> --slug
  <slug>`, then one `specstone move <fr> … --under <new story>` per FR and nf that goes to it.
- `doc` a feature of sub-features: one `specstone move <doc>#<ID> … --under <sub-feature>` per spec item one
  sub-feature alone uses; with none, no fix applies.
- `doc` a feature of stories: the sub-feature split, then the same moves.
- No fix applies at the doc type's `max_depth` or under 4 stories: say why.

## An item over its limit

- Fix it only in a bootstrap run the Owner started naming `item_over_limit` (a dispatched agent sees it in `batch:`):
  rewrite the item in its type's item shape from `specstone guide <type>`.
  - One rule per ID: each rule split off takes its section's next free ID.
  - A bound stays in its rule; mechanics, known limits, and trace move to the homes the guide names; drop nothing.
- Elsewhere leave it: it waits for the Owner; a bootstrap report lists it under `Waits on the Owner:`.
