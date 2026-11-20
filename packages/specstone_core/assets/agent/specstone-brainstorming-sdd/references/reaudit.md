# Re-audit only what changed

Items 1 to 3 run before each audit after the first; item 4 gives every audit's `check:`.

1. Run one `specstone get <drafts list> --json`, with no `--target`, and keep each draft's `bases.doc`.
2. When it refuses with `doc_not_found`, update the drafts list for each name it names: a doc moved between rounds
   takes the new name `move` printed (`moved <from> to <to>`), and a doc deleted, or listed and never created,
   drops out. Run the call again on that list.
3. For each changed draft, one whose `bases.doc` differs from its last `Audited:` hash or that has none (a split's
   new FR), run `specstone refs <changed draft>`. Its `Inbound` lines give its citers: a draft of the list that links to it or
   names it in `traced_from`, one hop only.
4. Send every re-audit as a fresh `specstone-sdd-auditor`, never a resumed one, with the document's path, `check:`
   the last author pass's `Check:` file with no doc write since it and no split since the last audit, and these targets:
   - A changed draft.
   - Each doc the round or pass added.
   - An unchanged draft that cites a changed draft.
   - Not an unchanged draft that cites no changed draft: its earlier finding stands.
   - Not a doc of the list that is no draft, approved between rounds or listed and never written.
5. In your round note to the Owner, name each doc approved between rounds and each name item 2 renamed or dropped.
