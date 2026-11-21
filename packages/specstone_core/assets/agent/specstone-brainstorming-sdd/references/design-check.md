`specstone-sdd-auditor` runs this with `stage: design`, its gate made; so does the runner of
`specstone-brainstorming-sdd` with no subagent or after a failed dispatch. Write nothing but the agent's `report:`
file; never edit the design document; ask the Owner nothing.

## 1. Read

1. **Inputs**: the design document's path, `amend: <N>[,<N> ...]`, `since: <snapshot path>`, and `bundles`, each
   with its read plan line, when given. Make the missing-input stop, its `OPEN QUESTIONS:` line naming:
   - the design document, when none is given;
   - `since`, for a `since:` path that does not exist, a snapshot equal to the design document, or differences that
     keep no decision (a fix outside every decision and Docs to change row);
   - `since` and `amend`, for both in one dispatch: a delta check takes no `amend`.
2. **Design document**: read it whole; list each decision by ID or label. With `amend`, keep only decisions whose
   heading lists a named `Amend <N>`, stubs included. Read a stub as an amended decision; another decision, ruling,
   or section still stating its removed rule is a gap of the stub's decision.
   When no heading lists an `<N>`, make the missing-input stop for the whole check, naming `amend`. With `since`,
   keep the decisions section 1 of `sweep.md` gives. With neither, keep every decision, stubs too.
3. **Targets**: each existing doc among the Docs to change rows; with `amend` or `since`, only rows of decisions step
   1.2 kept, a stub's included: with `amend`, in each named amend's `Amend <N> rows` table; with `since`, in that of
   the newest amend a kept decision's heading lists. An amend with no such table, or a heading listing no amend,
   takes the first table. A row in any other table has landed: no target, and it covers no hit. With `since`, the
   snapshot gives the rows of a decision kept by its snapshot text and each row deleted since. A row for a doc still
   to be created is no target.
4. **Bundles**: ground the targets as section 2 of `sweep.md` gives, each read-first file by its read plan. Run no
   `get`.

## 2. Sweep

Before any lens, follow section 3 of `sweep.md` for each decision step 1.2 kept, in list order.

## 3. Compare

Walk each lens, a bold-labeled bullet, over every kept decision in list order. A gap is the decision's own: what it
opens, changes, or leaves open in what it changes; a gap target text held before the design is no finding. Record
one gap per line, `D<n>: <gap>`:

- **Input left open:** a decision taking inputs or states with no input table, or with a table missing a form the
  targets already handle.
- **Reader missed:** a saved-file item that reads or writes what a decision changes, with no target row (step 1.3).
  Find it by the sweep and by the item's Input, Output, and rule nouns, not only the decision's terms.
- **Row mismatch:** a target row whose named sections and items hold none of its decision's terms; a row section
  with neither an item list nor `whole`; a decision's change no named item holds. A `design_references` row and a
  row only swapping a copy for a link are exempt from the first test.
- **Rule mismatch:** a decision relying on a `check` or CLI rule that states another condition than the rule's owner
  item.
- **Two builders:** a decision two builders would build differently.
- **Design contradicts:** a decision contradicting another decision, an Owner answer the design records, a
  constraint, or an owner item.
- For each gap, search the saved files, a reached doc's included, and the input tables of `sweep.md` section 4, for
  its wording and the rule or term it breaks. Each hit in another doc or section carrying the same gap is a
  sibling: its own `D<n>:` line under `Findings:`, never under `Outside the drafts:`. A hit true whatever answers the
  gap is no sibling.

## 4. Report

```
Design check: <design document path>; amend: <N list, or none>; since: <snapshot path, or none>
Swept: D<n>: <term>, <term>; <n> items hit, <m> with no row, <h> held
  <type>:<name>#<section> <item>: covered|gap|held: <why>
Held: <n> hits, listed in the report file
Lenses: Input left open, Reader missed, Row mismatch, Rule mismatch, Two builders, Design contradicts
Findings:
- D<n>: <gap>
- D<n>: <gap> [behavior]
```

- `Swept:` one line per kept decision, its own terms; counts and hit list per steps 3.7 and 3.5 of `sweep.md`. The
  hit list goes under it in the report file only.
- `Held:` the `held` lines over every hit list. `Lenses:` each lens label, in list order.
- `Findings:` one line per gap and sibling, or `none`; a gap in a doc names it `<type>:<name>#<key>`. End a line
  with `[behavior]` when its answer adds a state, input, output, edge case, error, or reader of a rule, or removes a
  decision; a line that only fixes the design's text stays untagged.
- No `Audited:` line.
- Reply `Report: <path>`, then the relay block: `Swept:` lines without hit lists, `Held:`, `Lenses:`, and
  `Findings:`, copied from the report file.
