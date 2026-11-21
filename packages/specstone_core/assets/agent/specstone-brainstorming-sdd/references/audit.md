With `stage: design`, follow `design-check.md` instead. `specstone-sdd-auditor` runs this with no `stage` or
`stage: drafts`, its gate made; so does the runner of `specstone-brainstorming-sdd`. Write only the agent's `report:`
file, no fix. Ask the Owner nothing.

## 1. Read

1. **Targets**: the dispatch's `targets`, each read whole and audited again.
2. **Hashes**: run one `specstone approve <targets> --dry-run --json`, the drafts list's names with no `--target`: it
   gives each draft's `hash` and changed units. A target it does not list is no draft; only it takes `specstone get <target> --json`.
   On `doc_not_found`, drop each name it names and list it under `Outside the drafts:`, with no `Audited:` line; any
   other refusal is a finding and drops its names too. Rerun on the rest; no target left: skip it and the steps below.
3. **Bundles**: run one `specstone context <doc> --for design --out` on the smallest doc holding every target when
   they sit in one feature, else once per top-level feature (the project doc for a project-level one), with no
   `--budget` or `--target`. Read the saved files per `specstone-read-sdd`, the read-first one whole by its read plan;
   ground a doc they lack with its own `specstone context <doc> --for design --out`, never `get`. On a non-zero exit,
   report its error as a finding and go on.
4. **Design document**, when given: read it whole; list each decision and ruling by ID or label. Then run
   `specstone list <type> --draft` for `user_story`, `fr`, and `nf`: the drafts among the targets are this
   change's.
5. **Check**: search the `check:` file per target; with none, run one bare
   `specstone check --out "<folder>/reports/check.audit.<XXXXXX>.txt"` and search it. A finding whose `waitsFor` is
   `owner` is no gap.
6. **Repeats**: run `specstone check <feature> --repeats --out "<folder>/reports/check.audit.<XXXXXX>.txt"`
   once per feature holding a draft; the Rule restated lens reads its saved file.

## 2. Compare

Walk each lens, a bold-labeled bullet, over every target in list order; the other bullets are its steps.
Record one gap per line for each lens:

- **Decision dropped:** a decision, ruling, or Docs to change row of the design document no target doc carries, or a
  draft that departs from its decision. Report one gap in each doc it misses, naming the draft (or the design's owner
  doc) and the decision; no other lens repeats it there, and a drop in another doc is a sibling.
  A draft still stating a removed decision's rule is a gap of that decision's stub row. A stub row whose sections
  hold none of its text is no gap.
- **Requirement invented:** a draft story, FR, NFR, or section of one tracing to no decision.
- **PRD and spec apart:** a PRD item (a story, FR, or edge case) the spec omits, or a spec item no PRD item asks for.
- **Docs contradict:** two docs stating different values or behavior for one thing; name both.
- **Edge case admission:** an edge case in step 1.2's changed units that breaks one of the first four edge case lines
  of `specstone guide fr`'s doc description; name that line; its fix is the drop, nested trigger, or move to the
  owner it gives.
- **Rule restated:** a draft stating in any words a rule another doc owns instead of citing it, a story rule
  included; name the owner doc and the item; its fix is an item link in the draft. Judge each step 1.6 group holding
  a draft's new text beside another doc's item; a group of drafts alone is no gap, nor is any group by itself.
- Without a design document, skip the first two lenses.
- **Feature pattern:** for each item of a bundle's pattern part, search the doc listing the pattern, its subtree, and
  its feature's spec folder for covering text or a skip line in that doc's `out_of_scope`; else report
  `<type>:<name>#out_of_scope: <pattern>/<item> neither covered nor skipped`, `<type>:<name>` the listing doc, typed
  as the part's bundle line.
- **Trim:** with `trims:`, judge each deleted, moved, and cut item its reports list by its guide line, and each
  rewritten cite by the cite table of `../../specstone-expert-sdd/references/trim.md`. A removed item stating behavior
  no other doc states is a gap whose fix restores it; a `Spec moves:` case awaiting its spec batch is none.
- **Repoint:** with no `check:` passed after an author pass, a move may have run; follow `repoint.md`.
- Read each draft item for two gaps `check` never names, each a `[style]` `Findings:` line naming its ID or first words:
  - **No example:** a non-obvious rule whose result on one concrete input you cannot state after one read.
  - **Clause order:** a condition after its rule, or clauses nested inside one sentence.
- For each gap any lens finds, search the bundle files for its wording and the rule or term it breaks.
  Each hit in another doc or section is its own gap; one no draft fixes goes under `Outside the drafts:`.

## 3. Report

```
Audit: <targets>; design document: <path, or none>
Lenses: <each lens label run, in list order>
Audited: <type>:<name>@<hash>
Findings:
- <type>:<name>#<section>: <gap>
- <type>:<name>#<section>: <gap> [behavior]
- <type>:<name>#<section>: <gap> [style]
- check: <finding, as printed>
Waits on the Owner:
- check: <each finding tagged (waits for the Owner), as printed>
Outside the drafts:
- <a gap or check finding no draft fixes>
- <type>:<name>: invented whole, a deletion for the Owner
- <type>:<name>: no draft
- <name>: names no doc
```

- **`Audited:`**: one per target that names a doc, the hash from step 1.2; it replaces an earlier audit's line for
  that draft.
- **`Findings:`**: each gap or `check` finding a draft fixes. Tag `[behavior]` a line whose fix brings a new state,
  input, output, edge case, error, or reader of a rule the design does not state; a text-only correction against the
  design stays untagged.
- **`Outside the drafts:`**: also each name dropped in step 1.2; a stub row is never a deletion.
- **An empty heading:** write `none` under it.
