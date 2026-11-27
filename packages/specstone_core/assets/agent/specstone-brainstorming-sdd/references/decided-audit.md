`specstone-sdd-auditor`, its gate made, runs this for `job: decided-audit`. Write only the agent's `report:` file, no
fix; ask the Owner nothing.

## Decided audit

`job: decided-audit` takes the change note whose decided lines, its `D<n> (decided): <text>` decisions, the drafts
carry; the decided engineer's report of a plan's last sync; and the drafts, their draft lists joined. It reads the drafts
of a Decided change once its work is built, in 1 pass, and reports only `Contradiction`, `Stale reader`, and
`Not carried` items. Run no `check`, no `check --repeats`, and no lens walk; no fix loop and no re-review follow it.

1. **Hashes and ground**: run steps 1 and 2 of `audit.md`'s **Builder check** on the drafts, a check of drafts; its ground
   call names each draft and each doc a `Decision:` line names as carrying.
2. **Read**: the change note's decided lines, the decided engineer report's `Decision:`, `Not landed:`, and
   `Readers:` lines, each carrying section a `Decision:` line names in the read-first file, and the rest of the
   review read-first file by its read plan. Besides step 1's calls and step 4's one `grep -n -E` over
   the refs file, run no other doc read, `search`, `refs`, or `context` call.
3. **Judge**: report each point of these three labels of `audit.md`'s **Judge** step.
   - `Contradiction`: two docs contradict once the drafts land, a decided line or a draft that works against any
     project vision included, naming that vision's ID.
   - `Stale reader`: a reader still states the old rule.
   - `Not carried`: a decided line, or the part of one, that no draft carries, one line in each doc it misses, naming
     the line's `D<n>` and the draft, or the doc the change note's Reach list gives it.
   A built change leaves a builder nothing to guess, so report no `Guess` and no `Misplaced` point, and run no feature
   pattern search.
4. **Siblings**: after judging, run one `grep -n -E` over the refs file joining every point's wording and the rule or
   term it breaks. Give each hit its own line. A sibling only in a story the refs file holds in summary is out of
   reach.

```
Findings:
- Contradiction: <docs>: <point>
  Fix: <type>:<name>#<key>
- Stale reader: <docs>: <point>
- Not carried: <docs>: <point>
Notes:
- <observation>
Audited: <doc>@<hash>
```

- List every line under one `Findings:` line, ranked by importance across the three labels, with no label or count
  line inside it. Each item opens with its docs as `audit.md` gives `<docs>`.
- Under an item whose fix you can state, write its `Fix:` lines as `audit.md` gives them, each after the **Dry run** of
  `audit.md` on its section. State a fix only as `Fix:` lines, never in prose; a question only the Owner settles gets
  no `Fix:` line.
- Put every point under `Findings:`, a point on a doc outside the drafts included. Each item, with its `Fix:` lines,
  goes to the approval ask.
- With no point, `Findings:` reads `nothing important left`.
- Put each observation that is no gap under `Notes:`, which the judge never reads and main relays to the Owner. Write
  no `Notes:` heading when there is none.
- Write one `Audited:` line per draft, its `<doc>` and hash from step 1.
