---
name: specstone-sync-sdd
description: Use when code in a Specstone project changed and its spec docs must catch up, such as after a plan task's commit, when a code file moved or was deleted and a record code path or `covers:` pointer may break, when new code does something no spec states, or when another Specstone skill or agent names `specstone-sync-sdd`.
---

# Sync the docs with changed code

## 1. Gate: the first call

Run these first, before git, a file read, or any other command:

```
specstone folder
specstone check --out "<folder>/reports/check.gate.<XXXXXX>.txt"
```

- `<folder>`: the path `folder` prints; `XXXXXX`: six `a-z0-9` characters, picked again while that file exists.
- **78, `project_not_found`:** tell the Owner the project is on the old format: `specstone migrate` moves it, or they keep the old skills. Stop; read or write no doc.
- **0 or 1:** new format, even from a subfolder; search the gate file for the work list.
- **Any other exit but 75, `index_busy` (rerun):** report the CLI's error and stop.
- Never look for `.specstone/`.

## 2. Work list, then hand off

- Work list: the gate file's `code_suspect`, `code_unconfirmed`, `implements_path_unresolved`, `implements_symbol_unresolved`, `covers_path_missing`, `code_uncovered`, `tests_unresolved`, and matrix-row findings; never `tests_missing`.
- Matrix-row finding: `matrix_test_unresolved`, `suspect` or `unconfirmed` with `waitsFor` `agent` on a Verification matrix row, or, under `verification_coverage` `edge_case`, a per-FR row's `matrix_row_malformed`.
- Leave out `waitsFor` `owner` findings.
- Owner names a feature: the list is its every code link that takes a state, findings or not.
- Take nothing from the task: code changed outside it counts.
- Empty list: tell the Owner no code changed since its docs were compared; stop, no dispatch, no further call.
- A named feature is one group; else each finding joins its code link doc's top-level feature group.
- A doc under no feature (a topic) is its own group; all `code_uncovered` findings form one `uncovered` group.
- A finding with no code link (a `tests_unresolved` line, a matrix-row finding) goes by its holding doc.
- Route each group by `references/routes.md`.
- To dispatch `specstone-sdd-engineer`, follow `../specstone-expert-sdd/references/dispatch.md` with `mode: sync`, `report:` `<folder>/reports/sdd-engineer.sync.<XXXXXX>.md`, and `scope: feature:<name>`, `scope: <type>:<name>`, or `scope: uncovered`.
- Pass `feature: <name>`, no `scope:`, only for the Owner-named feature as its one group.
- Pass `check:` the gate file on a first-route dispatch alone.
- Send no path list or doc text.
- Work no procedure step while a dispatch can run, but a small group.
- Name each report path as the gate names its file.
- Rerun any `specstone` command that ends `index_busy`.
- No subagent: follow `references/procedure.md` per group in route order; after a failed dispatch, for that group alone.

## 3. After the report

- Item 1 per report as it comes; items 2 and 3 once after the last report, over all groups' picks.
- A group you judged or followed stands in for item 1.

1. Show the Owner the agent's `Report:` line, then its relay block word for word, before your notes.
2. Follow `specstone-expert-sdd`'s "Get the drafts approved", with `--no-audit`.
3. Ask the Owner per `Mismatches:` point: fix the code (writes nothing) or the spec.
   - Ask per `Uncovered:` file: write a spec, or change or remove the code (writes nothing); write-a-spec routes as fix-the-spec.
   - A spec fix: a new `specstone-sdd-engineer` per group with picks, routed as its group: `mode: sync`, `picks`, the group's `scope:` (`scope: uncovered` for `Uncovered:`); `feature:` only if the Owner named it.
4. Once a waiting pointer's draft is approved, write that one entry, each `set` with the report's `--target <name>` when two or more:
   - Pipe the corrected list to `specstone set implementation:<feature> --field implements --base <hash>` or `specstone set <type>:<name> --field covers --base <hash>`.
   - Stamp a waiting match with the finding's fingerprint, no base; a waiting helper's from a `check` after its write.
   - A `planned` entry's `implemented`: `--field statuses` with `bases.fields.statuses`.
   - A refused stamp writes nothing more for its entry: report it; its finding stays.
   - A waiting removal, once approved or listed by a feature engineer: `specstone set --remove-task <task> ...` (`--target <name>` when two or more); name the tasks to the Owner.
5. Follow the `specstone-brainstorming-sdd` skill for each handed behavior and story or FR pick; write no PRD doc.
