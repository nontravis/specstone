---
name: specstone-brainstorming-sdd
description: Use when a change to a Specstone project adds a feature, a user story, or an FR, or reaches more than one PRD or spec doc, such as brainstorming a new feature, reshaping an existing one, or taking in a spec or design another tool wrote, or when another Specstone skill names `specstone-brainstorming-sdd`.
---

# Brainstorm a change into an approved design

A change rewriting one section or field, adding no story or FR: follow the `specstone-update-sdd` skill.

## 1. Ground: the first call

Target the smallest doc holding the whole change:

- One story: the story. A feature doc: the feature. A new feature: the project doc.
- Several stories: name each in one call, never the feature. Several docs: each in one call.
- Several docs picked from the docs tree: the gate is `specstone structure <doc> …`; on 0 name in one `context`
  call each doc its map shows the change reaching; else act as below.
- A story added runs no `structure`. Alone: one call, the feature with `--summary`. With existing docs too: that
  call, then one naming each existing doc.

Make the gate your first CLI call, before any doc or code read: `structure`, else `context`. On each
grounding call keep `--out` bare and last, with no `--budget` or `--target`.

```
specstone context <target> [<target> …] --for design --out
```

- **0:** the saved files are the ground. Before the first question, read them per the `specstone-read-sdd` skill,
  each read-first file by its read plan. Ground a doc they lack by its own
  `specstone context <doc> --for design --out`, never `get`; open no doc file.
- **78, `project_not_found`:** tell the Owner no Specstone project is found here; `specstone init` starts one.
  Stop; run nothing more, read or write no doc.
- **Any other exit:** report the CLI's error and stop.

From a source (another tool's spec or design, a link, or an issue) the first call is
`specstone context project --for design --out`; read the source only after it exits 0, then follow
`## Take in the source` in `references/source.md`.

Adding a story or feature: after the call, run `specstone guide feature`, answer its placement questions, and show
the Owner each answer; go on only after their yes.

## 2. Dialogue until the Owner picks an approach

The brainstorm skill is the listed skill whose description, never its name, says it turns a change into a design
by dialogue. No Specstone skill qualifies. Of two such skills take the one the project's instruction file
(`CLAUDE.md`, `AGENTS.md`) names, else the first listed.

- **A skill qualifies:** run it on step 1's grounding; it keeps the conversation. Write the change note at
  its write step; invoke nothing at its hand-off to a plan or build skill. Specstone's rules win.
- **None qualifies:** ask one question per message until scope, behavior, edge cases, and exclusions are clear; offer
  two or three approaches with trade-offs, recommending one; then write the change note.

Write no PRD or spec doc and dispatch no writer until the Owner picks an approach.

## 3. Write the change note

Write the change note by `references/design.md`, from step 1's saved files, the Owner's answers, and dependency
runs. Dispatch nothing to write it. It proposes each new or reshaped feature's `patterns:` value from
`specstone guide --pattern`.

Ask the Owner each open question a doc must state, and write the answer into the note. Dispatch no writer while one
is open. Then route the change by `references/class.md`: only an Undecided change takes steps 4 to 6.

## 4. Write the drafts, check them once

After step 1, run `specstone folder` once for `<folder>`. Each dispatch follows
`../specstone-expert-sdd/references/dispatch.md`, passing `report:` `<folder>/reports/sdd-engineer.author.<XXXXXX>.md`
or `<folder>/reports/sdd-auditor.audit.<XXXXXX>.md`. `XXXXXX` is six `a-z0-9` characters, picked again while that file
exists. Show the Owner each reply's `Report:` line, then its relay block word for word, before your notes, also under
`auto`, with no wait. Write no brief, rerun no `context` on a grounded target bar the `--groups` call.

1. Before the first writer dispatch, run `specstone context <every Reach doc> --for design --out --groups` once; a
   doc the change creates is no Reach doc, its parent is. Dispatch `specstone-sdd-engineer`, `mode: author`,
   `change note:` path. One group (no `==> group` line): one writer, no `docs`. Two or more: one fresh writer per
   group, one at a time, `docs:` its group's `targets:` line; then one cross-group writer, `group reports:` each group
   writer's report, `docs:` each doc their `Elsewhere:` lines name. Only the first writer takes `bundles:`, its
   group's files and read plan line, while no doc write ran since.
2. Run the writers' `Delete:`, `Move:`, and `Rename:` lines by `references/rounds.md` section 1.
3. Dispatch one fresh `specstone-sdd-auditor`, `job: builder-check`, with the change note's path, the drafts list, and
   each writer's report.
4. Sort its findings, ask the Owner once by `references/rounds.md` section 2, then fix them by
   `../specstone-expert-sdd/references/fix-loop.md`. No builder check repeats.

## 5. Get the drafts approved

Follow `../specstone-expert-sdd/references/approve.md`, with `--audit` per audit report and `--author` per writer
report. Show the change note's Decisions with each draft asked and with the approved list, also when no draft is
asked; a change from a source adds its Source map. Each `check` finding that waits for the Owner, and
each item outside the drafts, goes with the ask. An Owner change follows `references/rounds.md` section 4.

## 6. Hand off to the plan skill

With every draft approved, follow the `specstone-plan-sdd` skill with the whole approved drafts list and the change
note's path; it shows the Owner the plan and asks how to run it.

## Without a dispatch

With no subagent or after a failed dispatch, follow `references/no-dispatch.md`.
