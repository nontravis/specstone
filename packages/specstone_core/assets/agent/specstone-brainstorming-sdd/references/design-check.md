`specstone-sdd-auditor` runs this with `stage: design`, its gate made, the first line of `audit.md` routing it; so
does the runner of `specstone-brainstorming-sdd` with no subagent or after a failed dispatch. Write nothing but the
agent's `report:` file; never edit the design document. Ask the Owner nothing.

## 1. Read

1. **Inputs**: the design document's path, `amend: <N>[,<N> ...]`, `since: <snapshot path>`, and `bundles`, each
   with its read plan line, when given. With no design document, make the missing-input stop: its `OPEN QUESTIONS:` line names the design document.
   Make it, its line naming `since`, for a `since:` path that does not exist, a snapshot equal to the design
   document, or differences that keep no decision (a fix outside every decision and Docs to change row); and, its
   line naming `since` and `amend`, for both in one dispatch: a delta check takes no `amend`.
2. **Design document**: read it whole; list each decision by its ID or label. With `amend`, keep only the decisions
   whose heading lists a named `Amend <N>`: `amend: 4` keeps a decision headed `(Amend 2, Amend 4)` and a stub
   headed `(Amend 2, Amend 4, removed)`; `amend: 3,4` keeps `(Amend 3)` and `(Amend 2, Amend 4)`. Read the stub as an
   amended decision; another decision, ruling, or section of the design still stating its removed rule is a gap of
   the stub's decision. When no heading lists an `<N>`, make the missing-input stop for the whole check, its
   `OPEN QUESTIONS:` line naming `amend`. With `since`, keep the decisions section 1 of `sweep.md` gives. With
   neither, keep every decision, a stub too.
3. **Targets**: each doc that exists among the Docs to change rows; with `amend` or `since`, only the rows of the
   decisions step 1.2 kept, a stub's rows included: with `amend`, in each named amend's `Amend <N> rows` table; with
   `since`, in that of the newest amend a kept decision's heading lists. For an amend with no such table (a design
   written before this table form, or an amend before the first author pass), or a heading listing no amend, take
   the first table. A row in any other table has landed: no target, and it covers no hit. With `since`, the snapshot
   gives the rows of a decision kept by its snapshot text and each row deleted since it. A row for a doc still to be
   created is no target.
4. **Bundles**: ground the targets as section 2 of `sweep.md` gives, each read-first file by its read plan. Run no
   `get`.

## 2. Sweep

Before any lens, follow section 3 of `sweep.md` for each decision step 1.2 kept, in list order.

## 3. Compare

Walk each lens, a bold-labeled bullet, over every decision step 1.2 kept, in list order. A gap is the decision's
own: what it opens, changes, or leaves open in what it changes. Target text no decision changes or relies on is
context: a gap it held before the design is no finding. Record one gap per line, `D<n>: <gap>`, `D<n>` the decision
it names:

- **Input left open:** a decision taking inputs or states with no input table, or with a table missing a form the
  targets already handle, such as a bare `#anchor` link beside a relative link.
- **Reader missed:** an item of the saved files that reads or writes what a decision changes, with no target row
  (step 1.3). Find it by the sweep and by the item's Input, Output, and rule nouns, not only by the decision's terms.
- **Row mismatch:** a target row whose named sections and items hold none of its decision's terms; a row
  section with neither an item list nor `whole`; a decision's change that no named item holds. A
  `design_references` row and a row that only swaps a copy for a link are exempt from the first test: they hold no
  decision's term by nature.
- **Rule mismatch:** a decision relying on a `check` or CLI rule that states another condition than the rule's owner
  item, such as "an empty title" where the rule fires on an empty `# ` line.
- **Two builders:** a decision two builders would build differently.
- **Design contradicts:** a decision that contradicts another decision, an Owner answer the design records, a
  constraint, or an owner item.
- For each gap any lens finds, search the saved files for its wording and the rule or term it breaks, as the last
  bullet of `audit.md`'s compare step does, a reached doc's files included, and over the input tables section 4 of
  `sweep.md` names. Each hit in another doc or section that
  carries the same gap is a sibling: its own `D<n>:` line under `Findings:`, never under `Outside the drafts:`. A hit
  that stays true whatever answers the gap is no sibling.

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

- **`Swept:`**: one line per decision step 1.2 kept, its own terms, written forms implied. A missing line shows a
  skipped sweep; its counts and hit list are steps 3.7 and 3.5 of `sweep.md`. Under it, in the report file only,
  the hit list, so a dropped hit shows; each `gap` line is also a `Findings:` line, a `held` line none.
- **`Held:`**: the `held` lines over every hit list.
- **`Lenses:`**: the label of each lens, in list order.
- **`Findings:`**: one line per gap and per sibling, or `none`; a gap in a doc names it `<type>:<name>#<key>`. End a
  line with `[behavior]` when its answer adds a state, input, output, edge case, error, or reader of a rule, or
  removes a decision; a line that only fixes the design's text stays untagged.
- **No `Audited:` line**: no draft exists yet.
- **Reply**: `Report: <path>`, then the relay block, its `Swept:` lines with no hit list, `Held:`, `Lenses:`,
  and `Findings:` lines copied from the report file.
