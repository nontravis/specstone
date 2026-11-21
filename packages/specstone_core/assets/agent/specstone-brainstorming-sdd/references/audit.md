With `stage: design`, follow `design-check.md` instead. `specstone-sdd-auditor` runs this with no `stage` or
`stage: drafts`, its gate made; so does the runner of `specstone-brainstorming-sdd`. Write only the agent's `report:`
file, no fix. Ask the Owner nothing.

## 1. Read

1. **Targets**: the dispatch's `targets`, each read whole and audited again.
2. **Hashes**: run one `specstone approve <targets> --dry-run --json`, no `--target`: it gives each draft's `hash` and
   changed units. Only a target it does not list, which is no draft, takes `specstone get <target> --json`. On
   `doc_not_found`, drop each name it names, listed under `Outside the drafts:` with no `Audited:` line; any other
   refusal is a finding and drops its names too. Rerun on the rest; with no target left, skip the steps below.
3. **Bundles**: run one `specstone context <doc> --for design --out` on the smallest doc holding every target in one
   feature, else once per top-level feature (the project doc for a project-level one), with no `--budget` or
   `--target`. Read the saved files per `specstone-read-sdd`, the read-first one whole by its read plan. On a
   non-zero exit, report its error as a finding and go on.
4. **Design document**, when given: read it whole; list each decision and ruling. Run `specstone list <type> --draft`
   for `user_story`, `fr`, and `nf`: the drafts among the targets are this change's.
5. **Check**: search the `check:` file per target; with none, run one bare
   `specstone check --out "<folder>/reports/check.audit.<XXXXXX>.txt"` and search it. A `waitsFor` `owner` finding is
   no gap.
6. **Repeats**: run `specstone check <feature> --repeats --out "<folder>/reports/check.audit.<XXXXXX>.txt"` once per
   feature holding a draft.

## 2. Compare

Walk each lens, a bold-labeled bullet, over every target in list order; record one gap per line.

- **Decision dropped:** a decision, ruling, or Docs to change row no target carries, or a draft departing from its
  decision. One gap per doc it misses, naming the draft (or the design's owner doc) and the decision; no other
  lens repeats it there, and a drop in another doc is a sibling. A draft still stating a removed decision's rule is
  a gap of its stub row; a stub row whose sections hold none of its text is no gap.
- **Requirement invented:** a draft story, FR, NFR, or section tracing to no decision.
- **PRD and spec apart:** a PRD item (story, FR, edge case) the spec omits, or a spec item no PRD item asks for.
- **Docs contradict:** two docs stating different values or behavior for one thing; name both.
- **Edge case admission:** an edge case in step 1.2's changed units breaking one of the first four edge case lines
  of `specstone guide fr`'s doc description; name that line; its fix is the drop, nested trigger, or move it gives.
- **Rule restated:** a draft stating in any words a rule another doc owns, a story rule included; name the owner doc
  and item; its fix is an item link. Judge each step 1.6 group holding a draft's new text beside another doc's item;
  a group of drafts alone, or any group by itself, is no gap.
- Without a design document, skip the first two lenses.
- **Feature pattern:** for each item of a bundle's pattern part, search the listing doc, its subtree, and its
  feature's spec folder for covering text or a skip line in that doc's `out_of_scope`; else report
  `<type>:<name>#out_of_scope: <pattern>/<item> neither covered nor skipped`, `<type>:<name>` the listing doc, typed
  as the part's bundle line.
- **Trim:** with `trims:`, judge each deleted, moved, and cut item its reports list by its guide line, and each
  rewritten cite by the cite table of `../../specstone-expert-sdd/references/trim.md`. A removed item stating
  behavior no other doc states is a gap whose fix restores it; a `Spec moves:` case awaiting its spec batch is none.
- **Repoint:** with no `check:` after an author pass: a citer a size-fix move repointed or kept that still links the
  old item for the moved part, or the new item for the part left; name the citer and the item to link. List citers
  with `specstone refs <doc>` (`Inbound` lines) on both items' docs, and `specstone list --cites <ID>` for a citer
  naming the ID in frontmatter.
- Read each draft item for two `[style]` gaps `check` never names, naming its ID or first words:
  - **No example:** a non-obvious rule whose result on one concrete input you cannot state after one read.
  - **Clause order:** a condition after its rule, or clauses nested inside one sentence.
- For each gap, search the bundle files for its wording and the rule or term it breaks. Each hit in another doc or
  section is its own gap; one no draft fixes goes under `Outside the drafts:`.

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

- `Audited:` one per target naming a doc, its hash from step 1.2; it replaces an earlier audit's line.
- `Findings:` each gap or `check` finding a draft fixes. Tag `[behavior]` a fix bringing a new state, input,
  output, edge case, error, or reader of a rule the design does not state; a text-only correction stays untagged.
- `Outside the drafts:` also each name dropped in step 1.2; a stub row is never a deletion.
- Write `none` under an empty heading.
