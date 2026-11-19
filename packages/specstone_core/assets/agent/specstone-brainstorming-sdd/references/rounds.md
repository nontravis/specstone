Run this until the Owner approves the drafts.

## 1. Route each Owner decision

A decision adds or changes behavior when it brings a new state, input, output, edge case, error, or reader of a
rule. Removing a decision changes behavior too: it takes an amend and its design check. Every other decision only
words or records one.

- **A refused design path**, an open question with no document written: append nothing; write the document at the
  Owner's new path, by `design.md`.
- **Only words or records**: append it to the design document's Rulings, as `design.md` writes them;
  no design check; the author, or the fix round under way, goes on.
- **Adds or changes behavior**, or needs more PRD or spec grounding: ground a doc newly reached by its own
  `specstone context <doc> --for design --out`, never `get`, then amend the same file. `design.md` finds the
  decision's dependents before the author writes it. When the amend adds or changes behavior, dispatch the design
  check per the skill's step 3, `amend: <N>`. Your fix of its findings, an Owner answer included, is no amend unless
  it edits a decision an author pass read. An untagged line takes no check; a `[behavior]` fix takes one second check,
  the first's scope plus any amend the fix opened, never a third. Decide a `[behavior]` line of that check only when
  its answer stays inside the Owner's goals, rulings, and picked approach, and list it with the ask or before the
  author pass; else the Owner answers there, as a new decision.
- **Before the author**: after an append, or an amend and its check, ask for the approval again. When the design
  document holds open questions, gather the Owner's answers, append each that only words or records one, send the
  rest to one amend and its check, and ask for the approval only after it.
- **Once two rounds are spent**, a decision that adds or changes behavior, the Owner's decision on a finding past the
  cap included, takes an amend and its check, then one author pass that carries the amend alone, the one pass beyond
  the cap, then a re-audit (section 3) whose findings reach the Owner with the drafts, with no further round. Fix an
  Owner change that only corrects text per the `specstone-expert-sdd` skill, with no amend.

## 2. Run the fix rounds

The drafts list is the first author report's drafts plus each doc a fix round or pass added, renamed or dropped as
section 3 says.

- **A fresh author**: every author pass after the first, a fix round or the pass after an amend, is a new
  `mode: author` dispatch, never the resumed one. It takes the document's path, the drafts list, and `guide:` the
  first author's `Guide:` files; a fix round adds the audit's `Findings:` lines not tagged `[behavior]`
  (`[style]` too), and the pass after an amend each untagged line of its design check naming a draft by
  `<type>:<name>#<key>`, a sibling too; a line naming a doc outside the list is a Docs to change row. The author
  re-reads those drafts before its first write, then fixes those findings and each same-class hit, `[style]` hits
  included, as `author.md`'s Sweep each changed rule gives.
- **A `[behavior]` line**, or an Owner decision adding behavior, never goes to a fix round: take it to
  an amend and its own check (section 1). The one fresh author pass after, counted toward the cap, takes the amended
  design, the drafts list, and that audit's other lines.
- **A `[style]`-only audit** spends no round and gets no re-audit: fix each line in place by `specstone set --replace`.
  Run `specstone approve <drafts list> --dry-run --json`, then append to that audit's report file one
  `Styled: <type>:<name>@<hash>` line per fixed draft, `hash` as that call prints it.
- **A split proposal** the Owner okays: run its `specstone move` commands as an author's `Move:` lines. The new FRs
  join the drafts list, and a fresh author pass fills them before any audit: it joins the next round when one is due,
  else it is no round. Then the amend compare below.
- **The cap**: run at most two rounds, fix rounds and amend passes alike; no design check counts. Lines left after the
  second get no third round: the Owner sees them with the drafts, and their decision on one takes section 1's
  route.
- After each fix round or amend pass, re-audit as section 3 says.
- **Before every audit dispatch**, the skill's step 4 audit included, compare the design's last amend, the highest
  `Amend <N>` its headings list or `0`, with the `amend <N>` of the last author relay block's first line,
  `Design: <path>, amend <N>`:
  - The two equal: dispatch the audit.
  - The design's higher: run a fresh author pass with the amend first, then the audit.
  - No `Design:` line: run a fresh author pass first.

## 3. Re-audit only what changed

1. Run one `specstone get <drafts list> --json`, with no `--target`, and keep each draft's `bases.doc`.
2. When it refuses with `doc_not_found`, update the drafts list for each name it names: a doc moved between rounds
   takes the new name `move` printed, and a doc deleted, or listed and never created, drops out. Run the call again.
3. For each draft whose `bases.doc` differs from its last `Audited:` hash, a changed draft, run
   `specstone refs <changed draft>`. Its `Inbound` lines give its citers: a draft of the list that links to it or
   names it in `traced_from`, one hop only.
4. Send every re-audit as a fresh `mode: audit`, never a resumed one, with the document's path, `check:` the last
   author pass's `Check:` file with no doc write since it and no split since the last audit, and these targets:
   - A changed draft.
   - Each doc the round or pass added.
   - An unchanged draft that cites a changed draft.
   - Not an unchanged draft that cites no changed draft: its earlier finding stands.
   - Not a doc of the list that is no draft, approved between rounds or listed and never written.
5. In your round note to the Owner, name each doc approved between rounds and each name item 2 renamed or dropped.
