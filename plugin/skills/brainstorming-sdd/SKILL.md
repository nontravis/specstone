---
name: brainstorming-sdd
description: Use when a change to a Specstone project adds a feature, a user story, or an FR, or reaches more than one PRD or spec doc, such as brainstorming a new feature or reshaping an existing one, or when another `specstone:` skill names `specstone:brainstorming-sdd`.
---

# Brainstorm a change into an approved design

A change this skill takes reaches the PRD and spec only after the Owner approves its design document. When the
change only rewrites a single section or field of a doc that already exists, and adds no story or FR, it is a small
edit: use `specstone:update-sdd` instead.

## 1. Ground: the first call

Make this your first CLI call, before any other command or file read. Target the feature the change touches, one
call per feature; a change that adds a feature targets `project`.

```
specstone context <target> --for design --budget 20000
```

- **0:** the printed bundle grounds the brainstorm. Work from it; open none of its files.
- **1:** the bundle is over budget. Give `specstone:sdd-reader` the target IDs, mode `design`, and the change in a
  sentence, with no doc text; the whole sections it returns are the ground.
- **78, `project_not_found`:** tell the Owner the project is still on the old format; `specstone migrate` moves it,
  or they keep using the old skills. Stop: run nothing more, and read or write no doc.
- **Any other exit:** report the CLI's error and stop.

That call is the gate. Never look for `.specstone/` yourself first: the CLI searches each folder upward, while a look
at the working directory alone misses a project root above it.

## 2. Reach an approved design document

- **`superpowers:brainstorming` in your skill list:** run it on the change, grounded in step 1's docs. It keeps the
  conversation, the builder check, and the approval; at its write step, write through step 3. When it reaches its
  hand-off to `superpowers:writing-plans`, invoke nothing: go to step 4.
- **Not in your skill list:** run this flow; it ends at the same document and the same approval.
  1. Ask the Owner one question per message until scope, behavior, edge cases, and what stays out are clear.
  2. Offer two or three approaches with their trade-offs, and recommend one.
  3. Write the document through step 3.
  4. Ask the Owner to approve it; send each change they ask for through step 3, and ask again until they approve.

Until the Owner approves, write no PRD or spec doc and dispatch no `mode: author`. Ask for approval only once the
document holds no open question; approval of an approach is not approval of the document.

## 3. Write the document: design mode

Each `specstone:sdd-engineer` dispatch in steps 3 to 5 also passes `routed by: specstone:brainstorming-sdd`.

Write the Owner's approved answers (the decisions, the rulings in the Owner's own words, the approach picked, the
open questions) to a temp file outside the repository, such as one `mktemp` makes. Dispatch `mode: design` with
that brief's path and `docs/superpowers/specs/<YYYY-MM-DD>-<topic>-design.md`. Show the Owner its open questions
and `Findings:`. Add the answers, and each change from the builder check or the Owner, to the brief, and dispatch
again with the same inputs.

## 4. Write the drafts, then audit them

1. After the approval, and never before, dispatch `mode: author` with the document's path. Put no doc text and no
   design text in the prompt: the path is the hand-off.
2. Dispatch a fresh `mode: audit` with the document's path and the author's drafts list as its targets.
3. When the audit reports `Findings:` lines, send them to the author while it is live, else to a new `mode: author`
   dispatch with the document's path and the drafts list; then audit again with a fresh agent. Run at most two such
   fix rounds. The drafts list is the first report's, plus each doc a fix round adds.
4. Show the Owner each author report and the last audit's, whole, before they approve any draft. Each doc stays a
   draft until the Owner approves it, per `specstone:expert-sdd`.

## 5. Write the plan, then ask how to run it

After the Owner approves the drafts, dispatch `mode: plan` with the document's path, the drafts list, and
`docs/superpowers/plans/<YYYY-MM-DD>-<topic>.md`. Show the Owner its `NOT PLANNED` rows and open questions first,
and send the answers to plan mode with the same inputs. Then show the plan and ask how to run it.

## Without the `Agent` tool

Without it, or when a dispatch fails, read that mode's reference and follow it yourself. An audit you run is not a
fresh reader's, since you saw the drafts being made: tell the Owner so.

| Mode   | Reference                                                             |
|--------|-----------------------------------------------------------------------|
| author | `${CLAUDE_PLUGIN_ROOT}/skills/brainstorming-sdd/references/author.md` |
| design | `${CLAUDE_PLUGIN_ROOT}/skills/brainstorming-sdd/references/design.md` |
| audit  | `${CLAUDE_PLUGIN_ROOT}/skills/brainstorming-sdd/references/audit.md`  |
| plan   | `${CLAUDE_PLUGIN_ROOT}/skills/brainstorming-sdd/references/plan.md`   |

## Red flags

| Thought                                         | Do instead                                                 |
|-------------------------------------------------|------------------------------------------------------------|
| "The design is clear; draft the docs now."      | No `mode: author` before the document's approval.          |
| "I'll write the design document myself."        | Step 3: you hold the answers; the agent holds the docs.    |
| "The coverage table is clean; skip the audit."  | A fresh reader finds what the author's own table cannot.   |
| "Brainstorming says: invoke writing-plans now." | Step 4 first; step 5's plan cites IDs the drafts now hold. |
