`specstone-sdd-engineer` runs this in `mode: audit` with `stage: design`, its gate made, the first line of `audit.md`
routing it; so does the runner of `specstone-brainstorming-sdd` with no subagent or after a failed dispatch. Write
nothing but the agent's `report:` file; never edit the design document. Ask the Owner nothing.

## 1. Read

1. **Inputs**: the design document's path, and `amend: <N>` when given. With no design document, make the
   missing-input stop: its `OPEN QUESTIONS:` line names the design document.
2. **Design document**: read it whole; list each decision by its ID or label. With `amend: <N>`, keep only the
   decisions whose heading lists `Amend <N>`: `amend: 4` keeps a decision headed `(Amend 2, Amend 4)` and a stub
   headed `(Amend 2, Amend 4, removed)`. Read the stub as an amended decision; another decision, ruling, or section
   of the design still stating its removed rule is a gap of the stub's decision. When no heading lists it, make the
   missing-input stop, its `OPEN QUESTIONS:` line naming `amend`. With no `amend`, keep every decision, a stub too.
3. **Targets**: each doc that exists among the Docs to change rows; with `amend: <N>`, only the rows of the decisions
   step 2 kept, a stub's rows included. A row for a doc still to be created is no target.
4. **Bundles**: ground the features the targets fall under as step 1.3 of `audit.md` does, one
   `specstone context <feature> --for design --out` each. Run no `get`.

## 2. Compare

Walk each lens, a bold-labeled bullet, over every decision step 1.2 kept, in list order. A gap is the decision's
own: what it opens, changes, or leaves open in what it changes. Target text no decision changes or relies on is
context: a gap it held before the design is no finding. Record one gap per line, `D<n>: <gap>`, `D<n>` the decision
it names:

- **Input left open:** a decision taking inputs or states with no input table, or with a table missing a form the
  targets already handle, such as a bare `#anchor` link beside a relative link.
- **Reader missed:** an item of the saved files that reads or writes what a decision changes, with no Docs to change
  row. Find it by the item's Input, Output, and rule nouns, not only by the decision's terms.
- **Rule mismatch:** a decision relying on a `check` or CLI rule that states another condition than the rule's owner
  item, such as "an empty title" where the rule fires on an empty `# ` line.
- **Two builders:** a decision two builders would build differently.
- **Design contradicts:** a decision that contradicts another decision, an Owner answer the design records, a
  constraint, or an owner item.
- For each gap any lens finds, search the saved files for its wording and the rule or term it breaks, as the last
  bullet of `audit.md`'s compare step does. Each hit in another doc or section that carries the same gap is a
  sibling: its own `D<n>:` line under `Findings:`, never under `Outside the drafts:`. A hit that stays true
  whatever answers the gap is no sibling.

## 3. Report

```
Design check: <design document path>; amend: <N, or none>
Lenses: Input left open, Reader missed, Rule mismatch, Two builders, Design contradicts
Findings:
- D<n>: <gap>
- D<n>: <gap> [behavior]
```

- **`Lenses:`**: the label of each lens, in list order.
- **`Findings:`**: one line per gap and per sibling, or `none`. End a line with `[behavior]` when its answer adds a
  state, input, output, edge case, error, or reader of a rule; a line that only fixes the design's text stays
  untagged.
- **No `Audited:` line**: no draft exists yet.
- **Reply**: `Report: <path>`, then the relay block, its `Lenses:` and `Findings:` lines copied from the report file.
