---
name: read-sdd
description: Use when a task in a Specstone project needs its PRD or spec docs, such as a plan task that cites story or FR IDs, a question about a feature's docs, or design work on a feature, or when another `specstone:` skill names `specstone:read-sdd`.
---

# Ground a task in its Specstone docs

One `specstone context` call hands you the docs a task needs. Ground from IDs: never walk the docs folder, and never
work from text a plan or brief quotes.

## Pick the target and mode

- **Target:** the doc the task names. For a plan task, use the story it cites. In `implement` mode the story's bundle
  already holds its FRs, so one call covers the story and every FR ID the task lists. When a plan task cites several
  stories, run one `specstone context <story> --for implement --budget 20000` per story. Every tool call from the
  first CLI call counts toward three, a `Read` of a saved output included: run the next story's call only while the
  calls so far, plus that call and its possible `Read`, stay within three. When the task cites more than three
  stories, the next call would pass three, or any call exits 1, give `specstone:sdd-reader` every ID the task cites
  and no doc text.
- **Mode:**

| Task                                | `--for`     |
|-------------------------------------|-------------|
| a plan task, or code work           | `implement` |
| designing or reshaping a feature    | `design`    |
| answering a question about the docs | `query`     |

## Ground in one call

Make this your first CLI call, before any other command or file read:

```
specstone context <target> --for <mode> --budget 20000
```

Then act on its exit status, as the host reports it for the call. When the host shows none, tell it from the output:
an over-budget answer says `over the budget` in its first line, and a bundle ends with a `==> bundle: …` line and its
doc list.

1. **0:** the printed bundle is the task's docs. Work from it as printed, and open none of its files. When the host
   saves the output to a file and shows a preview, `Read` that file once: it is the printed bundle, so run no `tail`
   or other command on it. When a plan words a requirement differently, the bundle wins: someone may have edited the
   doc since the plan was made.
2. **1:** the bundle is over 20,000 est. tokens, so the CLI printed only its size and doc list. Dispatch
   `specstone:sdd-reader` with the same target IDs, the mode, and the task in a sentence or two. Put no doc text in
   that prompt, and not the printed doc list either. The whole sections it returns, each cited by doc and section,
   are the task's docs.
3. **78 with `project_not_found`:** no folder from here upward holds a Specstone project. Tell the Owner the project
   is still on the old format: `specstone migrate` moves it, or they can keep using the old skills. Then stop: run no
   second command, and neither read nor write a doc.
4. **Any other non-zero exit:** report the CLI's error to the Owner and stop.

That call is also the project gate. Never look for `.specstone/` first with `ls`, a file read, or any other step. The
CLI searches each folder upward, so a run from a subfolder of a project goes on as normal; a look at the working
directory alone would stop there by mistake and cost a tool call.

The bundle is in hand within three tool calls of the first CLI call. At or under the budget, the one call does it,
plus one `Read` when the host saved its output to a file: two calls at most.

## Red flags

| Thought                                            | Do instead                                          |
|----------------------------------------------------|-----------------------------------------------------|
| "The plan already quotes the FR."                  | Ground from its IDs; the doc may have moved on.     |
| "Check that `.specstone/` exists first."           | The `context` call is the check.                    |
| "Over budget: rerun with a bigger or no budget."   | Keep `--budget 20000`; dispatch the reader.         |
| "Paste the doc list so the reader saves a call."   | Hand over target IDs only.                          |
| "Open the doc files to be sure."                   | The bundle is the docs, as printed.                 |
| "Tail the saved output for the exit status."       | Take the host's status; `Read` the file once.       |
