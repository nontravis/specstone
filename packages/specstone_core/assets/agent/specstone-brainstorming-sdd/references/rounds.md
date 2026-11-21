## 1. Route each Owner decision

A behavior decision adds or changes a state, input, output, edge case, error, or reader of a rule, or removes a
decision; any other only words or records one.

- **Refused design path** (no document yet): append nothing; write at the Owner's new path by `design.md`.
- **Words or records only**: append to Rulings by `design.md`, no check; the author or fix round goes on.
- **Behavior, or more grounding needed**: ground a newly reached doc per `SKILL.md` step 1, exit 0, never `get`; amend
  the same file. After an author pass, a behavior amend is a new scope, its check `amend: <N>`; a later amend's check
  lists every amend it keeps, `amend: <N>[,<N> ...]`.
- **Sweep**: before each design check, send a fresh `specstone-sdd-sweeper` the document's path, the check's `amend`
  or `since`, and `bundles`. An Owner change adding a decision or a doc gets one `specstone-sdd-sweeper` sweep,
  `since:` the scope's last check snapshot, no snapshot saved. Add each sweep's `Rows:` lines word for word to the
  scope's table (the first, or the newest `Amend <N> rows` a kept decision lists); one sweep per check; no cap counts
  it. With no subagent or after a failed sweep, add no rows; after a failed one, tell the Owner it did not run.
- **Snapshot**: then copy the design to `<folder>/reports/sdd-auditor.audit.snapshot.<XXXXXX>.md`, `XXXXXX` that
  check's `report:` characters.
- **Chain**: an untagged line takes no check. Fixed `[behavior]` lines of a first or amend check take one delta
  check, `since:` its snapshot, no `amend`. A scope: the first check, or one amend's check (shared amends as one),
  plus at most one delta check.
- **Who decides**: a first or amend check's `[behavior]` line is yours only when its answer stays inside Intent,
  Rulings, and the picked approach, else the Owner's; either answer opens no scope.
  A delta check's `[behavior]` lines are the Owner's, listed with the ask or before the amend's author pass, no
  further check. Before the first author pass, a delta check's answer or an Owner change at the ask takes no amend
  and no check: write it in.
- **Then**: after an append, change, or amend and its check, ask for approval again, the change listed.
- **Round spent**: once the round is spent, a behavior decision, the Owner's on a finding past the cap included,
  takes an amend and its check, one author pass beyond the cap with the amend alone, and a re-audit (section 3)
  whose findings reach the Owner with the drafts; no further round.
- **Text-only Owner change**: fix it per the `specstone-expert-sdd` skill, no amend.

## 2. Run the fix round

Drafts list: the first author report's drafts plus docs a round or pass added, renamed or dropped by `reaudit.md`.

- **Style lines**: fix each audit `[style]` line in place by `specstone set --replace` before any author pass, run
  `specstone approve <drafts list> --dry-run --json`, and append one `Styled: <type>:<name>@<hash>` line per fixed
  draft to that audit's report file, `hash` as printed. A `[style]` line alone spends no round and gets no re-audit.
- **Fix round**: write the fix file `<folder>/reports/sdd-engineer.author.fix.<XXXXXX>.md` by the host's file write,
  then resume the first author with one message naming it. It opens with `mode: author`, `design:`, a new `report:`
  path, the drafts list, and `guide:` the first author's `Guide:` files, then the audit's untagged `Findings:` lines
  and each untagged line of a design check after an author pass naming a draft by `<type>:<name>#<key>`, siblings too.
  A line naming a doc outside the list is a Docs to change row.
- **Fresh author**: a fresh author takes the fix pass when the host cannot resume an agent, that agent has ended, or
  the resumed one answers with no tool call and its old report; main writes the fix file, then dispatches the fresh
  author as a normal author pass: `mode: author` and the fix file's inputs as its own, and it may name the file. The
  fill pass of a split and the pass after an amend are fresh, joined to a fix round or not, since an amend or a split
  changes what the author read.
- **`[behavior]` line** or behavior decision: never a fix round; an amend and its own check. The one fresh author
  pass after it is the round: the amended design's path, the drafts list, `guide:`, the audit's untagged lines, and
  its design check's untagged lines naming a draft by `<type>:<name>#<key>`, siblings too.
- **Split proposal** the Owner okays: run its `new` and `move` commands in order. Its new FRs join the drafts list;
  a fresh fill pass, with the proposal's lines, fills them before any audit. It joins the next round when due, else
  it is no round and carries no findings; past the round it still runs, its re-audit findings going to the Owner
  with the drafts. Then the amend compare.
- **Cap**: at most one round, a fix round or an amend pass; no design check or sweep counts. Lines left get no
  second round: the Owner sees them with the drafts before any approval, `--auto` asks each draft they name, and a
  decision on one takes section 1's route.
- After each fix round or amend pass, re-audit per section 3.
- **Before every audit dispatch**, the first included, compare the design's last amend (highest `Amend <N>` in its
  headings, or `0`) with the last author relay's first line, `Design: <path>, amend <N>`. Equal, no new FR awaiting
  fill: dispatch the audit. Design higher: fresh author pass with the amend first. No `Design:` line: fresh author
  pass first. A split's new FR awaits fill: fill pass first, with any amend, then the audit.

## 3. Send each audit

Read `reaudit.md` before each audit after the first. Send each audit as a fresh `specstone-sdd-auditor`, never
resumed, with the document's path and `check:` the last author pass's `Check:` file, only with no doc write since it
and no split since the last audit.
