The runner follows this at its write step.

## 1. Check the inputs

- **Answers**: the Owner's approved answers in the conversation (decisions in the Owner's words, rulings, the approach
  picked, open questions). For a change from a source, also follow `## Map the source` in `source.md`.
- **Grounding**: the saved bundle files of your `context --for design --out` calls, read per the
  `specstone-read-sdd` skill.
- **Design path**: the document to write or amend.

## 2. Ground each claim

Ground each claim in the saved bundle files of your `context` calls or in an Owner's answer, and cite only that text.
A claim neither grounds is an open question. Run no `get`, no `search`, and no `refs` for a doc.

Ground a claim about how a library, parser, or tool the change calls behaves only by a read-only run in a scratch
folder outside the docs, cited in one `Run:` line: the command and its output line. With no run, the claim is an open
question. The saved files ground a claim about the Specstone CLI.

Before any write, judge the design path by the saved files' `==> ` headers:

- **A design path inside the CheckedFolders** (the first folder of a doc path a saved bundle's `==> ` header holds,
  right under the docs folder: `prds/`, `specs/`, and `measurements/` with the shipped packs; a deeper folder of
  that name is outside), or a PRD or spec doc named as the file:
  write nothing; the path is an open question, and you write at the Owner's new path in its place.
- **Any other design path**: the file to write, at the host brainstorm skill's design document path, else
  `docs/designs/<YYYY-MM-DD>-<topic>-design.md`. When it exists, read it whole.

Cite each story, FR, and section by its Specstone name, `<type>:<name>#<section>`, never by file path or line. A
claim the docs contradict is an open question. Open each code path and symbol the Owner's answers or the saved files
name.

## 3. Write the document

Sections, in order:

1. **Intent**: the change and its why, goals and non-goals, actors served, and vision IDs (`PV-…`) advanced.
2. **Constraints**: what the docs fix that the change keeps, each cited by name.
3. **Rulings**: each dated, in the Owner's words, scope words (`only`, `not`, `never`, `after`)
   verbatim, naming the text it supersedes.
4. **Approaches**: the one picked, and why each other lost.
5. **Decisions**: one per thing decided, with an ID (`D1`, `D2`, ...), as the Owner decided it, its rule's
   owner doc (`none` with no rule), and the terms you searched for it. A decision that takes inputs or states (a rule
   with states, or one that adds a key, a flag, a link form, a refusal, or a doc type target) also gets an input
   table: one row per input or state, the result it gives, and each command or skill reading it. A refusal's row
   quotes its message literal.
6. **Docs to change**: a table, one row per doc: its `<type>:<name>` (a new doc: its type and parent), the sections
   it changes, and the decision IDs it carries. Every decision has a row, or a line on why no doc takes it. Each
   reached feature's `architecture` doc gets a `design_references` row linking this document, as
   `specstone guide architecture` says. With two or more `targets:`, a per-target spec doc's row also names its code
   target, a row with none an open question.
7. **Open questions**: each gap neither the Owner's answers nor the saved files settle.

Before the Docs to change table closes, find each decision's dependents:

- Name the owner doc of the decision's rule (`specstone-expert-sdd` rule 7); its owner item's cited-by lines give the
  docs that link it.
- Run `specstone check <feature> --repeats` for the repeat groups holding the owner item.
- Search the saved files for the decision's terms and the wording it supersedes, each in every written form: with
  and without a trailing `/`, in backticks or not, singular and plural, and a short form. Search every section of
  each doc in a row.
- Each doc found restating the rule instead of citing its owner gets a row: its change links the owner's item, or
  rewrites the doc when it owns a rule reading the decision's rule.
- With no cited-by line, the repeat groups and the text search carry the decision; record the searched terms either
  way.
- An amend that adds or changes behavior, or removes a decision (behavior too), runs these steps on its terms, after
  the removal read below, adding its rows and searched terms before the author writes it.

Decide each point the Owner's answers leave open that a PRD or spec doc must state, such as a refusal or a name rule,
naming the one owner item its rule takes, or list it as an open question; a design holding one open goes to no
author. Leave a code-level point, such as a class name, to the builder: no decision, no open question.

On an amend, edit every place still stating text a ruling supersedes. Number each amend (`Amend 1`, `Amend 2`,
...); any edit of a decision an author pass has read opens a new one, however small. Each decision an amend adds,
changes, or removes lists it in its heading, earlier amends kept, such as `(Amend 2, Amend 4)`.

An amend that removes a decision:

- **Read first**: read each doc its rows name, in the saved files; the doc's text, never its row names, says what the
  decision wrote there. A doc the removal would empty is an open question for the Owner, and no author takes the
  amend while it is open. Empty: no other decision's text left, or a required section or field emptied. A new FR only
  D3's rows name is emptied; an approved FR D3 only added a case to keeps its approved text. The Owner answers: delete
  the doc by their own route, move the text under another decision, or keep the decision.
- **An author pass read it**: keep its heading as a stub. The removing amend joins the amend list, which then ends
  `, removed`: Amend 5 removing a decision headed `(Amend 2)` gives `(Amend 2, Amend 5, removed)`. One line
  `Removed: <reason>` replaces the body.
- **No author pass read it**: delete it with its rows.
- Never reuse an ID, stub or deleted.
- **Stub rows**: keep them. A row naming the removed decision alone stays and becomes a stub row; a row naming it
  among others loses the ID from its Decisions cell, and a new stub row names the same doc. A stub row reads
  `take out the D<n> text: <sections>` in Sections and `D<n> (Amend <N>, removed)` in Decisions. `<sections>` are
  the sections the read found the text in, never `all`. No stub row asks the author or the audit to delete a doc.
- **A later amend** that removes or adds a decision naming a doc the read covered runs the read and question again.

Write or amend the file with your host's file write; write no other file, and no PRD or spec doc.

## 4. Check before you ask

No placeholder, no empty section but Open questions, no contradiction between sections or with a ruling,
and each decision specific enough that two builders would build the same thing.

Before the approval ask, check each saved file's sections outside the Docs to change rows for a wording a decision
supersedes: each found gets a row. Ask only once none is left. The text a removed decision stated is such wording;
its row is a stub row. This document is outside the check: it quotes that wording.

Then the skill's step 3 runs the design check. Fix each finding in the document: an untagged one by an edit;
a `[behavior]` one by deciding it, or asking the Owner if only they can, then section 3's dependents steps on its
terms.

## 5. Tell the Owner

Give the path, written or amended. List each open question, each claim its saved files could not ground, and each code
path or symbol not found.
