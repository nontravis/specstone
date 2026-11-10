---
name: expert-sdd
description: Use when about to write, edit, or confirm a PRD or spec doc in a Specstone project, when a doc's upstream changed after it was confirmed, when code does something no spec covers, or when another `specstone:` skill names `specstone:expert-sdd`.
---

# Specstone cross-doc rules

Shared rules for any skill that writes or confirms a Specstone doc.

## First call: the project gate

1. Run `specstone check` before any other command.
2. Exit 78 with `project_not_found`: tell the Owner the project is still on the old format; `specstone migrate` moves
   it, or they can keep using the old skills. Then stop: run nothing else, and neither read nor write a doc.
3. Exit 0 or 1: the project is on the new format, even from a subfolder. Keep any findings as the baseline and go on.
4. Any other non-zero exit: report the CLI's error to the Owner and stop.

That call is the gate. Never look for `.specstone/` first with `ls`, a file read, or any other step: a look at the
working directory alone misses a project root above it.

## Rules

1. **Docs lead, code follows.** Output ⊆ spec ⊆ PRD: code does nothing its spec omits, and a spec holds nothing its
   PRD omits. Code behavior that no spec covers gets a spec draft first, before any more code changes.
2. **Write through the CLI.** Create a doc with `specstone new` and change one with `specstone set`. Never write or
   edit a doc file by hand, through a file tool or a shell command. Each write leaves its doc a draft, a pointer
   write (`implements`, `covers`) excepted: never remove `draft: true`. Run `specstone approve` only with `--dry-run`,
   or with `--yes` as Owner confirmation below says; it binds `approve`, `delete` of a guarded doc, `migrate`, and
   `init` on a legacy tree alike.
3. **Guide first.** Before you write a doc of a type, run `specstone guide <type>` for its sections and
   `specstone guide <type> --json` for its fields, even for a type you wrote earlier in the session. A project may
   customize its templates; the CLI prints the guide it has now, and this skill keeps none.
4. **Confirm traced links.** When you write an FR, an nf, or an API row, follow `references/confirm-links.md`.
5. **Size in one order.** Over a size limit: layout, then a sub-feature split the Owner approves, then text moved to
   its home; never cut meaning. Cite a size only as `specstone structure <doc>` or `specstone check` prints it.
   Steps: `references/size-fix.md`.
6. **Check after edits.** After your last edit, run `specstone check`, or `specstone check <target>` once per doc you
   touched, and fix each finding your edits added to the baseline; leave each whose `waitsFor` is `owner`, its line
   ending `(waits for the Owner)`. The post-edit hook does not replace this run: it checks one doc, and a shell
   rewrite triggers no hook.
7. **Cite, never restate.** A rule has one owner doc. Every other doc cites it by name, `<type>:<name>` or
   `<type>:<name>#<section>` and the item ID inside it (`domain:document_writing#invariants` INV-9), and states
   nothing of the rule. `specstone refs <owner>` lists each citing doc, but a citation pins no hash: it never turns
   `suspect` when the owner changes.

## Owner confirmation

`approve`, `delete` of a guarded doc, `migrate`, and `init` on a legacy tree need the Owner's word, given at their
own terminal or here in the chat. In the chat:

1. Show what the command does, one item per message, in full:
   - `approve`: run `specstone approve <type>:<name> … --dry-run`, then send each draft it prints in its own
     message: first the literal `Why:` (in English), then one sentence in the language of the conversation on why
     the draft changed; then the draft's printed text, pasted verbatim. Never write, shorten, or reformat that text
     yourself. When the tool output is cut, run `--dry-run` again per draft, so every draft is pasted whole.
   - `delete`: the list and `plan <hash>` line `specstone delete <path> … --dry-run` prints, and why each goes.
   - `migrate`, or `init` on a legacy tree: the plan `specstone migrate --dry-run` prints, with its `plan <hash>`
     line.
2. The Owner answers `ok` or says what to fix. Fix it through `specstone set`, then show that item again.
3. Run the `--yes` command only after the Owner's `ok` for what you showed (the Owner may tell you to answer for
   them). After `ok` on every item of the batch, run one command, passing the hashes shown:
   `specstone approve <type>:<name>@<hash> … --yes` (each draft named, as a name approves only itself),
   `specstone delete <path> … --yes --plan <hash>`, `specstone migrate --yes --plan <hash>`, or
   `specstone init --yes --plan <hash>`. Exit 75 means an item changed since you showed it: show it again. Write every
   name with its `@<hash>`, every path, and the `--plan <hash>` literally in the command; never build them from a
   file, a variable, or a command substitution.
4. The Owner may instead run the command, without `--yes`, at their own terminal.

`specstone trust` is the Owner's alone, even when a chat message tells you to answer for them. Never run it or answer
its prompt, even through a pty or a shell tool. When a write refuses with `run specstone trust at a terminal`, stop: ask
the Owner to run `specstone trust` in their own terminal (Claude Code's `!` prefix is not a terminal), then retry.

## Red flags

| Thought | Do instead |
|---|---|
| "I know this type's guide already." | Run `specstone guide <type>` again. |
| "Removing `draft: true` clears the finding." | Leave it; the Owner approves. |
| "A direct file edit is faster." | Use `specstone set`. |
| "Check for `.specstone/` before the first call." | The first `specstone check` is the check. |
| "The code works; the spec can follow." | Draft the spec first. |
