---
name: specstone-read-sdd
description: Use when a task in a Specstone project needs its PRD or spec docs, such as a plan task that names the story, FR, NFR, or spec doc it builds, a question about a feature's docs, or design work on a feature, or when another Specstone skill names `specstone-read-sdd`.
---

# Ground a task in its Specstone docs

One `specstone context` call saves the docs a task needs and prints its index. Ground from IDs: never walk
the docs folder, and never work from text a plan or brief quotes.

## Pick the target and mode

- **Target:** the doc the task names. For `design`, the smallest doc that holds the change: a story's bundle holds its
  sibling stories in summary; a feature's holds them whole; add `--summary` on the feature to add a story. A plan task
  names each doc it builds: a story and its FRs, an NFR, or a spec doc. Run one
  `specstone context <story> --for implement --out` per story the task cites or whose FR it cites: in `implement` mode
  a story's bundle already holds its FRs, so that call covers the story and every FR ID the task lists under it. Run
  one `specstone context <target> --for implement --out` on each cited NFR or spec doc itself. Never target the
  feature: its `implement` bundle lists only its stories' names, not the FRs the task cites.
- **Code target:** the `--target` is a plan task's read line's, as written
  (`specstone context <story> --for implement --target <name> --out`); none in `query` or `design`. In `implement`
  with no plan target and no `--code` path, an `argument_missing` refusal names the targets: a main session asks the
  Owner and reruns with `--target <name>`; a Subagent runs no further call and reports the missing target, naming
  them, to its dispatcher.
- **Mode:**

| Task                                | `--for`     |
|-------------------------------------|-------------|
| a plan task, or code work           | `implement` |
| designing or reshaping a feature    | `design`    |
| answering a question about the docs | `query`     |

## Ground in one call

Make this your first CLI call, before any other command or file read, with `--out` bare and last and no `--budget`,
in every mode:

```
specstone context <target> --for <mode> --out
```

The CLI names the files under the project root's `.specstone/bundles/`; never pick a path yourself. Then act on its
exit status:

1. **0:** stdout is the index: per saved file a `==> bundle: … · <path> <==` header, then one line per doc with its
   line range in that file and, while the index stays within 200 lines and 8 KiB, its sections' first lines. Read
   with the host's file read, at any point of the task: in `implement` and `design`, the read-first file whole and the
   refs file by line range, for the parts needed; in `query`, the parts of its one file. Once the index lists docs
   only, find a section by searching the files for its `## ` header. The files are the task's docs: open no doc file.
   When a plan words a requirement differently, the files win: someone may have edited the doc since the plan was made.
2. **78 with `project_not_found`:** no folder from here upward holds a Specstone project. Tell the Owner the project
   is still on the old format: `specstone migrate` moves it, or they can keep using the old skills. Then stop: run no
   second command, and neither read nor write a doc.
3. **Any other non-zero exit:** report the CLI's error to the Owner and stop.

That call is also the project gate: never look for `.specstone/` first. The CLI searches each folder upward, so a run
from a subfolder goes on as normal; to read the files, such a session needs the project root among its working
directories. A later call with the same target and flags replaces the files: read by the newest index.

## Search before `get`

When the index does not show a fact the task needs, search the saved files with the host's text search before any
`specstone get`. Never `get` a doc the files hold; in design work, ground a doc they lack with its own
`specstone context <doc> --for design --out`, never `get`. A `get` only for a write's base hash before `set` is fine.

## Count the calls

One target takes three tool calls at most up to the task's first other action, its first code or task-file read,
edit, or design output: the `context` call and each search or part read before that action; an `argument_missing`
refusal counts among them. Loading this skill counts as none. Each further target, or doc design work newly reaches,
takes a call of its own. Part reads after that action fall outside the bound.

## Whole sections from the reader

You may dispatch `specstone-sdd-reader` for whole sections, each cited by doc and section, as
`../specstone-expert-sdd/references/dispatch.md` gives.
Hand it each saved file's path exactly as its header printed it, the mode, and the task: no doc text, no index lines,
and no path you join yourself. It reads those files and runs no `context` of its own. No bundle size calls for it.

## Red flags

| Thought                                         | Do instead                                         |
|-------------------------------------------------|----------------------------------------------------|
| "The plan already quotes the FR."               | Ground from its IDs; the doc may have moved on.    |
| "The bundle is big: hand it to the reader."     | Read the parts you need; size hands nothing off.   |
| "`get` the doc to be sure of one fact."         | Search the saved files first.                      |
| "Paste the index so the reader saves a call."   | Hand over the saved files' paths only.             |
