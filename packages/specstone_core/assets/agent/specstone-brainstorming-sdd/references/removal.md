# Removing a decision

## 1. Design: an amend that removes a decision

`design.md` reads this for an amend that removes a decision, before the decision's owner doc and terms are named.

- **Read first**: read each doc its rows name in the saved files; the doc's text, not its rows, shows what the
  decision wrote. A doc the removal empties (no other decision's text left, or a required section or field emptied)
  is an open question, and no author takes the amend while it is open: a new FR only D3's rows name empties; an
  approved FR D3 only added a case to keeps its approved text. The Owner's answers: delete the doc by their own route,
  move the text under another decision, or keep the decision.
- **An author pass read it**: keep its heading as a stub, its amend list adding the removing amend and `, removed`:
  Amend 5 turns `(Amend 2)` into `(Amend 2, Amend 5, removed)`. One line `Removed: <reason>` replaces the body.
- **No author pass read it**: delete it with its rows. Never reuse an ID, stub or deleted.
- **Stub rows**: a row naming only the removed decision stays as a stub row; a row naming others too loses that ID
  from its Decisions cell, and a new stub row names the same doc. A stub row reads `take out the D<n> text: <sections>`
  in Sections, the sections the read found the text in, each with its item list or `whole` as `design.md` step 6
  gives, never `all`, and `D<n> (Amend <N>, removed)` in Decisions. No
  stub row asks to delete a doc.
- **A later amend** removing or adding a decision that names a doc the read covered runs the read and question again.

## 2. Author: a stub row

`author.md` reads this for a removed decision's stub row (`take out the D<n> text: <sections>`): take that text out
of each section it names; delete no doc. Its coverage row is that section, or `NOT LANDED` while the text stays; a
section that never held it reads as taken out.
