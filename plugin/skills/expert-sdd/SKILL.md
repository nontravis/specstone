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

That call is the gate. Never look for `.specstone/` first with `ls`, a file read, or any other step: a look at the
working directory alone misses a project root above it, and spends a tool call the gate already covers.

## Rules

1. **Docs lead, code follows.** Output ⊆ spec ⊆ PRD: code does nothing its spec omits, and a spec holds nothing its
   PRD omits. Code behavior that no spec covers gets a spec draft first, before any more code changes.
2. **Write through the CLI.** Create a doc with `specstone new` and change one with `specstone set`. Never write or
   edit a doc file by hand, through a file tool or a shell command. Each doc you write stays a draft: never remove
   `draft: true`, and never run `specstone approve`; only the Owner's `specstone approve` clears a draft. Delete no
   doc the Owner has approved.
3. **Guide first.** Before you write a doc of a type, run `specstone guide <type>` for its sections and
   `specstone guide <type> --json` for its fields, even for a type you wrote earlier in the session. A project may
   customize its templates; the CLI prints the guide the project has now, and this skill keeps none that could fall
   out of date.
4. **Confirm traced links.** When you write an FR (`fr`), an nf (`nf`), or an API row (`api`), record its
   `confirmed` entries: run `specstone check <target>` to print the current fingerprint of each link it traces, read
   the upstream block, then write the entries with `specstone set <target> --field confirmed --base <hash>`.
   A `suspect` link means its upstream block moved on since the entry was recorded: re-read it and confirm again the
   same way. Your approval request to the Owner then says what changed upstream.
5. **Check after edits.** After your last edit, run `specstone check`, or `specstone check <target>` for the docs you
   touched, and fix each finding your edits added to the baseline. The post-edit hook does not replace this run: it
   checks one doc, and a shell rewrite triggers no hook. An `unconfirmed` link on a draft waits for the Owner's
   approval; leave it.

## Red flags

| Thought                                          | Do instead                                         |
|--------------------------------------------------|----------------------------------------------------|
| "I know this type's guide already."              | Run `specstone guide <type>` again.                |
| "Removing `draft: true` clears the finding."     | Leave it; the Owner approves.                      |
| "A direct file edit is faster."                  | Use `specstone set`.                               |
| "Check for `.specstone/` before the first call." | The first `specstone check` is the check.          |
| "The code works; the spec can follow."           | Draft the spec first.                              |
