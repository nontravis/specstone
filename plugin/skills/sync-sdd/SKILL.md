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
  `.specstone/config.yaml` here and in each folder above. Its findings give the work list (step 2).
- **Any other exit:** report the CLI's error and stop.

Never look for `.specstone/` yourself first: a look at the working directory misses a project root above it, and
costs a call the gate already makes.

## 2. Work list, then hand off

The work list is the gate's `code_suspect`, `code_unconfirmed`, `implements_path_unresolved`,
`implements_symbol_unresolved`, `covers_path_missing`, `code_uncovered`, and `tests_unresolved` findings, never a
`tests_missing` one. When the Owner names a feature, it is every code link of that feature that takes a state, findings
or not. Take nothing from the task: code changed outside a task is in the list too.

With an empty list, tell the Owner no code changed since its docs were compared, and stop with no dispatch and no
further call.

Else, with the `Agent` tool, dispatch `specstone:sdd-engineer` with `mode: sync`, `report:` a file `mktemp` makes
outside the repository, and the feature name when the Owner gave one. Send no list of paths or doc text, and work no
step of the procedure yourself. Without the tool, or when the dispatch fails, read `references/procedure.md` beside this
file (`${CLAUDE_PLUGIN_ROOT}/skills/sync-sdd/references/procedure.md`) and follow it.

## 3. After the report

When you followed the procedure yourself, its report stands in for item 1.

1. Show the Owner the agent's `Report:` line, then its relay block word for word, before your own notes.
2. Get each draft approved through `specstone:expert-sdd`'s Owner confirmation.
3. Ask the Owner, per point under `Mismatches:`, fix the code or fix the spec. Fix the code writes nothing: the next
   `check` lists the link again. Send a fix-the-spec pick to the same agent while it is live, else to a new one with the
   answers, when the fix lands in a spec doc. Ask the Owner, per file under `Uncovered:`, write a spec or change or
   remove the code; change or remove writes nothing, and a write-a-spec pick routes as a fix-the-spec pick does.
4. For each pointer that waited on an approval, once its draft is approved, write that one entry: pipe the corrected
   list to `specstone set implementation:<feature> --field implements --base <hash>` (or
   `specstone set <type>:<name> --field covers --base <hash>`), each with `--target <name>`, the target the report
   gives for that pointer, when the project has two or more, the hash from
   `bases.fields.implements` (or `bases.fields.covers`) of `specstone get <doc> --json` for the same doc, with the
   same `--target`.
5. Run `specstone:brainstorming-sdd` for each behavior the report hands over and each pick that lands in a story or FR,
   since the sync writes no PRD doc.
