---
name: specstone-sync-sdd
description: Use when code in a Specstone project changed and its spec docs must catch up, such as after a plan task's commit, when a code file moved or was deleted and a record code path or `covers:` pointer may break, when new code does something no spec states, or when another Specstone skill or agent names `specstone-sync-sdd`.
---

# Sync the docs with changed code

## 1. Gate: the first call

Make these your first CLI calls, before git, a file read, or any other command:

```
specstone folder
specstone check --out "<folder>/reports/check.gate.<XXXXXX>.txt"
```

`<folder>` is the path `folder` prints, `XXXXXX` six `a-z0-9` characters, picked again while that file exists.

- **78, `project_not_found`:** tell the Owner the project is still on the old format; `specstone migrate` moves it,
  or they keep using the old skills. Stop: run nothing more, and read or write no doc.
- **0 or 1:** the project is on the new format, even from a subfolder, since the CLI looks for
  `.specstone/config.yaml` here and in each folder above. Search its file for the work list (step 2).
- **Any other exit but 75, `index_busy` (run it again):** report the CLI's error and stop.

Never look for `.specstone/`: the gate finds a root above the working directory.

## 2. Work list, then hand off

The work list is the gate file's `code_suspect`, `code_unconfirmed`, `implements_path_unresolved`,
`implements_symbol_unresolved`, `covers_path_missing`, `code_uncovered`, `tests_unresolved`, and matrix-row findings,
never a `tests_missing` one. A matrix-row finding is a `matrix_test_unresolved` one, or a `suspect` or `unconfirmed` one
whose `waitsFor` is `agent`, on a Verification matrix row; one whose `waitsFor` is `owner` stays out. When the Owner
names a feature, it is every code link of that feature that takes a state, findings or not. Take nothing from the task:
code changed outside one is in the list too.

With an empty list, tell the Owner no code changed since its docs were compared, and stop with no dispatch and no
further call.

Else sort the list into groups. With a feature named, it is one group. With none, each finding goes to the group of the
top-level feature whose doc holds its code link, a sub-feature's finding to its top-level feature; a finding on a doc
under no feature, such as a topic, goes to that doc's own group; a `code_uncovered` finding goes to one `uncovered`
group. A finding with no code link, such as a `tests_unresolved` line or a matrix-row finding, goes by the doc that
holds the finding.

Then route each group as `references/routes.md` gives: feature groups' engineers at once, small groups by yourself
beside them, then each other group to one engineer at a time.

To dispatch `specstone-sdd-engineer`, follow `../specstone-expert-sdd/references/dispatch.md` with `mode: sync`,
`report:` `<folder>/reports/sdd-engineer.sync.<XXXXXX>.md`, and the group's input: `scope: feature:<name>`,
`scope: <type>:<name>`, or `scope: uncovered`; pass `feature: <name>` only for a feature the Owner named, as its one
group, with no `scope:`. Pass `check:` with the gate's file on a first-route dispatch alone; a later step runs its own
check first, as `routes.md` gives. Show each report's `Report:` line and relay block as it comes in. Send no list of
paths or doc text, and work no step of the procedure yourself while a dispatch can run, but a small group. Name
each report path as the gate names its file, `XXXXXX` picked again while that file exists.

Run again any `specstone` command that ends `index_busy`.

The main session's procedure is `references/procedure.md`. With no subagent, follow it once per group in route order,
on that group's findings. After a dispatch that fails, follow it for that group alone; the other groups go on by their
routes.

## 3. After the report

Run item 1 for each report as it comes in, and items 2 and 3 once, after the last group's report, over the picks of
every group. A group you judged or followed stands in for item 1 by its own changes and stamps.

1. Show the Owner the agent's `Report:` line, then its relay block word for word, before your own notes.
2. Get each draft approved through `specstone-expert-sdd`'s Owner confirmation.
3. Ask the Owner, per point under `Mismatches:`, fix the code or fix the spec. Fix the code writes nothing: the next
   `check` lists the link again. Ask the Owner, per file under `Uncovered:`, write a spec or change or
   remove the code; change or remove writes nothing, and a write-a-spec pick routes as a fix-the-spec pick does. When a
   fix lands in a spec doc, send the picks to a new `specstone-sdd-engineer` per group that holds picks, each routed as
   its group, with `mode: sync`, `picks`, and that group's `scope:` (`scope: uncovered` for an `Uncovered:` file), never
   `feature:` unless the Owner named the feature.
4. For each pointer that waited on an approval, once its draft is approved, write that one entry, each `set` with
   `--target <name>`, the report's, when the project has two or more: pipe the corrected list to
   `specstone set implementation:<feature> --field implements --base <hash>` (or
   `specstone set <type>:<name> --field covers --base <hash>`), the hash from `bases.fields.implements` (or
   `bases.fields.covers`) of `specstone get <doc> --json`, same `--target`. A waiting match then takes
   `specstone set <doc> --stamp <entry>=<fingerprint>` (the finding's, no base), and a `planned` entry's
   `implemented` goes to `statuses` by `--field statuses` with `bases.fields.statuses`. A refused stamp writes
   nothing more for its entry: report it, its finding left for the next sync. For each waiting removal, once approved,
   run `specstone set --remove-task <task> ...` (`--target <name>` when two or more), then name
   them to the Owner.
5. Follow the `specstone-brainstorming-sdd` skill for each behavior the report hands over and each pick that lands in
   a story or FR, since the sync writes no PRD doc.
