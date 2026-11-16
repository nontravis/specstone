The runner of `specstone-brainstorming-sdd` follows this at its write step, its gate already made and the Owner's
answers in hand. Each gap is an open question in the design document.

## 1. Check the inputs

- **Answers**: the Owner's approved answers in the conversation (decisions in the Owner's words, rulings, the approach
  picked, open questions). When they name a file to re-read, also follow `## Map the source` in `source.md`.
- **Grounding**: the saved bundle files of your `context --for design --out` calls, read per the
  `specstone-read-sdd` skill.
- **Design path**: the document to write or amend.

## 2. Ground each claim

Ground each claim in the saved bundle files of your `context` calls or in an Owner's answer, and cite only that text.
A claim neither grounds is an open question. Run no `get`, no `search`, and no `refs` for a doc.

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

Sections, in this order:

1. **Intent**: the change and its why, goals and non-goals, the actors it serves, and the vision IDs (`PV-…`)
   it advances, in a few lines.
2. **Constraints**: what the docs fix that the change keeps, each cited by name.
3. **Rulings**: each dated, in the Owner's words with the scope words (`only`, `not`, `never`, `after`)
   verbatim, each naming the text it supersedes.
4. **Approaches**: the one picked, and why each other lost.
5. **Decisions**: one per thing decided, with an ID (`D1`, `D2`, ...), as the Owner decided it, its rule's
   owner doc (`none` for a decision with no rule, such as a pure ruling or an approach pick), and the terms you
   searched for it. A decision whose rule has states, such as a refusal set or a set of name forms, also gets a table
   of each state against each command or skill that reads it.
6. **Docs to change**: a table, one row per doc: its `<type>:<name>` (a new doc: its type and parent), the sections
   it changes, and the decision IDs it carries. Every decision has a row, or a line saying why no doc takes it. A
   ruling that supersedes doc text gets a row for each doc that states it. Each feature the change reaches with
   an `architecture` doc gets a row for its `design_references` section, a link to this document, kept or dropped as
   the `Design references` section of `specstone guide architecture` says. With two or more `targets:`, a
   per-target spec doc's row also names its code target, a row with none an open question.
7. **Open questions**: each gap that neither the Owner's answers nor the saved files bear on.

Before the Docs to change table closes, find each decision's dependents in your saved files, with no `search` and no
`refs` call:

- Name the owner doc of the decision's rule (`specstone-expert-sdd` rule 7). The owner item's cited-by lines in the
  saved files give the docs that link it.
- Run `specstone check <feature> --repeats` for the repeat groups that hold the owner item, and search the saved files'
  text for the decision's terms and for the wording it supersedes.
- Each doc found that restates the rule instead of citing its owner gets a Docs to change row: its change links the
  owner's item that holds the rule, or rewrites the doc when that doc owns a rule that reads the decision's rule.
- When the owner item has no cited-by line, as in a tree that still cites by number labels, the repeat groups and the
  text search carry the decision. Record the searched terms either way, so the audit sees what was searched.
- An amend for an Owner decision that adds or changes behavior runs the same steps on that decision's
  terms and adds its rows and searched terms before the author writes it.

Decide a point a PRD or spec doc must state, such as a refusal or a name rule, that the Owner's answers leave open,
naming the one owner item its rule takes, or list it as an open question; a design holding such a point open goes to
no author. Leave a code-level point, such as a class name, to the builder, with no decision and no open question.

Leave out what a doc will carry verbatim (story text, FR statement, scenario, edge case, endpoint shape, an entity's
field list): name the decision.

On an amend, sweep each ruling: search the document for the text it supersedes and edit every place that still states
it.

Write the file, or amend it when it exists, with your host's file write. Write no other file, and no PRD or spec doc.

## 4. Check before you ask

No placeholder, no empty section but Open questions, no contradiction between sections or with a ruling,
and each decision specific enough that two builders would build the same thing.

## 5. Tell the Owner

Give the path, written or amended. List each open question, each claim its saved files could not ground, and each code
path or symbol not found.
