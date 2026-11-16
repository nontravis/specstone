---
name: specstone-brainstorming-sdd
description: Use when a change to a Specstone project adds a feature, a user story, or an FR, or reaches more than one PRD or spec doc, such as brainstorming a new feature, reshaping an existing one, or taking in a spec or design another tool wrote, or when another Specstone skill names `specstone-brainstorming-sdd`.
---

# Brainstorm a change into an approved design

A change that only rewrites one section or field of an existing doc, and adds no story or FR, is a small edit: follow
the `specstone-update-sdd` skill instead.

## 1. Ground: the first call

Make this call, the gate, your first CLI call, before any other command or file read.
Target the smallest doc that holds the whole change, one call per target: the story for a change inside one story,
the feature for one across stories, the feature with `--summary` to add a story, and the project doc to add a feature.
Keep `--out` bare and last, and pass no `--budget` on any host.
Pass no `--target`: a design read spans every code target.

```
specstone context <target> --for design --out
```

- **0:** the saved files are the ground: read them per the `specstone-read-sdd` skill, a doc they lack grounded by
  its own `specstone context <doc> --for design --out`, never `get`; open no doc file.
- **78, `project_not_found`:** tell the Owner the project is still on the old format; `specstone migrate` moves it,
  or they keep using the old skills. Stop: run nothing more; read or write no doc.
- **Any other exit:** report the CLI's error and stop.

For a change from a source, another tool's spec or design, that first call is
`specstone context project --for design --out`. Read or open the source, a link or an issue
included, only after it exits 0; then follow `## Take in the source` in
`references/source.md`.

For a change that adds a story or a feature, run `specstone guide feature` after that call, answer its placement
questions, and show the Owner each answer; go on only after their yes.

## 2. Reach an approved design document

The brainstorm skill is the one in your skill list whose description, never its name, says it turns a change into a
design through dialogue with the user. No Specstone skill qualifies. When two qualify,
take the one the project's instruction file (`CLAUDE.md`, `AGENTS.md`) names, else the first listed.

The design document proposes each new or reshaped feature's `patterns:` value, picked from `specstone guide --pattern`.

- **A skill qualifies:** run it on the change, grounded in step 1's docs. It keeps the conversation and the approval;
  at its write step, write through step 3. At its own hand-off to a plan or build skill, invoke nothing: once the
  Owner approves the document, go to step 4. Specstone's rules win on a conflict.
- **None qualifies:** run `references/dialogue.md`; it ends at the same document and approval.

Until the Owner approves, write no PRD or spec doc and dispatch no `mode: author`. Ask for approval only once the
document holds no open question; approval of an approach is not approval of the document.

## 3. Write the document

Write the one design document yourself, by `references/design.md`, once the Owner's answers are in: from step 1's saved
files and the Owner's answers, at the brainstorm skill's own design path, else
`docs/designs/<YYYY-MM-DD>-<topic>-design.md`. A refused path is an open question; write at the Owner's new path.
Dispatch nothing for it.

Route each later Owner answer or change per `references/rounds.md`.

## 4. Write the drafts, then audit them

After step 1's calls, take `<folder>` the path `specstone folder` prints, run once. Each dispatch of
`specstone-sdd-engineer` in this step follows `../specstone-expert-sdd/references/dispatch.md` and passes
`report:` `<folder>/reports/sdd-engineer.<mode>.<XXXXXX>.md`, `XXXXXX` six `a-z0-9` characters, picked again while that
file exists; show the Owner each reply's `Report:` line, then its relay block word for word, before your own notes.
Write no brief and run no `context` call again on a target already grounded before a dispatch; a claim your saved files
do not ground is an open question of the document.

1. After approval, dispatch `mode: author` with the document's path. Pass no doc or design text.
2. Run the author's `Move:` commands, if any. Dispatch a fresh `mode: audit` with the document's path and the drafts
   list as its targets.
3. Run fix rounds on its `Findings:` lines per `references/rounds.md`.
4. Show each author reply and the last audit's relay block; approve the drafts through the
   `specstone-expert-sdd` skill's Owner confirmation, testing both under `auto`.

## 5. Hand the approved drafts to the plan skill

After the Owner approves the drafts, follow the `specstone-plan-sdd` skill with the approved drafts list, whole, and the
document's path.

## Without a dispatch

A mode you run yourself follows its procedure: `references/author.md` or `references/audit.md`.

## Red flags

| Thought | Do instead |
|---|---|
| "The design is clear; draft the docs now." | No `mode: author` before the document's approval. |
| "The coverage table is clean; skip the audit." | A fresh reader finds what the author's own table cannot. |
