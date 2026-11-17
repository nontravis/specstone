`specstone-sdd-engineer` runs this in `mode: audit`, its gate already made; so does the runner of
`specstone-brainstorming-sdd`. Write nothing but the agent's `report:`
file, no fix. Ask the Owner nothing.

## 1. Read

1. **Targets**: the drafts the author reported, or the feature or doc the Owner named. A later audit takes the drafts
   list, each read whole and audited again.
2. **Hashes**: run one `specstone get <targets> --json` on every target. The drafts list's names need no
   `--target`. When it refuses with `doc_not_found`, for a target never created, or moved or deleted since the list
   was made, drop each name the refusal names and list it under `Outside the drafts:`, with no `Audited:` line. Any
   other refusal, such as `doc_type_unknown`, is a finding and drops its names too. Run the call again on the rest;
   when no target is left, skip it and the steps below.
3. **Bundles**: run `specstone context <target> --for design --out` once for each feature the targets fall under
   (the project doc for a project-level one). Pass no `--budget` and no `--target`:
   the bundle takes every code target's spec docs. Read the saved files per the `specstone-read-sdd` skill, the
   read-first one whole; ground a doc they lack with its own `specstone context <doc> --for design --out`, never
   `get`. On any exit but 0, report the CLI's error as a finding; go on with the rest.
4. **Design document**, when given: read it whole; list each decision and ruling by its ID or label. Then run
   `specstone list user_story --draft`, `specstone list fr --draft`, and `specstone list nf --draft`: the drafts
   among the targets are what this change wrote.
5. **Check**: run `specstone check <target>` once per target, and keep each finding as
   printed. A finding whose `waitsFor` is `owner` is no gap.

## 2. Compare

Walk each bold-labeled lens over every target, in list order. Record one gap per line,
`<type>:<name>#<section>: <gap>`, for each:

- **Decision dropped:** a decision, ruling, or Docs to change row of the design document no target doc carries, or a
  draft that departs from its decision. Report one gap in each doc it misses, naming the draft (or the design's owner
  doc) and the decision; no other lens repeats it there, and a drop in another doc is a sibling (last bullet).
- **Requirement invented:** a draft story, FR, NFR, or section of one tracing to no decision.
- **PRD and spec apart:** a PRD item (a story, FR, or edge case) the spec omits, or a spec item no PRD item asks for.
- **Docs contradict:** two docs that state different values or behavior for one thing; name both.
- **Statement untested:** an FR statement, or a clause of one, that no scenario or edge case covers.
- **Rule restated:** a draft stating a rule another doc owns instead of citing it (`specstone-expert-sdd` rule 7); name
  the owner doc and the item; its fix is an item link in the draft.
- Without a design document, skip the first two lenses; the rest still run.
- **Feature pattern:** for each item of a bundle's pattern part, search the doc listing the pattern, its subtree, and
  its feature's spec folder for covering text or a skip line in that doc's `out_of_scope`; else report
  `<type>:<name>#out_of_scope: <pattern>/<item> neither covered nor skipped`, `<type>:<name>` the listing doc, typed
  as the part's bundle line.
- **Repoint:** a citer a size-fix move repointed or kept that still links the old item though it cites the moved part,
  or links the new item though it means the part left behind; name the citer and the item it should link. List the
  citers with `specstone refs <doc>` (`Inbound` lines) on the old item's doc and the new one's, and with
  `specstone list --cites <ID>` for a citer naming the item's ID in frontmatter.
- Read each draft item for two gaps `check` never names, each a `Findings:` line naming its ID or first words:
  - **No example:** a non-obvious rule whose result on one concrete input you cannot state after one read.
  - **Clause order:** a condition after its rule, or clauses nested inside one sentence.
- For each gap any lens finds, search the bundle files saved in step 1.3 for its wording and the rule or term it
  breaks. Each hit in another doc or section is its own gap; one whose fix lies in no draft goes under
  `Outside the drafts:`.

## 3. Report

```
Audit: <targets>; design document: <path, or none>
Lenses: <lens>, <lens>, ...
Audited: <type>:<name>@<hash>
Findings:
- <type>:<name>#<section>: <gap>
- <type>:<name>#<section>: <gap> [behavior]
- check: <finding, as printed>
Waits on the Owner:
- check: <each finding tagged (waits for the Owner), as printed>
Outside the drafts:
- <a gap or check finding whose fix lies in no draft>
- <type>:<name>: invented whole, a deletion for the Owner
- <type>:<name>: no draft
- <name>: names no doc
```

- **`Lenses:`**: the label of each lens the audit ran, in list order.
- **`Audited:`**: one line per target that names a doc, its `docType` and `name` joined with `:`, then `@` and
  the `bases.doc` of the `get` of step 1; each replaces an earlier audit's line for that draft.
- **`Findings:`**: each gap or `check` finding a write inside a draft fixes, each sibling hit its own line. End a
  line with `[behavior]` when its fix brings a new state, input, output, edge case, error, or reader of a rule the
  design does not state; a line whose fix only corrects text against the design stays untagged.
- **`Waits on the Owner:`**: each `check` finding whose `waitsFor` is `owner`, its line ending
  `(waits for the Owner)`.
- **`Outside the drafts:`**: each gap or `check` finding whose fix lies in no draft, such as a baseline finding on
  an approved doc under a target; each target that is no draft, and each name dropped from the `get` call; and each
  whole draft story or FR that is invented, marked as a deletion for the Owner.
- **An empty heading:** write `none` under it. A `[behavior]` line goes to the runner's design amend, never a fix
  round.
