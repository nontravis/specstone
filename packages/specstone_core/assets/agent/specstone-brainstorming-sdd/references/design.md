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
   (`none` with no rule) and the terms it adds, changes, or supersedes. One taking inputs or states (a rule with
   states, or one adding a key, flag, link form, refusal, or doc type target) gets an input table, written before the
   author runs: a row per input or state, its result, and each command or skill reading it; a refusal's row quotes its
   message literal.
6. **Docs to change**: one row per doc: `<type>:<name>` (new: its type and parent), each changed section by its `get`
   key (an item list in parentheses is a hint), or `whole` for a new doc or a rewrite of every section, decision IDs.
   A decision with no row gets a line on why no doc takes it. Each doc the design check finds restating a decision's
   rule gets a row: remove the copy and link the owner's item; when it owns a rule reading the decision's rule, rewrite
   it. An `architecture` doc gets a `design_references` row linking this document, per `specstone guide
   architecture`, only when its section states a decision of this design after the change, linking each design whose
   decisions it still states; a feature merely reached takes none, nor does a doc whose only change swaps a copy for a link. With two or more `targets:`, a per-target
   spec doc's row names its code target; a row with none is an open question.
7. **Open questions**: each gap neither the answers nor the saved files settle.

The runner runs no dependents search: the design check sweeps every reader. An amend that adds or changes behavior, or
removes a decision, names its owner doc and terms the same way, after the removal read in `removal.md`, and adds its
rows before the author writes it.

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

Then the skill's step 3 runs the design check. Fix each finding in the document: an untagged one by an edit; a
`[behavior]` one by deciding it, or asking the Owner if only they can, then naming its owner doc and terms.

Ask for approval only once no design-check line is left naming a reader or a wording a decision supersedes outside the
Docs to change rows, a removed decision's text included: each such line gets a row (a stub row for removed text). This document is outside the sweep: it quotes that wording.

## 5. Tell the Owner

Give the path, written or amended. List each open question, each claim its saved files could not ground, and each code
path or symbol not found.
