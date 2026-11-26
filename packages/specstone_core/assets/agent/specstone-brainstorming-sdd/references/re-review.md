`specstone-sdd-auditor`, its gate made, runs this for `job: re-review`. Write only the agent's `report:` file, no
fix; ask the Owner nothing.

## Re-review

`job: re-review` takes `findings`, every finding of the run still open, verbatim, each with its `Fix:` lines;
`fix report`, each writer's report path of the round and the round number of its `## Round <n>` part, absent at the
approval step; `drafts`, each draft the findings name or the fix changed; `audits`, the run's earlier audit reports,
oldest first; and, in a brainstorm, the change note and the Owner's answers. Its `findings` at the approval step are
the audit items still open that name its drafts, verbatim, or `none`. It reads only the sections changed since each
draft's last audit, in 1 pass. Run no `check`, no `check --repeats`, and no lens walk, and no second read follows.
Edit no doc and no change note, and add no doc.

1. **Hashes**: run one `specstone approve <drafts> --dry-run --json --audit <path> …`, one `--audit` for each `audits`
   path, oldest first, no `--target`: its `doc` and `base` per draft are the `Audited:` `<doc>` and hash, and its
   `changedSections` per draft is the read set. On `doc_not_found`, drop each name it names and run it again on the
   rest; a dropped name gets no report line.
2. **Asks**: read `findings`, `audits`, each `fix report` path's `## Round <n>` part, and, in a brainstorm, the
   change note and the Owner's answers.
3. **Ground**: run one `specstone context <draft> <draft> --for review --out` naming every draft step 1 keeps, and
   read its read-first file by its read plan. Besides step 1's call, this call, and one `grep -n -E` over the refs
   file for each gap's wording and the rule or term it breaks, run no other doc read, `search`, `refs`, or `context`
   call.
4. **Read set**: read each section a draft's `changedSections` names, and nothing else. A section whose text equals
   its audited copy is not listed, since an earlier audit read it. A draft no report of `audits` names lists every
   section. A draft with no `changedSections`, its audited copy missing or its title, a frontmatter field, a heading,
   or the section order changed, is read whole. With an empty `changedSections`, such as a draft unchanged at the
   approval step, no section of it is read. A draft marked `citer of <type>:<name>`, a bootstrap round's citer at the
   approval step, is read at its citing items alone, found by the one `grep -n -E`, whatever step 1 lists for it.
5. **Judge**: each section read must close the finding it answers, in a brainstorm state the Owner's answer,
   contradict no other doc, and leave a planner or implementer nothing to guess.
6. **Verdicts**: under `Verdicts:`, give each open finding that names one of its drafts one verdict: `- ADDRESSED:`
   when the drafts now settle it, else `- NOT ADDRESSED:`, so this report, the last part naming each draft, restates
   every finding still open. Copy the finding's first line, its `- ` dropped, exactly after `- ADDRESSED: ` or
   `- NOT ADDRESSED: `, since an `- ADDRESSED:` verdict clears the earlier item it equals. A finding that names none
   of its drafts gets no `Verdicts:` line. With no open finding naming one of its drafts, write `Verdicts: none`.

```
Findings:
- <Label>: <docs>: <point>
  Fix: <type>:<name>#<key>
Verdicts:
- ADDRESSED: <item>
- NOT ADDRESSED: <item>
Outside the round:
- <docs whose fix it is>: <gap>
Notes:
- <observation>
Audited: <doc>@<hash>
```

- Put each new gap inside the read set under `Findings:` as a builder check item, its label `Guess`,
  `Contradiction`, `Stale reader`, `Not carried`, or `Misplaced`, ranked by importance, with its `Fix:` lines when you
  can state the fix: one `Fix: <type>:<name>#<key>` line per section the fix changes, indented two spaces, then that
  section's whole new body in a bare fence of three or more backticks, longer than any backtick run at a line start in
  the body, indented the same. State a fix only as `Fix:` lines, never in prose; a question only the Owner settles
  gets no `Fix:` line.
- Before each `Fix:` line, run the **Dry run** of `audit.md` on its section and write the line as it gives.
- A gap whose fix is a new doc gets a `Findings:` item with no `Fix:` line, so it goes to the Owner: a new doc lies
  beyond the round's findings.
- With no new gap, `Findings:` reads `nothing important left`.
- Under `Outside the round:`, put each gap inside the read set whose fix lies in no draft of the round, such as a
  citer the grep shows the changed text now contradicts, opening with every doc its fix lies in, as `audit.md` gives
  `<docs>`. Restate each `Outside the drafts:` and `Outside the round:` item of `audits` still open. A gap on a draft
  marked `citer of <type>:<name>` goes under `Outside the round:` too, never `Findings:`, since the second `--auto`
  call names no citer. Write `none` when there is none.
- Put each observation outside the read set, or that is no gap, under `Notes:`, which the judge never reads, so it
  never extends the loop, and main relays it to the Owner. Write no `Notes:` heading when there is none.
- Write one `Audited:` line per draft, its `<doc>` and hash from step 1, so the next `--auto` call judges each draft by
  this report.
