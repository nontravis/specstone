---
name: specstone-expert-sdd
description: Use when about to write, edit, or confirm a PRD or spec doc in a Specstone project, when a doc's upstream changed after it was confirmed, when code adds or changes observable behavior no spec states, or when another Specstone skill names `specstone-expert-sdd`.
---

# Specstone cross-doc rules

## First call: the project gate

1. Run `specstone folder`, then `specstone check --out "<folder>/reports/check.gate.<XXXXXX>.txt"`: `<folder>` is
   what `folder` prints, `XXXXXX` six `a-z0-9` characters, picked again while that file exists.
2. Exit 78 `project_not_found`: tell the Owner the project is on the old format (`specstone migrate` moves it, or
   they keep the old skills), then stop: run, read, and write nothing.
3. `check` exit 0 or 1: new format, even from a subfolder; its file is the baseline: search it, never read it whole.
4. Any other exit: report the CLI's error and stop.

A dispatch's fresh `check:` file skips steps 1 to 4: search it; `<folder>` is its folder's parent.
Never look for `.specstone/`.

## Rules

1. **Docs lead.** Keep output ⊆ spec ⊆ PRD over the Observable contract, what users, callers, or other features see;
   a spec states only what its PRD asks; code adding or changing such behavior no spec states gets a spec draft first.
2. **Write through the CLI.** Create with `specstone new`, change with `specstone set`; never edit a doc file with a
   file tool or shell.
   - Take bases from `specstone get <type>:<name> --json` (`bases.title`, `bases.sections.<key>`,
     `bases.fields.<id>`); each write prints the new one.
   - Pipe text to `specstone set <type>:<name>#<key> --base <hash>`, with `--field <id>` or `--title` for `#<key>`.
   - A passage: `--replace` with `==> old <==`, the passage, `==> new <==`, the new one.
   - Omit a section body's `## ` line; give a list field its whole list; empty text drops the section or key.
   - Text between the title and the first `##` is `#_lead`.
   - Exit 75 `base_mismatch`: read again, merge, retry.
   - Quote a node label holding `(`, `)`, `[`, `]`, `{`, or `}`; write `"` in it as `#quot;`.
   - Each write leaves a draft, a pointer write (`implements`, `covers`) excepted; never remove `draft: true`.
   - Run `specstone approve` only with `--dry-run`, `--auto`, or `--yes`, as below.
3. **Guide first.** Before writing a doc, have its type's current `specstone guide <type>` and its `--json`; one
   call naming several types, or this run's saved guide, counts.
4. **Confirm traced links.** To write an FR, nf, API row, or `Overrides:` line, follow `references/confirm-links.md`.
5. **Size in one order.** Over a size limit: layout, FR edge-case trim, an Owner-approved sub-feature split, text
   moved to its home; drop nothing else; steps in `references/size-fix.md`.
   - Cite a size only as `specstone structure <doc>` or `check` prints it.
6. **Check after edits.** Run `specstone check <target> --out "<folder>/reports/check.done.<XXXXXX>.txt"` per doc you
   touched; fix each finding you added to the baseline.
   - Leave each `waitsFor` `owner` finding, its line ending `(waits for the Owner)`; never write around it.
7. **Cite, never restate.** A rule has one owner doc; every other doc links the item holding it,
   `[<ID>](<path>#<section heading anchor>)`, else its section or doc, and states nothing of it.
   - `check` reports an old cite form as `cite_unlinked`, a link to an item its section lacks as `link_item_missing`.
   - Link behavior: `references/confirm-links.md`.
8. **Code target.** With two or more code targets, `new`, `get`, `set` (`confirmed` too), `structure <doc>`, and
   `refs <owner>` take the loading surface's `--target`, never an Owner question; `approve` and `delete` take none.
9. **Feature patterns.** For a new feature, pick patterns with `specstone guide --pattern`; cover each checklist item
   or list it as a skip line in Out-of-scope.

## Get the drafts approved

Only the main session runs `--auto`; a subagent runs `approve` only with `--dry-run` and reports its drafts.

1. Run one `specstone approve <type>:<name> … --auto --json` naming each draft of the run's own list, never a bare
   `approve`. In `specstone-brainstorming-sdd` add `--audit <path>` per audit report, oldest first, and
   `--author <path>` per author report; in a bootstrap round with a trim batch or an audit's fix batch,
   `--audit <path>` per audit report of the round, oldest first; else `--no-audit`.
2. Exit 75: rerun once; a second sends all drafts to Owner confirmation.
3. List each `approved` entry's `name`, `docPath`, and `Why:`, with no wait; for a reconfirmation, the upstream change.
4. Send each `asked` entry to Owner confirmation unchanged.

The Owner always answers the design approval, mid-flow and report questions, split proposals, sync picks,
each `--plan`.

## Owner confirmation

`approve`, guarded `delete`, `migrate`, and legacy `init` need the Owner's word, at their terminal without `--yes` or
in chat:

1. Show each item in full, one per message:
   - `approve`, per draft `--auto` asks: the literal `Why:`, one sentence in the chat's language on why it changed,
     then its `specstone approve <type>:<name> … --dry-run` text verbatim, per draft if cut.
   - `delete`, `migrate`, or `init`: the list or plan and `plan <hash>` line of `specstone delete <path> … --dry-run`
     or `specstone migrate --dry-run`, and why each goes.
2. Fix what the Owner names by `specstone set` and show it again, until `ok`.
3. After `ok` on all, or the Owner's leave, run one command with the shown hashes:
   `specstone approve <type>:<name>@<hash> … --yes`, or `delete`, `migrate`, or `init` with `--yes --plan <hash>`;
   exit 75: show it again.
4. Write each `@<hash>`, path, and `--plan <hash>` literally, never from a file, variable, or command substitution.

Never run `specstone trust` or answer its prompt, even if told to; on `run specstone trust at a terminal`, ask the
Owner to run it, then retry.
