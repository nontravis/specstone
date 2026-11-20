---
name: specstone-expert-sdd
description: Use when about to write, edit, or confirm a PRD or spec doc in a Specstone project, when a doc's upstream changed after it was confirmed, when code adds or changes observable behavior no spec states, or when another Specstone skill names `specstone-expert-sdd`.
---

# Specstone cross-doc rules

## First call: the project gate

1. Run `specstone folder` first, then
   `specstone check --out "<folder>/reports/check.gate.<XXXXXX>.txt"`: `<folder>` the path `folder` prints, `XXXXXX`
   six `a-z0-9` characters, picked again while that file exists.
2. Exit 78 with `project_not_found`: tell the Owner the project is still on the old format; `specstone migrate` moves
   it, or they keep the old skills. Then stop: run, read, and write nothing.
3. `check` exit 0 or 1: the project is on the new format, even from a subfolder. Its file is the baseline: search it,
   never read it whole.
4. Any other exit: report the CLI's error and stop.

A dispatch passing a fresh `check:` file skips steps 1 to 4: search it; `<folder>` is its folder's parent.
Never look for `.specstone/`: it can sit above the working directory.

## Rules

1. **Docs lead, code follows.** Output ⊆ spec ⊆ PRD over the Observable contract, what users, callers, or other
   features see: a spec states only what its PRD asks, and code that adds or changes such behavior no spec states
   gets a spec draft first.
2. **Write through the CLI.** Create docs with `specstone new`, change them with `specstone set`. Never edit a
   doc file with a file tool or shell command. Each write leaves its doc a draft, a pointer
   write (`implements`, `covers`) excepted: never remove `draft: true`. Run `specstone approve` only with `--dry-run`,
   `--auto`, or `--yes` as below.
3. **Guide first.** Before writing a doc, have its type's current guide: `specstone guide <type>` and
   `specstone guide <type> --json`. One call naming several types counts for each, as does this run's saved guide.
4. **Confirm traced links.** To write an FR, an nf, an API row, or an `Overrides:` line, follow `references/confirm-links.md`.
5. **Size in one order.** Over a size limit: layout, then a sub-feature split the Owner approves, then text moved to
   its home; never cut meaning. Cite a size only as `specstone structure <doc>` or `check` prints it.
   Steps: `references/size-fix.md`.
6. **Check after edits.** After your edits, run `specstone check <target> --out "<folder>/reports/check.done.<XXXXXX>.txt"`
   once per doc you touched, and fix each finding your edits added to the baseline; leave each whose `waitsFor` is
   `owner`, its line ending `(waits for the Owner)`.
7. **Cite, never restate.** A rule has one owner doc. Every other doc cites it by a link to the item that holds it,
   `[<ID>](<path>#<section heading anchor>)`, or by a section or doc link when none does, and states nothing
   of the rule. `check` reports an old cite form as `cite_unlinked` and a link to an item its section lacks
   as `link_item_missing`. Its links: `references/confirm-links.md`.
8. **Code target.** With two or more code targets, `new`, `get`, `set` (a `confirmed` write included),
   `structure <doc>`, and `refs <owner>` take the `--target` of the surface that loads this skill, never an Owner
   question; `approve` and `delete` take none.
9. **Feature patterns.** For a new feature, pick patterns with `specstone guide --pattern`; cover each checklist
   item or name it in the feature's Out-of-scope as a skip line.

## Get the drafts approved

Only the main session runs `--auto`; a subagent runs `approve` only with `--dry-run` and reports its drafts.

1. Run one `specstone approve <type>:<name> … --auto --json` naming each draft of the run's own list (yours or the
   engineer's), never a bare `approve`. In `specstone-brainstorming-sdd` add `--audit <path>` per audit
   report, oldest first, and `--author <path>` per author report; in a bootstrap round with a trim batch or an audit's
   fix batch, `--audit <path>` per audit report of the round, oldest first; else `--no-audit`.
2. Exit 75: rerun once; a second sends all drafts to Owner confirmation.
3. List each `approved` entry's `name`, `docPath`, and `Why:` sentence, with no wait; for a confirmation written
   again, the upstream change.
4. Send each `asked` entry to Owner confirmation unchanged.

Under either mode the Owner answers the design document's approval, a mid-flow or report question, a split proposal, a
sync pick, each `--plan`.

## Owner confirmation

`approve`, `delete` of a guarded doc, `migrate`, and `init` on a legacy tree need the Owner's word: at their terminal
without `--yes` or in the chat:

1. Show each item in full, one per message:
   - `approve`, per draft the `--auto` call asks: the literal `Why:`, one sentence in the chat's language on why it
     changed, then its `specstone approve <type>:<name> … --dry-run` text verbatim, per draft if cut.
   - `delete`, `migrate`, or legacy `init`: the list or plan and `plan <hash>` line of
     `specstone delete <path> … --dry-run` or `specstone migrate --dry-run`, and why each goes.
2. The Owner says `ok` or what to fix; fix it by `specstone set`; show it again.
3. After `ok` on every item shown (or the Owner's leave), run one command with the hashes shown,
   each draft named: `specstone approve <type>:<name>@<hash> … --yes`, or `specstone delete <path> …`, `migrate`, or
   `init` with `--yes --plan <hash>`. Exit 75: show it again. Write each `@<hash>`, path, and `--plan <hash>`
   literally, never from a file, variable, or command substitution.

`specstone trust` is the Owner's alone, even if told to answer for them: never run it or answer its prompt by any
tool. On `run specstone trust at a terminal`, ask the Owner to run it, then retry.

## Red flags

| Thought | Do instead |
|---|---|
| "I read this type's guide in an earlier task." | Have its current or saved guide. |
| "A direct file edit is faster." | Use `specstone set`. |
