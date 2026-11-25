---
name: specstone-read-sdd
description: Use when a task in a Specstone project needs its PRD or spec docs, such as a plan task that names the story, FR, NFR, or spec doc it builds, a question about a feature's docs, or design work on a feature, or when another Specstone skill names `specstone-read-sdd`.
---

# Ground a task in its Specstone docs

One `specstone context` call saves the docs a task needs and prints its index. Ground from IDs: never walk
the docs folder, and never work from text a plan or brief quotes.

## Pick the targets and mode

- **Targets:** the docs the task names: in `implement` and `design`, all in one call; in `query`, one call per doc. A
  plan task names each doc it builds: name each story it cites or whose FR it cites, and each NFR or spec doc it
  cites, in one `specstone context <story> <story> <doc> --for implement --out`; a story's `implement` bundle holds
  its FRs. Never target the feature: its `implement` bundle lists only its stories' names. For other work over
  several docs, or a `design` change whose doc you must pick, follow `references/several-docs.md` first.
- **Code target:** the `--target` is a plan task's read line's, as written; none in `query` or `design`. In
  `implement` with no plan target and no `--code` path, an `argument_missing` refusal names the targets: a main
  session asks the Owner and reruns with `--target <name>`; a Subagent runs no further call and reports the missing
  target, naming them, to its dispatcher.
- **Mode:**

| Task | `--for` |
|---|---|
| a plan task, or code work | `implement` |
| designing or reshaping a feature | `design` |
| answering a question about the docs | `query` |

## Ground in one call

Make this your first CLI call, unless `references/several-docs.md` puts `structure` first, before any doc or code
read, with `--out` bare and last and no `--budget`:

```
specstone context <target> [<target> …] --for <mode> --out
```

The CLI names the files under the project root's `.specstone/bundles/`; never pick a path yourself. Then act on its
exit status:

1. **0:** stdout is the index: per saved file a `==> bundle: … · <path> <==` header, the read-first one followed by
   its read plan line, then one line per doc with its line range and, within 200 lines and 8 KiB, its sections' first
   lines. In `implement` and `review` the refs file prints its header alone. Read them with the host's file read; they are the
   task's docs: open no doc file, and they win over a plan's wording.
   - **Read plan:** in `implement`, `design`, and `review`, read the read-first file whole: every range the plan
     line names, in order, each read passing the range's first and last line, before the task's first other action.
     A range larger than one host read goes in consecutive parts to its end. Skip none; a `review` check then greps
     its refs file once. A read-first size warning stops no read: ask nothing, go on.
   - **Refs file:** open parts by line range, found in `implement` by the refs file's head, in `design` by the stdout
     index. In `implement`, a refs header showing ` · <n> moved` adds a read of the refs head after the read plan. A
     refs part marked ` · moved` is one of the task's docs: open it by its range before acting on a fact it holds.
     Read each by its own range, a part over one host read in consecutive parts, and no read of them is a doc read.
     In `query`, read the parts of its one file.
   - Once the index lists docs only, search the files for a section's `## ` header.
2. **78 with `project_not_found`:** tell the Owner the project is still on the old format: `specstone migrate` moves it,
   or they keep the old skills. Then stop: run nothing more; read and write no doc.
3. **Any other non-zero exit:** report the CLI's error to the Owner and stop.

That call is also the project gate: never look for `.specstone/` first. A session in a subfolder needs the project
root as a working directory to read the files. A later call with the same targets and flags replaces the files: read
by the newest index.

## Search before `get`

When the index does not show a fact the task needs, search the saved files, moved parts included, with the host's
text search before any `specstone get`. Never `get` a doc the files hold; in design work, ground a doc they lack with
its own `specstone context <doc> --for design --out`, never `get`. A `get` only for a write's base hash before `set`
is fine. Save a long `guide`, `get`, `search`, or `refs` output you read in parts with bare `--out`, a `check` one
with `--out` `<folder>/reports/check.<role>.<XXXXXX>.txt`, `<role>` your caller's, `<folder>` the path `specstone folder` prints,
then search its file. Change one passage with `set --replace`. Write no file by shell redirect, `sed -i`, `perl -pi`,
or `tee`; hand edit no doc file.

## Count the calls

Up to the task's first other action (its first code or task-file read, edit, or design output), count each
`structure` and `context` call, `argument_missing` refusal, read, and search; loading this skill counts none. A
further target in the same call adds none; a doc design work newly reaches takes its own. Aim for three, measured
after: never by skipping a range.

## Whole sections from the reader

You may dispatch `specstone-sdd-reader` for whole sections, as
`../specstone-expert-sdd/references/dispatch.md` gives.
Hand it each saved file's path exactly as its header printed it, the read plan line as printed, the mode, and the
task: no doc text, no index lines, and no path you join yourself. It runs no `context`.

## Red flags

| Thought | Do instead |
|---|---|
| "The plan already quotes the FR." | Ground from its IDs; the doc may have moved on. |
| "Three calls are spent: skip the last range." | Read every range of the plan, in order. |
| "The bundle is big: hand it to the reader." | Read it yourself; size hands nothing off. |
| "`get` the doc to be sure of one fact." | Search the saved files first. |
