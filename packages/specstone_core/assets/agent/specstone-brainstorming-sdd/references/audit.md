`specstone-sdd-engineer` runs this in `mode: audit`, its gate already made; so does the runner of
`specstone-brainstorming-sdd` when it runs the mode itself. Write nothing but the agent's `report:`
file: no doc, no other file, no fix. Ask the Owner nothing: each gap goes into your report.

`specstone check` reads each doc's form, not what it means. Read the docs as a reader who did not write them, and
report what the author's coverage table cannot show.

## 1. Read

1. **Targets**: the drafts the author reported, or the feature or doc the Owner named. An audit after a fix round,
   or after the author pass that follows an amend, takes the drafts list, each read whole and audited again.
2. **Hashes**: run one `specstone get <targets> --json` on every target. The drafts list's names need no
   `--target`. Each doc's `Audited:` line joins its JSON
   `docType` and `name` with `:`, then `@` and its `bases.doc`. When it refuses with `doc_not_found`, for a target
   never created, or moved or deleted since the list was made, drop each name the refusal names and list it under
   `Outside the drafts:`, with no `Audited:` line. Any other refusal, such as `doc_type_unknown` or a section fault,
   is a finding and drops each name it names too. Run the call again on the rest; when no target is left, skip the
   rerun and the steps below. A dropped name is no target for the steps below: no bundle and no `check` for it.
3. **Bundles**: run `specstone context <target> --for design --out` once for each feature the targets fall under
   (the project doc for a project-level one). Pass no `--budget`.
   Pass no `--target`: the bundle takes every code target's spec docs. Read the saved files per the `specstone-read-sdd`
   skill, the read-first one whole; ground a doc they lack with its own
   `specstone context <doc> --for design --out`, never `get`.
   - **0:** the bundle is what you audit.
   - **Any other exit:** report the CLI's error as a finding, and go on with the rest.
4. **Design document**, when given: read it whole, and list each decision and ruling by its ID or label. Then run
   `specstone list user_story --draft`, `specstone list fr --draft`, and `specstone list nf --draft`: the drafts
   among the targets are what this change wrote.
5. **Check**: run `specstone check <target>` once per target, not over the whole project, and keep each finding as
   printed. A finding whose `waitsFor` is `owner`, its line ending `(waits for the Owner)`, is no gap.

## 2. Compare

Record one gap per line, `<type>:<name>#<section>: <gap>`, for each of these:

- **Decision dropped:** a decision, ruling, or Docs to change row of the design document no target doc carries.
- **Requirement invented:** a draft story, FR, or NFR, or a draft section of one, tracing to no decision of the
  document.
- **PRD and spec apart:** a PRD item (a story, FR, or edge case) the spec omits, or a spec item no PRD item asks for.
- **Docs contradict:** two docs that state different values or behavior for one thing; name both.
- **Statement untested:** an FR statement, or a clause of one, no scenario of its story and no edge case covers.
- **Rule restated:** a draft stating a rule another doc owns instead of citing it (`specstone-expert-sdd` rule 7); name
  the owner doc and the item; its fix is an item link in the draft.
- **No design document:** skip the first two gaps and the draft-and-decision lens; the other comparisons and `check`
  still run.
- **Feature pattern:** for each item of a bundle's pattern part, search the doc listing the pattern, its subtree, and
  its feature's spec folder, if any, for covering text or a skip line in that doc's `out_of_scope`; else report
  `<type>:<name>#out_of_scope: <pattern>/<item> neither covered nor skipped`, `<type>:<name>` the listing doc, typed
  as the part's bundle line.
- **Draft and decision:** a draft that departs from the decision it carries out, or a decision the design gives
  an owner item no draft states; name the draft or the owner item's doc, and the decision.
- **Repoint:** a citer a size-fix move repointed or kept that still links the old item though it cites the moved part,
  or links the new item though it means the part left behind; name the citer and the item it should link.

## 3. Report

```
Audit: <targets>; design document: <path, or none>
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

- **`Audited:`**: one line per target that names a doc, a draft or not, its hash that doc's `bases.doc` from the
  `get` of step 1; each replaces the line an earlier audit wrote for that draft.
- **`Findings:`**: each gap or `check` finding a write inside a draft fixes. End a `Findings:` line with `[behavior]`
  when its fix brings a new state, input, output, edge case, error, or reader of a rule the design does not state; a
  line whose fix only corrects text against the design stays untagged.
- **`Waits on the Owner:`**: each `check` finding whose `waitsFor` is `owner`, its line ending
  `(waits for the Owner)`; `specstone-expert-sdd`'s Owner confirmation clears it.
- **`Outside the drafts:`**: each gap or `check` finding whose fix lies in no draft, such as a baseline finding on
  an approved doc under a target, or a decision the author reported not landed; each target that is no draft, and
  each name dropped from the `get` call; and each whole draft story or FR that is invented, marked as a deletion for
  the Owner. It goes to the Owner, never to a fix round.
- **An empty heading:** write `none` under it. A fix round takes only the untagged `Findings:` lines; a `[behavior]`
  line goes to the runner's design amend.
