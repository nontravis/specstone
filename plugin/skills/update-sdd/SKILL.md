---
name: update-sdd
description: Use when the Owner asks to change one value or passage in a PRD or spec doc that already exists, such as raising a timeout an FR states, rewording one section, setting one field, or confirming a requirement again after the doc it traces changed, or when another `specstone:` skill names `specstone:update-sdd`.
---

# Update one doc section or field as a draft

A small edit skips the design round: you rewrite one target, and the Owner's approval of the change you name is its
only review. Follow `specstone:expert-sdd` before and after the write.

## 1. Sort the request

It is a small edit only when all four hold. Sort it from the request, before any command runs.

- It changes one section, or one frontmatter field, of one doc.
- That doc exists already.
- It adds no user story and no FR.
- It leaves `implements:` and `covers:` alone: those fields point at code.

| Request                                     | Path                                                      |
|---------------------------------------------|-----------------------------------------------------------|
| An FR's timeout goes from 10 s to 30 s      | small edit, even though it changes a number the FR states |
| A new scenario that only a new FR can carry | `specstone:brainstorming-sdd`                             |
| One wording fix, wanted in two docs         | `specstone:brainstorming-sdd`                             |
| An `implements:` path the code moved        | `specstone:sync-sdd`                                      |

Not a small edit: an `implements:` or `covers:` change is code sync and goes to `specstone:sync-sdd`; anything
else goes to `specstone:brainstorming-sdd`. Hand it over and stop: write nothing here, and run no `specstone set`.

## 2. Gate on the target, then read it

Make this your first CLI call, before any other command or file read. It is the `specstone:expert-sdd` gate, run on
the one doc you will write:

```
specstone check <type>:<name>
```

- **0 or 1:** go on. Keep its findings on the target as the baseline for step 3.
- **78, `project_not_found`:** tell the Owner the project is still on the old format; `specstone migrate` moves it,
  or they keep using the old skills. Stop: run nothing more, and read or write no doc.
- **Any other exit:** report the CLI's error and stop.

That call is the gate. Never check for `.specstone/` yourself first: the CLI looks in each folder upward, so a run
from a project's subfolder goes on, while a look at the working directory alone would stop there by mistake.

Then read the target:

```
specstone get <type>:<name>#<section key>
specstone get <type>:<name> --json
```

- **A section:** the first prints its text, with the base hash on the naming line (`· base <hash>`). Key unknown? The
  second lists each section key under `bases.sections`.
- **A field:** the second; the base is `bases.fields.<id>`.

If the text shows the change reaches past this one target, go to step 1's hand-over with nothing written. A non-zero
exit: report the CLI's error and stop.

## 3. Write the edit

Pipe the new body (no `## ` heading line) or the new YAML value to the matching call:

```
specstone set <type>:<name>#<section key> --base <hash>
specstone set <type>:<name> --field <id> --base <hash>
```

- **0:** the write marked the doc `draft: true`. Leave that flag.
- **75, `base_mismatch`:** the target changed after your read. The refusal prints the naming line with the new base,
  then the current text. Merge your edit into that text and run the same `specstone set` again with that base; never
  write your old text over it.
- **Any other exit:** stop, and report the refusal the CLI printed.

After the write, run `specstone check <type>:<name>` again. Fix, as `specstone:expert-sdd` says, only the findings
on that target that step 2's baseline lacks; leave every other one alone.

Confirming a requirement again after `specstone check` marks a link `suspect` is a small edit of its `confirmed`
field; `specstone:expert-sdd` says how to record it.

## 4. Name the change for the Owner

Write no design document. Tell the Owner the doc, the section or field, what it said before, and what it says now.
For a confirmation, add the upstream change you checked it against. Then ask them to run, at their own terminal:

```
specstone approve <type>:<name>
```

When that doc holds others, as a feature holds its stories and a story its FRs, say so with the line: this call
also approves, at the Owner's `y` for each, every draft under that doc, not only your edit.

Never run it yourself: it refuses any caller but an interactive terminal (exit 77), and with no design document or
coverage table, the Owner's look at your named change is the edit's one check.

## Red flags

| Thought                                            | Do instead                                   |
|----------------------------------------------------|----------------------------------------------|
| "Two docs, but each change is one line."           | Hand over to `specstone:brainstorming-sdd`.  |
| "The new FR is short; one `set` fits it."          | Hand over to `specstone:brainstorming-sdd`.  |
| "A quick design document first, to be safe."       | A small edit has none; name the change.      |
| "Base mismatch: rerun with my text."               | Merge into the current text first.           |
| "I'll run `specstone approve` to finish."          | Ask the Owner to run it.                     |
