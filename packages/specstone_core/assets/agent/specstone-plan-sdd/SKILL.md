---
name: specstone-plan-sdd
description: Use when approved docs in a Specstone project have no implementation plan yet, such as an approved story, FR, NFR, or spec doc to build, the user stories still `planned`, or a brainstorm's approved drafts, or when another Specstone skill names `specstone-plan-sdd`.
---

# Plan approved docs, then ask how to run the plan

`specstone-plan-engineer` holds every plan rule and writes the plan, bar the case `references/main-writer.md`'s
test passes: you write it by `../../agents/specstone-plan-engineer.md`. You gate, pick targets, relay, and ask how
to run it.

## 1. List the stories: the gate, the code target, the targets

Make this your first CLI call, before git, a file read, or any other command, given targets or not, with no
`--target`:

```
specstone list user_story --status planned --json
```

- **78, `project_not_found`:** tell the Owner the project is still on the old format; `specstone migrate` moves it,
  or they keep using the old skills. Stop: run nothing more, and read or write no doc.
- **`argument_missing` naming two or more code targets:** ask the Owner which code target the plan is for, given
  target names and a drafts list alike; the answer is `code target:` in step 2, and `--target <name>` on a rerun of
  this list when no target is given. A one-target project's list refuses nothing: ask nothing, pass none. Learn it
  from the refusal, never from `.specstone/config.yaml`.
- **Any other non-zero exit:** report the CLI's error and stop.
- **0:** the project is on the new format: the CLI looks for
  `.specstone/config.yaml` here and in each folder above. Run no `check`: the gate is the agent file's own, run by
  whoever follows it.

- **From `specstone-brainstorming-sdd`:** its last step follows this skill with the approved drafts list and the
  change note's path. Take the list whole, a project or feature doc included:
  which docs a task builds is `specstone-plan-engineer`'s call alone. A Decided change comes with its note's path
  alone: offer the Owner no pick, and send no `targets:`.
- **Target names given:** each an approved story, FR, NFR, or spec doc. Take them as named.
- **No target, outside a brainstorm:** Offer the Owner each story of the list, rerun with `--target <name>` after the
  ask, whose `draft` is `false`, by name and title. When none is left, say so and ask the
  Owner for target names. Dispatch nothing until the Owner picks or names targets.

A target that already has a plan gets a new one at the Owner's word: search for no earlier plan.

## 2. Hand off

Unless the test in `references/main-writer.md` passes, dispatch one `specstone-plan-engineer` as
`../specstone-expert-sdd/references/dispatch.md` gives, with these inputs and no doc text:

- `targets:` the target names, or the approved drafts list whole; leave the line out for a Decided change;
- `code target:` the Owner's answer; leave the line out when none was asked;
- `change note:` its path, when a brainstorm passed one;
- `report:` `<folder>/reports/plan-engineer.plan.<XXXXXX>.md`, `<folder>` the path `specstone folder` prints, run
  once after step 1, `XXXXXX` six `a-z0-9` characters, picked again while that file exists; each round reuses it.

When that test passes, or no dispatch can run, follow `../../agents/specstone-plan-engineer.md` under the same
inputs, writing its one plan file and its report; that report stands in for the reply. After a failed dispatch,
before you first save the plan, look in the folder that file's step 8 saves it to for a plan file written after the
dispatch began whose tasks name one of these targets. When one is there, take it as the `plan path`, name it in the
report, and write no second plan. Amend no other file; with no match, pick a new path by step 8's rule.

## 3. Relay the reply

`Plan: none (groups)` is no `none` line: follow `references/groups.md` in place of item 1. The run's first written
plan takes the check of `references/fresh-read.md` before item 1.

1. Show the Owner the reply's `Report:` line, then its relay block word for word, every row included, before your
   own notes.
2. Ask the Owner once about each `NOT PLANNED` row, spec gap, conflict, and open question the block holds that no
   earlier round asked. Send the round's answers once to the same agent while it is live, else dispatch a new one (a
   plan you wrote follows `references/main-writer.md`),
   with step 2's inputs written out again, `targets:` whole and `code target:`, never "unchanged", plus `answers:`,
   and `plan path:` when there is one: the plan the `Plan:` line named, which it amends, or the Owner's new path.
   With a new path, `answers:` names any plan already written.
   `Plan: none` names no plan, so it gives no `plan path:`.
3. Relay each amended reply as item 1 says; an item the Owner answered that stays unchanged shows in it, never asked
   again. Go on to step 4 when a reply holds no item not yet asked, or the Owner sends no more answers.

## 4. Ask how to run the plan

When the last reply's `Plan:` line reads `none`, tell the Owner no plan was written, pointing at the rows and
`Findings:` you relayed; offer no run skill, and stop.

Else show the Owner the plan the `Plan:` line names. Then find the run skills in your skill list: each skill whose
description says it runs an implementation plan. Judge by that description alone, never by a skill's name or a name
any file of this plugin holds.

- **One or more qualify:** offer every one, each by its name and its description's words, and ask which runs the
  plan. With two or more, pick none for the Owner.
- **The Owner picks one:** follow it and hand it the plan's path.
- **None qualifies, or the Owner picks none:** say the plan is ready to run, and name its path.

Beside that question, follow `references/tickets.md`.

Run no task: each task's implementer grounds itself by its read line,
`specstone context <target> --for implement --out`, per the `specstone-read-sdd` skill.
