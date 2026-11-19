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
  `specstone context <doc> --for design --out`, never `get`, then amend the same file. When the amend adds or
  changes behavior, dispatch the design check per the skill's step 3, `amend: <N>`. Your fix of its findings is no
  amend unless it edits a decision an author pass read. An untagged line takes no check; a `[behavior]` fix takes one
  second check, the first's scope plus any amend the fix opened, never a third. Decide a `[behavior]` line of either
  check only when its answer stays inside the Owner's goals, rulings, and picked approach; any other line is the
  Owner's, and an Owner answer that adds behavior takes a numbered amend and its check. List a second check's
  `[behavior]` line, decided or the Owner's, with the ask or before the author pass; only the Owner's line waits
  for the Owner there.
- **Before the author**: after an append, or an amend and its check, ask for the approval again. When the design
  document holds open questions, gather the Owner's answers, append each that only words or records one, send the
  rest to one amend and its check, and ask for the approval only after it.
- **Once two rounds are spent**, a decision that adds or changes behavior, the Owner's decision on a finding past the
  cap included, takes an amend and its check, then one author pass that carries the amend alone, the one pass beyond
  the cap, then a re-audit (`reaudit.md`) whose findings reach the Owner with the drafts, with no further round. Fix an
  Owner change that only corrects text per the `specstone-expert-sdd` skill, with no amend.

## 2. Run the fix rounds

The drafts list is the first author report's drafts plus each doc a fix round or pass added, renamed or dropped as
`reaudit.md` says.

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
  join the drafts list, and a fresh author pass, the fill pass, fills them before any audit. It takes the proposal's
  lines and joins the next round when one is due; else it is no round and carries no findings. Past both rounds it
  still runs, and its re-audit's findings reach the Owner with the drafts, with no further round. Then the amend
  compare below.
- **The cap**: run at most two rounds, fix rounds and amend passes alike; no design check counts. Lines left after the
  second get no third round: the Owner sees them with the drafts before approving any, and their decision on one
  takes section 1's route.
- After each fix round or amend pass, re-audit as `reaudit.md` says.
- **Before every audit dispatch**, the skill's step 4 audit included, compare the design's last amend, the highest
  `Amend <N>` its headings list or `0`, with the `amend <N>` of the last author relay block's first line,
  `Design: <path>, amend <N>`:
  - The two equal: dispatch the audit.
  - The design's higher: run a fresh author pass with the amend first, then the audit.
  - No `Design:` line: run a fresh author pass first.
  - A split's new FR awaits its fill: run the fill pass first, with any amend, then the audit.

## 3. Re-audit only what changed

Follow `reaudit.md`; its item 4 sends each re-audit.
