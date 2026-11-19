---
name: specstone-sync-sdd
description: Use when code in a Specstone project changed and its spec docs must catch up, such as after a plan task's commit, when a code file moved or was deleted and a record code path or `covers:` pointer may break, when new code does something no spec states, or when another Specstone skill or agent names `specstone-sync-sdd`.
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
`implements_symbol_unresolved`, `covers_path_missing`, `code_uncovered`, `tests_unresolved`, and matrix-row findings,
never a `tests_missing` one. A matrix-row finding is a `matrix_test_unresolved` one, or a `suspect` or `unconfirmed` one
whose `waitsFor` is `agent`, on a Verification matrix row, or, under `verification_coverage` `edge_case`, a per-FR
row's `matrix_row_malformed`; one whose `waitsFor` is `owner` stays out. When the Owner
names a feature, it is every code link of that feature that takes a state, findings or not. Take nothing from the task:
code changed outside a task is in the list too.

With an empty list, tell the Owner no code changed since its docs were compared, and stop with no dispatch and no
further call.

Else sort the list into groups. With a feature named, it is one group. With none, each finding goes to the group of the
top-level feature whose doc holds its code link, a sub-feature's finding to its top-level feature; a finding on a doc
under no feature, such as a topic, goes to that doc's own group; a `code_uncovered` finding goes to one `uncovered`
group. A finding with no code link, such as a `tests_unresolved` line or a matrix-row finding, goes by the doc that
holds the finding.

Then dispatch `specstone-sdd-engineer` for each group in turn, one at a time, as
`../specstone-expert-sdd/references/dispatch.md` gives, with `mode: sync`, `report:`
`<folder>/reports/sdd-engineer.sync.<XXXXXX>.md`, and the group's input: `scope: feature:<name>`,
`scope: <type>:<name>`, or `scope: uncovered`; pass `feature: <name>` only for a feature the Owner named, as its one
group, with no `scope:`. Show each report's `Report:` line and relay block before the next dispatch. Send no list of
paths or doc text, and work no step of the procedure yourself while a dispatch can run. Take `<folder>` the path
`specstone folder` prints, run once after the gate; `XXXXXX` is six `a-z0-9` characters, picked again for each report
while that file exists.

The procedure for the main session is `references/procedure.md` beside this file. With no subagent on the host, follow
the procedure yourself once per group, in the same order, taking only that group's findings. After a dispatch that
fails, follow it for that group alone, then dispatch the next group again.

## 3. After the report

Run item 1 for each group as its report comes in, and items 2 and 3 once, after the last group's report, over the picks
of every group. A group you followed yourself stands in for item 1 by its own changes.

1. Show the Owner the agent's `Report:` line, then its relay block word for word, before your own notes.
2. Get each draft approved through `specstone-expert-sdd`'s Owner confirmation.
3. Ask the Owner, per point under `Mismatches:`, fix the code or fix the spec. Fix the code writes nothing: the next
   `check` lists the link again. Ask the Owner, per file under `Uncovered:`, write a spec or change or
   remove the code; change or remove writes nothing, and a write-a-spec pick routes as a fix-the-spec pick does. When a
   fix lands in a spec doc, send the picks to a new `specstone-sdd-engineer` per group that holds picks, one at a time,
   each with `mode: sync`, `picks`, and that group's `scope:` (`scope: uncovered` for an `Uncovered:` file), never
   `feature:` unless the Owner named the feature.
4. For each pointer that waited on an approval, once its draft is approved, write that one entry: pipe the corrected
   list to `specstone set implementation:<feature> --field implements --base <hash>` (or
   `specstone set <type>:<name> --field covers --base <hash>`), each with `--target <name>`, the target the report
   gives for that pointer, when the project has two or more, the hash from
   `bases.fields.implements` (or `bases.fields.covers`) of `specstone get <doc> --json` for the same doc, with the
   same `--target`. A waiting match is written whole: the
   fingerprint ends the entry, and a `planned` entry's `implemented` goes to `statuses` through `--field statuses` with
   `bases.fields.statuses`. For each waiting removal, once its draft is approved, run
   `specstone set --remove-task <task> ...` (with `--target <name>` when the project has two or more), then name the
   removed tasks to the Owner.
5. Follow the `specstone-brainstorming-sdd` skill for each behavior the report hands over and each pick that lands in
   a story or FR, since the sync writes no PRD doc.
