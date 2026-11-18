The runner follows this at its write step.

## 1. Check the inputs

- **Answers**: the Owner's approved answers in the conversation (decisions in the Owner's words, rulings, the approach
  picked, open questions); for a change from a source, also follow `## Map the source` in `source.md`.
- **Grounding**: the saved bundle files of your `context --for design --out` calls, read per `specstone-read-sdd`.
- **Design path**: the document to write or amend.

## 2. Ground each claim

Ground each claim in the saved files or an Owner's answer, citing only that text, and one on how a library, parser,
or tool the change calls behaves only by a read-only run in a scratch folder outside the docs, cited in one `Run:`
line (the command and its output line). A claim none grounds is an open question. The saved files ground a claim
about the Specstone CLI. Run no `get`, `search`, or `refs` for a doc.

Before any write, judge the design path by the saved files' `==> ` headers:

- **Inside the CheckedFolders** (a header's doc path's first folder right under the docs folder: `prds/`, `specs/`,
  and `measurements/` with the shipped packs; a deeper folder of that name is outside), or a PRD or spec doc: write
  nothing; the path is an open question; write at the Owner's new path.
- **Any other path**: the file to write: the host brainstorm skill's design document path, else
  `docs/designs/<YYYY-MM-DD>-<topic>-design.md`; read an existing one whole.

Cite each story, FR, and section as `<type>:<name>#<section>`, never by file path or line. A claim the docs
contradict is an open question. Open each code path and symbol the answers or saved files name.

## 3. Write the document

Sections, in order:

1. **Intent**: the change and its why, goals and non-goals, actors served, and vision IDs (`PV-…`) advanced.
2. **Constraints**: what the docs fix that the change keeps, each cited by name.
3. **Rulings**: each dated, in the Owner's words, scope words (`only`, `not`, `never`, `after`) verbatim, naming the
   text it supersedes.
4. **Approaches**: the one picked, and why each other lost.
5. **Decisions**: one per thing decided, ID `D1`, `D2`, ..., as the Owner decided it, with its rule's owner doc
   (`none` with no rule) and the terms you searched. One taking inputs or states (a rule with states, or one adding a
   key, flag, link form, refusal, or doc type target) gets an input table: a row per input or state, its result, and
   each command or skill reading it; a refusal's row quotes its message literal.
6. **Docs to change**: one row per doc: `<type>:<name>` (new: its type and parent), sections changed, decision IDs.
   A decision with no row gets a line on why no doc takes it. Each reached feature's `architecture` doc gets a
   `design_references` row linking this document, per `specstone guide architecture`. With two or more `targets:`,
   a per-target spec doc's row names its code target; a row with none is an open question.
7. **Open questions**: each gap neither the answers nor the saved files settle.

Before the Docs to change table closes, find each decision's dependents:

- Name its rule's owner doc (`specstone-expert-sdd` rule 7); the owner item's cited-by lines give the docs linking it.
  Run `specstone check <feature> --repeats` for the repeat groups holding that item.
- Search the saved files, every section of each row's doc included, for the decision's terms and the wording it
  supersedes, in every written form: with and without a trailing `/`, in backticks or not, singular and plural, and a
  short form.
- A doc restating the rule instead of citing its owner gets a row: link the owner's item, or rewrite the doc when it
  owns a rule reading the decision's rule.
- With no cited-by line, the repeat groups and text search carry the decision.
- An amend that adds or changes behavior, or removes a decision, runs these steps on its terms after the removal read
  in `removal.md`, adding its rows and searched terms before the author writes it.

Decide each point the answers leave open that a PRD or spec doc must state, such as a refusal or a name rule, naming
the one owner item its rule takes, or list it as an open question; a design holding an open one goes to no author.
Leave a code-level point, such as a class name, to the builder: no decision, no open question.

On an amend, edit every place still stating text a ruling supersedes. Number each amend (`Amend 1`, `Amend 2`, ...);
any edit of a decision an author pass read opens a new one, however small. Each decision an amend adds, changes, or
removes lists it in its heading, earlier amends kept: `(Amend 2, Amend 4)`.

For an amend that removes a decision, follow section 1 of `removal.md`: its read, stub, and stub rows.

Write or amend the file with your host's file write; write no other file, and no PRD or spec doc.

## 4. Check before you ask

No placeholder, no empty section but Open questions, no contradiction between sections or with a ruling, and each
decision specific enough that two builders would build the same thing.

Before the approval ask, check the saved files' sections outside the Docs to change rows for wording a decision
supersedes, a removed decision's text included, until none is left: each hit gets a row, a stub row for removed text.
This document is outside the check: it quotes that wording.

Then the skill's step 3 runs the design check. Fix each finding in the document: an untagged one by an edit; a
`[behavior]` one by deciding it, or asking the Owner if only they can, then section 3's dependents steps on its terms.

## 5. Tell the Owner

Give the path, written or amended. List each open question, each claim its saved files could not ground, and each code
path or symbol not found.
