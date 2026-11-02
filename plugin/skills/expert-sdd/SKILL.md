---
name: expert-sdd
description: Use when about to write, edit, or confirm a PRD or spec doc in a Specstone project, when a doc's upstream changed after it was confirmed, when code does something no spec covers, or when another `specstone:` skill names `specstone:expert-sdd`.
---

# Specstone cross-doc rules

Shared rules for any skill that writes or confirms a Specstone doc. No doc type's writing guide lives here: the CLI
prints each one as the project defines it.

## First call: the project gate

1. Run `specstone check` before any other command.
2. Exit 78 with `project_not_found`: tell the Owner the project is still on the old format; `specstone migrate` moves
   it, or they can keep using the old skills. Then stop: run nothing else, and neither read nor write a doc.
3. Exit 0 or 1: the project is on the new format, even from a subfolder, since the CLI searches each parent folder
   for `.specstone/config.yaml`. Keep any findings as the baseline and go on.
4. Any other non-zero exit: report the CLI's error to the Owner and stop.

That call is the gate. Never look for `.specstone/` first with `ls`, a file read, or any other step: a look at the
working directory alone misses a project root above it, and spends a tool call the gate already covers.

## Rules

1. **Docs lead, code follows.** Output ⊆ spec ⊆ PRD: code does nothing its spec omits, and a spec holds nothing its
   PRD omits. Code behavior that no spec covers gets a spec draft first, before any more code changes.
2. **Write through the CLI.** Create a doc with `specstone new` and change one with `specstone set`. Never write or
   edit a doc file by hand, through a file tool or a shell command. Each write leaves its doc a draft, a pointer
   write (`implements`, `covers`) excepted: never remove `draft: true`, and never run `specstone approve` without
   `--yes`. Run `--yes` only as Owner confirmation below says; it binds `approve`, `delete` of an approved doc,
   `migrate`, and `init` on a legacy tree alike.
3. **Guide first.** Before you write a doc of a type, run `specstone guide <type>` for its sections and
   `specstone guide <type> --json` for its fields, even for a type you wrote earlier in the session. A project may
   customize its templates; the CLI prints the guide the project has now, and this skill keeps none that could fall
   out of date.
4. **Confirm traced links.** When you write an FR (`fr`), an nf (`nf`), or an API row (`api`), record its
   `confirmed` entries: run `specstone check <target>` to print the current fingerprint of each link it traces, read
   the upstream block, then write the entries with `specstone set <target> --field confirmed --base <hash>`.
   Take `<hash>` from `bases.fields.confirmed` in `specstone get <target> --json`, never from a fingerprint `check`
   prints. A `suspect` link means its upstream block moved on since the entry was recorded: re-read it and confirm
   again the same way. Your approval request to the Owner then says what changed upstream.
5. **Check after edits.** After your last edit, run `specstone check`, or `specstone check <target>` once per doc you
   touched, and fix each finding your edits added to the baseline. The post-edit hook does not replace this run: it
   checks one doc, and a shell rewrite triggers no hook. An `unconfirmed` link on a draft waits for the Owner's
   approval; leave it.

## Owner confirmation

`approve`, `delete` of an approved doc, `migrate`, and `init` on a legacy tree need the Owner's word, given at their
own terminal or here in the chat. In the chat:

1. Show what the command does, one item per message, in full:
   - `approve`: each draft's file path and its hash, `bases.doc` of `specstone get <type>:<name> --json`, then each
     changed section or field, its old text marked `📜 เดิม:`, a blank line, then its new text marked `🆕 ใหม่:`, never shortened
     with `...`. Mark text you wrote `[AI เขียน]` and a removal you propose `[AI เสนอ]`; keep these markers verbatim,
     as the Owner reads Thai.
   - `delete`: the list and `plan <hash>` line `specstone delete <path> … --dry-run` prints, and why each goes.
   - `migrate`, or `init` on a legacy tree: the plan `specstone migrate --dry-run` prints, with its `plan <hash>`
     line.
2. The Owner answers `ok` or says what to fix. Fix it through `specstone set`, then show that item again.
3. Run the `--yes` command only after the Owner's `ok` for what you showed (the Owner may tell you to answer for
   them). After `ok` on every item of the batch, run one command, passing the hashes you showed:
   `specstone approve <type>:<name>@<hash> … --yes` (each draft named, as a name approves only itself),
   `specstone delete <path> … --yes --plan <hash>`, `specstone migrate --yes --plan <hash>`, or
   `specstone init --yes --plan <hash>`. Exit 75 means an item changed since you showed it: show it again. Write every
   name with its `@<hash>`, every path, and the `--plan <hash>` literally in the command; never build them from a
   file, a variable, or a command substitution.
4. The Owner may instead run the command, without `--yes`, at their own terminal.

## Red flags

| Thought                                          | Do instead                                         |
|--------------------------------------------------|----------------------------------------------------|
| "I know this type's guide already."              | Run `specstone guide <type>` again.                |
| "Removing `draft: true` clears the finding."     | Leave it; the Owner approves.                      |
| "A direct file edit is faster."                  | Use `specstone set`.                               |
| "Check for `.specstone/` before the first call." | The first `specstone check` is the check.          |
| "The code works; the spec can follow."           | Draft the spec first.                              |
