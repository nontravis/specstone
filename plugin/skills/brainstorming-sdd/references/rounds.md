The runner of `specstone:brainstorming-sdd` follows this from the first design-mode reply until the Owner approves
the drafts. Its rules are those of `agent_plugin/write_prd_and_spec/run_brainstorm_to_design`, each cited by its edge
case. Each dispatch passes `report:`, and each reply goes to the Owner, as the skill's step 3 says.

## 1. Route each Owner decision

A decision adds or changes behavior when it brings a new state, input, output, edge case, error, or reader of a
rule (E12). Every other decision only words or records one.

- **Only words or records**: append it to the design document's Rulings yourself, as design mode writes them, and
  dispatch nothing; the author, or the fix round under way, goes on (E07, E12).
- **Adds or changes behavior**, or needs more PRD or spec grounding: add it to the brief and dispatch `mode: design`
  again with the brief's path and the document's path, an amend of the same file. Design mode searches the
  decision's terms (`references/design.md`) before the author writes it (E07, E12).
- **Before the author**: after an append or an amend, ask for the approval again (E07). When the design report holds
  open questions, gather the Owner's answers, append each that only words or records one, send the rest to one
  amend, and ask for the approval only after it (E10).
- **During fix rounds**: an amend, then one fresh author pass and a re-audit, as step 2 says (E12).
- **After the second fix round**, the Owner's decision on a finding past the cap included (E06): an amend, then one
  author pass that carries the amend alone and is no fix round, then a re-audit (step 3) whose findings reach the
  Owner with the drafts, with no further round. Fix an Owner change that only corrects text per
  `specstone:expert-sdd`, with no amend (E12).

## 2. Run the fix rounds

The drafts list is the first author report's drafts plus each doc a fix round or pass added, renamed or dropped as
step 3 says.

- **A fresh author**: every author pass after the first, each fix round and the pass that follows an amend, is a new
  `mode: author` dispatch, never the resumed one (E05). It takes the document's path and the drafts list; a fix
  round adds the audit's `Findings:` lines that carry no `[behavior]` tag, those that only correct text against the
  design. The author re-reads those drafts before its first write
  (`agent_plugin/write_prd_and_spec/write_drafts_with_coverage` E12) and fixes only those findings, in those drafts.
- **A `[behavior]` line** never goes to a fix round: put it, with the decision that answers it, in the brief for an
  amend (step 1). The one fresh author pass after the amend takes the amended design and the drafts list. When the
  audit that raised it also holds untagged lines, that pass takes them too and counts as a fix round; a pass that
  carries the amend alone is no fix round (E12).
- **The cap**: run at most two fix rounds, counted across an amend. Lines left after the second get no third round:
  the Owner sees them with the drafts before approving any, and their decision on one takes step 1's route (E06).
- After each fix round, and after each pass that follows an amend, re-audit as step 3 says.

## 3. Re-audit only what changed

1. Run one `specstone get <drafts list> --json` and keep each draft's `bases.doc`.
2. When it refuses with `doc_not_found`, update the drafts list for each name it names: a doc moved between rounds
   takes the new name `move` printed (`moved <from> to <to>`), and a doc deleted, or listed and never created,
   drops out. Run the call again on that list.
3. Dispatch a fresh `mode: audit` with the document's path and, as its targets, the drafts whose `bases.doc`
   differs from their last `Audited:` hash, plus each doc the round or pass added.
   - A draft whose hash equals its last `Audited:` hash is not read again; its earlier finding stands.
   - A doc of the list that is no draft, approved between rounds or listed and never written, is no target.
4. In your round note to the Owner, name each doc approved between rounds and each name step 2 renamed or dropped
   (E13).
