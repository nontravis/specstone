`specstone:sdd-engineer` runs this in `mode: design`, its gate already made; so does the runner of
`specstone:brainstorming-sdd` when it has no `Agent` tool or the dispatch failed. As the agent, ask the Owner
nothing: each gap goes into your report as an open question.

The design document is the Owner's approval surface, not a draft of the docs: it records what was decided and why,
and the PRD and spec docs carry the content once the Owner approves it.

## 1. Check the inputs

- **Brief**: the Owner's approved answers: the decisions, the rulings in the Owner's own words, the approach picked,
  and the open questions. Read it whole.
- **Design document**: the file to write, under `docs/superpowers/specs/`, named `<YYYY-MM-DD>-<topic>-design.md`.
  When it exists, read it whole: you amend it with `Edit` and never write a second file.
- **A path outside `docs/superpowers/specs/`, or a PRD or spec doc named as the file:** write nothing; report the
  path as an open question.

## 2. Ground each claim

For each feature the brief touches, run `specstone context <target> --for design`; a change that adds a feature
targets `project`. As the skill's runner, its step 1 bundle is your ground: run no second call.

- **0:** the printed bundle is the ground. Cite only what it printed.
- **Any other exit:** report the CLI's error and stop.

Cite each story, FR, and section by its Specstone name, `<type>:<name>#<section>`, never by file path or line. A
claim in the brief that the docs contradict is an open question; a decision that changes what a doc says is a change,
mapped in step 3.

## 3. Write the document

Sections, in this order:

1. **Intent**: the change and its why, its goals and non-goals, in a few lines.
2. **Constraints**: what the docs already fix that the change keeps, each cited by name.
3. **Rulings**: each dated, in the Owner's own words with the scope words (`only`, `not`, `never`, `after`)
   verbatim, each naming the text it supersedes.
4. **Approaches**: the one picked, and why each other lost.
5. **Decisions**: one per thing decided, each with its own ID (`D1`, `D2`, ...), as the Owner decided it.
6. **Docs to change**: a table, one row per doc: its `<type>:<name>` (a new doc: its type and parent), the sections
   it changes, and the decision IDs it carries. Every decision has a row, or a line saying why no doc takes it.
7. **Open questions**: each gap that neither the brief nor any doc bears on.

Leave out what a doc will carry verbatim: no story text, FR statement, scenario, edge case, endpoint shape, or list of
an entity's fields. Name the decision and let the doc hold the content: "three stories, split by payout state", not
three drafted stories. Restate nothing the bundle says; cite it.

Write the file with `Write`, or the change with `Edit` when it exists. Write no other file and no PRD or spec doc.

## 4. Check before you report

- No placeholder, no `TBD`, and no empty section but Open questions.
- No section contradicts another, and no decision contradicts a ruling.
- Each decision is specific enough that two builders would build the same thing.
- Each claim about the project cites a doc the bundle printed.

## 5. Report

```
Design document: <path>, written | amended
Open questions:
- <a gap neither the brief nor any doc bears on>
Findings: <each claim the bundle could not ground, or none>
```
