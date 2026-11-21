---
name: specstone-brainstorming-sdd
description: Use when a change to a Specstone project adds a feature, a user story, or an FR, or reaches more than one PRD or spec doc, such as brainstorming a new feature, reshaping an existing one, or taking in a spec or design another tool wrote, or when another Specstone skill names `specstone-brainstorming-sdd`.
---

# Brainstorm a change into an approved design

A change rewriting one section or field, adding no story or FR: follow the `specstone-update-sdd` skill instead.

## 1. Ground: the first call

Target the smallest doc that holds the whole change:

- One story: the story. Across stories: the feature. A new feature: the project doc.
- Several docs: name each in one call, `specstone context <doc> <doc> … --for design --out`.
- Several docs picked from the docs tree: the gate is `specstone structure <doc> …`; on 0 name each doc its map
  shows the change reaching in one `context` call; on another exit act as below.
- A story added runs no `structure`. Alone: one call, the feature with `--summary`. With existing docs too:
  `specstone context <feature> --for design --summary --out` first, as the gate, then one call naming each existing
  doc.

Make the gate your first CLI call, before any doc or code read: the `structure` call, else `context`. On every
grounding call keep `--out` bare and last, with no `--budget` or `--target`.

```
specstone context <target> [<target> …] --for design --out
```

- **0:** the saved files are the ground. Before the first question, read them per the `specstone-read-sdd` skill,
  each read-first file by its read plan. Keep each read plan line with its saved paths for `bundles`. Ground a doc
  they lack by its own `specstone context <doc> --for design --out`, never `get`; open no doc file.
- **78, `project_not_found`:** tell the Owner the project is on the old format; `specstone migrate` moves it, or they
  keep the old skills. Stop; read or write no doc.
- **Any other exit:** report the CLI's error and stop.

From a source (another tool's spec or design), the first call is `specstone context project --for design --out`;
read or open the source, a link or issue too, only after it exits 0, then follow `## Take in the source` in
`references/source.md`.

Adding a story or feature: after the call, run `specstone guide feature`, answer its placement questions, and show
the Owner each answer; go on only after their yes.

## 2. Reach an approved design document

The brainstorm skill is the listed skill whose description, never its name, says it turns a change into a design
through dialogue with the user. No Specstone skill qualifies. Of two qualifying, take the one the project's
instruction file (`CLAUDE.md`, `AGENTS.md`) names, else the first listed.

The design proposes each new or reshaped feature's `patterns:` value from `specstone guide --pattern`.

- **A skill qualifies:** run it on the change grounded in step 1; it keeps the conversation and the approval. Write
  through step 3 at its write step; invoke nothing at its hand-off to a plan or build skill; once the Owner approves,
  go to step 4. Specstone's rules win on a conflict.
- **None qualifies:** ask one question per message until scope, behavior, edge cases, and exclusions are clear;
  offer two or three approaches with trade-offs, recommending one; write through step 3; ask for approval, sending
  each change through step 3, until approved.

Until the Owner approves, write no PRD or spec doc and dispatch no `mode: author`. Ask for approval only when the
document holds no open question; approving an approach is not approving the document.

## 3. Write the document

Write one design document by `references/design.md`, from step 1's saved files and the Owner's answers, at the
brainstorm skill's design path, else `docs/designs/<YYYY-MM-DD>-<topic>-design.md`. Dispatch nothing to write it.

Before the approval ask, dispatch the design check: a fresh `specstone-sdd-auditor`, `stage: design`, the document's
path, and `bundles:` each saved bundle file with no doc write since, beside its read plan line. Fix each finding by
`references/design.md`, then ask for approval, or, after an author pass, go on to the amend's pass unasked. Sweeps,
amend and delta checks, and each later Owner answer or change follow `references/rounds.md`.

## 4. Write the drafts, then audit them

After step 1, run `specstone folder` once; `<folder>` is its path. Each dispatch follows
`../specstone-expert-sdd/references/dispatch.md` and passes `report:` `<folder>/reports/sdd-engineer.author.<XXXXXX>.md`,
`<folder>/reports/sdd-auditor.audit.<XXXXXX>.md`, or `<folder>/reports/sdd-sweeper.sweep.<XXXXXX>.md`. `XXXXXX` is
six `a-z0-9` characters, picked again while that file exists. Show the Owner each reply's `Report:` line, then its
relay block word for word, before your notes. Before a dispatch, write no brief and rerun no `context` on a grounded
target. A claim the saved files do not ground is an open question.

1. After approval, dispatch `specstone-sdd-engineer`, `mode: author`, with only the document's path.
2. Run the author's `Move:` commands, then the amend compare of `references/rounds.md` section 2. Dispatch a
   fresh `specstone-sdd-auditor` with the document's path, the drafts list as targets, and `check:` per
   `references/rounds.md` section 3; never skip it on a clean coverage table.
3. Run the fix round on its `Findings:` lines per `references/rounds.md`.
4. Show each author reply and the last audit's relay block; follow the `specstone-expert-sdd` skill's
   "Get the drafts approved", with `--audit` and `--author`.

## 5. Hand off to the plan skill

Once every draft is approved, follow the `specstone-plan-sdd` skill with the whole approved drafts list and the
document's path.

## Without a dispatch

Follow the `specstone-expert-sdd` skill, then run the mode's procedure yourself: `references/author.md`,
`references/audit.md`, or, for the design check, `references/design-check.md`.
