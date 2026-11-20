Before each design check, `specstone-sdd-sweeper` runs sections 1 to 3, then 5; the check of `design-check.md` runs
1 to 3 before any lens. Both run section 1 when given `since`, section 2 once, section 3 per decision step 1.2 of
`design-check.md` kept, in list order. Write nothing but the agent's `report:` file.

## 1. Keep since a snapshot

With `since: <snapshot path>`, compare the design document with that snapshot:

- Keep each decision whose text differs from the snapshot or is new, and each whose Docs to change row was added,
  changed, or deleted.
- Keep a decision removed since the snapshot: by its stub, or, with no stub, by its text in the snapshot, so its
  rule's readers are swept. Keep a stub only when its decision was removed since the snapshot.
- An amend a fix opened is in the kept text already.

## 2. Ground

1. **Features**: run one `specstone context <feature> --for design --out` per feature the targets fall under. Run no
   `get`.
2. **Bundles**: main's `bundles` stand in for a feature only when they are that feature's own full design bundle; read
   them in place of its call. A story's or FR's bundle, a feature's `--summary` bundle, and a `context project` bundle
   stand in for no feature: each target's feature takes its own call.
3. **Cited docs**: a doc the read-first file holds only as a cited excerpt (its index line marked `cited`, `cites`, or
   `cited by`, with no part of its own in that file), such as an ancestor feature's spec doc, is reached as step 3.3
   gives. The refs file's excerpt docs are not reached this way.

## 3. Sweep each decision

1. **Terms**: run one search per term over every saved file of the check, a reached doc's files included: each term,
   key, literal, state, refusal, and finding the decision adds or changes, and each wording it supersedes, in every
   written form: with and without a trailing `/`, in backticks or not, singular and plural, and a short form ("five
   version spots" also as "five spots"). Then search the ID of each item the decision changes inside that item's own doc
   block, and search each other name a hit gives the changed thing, such as a role label ("its split line"), once more
   over every saved file. A hit naming the changed thing by any name is a hit of the decision.
2. **Readers**: read the owner item's cited-by lines. Run
   `specstone check <feature> --repeats --out "<folder>/reports/check.audit.<XXXXXX>.txt"` once per target feature
   for the whole sweep, reusing its file for later decisions; search it for the item's doc path. With no cited-by
   line, the repeat groups and the term search carry the decision.
3. **Reach**: ground each doc a cited-by line or repeat group names outside the grounded features, and each cited doc
   of step 2.3, by `specstone context <doc> --for design --out`, then run step 3.1 on its files. Run no `--repeats` on
   it and follow none of its cited-by lines: the reach stops one hop out.
4. **Covered**: a hit is `covered` only when one target row of step 1.3 of `design-check.md` names its doc and section,
   lists the hit's decision in its Decisions cell, and either names the hit item in its item list, gives the section as
   `whole`, or names the section by a bare key (the author reads that block whole; the row's Row mismatch line stands).
   Any other hit is a `gap` or, as step 3.5 gives, `held`: a row naming other items of the same doc or section, or
   listing the item for another decision only, does not cover it.
5. **Hit list**: under the decision's `Swept:` line, in the report file only, write one
   `  <type>:<name>#<section> <item>: covered|gap|held: <why>` line per search hit in a reader doc; leave no hit out.
   A hit no row covers and judged to stay true whatever the decision says, such as a history or design-reference
   line or a generic mention, is `held: <why>`, its reason one clause. Name an item with no ID by a table row's first
   cell, a diagram line's node ID, or a sentence's quoted words.
6. **Gaps**: each `gap` hit, and each superseded wording left outside the rows, is a `D<n>: <gap>` line under
   `Findings:`; a `held` hit is none. A doc written before its rule, restating it instead of citing its owner, is one
   too. Name a doc gap `<type>:<name>#<key>`, an item `<type>:<name>#<section>`.
7. **Count**: for the decision's `Swept:` line, the items hit, those with no covering row (`gap` and `held`), and the
   `held` ones.

## 4. Siblings

The sibling search of each gap, in section 3 of `design-check.md`, also runs over the other decisions' input tables:
a form one decision's table lacks is checked in each table taking the same input.

## 5. The sweeper's report

The sweeper walks no lens and writes no `Findings:` line: each line of step 3.6 is a `Rows:` row. Its
`report:` file, in this order, the hit lists in the file only:

```
Sweep: <design document path>; amend: <N list, or none>; since: <snapshot path, or none>
Ignored: <keys, or none>
Swept: D<n>: <term>, <term>; <n> items hit, <m> with no row, <h> held
  <type>:<name>#<section> <item>: covered|gap|held: <why>
Rows:
| <Doc cell> | <Sections cell> | <Decisions cell> |
```

- **`Ignored:`**: each of `mode`, `stage`, `targets`, `check`, `trims` the brief gives, or `none`.
- **`Rows:`**: one Docs to change row per doc and decision, in the table's form, which the runner adds word for word;
  a `held` hit takes none; `Rows: none` when none.
  - **Doc:** `<type>:<name>`; with two or more code targets, a per-target spec doc adds `(target: <name>)`.
  - **Sections:** each section the hits fall in, by its `get` key, its items in parentheses; a hit restating the
    decision's rule adds `; copy: remove, link the owner item` inside them, such as
    `edge_cases (E07, E17; copy: remove, link the owner item)`.
  - **Decisions:** `D<n>`.
  - **A removed decision's stub:** Sections `take out the D<n> text: <sections>`, each by its `get` key with its
    items, never `all`; Decisions `D<n> (Amend <N>, removed)`.
