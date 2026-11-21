## 1. Route each Owner decision

A behavior decision adds or changes a state, input, output, edge case, error, or reader of a rule, or removes a
decision; any other only words or records one.

- **Refused design path** (no document yet): append nothing; write at the Owner's new path by `design.md`.
- **Words or records only**: append to Rulings by `design.md`, no design check; the author or fix round goes on.
- **Behavior, or more grounding needed**: ground a newly reached doc by its own
  `specstone context <doc> --for design --out`, never `get`; amend the same file. A behavior amend takes a design
  check, `amend: <N>`; amends before the ask share one, `amend: <N>[,<N> ...]`; a later one gets its own.
- **Sweep**: before each design check, send a fresh `specstone-sdd-sweeper` the document's path, the check's `amend`
  or `since`, and `bundles`. Add its `Rows:` lines word for word to the scope's table (the first, or the newest
  `Amend <N> rows` a kept decision lists); no second sweep; no cap counts it. With no subagent or after a failed
  sweep, add no rows; after a failed one, tell the Owner it did not run.
- **Snapshot**: then copy the design to `<folder>/reports/sdd-auditor.audit.snapshot.<XXXXXX>.md` by the host's
  file write, `XXXXXX` that check's `report:` characters.
- **Chain**: an untagged line takes no check. Fixed `[behavior]` lines of a first or amend check take one delta
  check, `since:` its snapshot, no `amend`. A scope: the first check, or one amend's check (shared amends as one),
  plus at most one delta check.
- **Who decides**: you decide a `[behavior]` line only when its answer stays inside Intent, Rulings, and the picked
  approach; else the Owner. Either answer to a first or amend check's line opens no scope: its fix takes the delta
  check.
- **Delta check**: its `[behavior]` lines are the Owner's, listed with the ask or before the amend's author pass, no
  further check. An answer adding behavior takes a numbered amend and its `amend: <N>` check, a new scope; else
  Rulings.
- **Then**: after an append, or an amend and its check, ask for approval again. Open questions: append each wording
  answer, send the rest to one amend and its check, then ask.
- **Round spent**: once the round is spent, a behavior decision, the Owner's on a finding past the cap included,
  takes an amend and its check, one author pass beyond the cap with the amend alone, and a re-audit (section 3)
  whose findings reach the Owner with the drafts; no further round.
- **Text-only Owner change**: fix it per the `specstone-expert-sdd` skill, no amend.

## 2. Run the fix round

Drafts list: the first author report's drafts plus docs a round or pass added, renamed or dropped by section 3.

- **Fresh author**: each pass after the first is a new `mode: author` dispatch, never resumed, with the document's
  path, the drafts list, and `guide:` the first author's `Guide:` files. A fix round adds the audit's `Findings:`
  lines not tagged `[behavior]`; an amend's pass adds its design check's untagged lines naming a draft by
  `<type>:<name>#<key>`, siblings too. A line naming a doc outside the list is a Docs to change row.
- **`[behavior]` line** or behavior decision: never a fix round; an amend and its own check. The one fresh author
  pass after it is the round: amended design, drafts list, the audit's other lines.
- **`[style]`-only audit**: no round, no re-audit. Fix each line in place by `specstone set --replace`, run
  `specstone approve <drafts list> --dry-run --json`, and append one `Styled: <type>:<name>@<hash>` line per fixed
  draft to that audit's report file, `hash` as printed.
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

## 3. Re-audit only what changed

Items 1 to 3 run before each audit after the first; item 4 sends every audit.

1. Run one `specstone get <drafts list> --json`, no `--target`; keep each draft's `bases.doc`.
2. On `doc_not_found`, fix the list: a doc moved between rounds takes its new name (`moved <from> to <to>`); one
   deleted, or listed and never created, drops. Rerun.
3. A changed draft: `bases.doc` differs from its last `Audited:` hash, or it has none (a split's new FR). Run
   `specstone refs <changed draft>`: its `Inbound` lines give citers, listed drafts linking it or naming it in
   `traced_from`, one hop.
4. Send each audit as a fresh `specstone-sdd-auditor`, never resumed, with the document's path and `check:` the last
   author pass's `Check:` file, only with no doc write since it and no split since the last audit. Targets: changed
   drafts, docs the round or pass added, unchanged drafts citing a changed one; never an unchanged draft citing none
   (its finding stands) or a listed doc that is no draft (approved between rounds, or never written).
5. In the round note to the Owner, name each doc approved between rounds and each name item 2 renamed or dropped.
