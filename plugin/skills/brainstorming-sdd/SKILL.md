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

That call is the gate. Never look for `.specstone/` yourself first: the CLI searches each folder upward, so a run
from a project's subfolder goes on, while a look at the working directory alone would stop there by mistake.

## 2. Reach an approved design document

- **`superpowers:brainstorming` in your skill list:** run it on the change, grounded in step 1's docs. When it
  reaches its hand-off to `superpowers:writing-plans`, invoke nothing yet: go to step 3.
- **Not in your skill list:** run this flow; it ends at the same document and the same approval.
  1. Ask the Owner one question per message until scope, behavior, edge cases, and what stays out are clear.
  2. Offer two or three approaches with their trade-offs, and recommend one.
  3. Write `docs/superpowers/specs/<YYYY-MM-DD>-<topic>-design.md`: each decision with its own ID (`D1`, `D2`, …),
     the stories and FRs it adds or changes, and the docs it changes or adds.
  4. Ask the Owner to approve the document; revise and ask again until they do.

Until the Owner approves, write no PRD or spec doc and do not dispatch `specstone:sdd-engineer`. Approval of an
approach is not approval of the document.

## 3. Hand the design to the engineer

After the approval, and never before, dispatch `specstone:sdd-engineer` with `mode: author` and the design
document's path. Put no doc text and no design text in the prompt: the path is the hand-off.

Show the Owner its report whole, `Not landed:` lines included, before they approve any draft. Each doc it wrote
stays a draft until the Owner approves it, per `specstone:expert-sdd`.

## 4. Name the next step: the plan

End by telling the Owner the next step is `superpowers:writing-plans`, with this rule for its plan:

- Every task names the story and FR IDs it builds, and nothing of their text: no statement, edge case, or table.
- Its implementer reads each one fresh by running `specstone context <target> --for implement`
  (`specstone:read-sdd`).

Write no plan here.

## Red flags

| Thought                                           | Do instead                                              |
|---------------------------------------------------|---------------------------------------------------------|
| "The design is clear; draft the docs now."        | No doc and no dispatch before the document's approval.  |
| "Check that `.specstone/` exists first."          | The `context` call is the check.                        |
| "Paste the FR into the plan task to save a call." | Cite its ID; the doc may change before the task runs.   |
| "It is one value in one doc."                     | A small edit: `specstone:update-sdd`.                   |
| "Brainstorming says: invoke writing-plans now."   | Step 3 first: the plan cites IDs the engineer writes.   |
