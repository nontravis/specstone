## 1. Inputs

Write from the Owner's approved answers and the saved bundle files; for a change from a source, also follow
`## Map the source` in `source.md`.

## 2. Ground each claim

- Ground each claim in the saved files or an Owner answer, citing only that text; the saved files ground a claim
  about the Specstone CLI.
- Ground a claim on how a library, parser, or tool behaves only by a read-only run in a scratch folder outside the
  docs, cited in one `Run:` line (the command and its output line).
- A claim nothing grounds, or the docs contradict, is an open question.
- Run no `get`, `search`, or `refs` for a doc. Open each code path and symbol the answers or saved files name.
- Cite each story, FR, and section as `<type>:<name>#<section>`, never by file path or line.
- Before any write, judge the design path by the saved files' `==> ` headers. Inside the CheckedFolders (a header
  doc path's first folder right under the docs folder, never a deeper one), or a PRD or spec doc: write nothing; the
  path is an open question. Any other path: write it; read an existing one whole.

## 3. Write the document

Sections, in order:

1. **Intent**: the change and its why, goals and non-goals, actors served, vision IDs (`PV-…`) advanced.
2. **Constraints**: what the docs fix that the change keeps, each cited by name.
3. **Rulings**: each dated, in the Owner's words, scope words (`only`, `not`, `never`, `after`) verbatim, naming the
   text it supersedes.
4. **Approaches**: the one picked, and why each other lost.
5. **Decisions**: `D1`, `D2`, ..., one per thing decided, as the Owner decided it, with its rule's owner doc (`none`
   with no rule) and the terms it adds, changes, or supersedes. One taking inputs or states (a rule with states, or
   one adding a key, flag, link form, refusal, or doc type target) gets an input table before the author runs: a row
   per input or state, its result, and each command or skill reading it; a refusal's row quotes its message literal.
6. **Docs to change**: one row per doc: `<type>:<name>` (new: its type and parent); each changed section by its
   `get` key with its item list in parentheses (item IDs, a row's first cell, a node ID, a scenario number, quoted
   words; `new E19` if added; `E24: <note>`), `<key> whole` for one rewritten whole, or `whole` for a new doc or a
   rewrite of every section; decision IDs.
   - A key with neither: a design-check line.
   - Each amend's rows form an `Amend <N> rows` table; a landed one is no later target.
   - A decision with no row gets a line on why.
   - A doc the sweep finds restating a decision's rule gets a row: remove the copy and link the owner's item;
     rewrite a reader that owns a rule.
   - An `architecture` doc gets a `design_references` row linking this document (`specstone guide architecture`)
     only when its section states a decision of this design after the change, linking each design it still states;
     a feature merely reached, or a doc only swapping a copy for a link, takes none.
   - With two or more `targets:`, a per-target spec doc's row names its code target; a row with none is an open
     question.
7. **Open questions**: each gap neither the answers nor the saved files settle.

- Take each reader from a sweeper's `Rows:` lines; run no reader search.
- An amend that adds or changes behavior, or removes a decision, names its owner doc and terms and adds its rows
  before the author writes it, a removal first by section 1 of `removal.md`: its read, stub, and stub rows.
- Decide each open point a PRD or spec doc must state (a refusal, a name rule), naming its one owner item, or list it
  as an open question; a design holding one goes to no author.
- Leave a code-level point (a class name) to the builder: no decision, no open question.
- On an amend, edit every place still stating text a ruling supersedes.
- Number amends `Amend 1`, `Amend 2`, ...; any edit of a decision an author pass read opens a new one; any other fix opens none.
- Each decision an amend adds, changes, or removes lists it in its heading, earlier ones kept: `(Amend 2, Amend 4)`.
- Write by the host's file write; write no other file but the snapshot (`rounds.md` section 1), and no PRD or spec
  doc.

## 4. Check before you ask

- No placeholder, no empty section but Open questions, no contradiction between sections or with a ruling; each
  decision specific enough that two builders would build the same thing.
- Fix each design-check finding: an untagged one by an edit; a `[behavior]` one by deciding it, or asking the Owner
  if only they can, then naming its owner doc and terms.
- Ask for approval only when no design-check line names a reader or a superseded wording outside the Docs to change
  rows, a removed decision's text included; give each a row (a stub row for removed text). This document is outside
  the sweep.

## 5. Tell the Owner

The path, written or amended; each open question, each claim the saved files could not ground, and each code path or
symbol not found.
