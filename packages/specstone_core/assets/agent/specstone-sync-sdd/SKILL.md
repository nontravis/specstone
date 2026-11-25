---
name: specstone-sync-sdd
description: Use when code in a Specstone project changed and its spec docs must catch up, such as after a plan task's commit, when a code file moved or was deleted and a record code path or `covers:` pointer may break, when new code does something no spec states, or when another Specstone skill or agent names `specstone-sync-sdd`.
---

# Sync the docs with changed code

## 1. The first call

Run `specstone context --for sync --out` first, before git, a file read, or any other command but the deferred write below. When the Owner names a feature, it is the target: `specstone context feature:<name> --for sync --out`.

- **78, `project_not_found`:** tell the Owner no Specstone project is found here; `specstone init` starts one. Stop; run nothing more, read or write no doc.
- **75, `index_busy`:** rerun it. **Any other exit but 0:** report the CLI's error and stop.
- **Stdout says no code changed since its docs were compared:** tell the Owner so; stop, with no dispatch and no further call.
- Else stdout prints one line per group: its scope, its route word, and its group file's path.
- This call alone gives the work list and groups, never the task's path list, so code changed outside it counts.
- `<folder>`: the folder holding the reports folder of those group files. Never look for `.specstone/`.
- **A plan that deferred its record writes:** before the first call, put every `tests` line its implementers reported, then every `row` line, in one sync file `<folder>/reports/<agent>.sync.<XXXXXX>.md`, `<folder>` the path `specstone folder` prints and `<agent>` your agent name. Write it by one `specstone set --sync <sync file>`, with `--target <name>` when the plan names one, answering a refused line by `references/procedure.md` step 5; then make the first call, which pre-fills each new row's `match` line.

## 2. Route each group

- Run each group by its route word, `small`, `engineer`, or `last`, as `references/routes.md` gives.
- To dispatch `specstone-sdd-engineer`, follow `../specstone-expert-sdd/references/dispatch.md` with `mode: sync`, `report:` `<folder>/reports/sdd-engineer.sync.<XXXXXX>.md`, the group's scope as `scope: feature:<name>`, `scope: <type>:<name>`, or `scope: uncovered`, and `group file:` the path the first call printed for it.
- `XXXXXX`: six `a-z0-9` characters, picked again while that file exists.
- For a feature the Owner named, pass `feature: <name>` in place of `scope:`; its one group is never small.
- At a plan's last sync and each of its reruns, each engineer dispatch also carries `change note:` the path the plan's last task names.
- Send no path list and no doc text.
- Work no group yourself while a dispatch can run, but a `small` one.
- Rerun any `specstone` command that ends `index_busy`.
- No subagent: follow the `specstone-expert-sdd` skill, then `references/procedure.md` per group in route order, each from its group file, with a `change note` also `references/decided.md`; after a failed dispatch, both for that group alone.

## 3. After the report

- Item 1 per report as it comes; items 2 to 4 once after the last report, over all groups' picks.
- A group you judged or followed stands in for item 1.

1. Show the Owner the agent's `Report:` line, then its relay block word for word, before your notes.
2. Follow `../specstone-expert-sdd/references/approve.md`, with `--no-audit`, bar a Decided change's drafts, which item 4 approves.
3. Ask the Owner per `Mismatches:` point: fix the code (writes nothing) or the spec.
   - Ask per `Uncovered:` file: write a spec, or change or remove the code (writes nothing); write-a-spec routes as fix-the-spec.
   - A spec fix: a new `specstone-sdd-engineer` per group with picks, routed as its group: `mode: sync`, `picks`, the group's `scope:` (`scope: uncovered` for an `Uncovered:` file) and the first call's `group file:`; `feature:` only if the Owner named it.
4. For a Decided change's drafts, after the last rerun and item 3's spec fixes, with no fix-the-work pick on a decided-line point left to rerun, dispatch one fresh `specstone-sdd-auditor` by `../specstone-expert-sdd/references/dispatch.md`, with `job: decided-audit`, the change note's path, the drafts list, a decided-line point's fix-the-spec drafts included, and each engineer report.
   - Then follow `../specstone-expert-sdd/references/approve.md` for those drafts, the audit's report its one `--audit`, before the branch lands.
5. Once a waiting line's draft is approved, write it, with the report's `--target <name>` when two or more:
   - Run `specstone set --sync` again on the same group file: it writes the waiting lines, each waiting `remove-task` line included; name to the Owner the tasks it removes, found as `references/task-refs.md` finds them.
   - A waiting line it refuses then: leave it out, write the rest again, a pointer fix included; write no fingerprint or status for its entry; report it; its finding stays.
   - A waiting helper: `references/helpers.md`'s `--field covers` write, with no fingerprint.
   - A new spec's waiting pointer: `references/procedure.md` step 6's `--field covers` or `--field implements` write, with no fingerprint.
6. Follow the `specstone-brainstorming-sdd` skill for each handed behavior and story or FR pick; write no PRD doc but a decided line's drafts, through its engineer.
