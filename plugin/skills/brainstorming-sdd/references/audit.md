`specstone:sdd-engineer` runs this in `mode: audit`, its gate already made; so does the runner of
`specstone:brainstorming-sdd` when it has no `Agent` tool or the dispatch failed. Write nothing but the agent's `report:`
file: no doc, no other file, no fix. As the agent, ask the Owner nothing: each gap goes into your report.

`specstone check` reads each doc's form, not what it means. Read the docs as a reader who did not write them, and
report what the author's own coverage table cannot show.

## 1. Read

1. **Targets**: the drafts the author reported, or the feature or doc the Owner named. Run
   `specstone context <target> --for design` once for each feature the targets fall under (`project` for a
   project-level doc), not once per target: a design bundle already holds the whole feature. Read each bundle whole.
   - **0:** the bundle is what you audit.
   - **Any other exit:** report the CLI's error for that call as a finding, and go on with the rest.
2. **Design document**, when given: read it whole, and list each decision and ruling by its ID or label. Then run
   `specstone list user_story --draft`, `specstone list fr --draft`, and `specstone list nf --draft`: the drafts
   among the targets are what this change wrote.
3. **Check**: run `specstone check <target>` once per target, not over the whole project, and keep each finding as
   printed. An `unconfirmed` link on a draft is no gap: it waits for the Owner's approval.

## 2. Compare

Record one gap per line, `<type>:<name>#<section>: <gap>`, for each of these:

| Gap                  | What you find                                                                                |
|----------------------|----------------------------------------------------------------------------------------------|
| Decision dropped     | a decision, ruling, or Docs to change row of the design document that no target doc carries  |
| Requirement invented | a draft story, FR, or NFR, or a draft section of one, tracing to no decision of the document |
| PRD and spec apart   | a PRD item (a story, FR, or edge case) the spec omits, or a spec item no PRD item asks for   |
| Docs contradict      | two docs that state different values or behavior for one thing; name both                    |
| Statement untested   | an FR statement, or a clause of one, that no scenario of its story and no edge case covers   |

- **No design document:** skip the first two rows; every other comparison and `check` still run.
- **A gap you could fix:** report it and fix nothing. The author fixes it in a fix round, or the Owner decides.

## 3. Report

```
Audit: <targets>; design document: <path, or none>
Findings:
- <type>:<name>#<section>: <gap>
- check: <finding, as printed>
Waits on the Owner:
- check: <each unconfirmed link on a draft, as printed>
Outside the drafts:
- <a gap or check finding whose fix lies in no draft>
- <type>:<name>: invented whole, a deletion for the Owner
```

- **`Findings:`**: each gap or `check` finding a write inside a draft fixes, so a fix round can act on it.
- **`Waits on the Owner:`**: each `unconfirmed` link on a draft; the Owner's approval clears it.
- **`Outside the drafts:`**: each gap or `check` finding whose fix lies in no draft, such as a baseline finding on
  an approved doc under a target, or a decision the author reported not landed; and each whole draft story or FR
  that is invented, marked as a deletion for the Owner, since author mode deletes no doc. It goes to the Owner,
  never to a fix round.
- **An empty heading:** write `none` under it. A fix round takes only the `Findings:` lines.
