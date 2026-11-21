The runner of `specstone-brainstorming-sdd` reads this before each audit after the first: the audit after a fix round,
an amend pass, or a split's fill pass.

1. Run one `specstone get <drafts list> --json`, no `--target`; keep each draft's `bases.doc`.
2. On `doc_not_found`, fix the list: a doc moved between rounds takes its new name (`moved <from> to <to>`); one
   deleted, or listed and never created, drops. Rerun.
3. A changed draft: `bases.doc` differs from its last `Audited:` hash, or it has none (a split's new FR). A draft whose
   hash changed only by main's style writes, its `Styled:` hash its current one, is no changed draft. Run
   `specstone refs <changed draft>`: its `Inbound` lines give citers, listed drafts linking it or naming it in
   `traced_from`, one hop.
4. Targets: changed drafts, docs the round or pass added, unchanged drafts citing a changed one; never an unchanged
   draft citing none (its finding stands) or a listed doc that is no draft.
5. Pass three inputs beside the document's path and `check:`:
   - `findings:` the lines the round took: the last audit's untagged and `[behavior]` `Findings:` lines, and the
     untagged design-check lines it carried; none for a `[style]` line main fixed. The audit after the pass beyond
     the cap takes as `findings:` only the lines that pass carried; the audit after a fill pass run alone takes none.
     An Owner decision on a `- NOT ADDRESSED:` or `Outside the round:` item routes by section 1 of `rounds.md`, never
     as a `findings:` line.
   - `sections:` the last author pass's `Sections:` line.
   - `citers:` item 3's citers, drafts of the list alone.
6. In the round note to the Owner, name each doc approved between rounds and each name item 2 renamed or dropped.
