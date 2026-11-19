Run this until the Owner approves the drafts.

## 1. Route each Owner decision

A decision adds or changes behavior when it brings a new state, input, output, edge case, error, or reader of a
rule. Removing a decision changes behavior too: it takes an amend and its design check. Every other decision only
words or records one.

- **A refused design path**, an open question with no document written: append nothing; write the document at the
  Owner's new path, by `design.md`.
- **Only words or records**: append it to the design document's Rulings, as `design.md` writes them;
  dispatch nothing, no design check; the author, or the fix round under way, goes on.
- **Adds or changes behavior**, or needs more PRD or spec grounding: ground a doc newly reached by its own
  `specstone context <doc> --for design --out`, never `get`, then amend the same file. `design.md` finds the
  decision's dependents before the author writes it. When the amend adds or changes behavior, dispatch the design
  check per the skill's step 3, `amend: <N>`; amends made before the approval ask share one,
  `amend: <N>[,<N> ...]`. Your fix of its findings, an Owner answer included, is no amend; a `[behavior]`
  fix takes one second check of the same scope, never a third.
- **Before the author**: after an append, or an amend and its check, ask for the approval again. When the design
  document holds open questions, gather the Owner's answers, append each that only words or records one, send the
  rest to one amend and its check, and ask for the approval only after it.
- **During fix rounds**, a decision that adds or changes behavior takes an amend and its own check before its author
  pass, then one fresh author pass, counted toward the cap, and a re-audit, as section 2 says.
- **Once two rounds are spent**, a decision that adds or changes behavior, the Owner's decision on a finding past the
  cap included, takes an amend and its check, then one author pass that carries the amend alone, the one pass beyond
  the cap, then a re-audit (section 3) whose findings reach the Owner with the drafts, with no further round. Fix an
  Owner change that only corrects text per the `specstone-expert-sdd` skill, with no amend.

## 2. Run the fix rounds

The drafts list is the first author report's drafts plus each doc a fix round or pass added, renamed or dropped as
section 3 says.

- **A fresh author**: every author pass after the first, each fix round and the pass that follows an amend, is a new
  `mode: author` dispatch, never the resumed one. It takes the document's path, the drafts list, and `guide:` the
  first author's `Guide:` files; a fix round adds the audit's `Findings:` lines that carry no `[behavior]` tag
  (`[style]` too), and the pass after an amend each untagged line of its design check that names a draft. The author
  re-reads those drafts before its first write, then fixes those findings and each same-class hit, `[style]` hits
  included, as `author.md`'s Sweep each changed rule gives.
- **A `[behavior]` line** never goes to a fix round: take it, with its answering decision, to an amend (section 1).
  The one fresh author pass after takes the amended design and the drafts list, and the untagged lines of the audit
  that raised it.
- **A `[style]`-only audit** spends no round and gets no re-audit: fix each line in place by `specstone set --replace`.
  Run `specstone approve <drafts list> --dry-run --json`, then append to that audit's report file one
  `Styled: <type>:<name>@<hash>` line per fixed draft, `hash` as that call prints it.
- **A split proposal** the Owner okays: run its `specstone move` commands as an author's `Move:` lines. The new FRs
  join the drafts list, and a fresh author pass fills them before any audit: it joins the next round when one is due,
  else it is no round. Then the amend compare below.
- **The cap**: run at most two rounds, fix rounds and amend passes alike; no design check counts. Lines left after the
  second get no third round: the Owner sees them with the drafts before approving any, and their decision on one takes
  section 1's route.
- After each fix round, and after each pass that follows an amend, re-audit as section 3 says.
- **Before every audit dispatch**, the skill's step 4 audit included, compare the design's last amend, the highest
  `Amend <N>` its headings list or `0`, with the `amend <N>` of the last author relay block's first line,
  `Design: <path>, amend <N>`:
  - The two equal: dispatch the audit.
  - The design's higher: run a fresh author pass with the amend first, as a pass after an amend above, then the audit.
  - No `Design:` line: run a fresh author pass first.

## 3. Re-audit only what changed

1. Run one `specstone get <drafts list> --json` and keep each draft's `bases.doc`. The drafts list's names need no
   `--target`.
2. When it refuses with `doc_not_found`, update the drafts list for each name it names: a doc moved between rounds
   takes the new name `move` printed (`moved <from> to <to>`), and a doc deleted, or listed and never created,
   drops out. Run the call again on that list.
3. For each draft whose `bases.doc` differs from its last `Audited:` hash, a changed draft, run
   `specstone refs <changed draft>`. Its `Inbound` lines give its citers: a draft of the list that links to it or
   names it in `traced_from`, one hop only.
4. Send every re-audit as a fresh `mode: audit`, never as a follow-up to an earlier audit's agent, with
   the document's path, `check:` the last author pass's `Check:` file when no `Move:` ran since, and these targets:
   - A changed draft.
   - Each doc the round or pass added.
   - An unchanged draft that cites a changed draft.
   - Not an unchanged draft that cites no changed draft: its earlier finding stands.
   - Not a doc of the list that is no draft, approved between rounds or listed and never written.
5. In your round note to the Owner, name each doc approved between rounds and each name item 2 renamed or dropped.
