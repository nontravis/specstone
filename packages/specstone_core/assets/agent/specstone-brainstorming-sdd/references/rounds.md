Run this until the Owner approves the drafts.

## 1. Route each Owner decision

A decision adds or changes behavior when it brings a new state, input, output, edge case, error, or reader of a
rule. Every other decision only words or records one.

- **A refused design path**, an open question with no document written: append nothing; write the document at the
  Owner's new path in place of the refused one, by `design.md`.
- **Only words or records**: append it to the design document's Rulings yourself, as `design.md` writes them, and
  dispatch nothing; the author, or the fix round under way, goes on.
- **Adds or changes behavior**, or needs more PRD or spec grounding: ground a doc newly reached by its own
  `specstone context <doc> --for design --out`, never `get`, then amend the same file yourself. `design.md` finds the
  decision's dependents before the author writes it.
- **Before the author**: after an append or an amend, ask for the approval again. When the design document holds
  open questions, gather the Owner's answers, append each that only words or records one, send the rest to one
  amend, and ask for the approval only after it.
- **During fix rounds**, a decision that adds or changes behavior takes an amend, then one fresh author pass and a
  re-audit, as section 2 says.
- **After the second fix round**, a decision that adds or changes behavior, the Owner's decision on a finding past the
  cap included, takes an amend, then one author pass that carries the amend alone and is no fix round, then a
  re-audit (section 3) whose findings reach the Owner with the drafts, with no further round. Fix an Owner change
  that only corrects text per the `specstone-expert-sdd` skill, with no amend.

## 2. Run the fix rounds

The drafts list is the first author report's drafts plus each doc a fix round or pass added, renamed or dropped as
section 3 says.

- **A fresh author**: every author pass after the first, each fix round and the pass that follows an amend, is a new
  `mode: author` dispatch, never the resumed one. It takes the document's path and the drafts list; a fix
  round adds the audit's `Findings:` lines that carry no `[behavior]` tag, those that only correct text against the
  design. The author re-reads those drafts before its first write, then fixes those findings and each same-class hit
  as `author.md`'s Sweep each changed rule gives.
- **A `[behavior]` line** never goes to a fix round: take it, with the decision that answers it, to an
  amend (section 1). The one fresh author pass after the amend takes the amended design and the drafts list. When the
  audit that raised it also holds untagged lines, that pass takes them too and counts as a fix round; a pass that
  carries the amend alone is no fix round.
- **The cap**: run at most two fix rounds, counted across an amend. Lines left after the second get no third round:
  the Owner sees them with the drafts before approving any, and their decision on one takes section 1's route.
- After each fix round, and after each pass that follows an amend, re-audit as section 3 says.

## 3. Re-audit only what changed

1. Run one `specstone get <drafts list> --json` and keep each draft's `bases.doc`. The drafts list's names need no
   `--target`.
2. When it refuses with `doc_not_found`, update the drafts list for each name it names: a doc moved between rounds
   takes the new name `move` printed (`moved <from> to <to>`), and a doc deleted, or listed and never created,
   drops out. Run the call again on that list.
3. For each draft whose `bases.doc` differs from its last `Audited:` hash, a changed draft, run
   `specstone refs <changed draft>`. Its `Inbound` lines give its citers: a draft of the list that links to it or
   names it in `traced_from`, one hop only.
4. Send every re-audit as a fresh `mode: audit`, never as a follow-up message to the agent of an earlier audit, with
   the document's path and these targets:
   - A changed draft.
   - Each doc the round or pass added.
   - An unchanged draft that cites a changed draft.
   - Not an unchanged draft that links to no changed draft: its earlier finding stands.
   - Not a doc of the list that is no draft, approved between rounds or listed and never written.
5. In your round note to the Owner, name each doc approved between rounds and each name item 2 renamed or dropped.
