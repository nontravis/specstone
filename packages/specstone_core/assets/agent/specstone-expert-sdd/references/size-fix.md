# Fix a doc over its size limit

This covers the four size findings `specstone check` raises, `chars_over_limit`, `lines_over_limit`,
`item_over_limit`, and `bundle_over_limit`, under `specstone-expert-sdd`'s rule 5.

## The order

Answer each `chars_over_limit` or `lines_over_limit` finding once in your report, though `check` tags it
`(waits for the Owner)`: a split proposal, or why none applies. Give `item_over_limit` neither: it needs no
answer; `An item over its limit` covers it. A `bundle_over_limit` finding skips steps 1 to 3 and takes the fix its
`doc` key gives, with step 4 for each moved item; `A bundle over its limit` covers it.

1. **Layout.** Every write lays its doc out. A size finding `check` still lists takes the next step; `check` counts
   the laid-out doc.
2. **Split.** `chars_over_limit` or `lines_over_limit` on a feature of 4 stories or more: propose a sub-feature
   split, as below. `item_over_limit` skips this step: a split never shrinks one item.
3. **Text to its home.** After an approved split, the next round fills each new feature draft and moves each spec
   doc's text to its sub-feature's spec doc. Without a split, text moves only as the Owner picks.
4. **A moved item.** An item of a `prefix_id` section or a scenario to another doc: one ready
   `specstone move <doc>#<ID> … --under <doc>` or `specstone move <story>#S<N> … --under <story>`, which rewrites each
   citer. For a keyed item, or a new ID split off inside one doc: in the same pass, run
   `specstone refs <old item's doc>`, repoint each citer that cites the moved part to the new item's link, and keep
   each other citer. `check` cannot tell which part a citer means, so the audit checks each repoint.

## The split proposal

Group the feature's stories into sub-features by the placement questions `specstone guide feature` prints: at least 2
sub-features of at least 2 stories each. Name each sub-feature's slug and its stories, then the ready commands in run
order, one `new` per sub-feature, then its `move` lines, then the two extra `move` lines:

```
specstone new feature --parent <feature> --slug <slug>
specstone move <story> … --under <sub-feature>
specstone move feature:<x> … --under <feature>
specstone move <story>#S<N> … --under <story>
```

The `move feature` line is for a feature that exists; the scenario line is for a story past its scenario cap.

Run none of them before the Owner's ok, and then in that order. A dispatched agent runs none: its report holds them
for the main session. A split the Owner turns down leaves nothing to delete.

## A finding that names items to move

A size finding with `candidates` or `split`, or an FR over its character cap, takes this route; every other size
finding keeps its route above. Run the commands as the split's: none before the Owner's ok, then in run order, and a
dispatched agent's report holds them.

- `candidates`: in place of `No split applies`, one `specstone move <doc>#<ID> … --under <doc>` per sub-feature, its
  target that sub-feature's doc of the same type. The Owner approves the drafts each move leaves.
- `split`: the sub-feature split above; when it cannot be formed, as with fewer stories than it needs, the finding
  keeps `No split applies`.
- An FR over its character cap, in place of `No split applies`: one `specstone new fr --parent <story> --slug <slug>`
  per new FR in the same story, then one `specstone move <fr>#<edge case ID> … --under <new fr>` per new FR.

## No split applies

Say why in your report and leave the finding as it is: it waits for the Owner.

- A feature of fewer than 4 stories, since a split needs at least 2 sub-features of at least 2 stories each, and a
  feature holds stories or sub-features, never both; or a top doc, such as the gnfr doc: the Owner picks text moved to its
  home or the doc type's limit raised in the project's templates.

## A bundle over its limit

The size is the design read-first file of the finding's `doc`, never one doc's text, so no layout step shrinks it. The
fix follows the `doc` key; a story's file never takes a sub-feature split. Propose the fix with its ready commands, as
the split does, and run none before the Owner's ok. The finding waits for the Owner; answer it once in your report.

- `doc` is a story: split it in its feature into two stories, one `specstone new user_story --parent <feature> --slug
  <slug>`, then one `specstone move <fr> … --under <new story>` per FR and nf that goes to it, so the FRs and nfs are
  shared between the two stories.
- `doc` is a feature whose children are sub-features: one `specstone move <doc>#<ID> … --under <sub-feature>` per
  spec item that one sub-feature alone uses. With no such item, no fix applies.
- `doc` is a feature whose children are stories: the sub-feature split above, then the same moves for each spec item
  one sub-feature alone uses.
- No fix applies to a feature at its doc type's `max_depth`, since no sub-feature nests below it, nor to a feature of
  fewer than 4 stories, since no grouping gives it 2 sub-features of 2 stories each.

Where no fix applies, say why in your report and leave the finding as it is: it waits for the Owner.

## An item over its limit

Only a bootstrap run the Owner started naming `item_over_limit` fixes it; a dispatched agent sees the name in
`batch:`. That run rewrites the item in its doc type's item shape, as `specstone guide <type>` gives it:

- one rule per ID: each rule split off takes the next free ID of its section;
- a bound stays in its rule;
- its mechanics, known limits, and trace move to the homes the guide names;
- no statement is dropped.

Anywhere else, leave the finding as it is: it waits for the Owner. A bootstrap report lists it under
`Waits on the Owner:` until a run names `item_over_limit`.
