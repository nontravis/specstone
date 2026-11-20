Run this until the Owner approves the drafts.

## 1. Route each Owner decision

A decision adds or changes behavior when it brings a new state, input, output, edge case, error, or reader of a
rule, or removes a decision; every other decision only words or records one.

- **A refused design path**, an open question with no document written: append nothing; write the document at the
  Owner's new path, by `design.md`.
- **Only words or records**: append it to the design's Rulings by `design.md`, with no design check; the author, or
  the fix round under way, goes on.
- **Adds or changes behavior**, or needs more PRD or spec grounding: ground a doc newly reached by its own
  `specstone context <doc> --for design --out`, never `get`, then amend the same file. When the amend adds or
  changes behavior, dispatch the design check per the skill's step 3, `amend: <N>`. Your fix of its findings is no
  amend unless it edits a decision an author pass read.
  - **Sweep**: before each design-check dispatch, send a fresh `specstone-sdd-sweeper` the document's path and the
    check's `amend` or `since` and `bundles`; add each `Rows:` line word for word to the scope's table, the first or
    the newest `Amend <N> rows` a kept decision lists, with no second sweep; no cap counts it. With no subagent or
    after a failed sweep, add no rows; after a failed one, tell the Owner it did not run.
  - **Snapshot**: then copy the design to `<folder>/reports/sdd-auditor.audit.snapshot.<XXXXXX>.md` by the host's
    file write, `XXXXXX` that check's `report:` characters.
  - **Chain**: an untagged line takes no check. A first or amend check's fixed `[behavior]` lines take one delta
    check, `since:` its snapshot and no `amend`; with none, the chain ends. A scope is the first check before the
    ask, or one amend's check (shared amends count as one), plus at most one delta check.
  - **Who decides**: decide a `[behavior]` line only when its answer stays inside the Intent, Rulings, and
    picked approach; any other line is the Owner's. Your answer, like the Owner's to a first or amend check's line,
    opens no scope: its fix takes the scope's delta check.
  - **The delta check**: its `[behavior]` lines are the Owner's, whatever the answer, listed with the ask or
    before the amend's author pass, with no further check. An answer adding behavior takes a numbered amend and its
    `amend: <N>` check, a new scope; else it goes to Rulings.
- **Before the author**: after an append, or an amend and its check, ask for approval again. When the design
  document holds open questions, gather the Owner's answers: append each that only words or records one, send the
  rest to one amend and its check, then ask.
- **Once the round is spent**, a decision that adds or changes behavior, the Owner's on a finding past the cap
  included, takes an amend and its check, then one author pass beyond the cap carrying the amend alone, then a
  re-audit (`reaudit.md`) whose findings reach the Owner with the drafts, with no further round. Fix an Owner change
  that only corrects text per the `specstone-expert-sdd` skill, with no amend.

## 2. Run the fix round

The drafts list is the first author report's drafts plus each doc a fix round or pass added, renamed or dropped as
`reaudit.md` says.

- **A fresh author**: every author pass after the first is a new `mode: author` dispatch, never the resumed one. It
  takes the document's path, the drafts list, and `guide:` the first author's `Guide:` files; a fix round adds the
  audit's `Findings:` lines not tagged `[behavior]`, and the pass after an amend each untagged line of its design check
  naming a draft by `<type>:<name>#<key>`, a sibling too; a line naming a doc outside the list is a Docs to change row.
  The author reads their sections before its first write, then fixes them and each same-class hit, `[style]` ones
  included, by `author.md`'s Sweep each changed rule.
- **A `[behavior]` line**, or an Owner decision adding behavior, never goes to a fix round: take it to an amend and its
  own check (section 1). The one fresh author pass after, counted as the one round, takes the amended design, the drafts
  list, and that audit's other lines.
- **A `[style]`-only audit** spends no round and gets no re-audit: fix each line in place by `specstone set --replace`.
  Run `specstone approve <drafts list> --dry-run --json`, then append one `Styled: <type>:<name>@<hash>` line per fixed
  draft to that audit's report file, `hash` as that call prints it, for `--auto`.
- **A split proposal** the Owner okays: run its `new` and `move` commands in order, as an author's `Move:` lines. The
  new FRs join the drafts list, and a fresh author pass, the fill pass, fills them before any audit. It takes the
  proposal's lines and joins the next round when one is due; else it is no round and carries no findings. Past the round
  it still runs, and its re-audit's findings reach the Owner with the drafts, with no further round. Then the
  amend compare below.
- **The cap**: run at most one round, a fix round or an amend pass; no design check or sweep counts. Lines left after
  it get no second round: the Owner sees them with the drafts before any is approved, `--auto` asks each draft they
  name, and a decision on one takes section 1's route.
- After each fix round or amend pass, re-audit as `reaudit.md` says; its item 4 sends each re-audit.
- **Before every audit dispatch**, the first included, compare the design's last amend, the highest `Amend <N>` its
  headings list or `0`, with the `amend <N>` of the last author relay block's first line, `Design: <path>, amend <N>`:
  - The two equal and no new FR awaits its fill: dispatch the audit.
  - The design's higher: run a fresh author pass with the amend first, then the audit.
  - No `Design:` line: run a fresh author pass first.
  - A split's new FR awaits its fill: run the fill pass first, with any amend, then the audit.
