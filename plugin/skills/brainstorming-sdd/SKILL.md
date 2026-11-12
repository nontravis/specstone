---
name: brainstorming-sdd
description: Use when a change to a Specstone project adds a feature, a user story, or an FR, or reaches more than one PRD or spec doc, such as brainstorming a new feature or reshaping an existing one, or when another `specstone:` skill names `specstone:brainstorming-sdd`.
---

# Brainstorm a change into an approved design

A change this skill takes reaches the PRD and spec only after the Owner approves its design document. A change that
only rewrites one section or field of an existing doc, and adds no story or FR, is a small edit: use
`specstone:update-sdd` instead.

## 1. Ground: the first call

Make this your first CLI call, before any other command or file read. Target the smallest doc that holds the whole
change, one call per target: the story for a change inside one story, the feature for one across stories, the feature
with `--summary` to add a story, and `project` to add a feature. Without the `Agent` tool, pass no `--budget`; `Read`
a saved output once, in parts if too long.

```
specstone context <target> --for design --budget 20000
```

- **0:** the printed bundle grounds the brainstorm. Work from it; open no doc file.
- **1:** over budget: give `specstone:sdd-reader` the target IDs, `--summary` beside each target
  whose call used it, mode `design`, and the change in a sentence, with no doc text; the whole sections it returns
  are the ground.
- **78, `project_not_found`:** tell the Owner the project is still on the old format; `specstone migrate` moves it,
  or they keep using the old skills. Stop: run nothing more; read or write no doc.
- **Any other exit:** report the CLI's error and stop.

That call is the gate. Never look for `.specstone/` first: the CLI searches upward; a look at the working directory
misses a root above it.

For a change that adds a story or a feature, run `specstone guide feature` after that call, answer its placement
questions, and show the Owner each answer; go on only after their yes.

## 2. Reach an approved design document

The brainstorm skill is the one in your skill list whose description says it turns a change into a design through
dialogue with the user. Judge by that alone, never by name. No `specstone:` skill qualifies. When two qualify,
take the one the project's `CLAUDE.md` names, else the first listed.

- **A skill qualifies:** run it on the change, grounded in step 1's docs. It keeps the conversation and the approval;
  at its write step, write through step 3. At its own hand-off to a plan or build skill, invoke nothing: once the
  Owner approves the document, go to step 4. Specstone's rules win on a conflict.
- **None qualifies:** run this flow; it ends at the same document and the same approval.
  1. Ask the Owner one question per message until scope, behavior, edge cases, and what stays out are clear.
  2. Offer two or three approaches with their trade-offs, and recommend one.
  3. Write the document through step 3.
  4. Ask the Owner to approve it; send each change they ask for through step 3, and ask again until they approve.

Until the Owner approves, write no PRD or spec doc and dispatch no `mode: author`. Ask for approval only once the
document holds no open question; approval of an approach is not approval of the document.

## 3. Write the document: design mode

Each `specstone:sdd-engineer` dispatch in steps 3 and 4 passes `report:`, a `mktemp` file outside the repository;
show the Owner each reply's `Report:` line, then its relay block word for word, before your own notes.

Write the Owner's approved answers (the decisions, the rulings in the Owner's own words, the approach picked, the open
questions) to a `mktemp` file outside the repository, once every answer is in. Dispatch `mode: design` once, with that
brief's path and the document's: the brainstorm skill's own path for design documents, else
`docs/designs/<YYYY-MM-DD>-<topic>-design.md`.

Route each later Owner answer or change per `${CLAUDE_PLUGIN_ROOT}/skills/brainstorming-sdd/references/rounds.md`.

## 4. Write the drafts, then audit them

1. After the approval, dispatch `mode: author` with the document's path. Put no doc or design text in the prompt:
   the path is the hand-off.
2. Run the author's `Move:` commands, if any. Dispatch a fresh `mode: audit` with the document's path and the drafts
   list as its targets.
3. Run fix rounds on its `Findings:` lines per `${CLAUDE_PLUGIN_ROOT}/skills/brainstorming-sdd/references/rounds.md`.
4. Before the Owner approves any draft, show each author reply and the last audit's. Each doc stays a draft
   until then, per `specstone:expert-sdd`.

## 5. Hand the approved drafts to the plan skill

After the Owner approves the drafts, invoke `specstone:plan-sdd` through `Skill` with the approved drafts list, whole,
and the document's path. It writes the plan and asks the Owner how to run it.

## Without the `Agent` tool

Without it, or when a dispatch fails, read that mode's reference and follow it yourself. An audit you run is no
fresh reader's, since you saw the drafts made: tell the Owner so.

- author: `${CLAUDE_PLUGIN_ROOT}/skills/brainstorming-sdd/references/author.md`
- design: `${CLAUDE_PLUGIN_ROOT}/skills/brainstorming-sdd/references/design.md`
- audit: `${CLAUDE_PLUGIN_ROOT}/skills/brainstorming-sdd/references/audit.md`

## Red flags

| Thought                                         | Do instead                                               |
|-------------------------------------------------|----------------------------------------------------------|
| "The design is clear; draft the docs now."      | No `mode: author` before the document's approval.        |
| "I'll write the design document myself."        | Step 3: you hold the answers; the agent holds the docs.  |
| "The coverage table is clean; skip the audit."  | A fresh reader finds what the author's own table cannot. |
| "The brainstorm hands off to a plan skill now." | Invoke nothing; step 4 first, then `specstone:plan-sdd`. |
