# Removing a decision

## 1. Design: an amend that removes a decision

- **Read first**: read each doc its rows name in the saved files; the doc's text, not its rows, shows what the
  decision wrote.
- A doc the removal empties (no other decision's text left, or a required section or field emptied) is an open
  question; no author takes the amend while it is open. The Owner answers: delete the doc their own way, move the
  text under another decision, or keep the decision.
- **An author pass read it**: keep its heading as a stub, its amend list adding the removing amend and `, removed`;
  one line `Removed: <reason>` replaces the body.
- **No author pass read it**: delete it with its rows. Never reuse an ID.
- **Stub rows**: a row naming only it stays as a stub row; a row naming others too drops its ID, and a new stub row
  names the same doc. A stub row's Sections cell reads `take out the D<n> text: <sections>`, each section the read
  found with its item list or `whole`, never `all`; its Decisions cell `D<n> (Amend <N>, removed)`. No stub row asks
  to delete a doc.
- A later amend removing or adding a decision on a doc the read covered runs the read and question again.

## 2. Author: a stub row

Take the text out of each section a stub row names; delete no doc. Its coverage row is that section, or
`NOT LANDED` while the text stays; a section that never held it reads as taken out.
