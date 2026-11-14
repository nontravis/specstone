`specstone:sdd-engineer` runs this in `mode: audit`, its gate already made; so does the runner of
`specstone:brainstorming-sdd` when it has no `Agent` tool or the dispatch failed. Write nothing but the agent's `report:`
file: no doc, no other file, no fix. As the agent, ask the Owner nothing: each gap goes into your report.

`specstone check` reads each doc's form, not what it means. Read the docs as a reader who did not write them, and
report what the author's own coverage table cannot show.

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
3. **Bundles**: run `specstone context <target> --for design` once for each feature the targets fall under
   (the project doc for a project-level one), not once per target: a design bundle already holds the whole feature. Pass no
   `--target`: the bundle takes every code target's spec docs. Read each bundle whole.
   - **0:** the bundle is what you audit.
   - **Any other exit:** report the CLI's error for that call as a finding, and go on with the rest.
4. **Design document**, when given: read it whole, and list each decision and ruling by its ID or label. Then run
   `specstone list user_story --draft`, `specstone list fr --draft`, and `specstone list nf --draft`: the drafts
   among the targets are what this change wrote.
5. **Check**: run `specstone check <target>` once per target, not over the whole project, and keep each finding as
   printed. A finding whose `waitsFor` is `owner`, its line ending `(waits for the Owner)`, is no gap: only the
   Owner clears it.

## 2. Compare

Record one gap per line, `<type>:<name>#<section>: <gap>`, for each of these:

| Gap                  | What you find                                                                                |
|----------------------|----------------------------------------------------------------------------------------------|
| Decision dropped     | a decision, ruling, or Docs to change row of the design document that no target doc carries  |
| Requirement invented | a draft story, FR, or NFR, or a draft section of one, tracing to no decision of the document |
| PRD and spec apart   | a PRD item (a story, FR, or edge case) the spec omits, or a spec item no PRD item asks for   |
| Docs contradict      | two docs that state different values or behavior for one thing; name both                    |
| Statement untested   | an FR statement, or a clause of one, that no scenario of its story and no edge case covers   |
| Rule restated        | a draft stating a rule another doc owns instead of citing it (`specstone:expert-sdd` rule 7) |

- **Rule restated:** name the owner doc and the item; its fix is a citation in the draft.
- **No design document:** skip the first two rows; every other comparison and `check` still run.
- **A gap you could fix:** report it and fix nothing. The author fixes it in a fix round, or the Owner decides.

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
- **`Findings:`**: each gap or `check` finding a write inside a draft fixes, so a fix round can act on it. End a
  `Findings:` line with `[behavior]` when its fix brings a new state, input, output, edge case, error, or reader of a rule the design does not state; a line whose fix only corrects text
  against the design stays untagged.
- **`Waits on the Owner:`**: each `check` finding whose `waitsFor` is `owner`, its line ending
  `(waits for the Owner)`; only the Owner clears it.
- **`Outside the drafts:`**: each gap or `check` finding whose fix lies in no draft, such as a baseline finding on
  an approved doc under a target, or a decision the author reported not landed; each target that is no draft, and
  each name dropped from the `get` call; and each whole draft story or FR that is invented, marked as a deletion for
  the Owner, since author mode deletes no doc. It goes to the Owner, never to a fix round.
- **An empty heading:** write `none` under it. A fix round takes only the untagged `Findings:` lines; a `[behavior]`
  line goes to a design-mode amend.
