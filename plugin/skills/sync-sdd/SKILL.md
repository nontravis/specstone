---
name: sync-sdd
description: Use when code in a Specstone project changed and its spec docs must catch up, such as after a plan task's commit, when a code file moved or was deleted and a record code path or `covers:` pointer may break, when new code does something no spec states, or when another `specstone:` skill or agent names `specstone:sync-sdd`.
---

# Sync the docs with changed code

## 1. Gate: the first call

Make this your first CLI call, before git, a file read, or any other command:

```
specstone check
```

- **78, `project_not_found`:** tell the Owner the project is still on the old format; `specstone migrate` moves it,
  or they keep using the old skills. Stop: run nothing more, and read or write no doc.
- **0 or 1:** the project is on the new format, even from a subfolder, since the CLI looks for
  `.specstone/config.yaml` here and in each folder above. Keep the findings as the baseline.
- **Any other exit:** report the CLI's error and stop.

Never look for `.specstone/` yourself first: a look at the working directory misses a project root above it, and
costs a call the gate already makes.

## 2. Hand off

With the `Agent` tool, dispatch `specstone:sdd-engineer` with `mode: sync`, `report:` a file `mktemp` makes outside the
repository, and the changed paths the task lists, or the base commit when it lists none. Send no doc text, and work no
step of the procedure yourself. Without the tool, or when the dispatch fails, read `references/procedure.md` beside this
file (`${CLAUDE_PLUGIN_ROOT}/skills/sync-sdd/references/procedure.md`) and follow it.

## 3. After the report

When you followed the procedure yourself, its report stands in for item 1.

1. Show the Owner the agent's `Report:` line, then its relay block word for word, before your own notes.
2. Get each draft approved through `specstone:expert-sdd`'s Owner confirmation.
3. Ask the Owner each open question; send the answers to the same agent while it is live, else dispatch a new one
   with them.
4. For each pointer that waited on an approval, once its draft is approved, write that one entry: pipe the corrected
   list to `specstone set implementation:<feature> --field implements --base <hash>` (or
   `specstone set <type>:<name> --field covers --base <hash>`), each with `--target <name>`, the changed path's code
   target, when the project has two or more (`domain:agent_plugin` INV-25), the hash from `bases.fields.implements`
   (or `bases.fields.covers`) of `specstone get <doc> --json` for the same doc, with the same `--target`.
5. Run `specstone:brainstorming-sdd` for each behavior the report hands over.
