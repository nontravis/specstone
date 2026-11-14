`specstone:sdd-engineer` runs this in `mode: design`, its gate already made; so does `specstone:brainstorming-sdd`'s
runner without the `Agent` tool or after a failed dispatch. As the agent, ask the Owner nothing: each gap is an open
question in your report.

## 1. Check the inputs

- **Brief**: the Owner's approved answers: decisions, rulings in the Owner's words, the approach picked, and open
  questions. Read it whole. When it names a file to re-read, also follow `## Map the source` in
  `${CLAUDE_PLUGIN_ROOT}/skills/brainstorming-sdd/references/source.md`.
- **Design path**: the document to write or amend; step 2 judges it.

## 2. Ground each claim

Run `specstone context <target> --for design` on the smallest doc that holds the brief's whole change: the story
for a change inside one story, the feature for one across stories, the feature with `--summary` to add a story, and
the project doc to add a feature. Pass no `--target`: a design read spans every code target.
As the skill's runner, run no other call: your ground is what its step 1 gave, the bundle or `specstone:sdd-reader`'s
sections, and, for a change from a source, the gate call's bundle plus any `--no-project` call's or the reader's
sections.

- **0:** the bundle is your ground. Cite only what your ground holds.
- **Any other exit:** report the CLI's error and stop.

Before any write, judge the design path by that bundle:

- **A design path inside the CheckedFolders** (the first folder of a doc path a bundle header prints, right under the
  docs folder: `prds/` and `specs/` with the shipped packs; a deeper folder of that name is outside), or a PRD or spec
  doc named as the file: write nothing but the agent's `report:` file; report the path as an open question.
- **Any other design path**: the file to write, at the host brainstorm skill's design document path, else
  `docs/designs/<YYYY-MM-DD>-<topic>-design.md`. When it exists, read it whole.

Cite each story, FR, and section by its Specstone name, `<type>:<name>#<section>`, never by file path or line. A
claim in the brief that the docs contradict is an open question; a decision that changes what a doc says is a change,
mapped in step 3. Open each code path and symbol the brief names; list each not found under `Findings:`.

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
7. **Open questions**: each gap that neither the brief nor any doc bears on.

Before the Docs to change table closes, search each decision's dependents:

- Name the owner doc of the decision's rule (`specstone:expert-sdd` rule 7). Run `specstone refs <owner>` for the
  docs that cite it, and `specstone search` on the decision's terms and on the wording it supersedes. A per-target owner
  goes to `refs` by its DocPath.
- Each doc found that restates the rule instead of citing its owner gets a Docs to change row: its change cites the
  owner by name, or rewrites the doc when that doc owns a rule that reads the decision's rule.
- When `refs` lists no typed citer, as in a tree that still cites by number labels, the search carries the decision,
  as it does for the limit of `refs` that rule 7 names. Record the searched terms either way, so the audit sees what
  was searched.
- An amend for an Owner decision that adds or changes behavior runs the same search on that decision's
  terms and adds its rows and searched terms before the author writes it.

Leave out what a doc will carry verbatim: no story text, FR statement, scenario, edge case, endpoint shape, or an
entity's field list. Name the decision; the doc holds the content.

When you amend, sweep each ruling: search the document for the text it supersedes and edit every place
that still states it.

Write the file with `Write`, or amend it with `Edit` when it exists. Write no other file but the agent's `report:` file, and no PRD or spec doc.

## 4. Check before you report

- No placeholder, no `TBD`, and no empty section but Open questions.
- No section contradicts another, and no decision contradicts a ruling.
- Each decision is specific enough that two builders would build the same thing.

## 5. Report

```
Design document: <path>, written | amended
Sections touched: <each section an amend or a ruling sweep changed, or none>
Open questions:
- <a gap>
Findings: <each claim the bundle could not ground, each code path or symbol not found, or none>
```
