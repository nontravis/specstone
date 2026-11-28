# Fix a doc over its size limit

## The order

Over a size limit: layout, FR edge-case trim, an Owner-approved sub-feature split or fold, text moved to its home;
drop nothing but step 2's cuts. Cite a size only as `specstone structure <doc>` or `check` prints it.

- Answer each `chars_over_limit`, `lines_over_limit`, `subsections_over_limit`, and FR edge-case
  `item_count_out_of_range` once in your report, though tagged `(waits for the Owner)`: a proposal, or why none.
- `item_over_limit` gets neither: `An item over its limit` covers it.
- A `bundle_over_limit` or `subsections_over_limit` skips steps 1 to 4: its own section, then step 5.

1. **Layout.** Every write lays its doc out; a size finding `check` still lists takes the next step.
2. **Trim.** An `item_count_out_of_range` on an FR's edge cases, or a `chars_over_limit` on an FR: trim its edge
   cases by `trim.md` first; what stays over takes the new FRs of `A finding that names items to move`. A
   `code_blocks_over_limit` takes no split: the same trim cuts its section's examples to its cap.
3. **Split.** `chars_over_limit` or `lines_over_limit` on a feature of 4 stories or more: propose a sub-feature split,
   or on the feature map the fold below; `item_over_limit` skips this step.
4. **Text to its home.** An approved split or fold's plan file moves each spec doc's text; the next round fills each
   new feature draft. Without either, text moves only as the Owner picks.
5. **A moved item.** One plan line per item, `<doc>#<ID> -> <doc>` or `<story>#S<N> -> <story>`, a row or block
   `<unit> -> <doc>`, applied as the split's plan is; it rewrites each citer.
   - A new ID split off in one doc: in the same pass run `specstone refs <old item's doc>`, repoint each citer of the
     moved part to the new item's link, keep the rest.

## The split proposal

- Group the feature's stories by the placement questions of `specstone guide feature`: 2 or more sub-features of 2 or
  more stories each.
- Name each sub-feature's slug and stories, and give one move plan file per split, saved in the run's reports
  folder by
  `specstone move --plan-out <feature> <spec doc> … --out "<folder>/reports/sdd-engineer.<mode>.plan.<XXXXXX>.txt"`
  and edit its lines. Put each `new` line above every line that names its doc.
  - One `new feature --parent <feature> --slug <slug>` line per sub-feature.
  - Set each story's line to `<story> -> <sub-feature>`.
  - Set a feature that exists to `feature:<x> -> <feature>`; leave every other line `keep`.
  - One `new <spec type> --parent <sub-feature>` line per spec doc a sub-feature takes text for, then one
    `<doc>#<ID or section/key> -> <sub-feature's spec doc>` line per unit that sub-feature alone uses.
  - For a story past its scenario cap, add the lines of `size-fix-story.md`.
- After the Owner's ok the main session runs one `specstone move --plan-file "<file>"`, a dispatched agent only
  writes the file and reports its path; on `plan_mismatch`, save the skeleton again.

## The fold proposal

- Group related top features of the feature map under one top feature: name each parent and its features.
- Start the plan file from the skeleton of the feature map when it lists the top features, else by hand: `new feature
  --slug <slug>` only when every fitting parent holds stories, then one `feature:<x> -> feature:<parent>` line each.
- Never fold past the `feature` type's `max_depth`; cut no text.
- When no fold fits, say why and leave the finding: the Owner may raise the cap in the project layer.
- Apply the file after the Owner's ok, as the split does.

## A finding that names items to move

A size finding with `candidates` or `split`, or an FR still over a cap after step 2, takes this route, by a plan file.

- `candidates`, in place of `No split applies`: one `<doc>#<ID> -> <sub-feature's doc of the same type>` line per
  item; the Owner approves the drafts.
- `split`: the sub-feature split above; when none can form, the finding keeps `No split applies`.
- An FR still over a cap, in place of `No split applies`: one `new fr --parent <story> --slug <slug>` line per new FR
  in the same story, then one `<fr>#<edge case ID> -> <new fr>` line per edge case that moves. In author or sync mode,
  the engineer applies it at once by `../../specstone-brainstorming-sdd/references/author.md`
  `## 7. Split an FR past its edge-case cap`.

## No split applies

- Say why; the finding waits for the Owner.
- A feature of fewer than 4 stories, or a top doc but the feature map, such as the gnfr doc: the Owner picks text
  moved home or the doc type's limit raised in the project's templates.

## A bundle over its limit

- The size is the design read-first file of the finding's `doc`, so no layout shrinks it; a story takes no
  sub-feature split.
- Propose the fix by the `doc` key as a plan file, applied after the Owner's ok; answer once; it waits.
- `doc` is a story: split it in its feature into two stories, one `new user_story --parent <feature> --slug <slug>`
  line, then one `<fr> -> <new story>` line per FR and nf that moves.
- `doc` is a feature whose children are sub-features: one `<doc>#<ID> -> <sub-feature's doc of the same type>` line
  per spec item that one sub-feature alone uses; with none, no fix applies.
- `doc` is a feature whose children are stories: the sub-feature split above.
- No fix applies to a feature at its doc type's `max_depth` or with fewer than 4 stories: say why.

## An item over its limit

- Fix it only in a bootstrap run the Owner started naming `item_over_limit` (a dispatched agent sees it in `batch:`):
  rewrite the item in its type's item shape from `specstone guide <type>`.
  - One rule per ID: each rule split off takes its section's next free ID.
  - A bound stays in its rule; mechanics, known limits, and trace move to the homes the guide names; drop nothing.
- Elsewhere it waits for the Owner; a bootstrap report lists it under `Waits on the Owner:`.
