---
name: specstone-expert-sdd
description: Use when about to write, edit, or confirm a PRD or spec doc in a Specstone project, when a doc's upstream changed after it was confirmed, when code adds or changes observable behavior no spec states, or when another Specstone skill names `specstone-expert-sdd`.
---

# Specstone cross-doc rules

## First call: the project gate

1. Run `specstone folder`, then `specstone check --out "<folder>/reports/check.gate.<XXXXXX>.txt"`: `<folder>` is
   what `folder` prints, `XXXXXX` six `a-z0-9` characters, picked again while that file exists.
2. Exit 78 `project_not_found`: tell the Owner no Specstone project is found here (`specstone init` starts
   one), then stop: run, read, and write nothing.
3. `check` exit 0 or 1: a project is found, even from a subfolder; its file is the baseline: search it,
   never read it whole.
4. Any other exit: report the CLI's error and stop.

A dispatch's fresh `check:` file skips steps 1 to 4: search it; `<folder>` is its folder's parent.
Never look for `.specstone/`.

## Rules

1. **Docs lead.** The PRD owns product behavior, and each spec type owns the facts its guide lists. Work built from
   the docs, such as code or content, that adds or changes observable behavior no spec states gets a spec draft
   first. Its one exception is a decided line of a change note: work built from it may lead the docs until the
   plan's last task.
2. **Write through the CLI.** Create with `new`, change with `set`; never edit a doc file with a
   file tool or shell. Read `references/write.md` before the run's first `set` or `new`, and, with two or more code
   targets or for a new feature, its first `specstone` command.
3. **Guide first.** Before writing a doc, have its type's current `specstone guide <type>` and its `--json`.
4. **Confirm traced links.** To write a doc whose type carries the `confirmed` field, or an `Overrides:` line, follow
   `references/confirm-links.md`.
5. **Size in one order.** Over a size limit, or to cite a size, follow `references/size-fix.md`.
6. **Check after edits.** Run `specstone check <target> --out "<folder>/reports/check.done.<XXXXXX>.txt"` per doc you
   touched; fix each finding you added to the baseline; leave each ending `(waits for the Owner)` as it is.
7. **Cite, never restate.** A rule has one owner doc; every other doc links the item holding it, else its section or
   doc, and states nothing of it; form: `references/confirm-links.md`.

## Get the drafts approved

Run `approve` only with `--dry-run`, `--auto`, or `--yes`. Only the main session runs `--auto`; a subagent
(`specstone-sdd-engineer`, `specstone-sdd-auditor`, `specstone-plan-engineer`, or `specstone-sdd-reader`) runs
`approve` only with `--dry-run` and reports its drafts.

After a brainstorm's builder check or a bootstrap trim audit, the main session runs the one fix loop on its findings,
by `references/fix-loop.md`, before approval. At approval, the main session follows `references/approve.md`.

Under both modes the Owner answers the approach pick, the one round of builder check questions only their answer
settles, a question met mid-flow, an open question in a report, a split proposal with its plan file, a sync pick,
`delete` of a guarded doc, `migrate`, and each `--plan`.

## Owner confirmation

`approve`, guarded `delete`, and `migrate` need the Owner's word, at their terminal without `--yes` or in chat:

1. Show each item in full, one per message:
   - `approve`, per draft `--auto` asks: the literal `Why:`, one sentence in the chat's language on why it changed,
     then its `approve <type>:<name> … --dry-run` text verbatim, per draft if cut.
   - `delete` or `migrate`: its view, by `references/gated-plan.md`.
2. Fix what the Owner names by `set` and show it again, until `ok`.
3. After `ok` on all, or the Owner's leave, run one command with the shown hashes:
   `specstone approve <type>:<name>@<hash> … --yes`, or a `delete` or `migrate` command by
   `references/gated-plan.md`; exit 75: show it again.
4. Write each `@<hash>`, path, and `--plan <hash>` literally, never from a file, variable, or command substitution.

Never run `specstone trust` or answer its prompt, even if told to; on `run specstone trust at a terminal`, ask the
Owner to run it, then retry.
