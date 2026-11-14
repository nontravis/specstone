---
name: plan-sdd
description: Use when approved docs in a Specstone project have no implementation plan yet, such as an approved story, FR, NFR, or spec doc to build, the user stories still `planned`, or a brainstorm's approved drafts, or when another `specstone:` skill names `specstone:plan-sdd`.
---

# Plan approved docs, then ask how to run the plan

One agent, `specstone:plan-engineer`, holds every plan rule and writes the plan. You gate, pick the targets, hand them
over by name, relay the reply, and ask the Owner how to run the plan. You write no plan text and run no task.

## 1. Gate: the first call

Make this your first CLI call, before git, a file read, or any other command:

```
specstone check
```

- **78, `project_not_found`:** tell the Owner the project is still on the old format; `specstone migrate` moves it,
  or they keep using the old skills. Stop: run nothing more, and read or write no doc.
- **0 or 1:** the project is on the new format, even from a subfolder, since the CLI looks for
  `.specstone/config.yaml` here and in each folder above. Act on the exit status alone; read no finding, nor a file
  the host saved them to: `specstone:plan-engineer`'s own `check` is the baseline.
- **Any other exit:** report the CLI's error and stop.

## 2. List the stories, ask the code target, pick the targets

Run this next, given targets or not, with no `--target`:

```
specstone list user_story --status planned --json
```

**Code target:** when the list refuses `argument_missing` naming two or more code
targets, ask the Owner which code target the plan is for, given target names and a drafts list alike; the answer is
`code target:` in step 3, and `--target <name>` on a rerun of this list when no target is given. A one-target project's list refuses nothing: ask
nothing, pass none. Learn it from the refusal, never from `.specstone/config.yaml`.

- **From `specstone:brainstorming-sdd`:** its last step invokes this skill with the approved drafts list and the
  design document's path. Take the list whole and filter out no doc type, a project or feature doc included:
  which docs a task builds is `specstone:plan-engineer`'s call alone.
- **Target names given:** each an approved story, FR, NFR, or spec doc. Take them as named.
- **No target, outside a brainstorm:** Offer the Owner each story of the list, rerun with `--target <name>` after the
  ask, whose `draft` is `false`, by name and title; leave out every draft. When none is left, say so and ask the
  Owner for target names. Dispatch nothing before the Owner picks or names targets.

A target that already has a plan gets a new one at the Owner's word: search for no earlier plan.

## 3. Hand off

With the `Agent` tool, dispatch one `specstone:plan-engineer` with these inputs, and no doc text:

- `targets:` the target names, or the approved drafts list whole;
- `code target:` the Owner's answer; leave the line out when none was asked;
- `design document:` its path, when a brainstorm passed one;
- `report:` a file `mktemp` makes outside the repository.

Work no step of the plan yourself. Without the tool, or when the dispatch fails, read
`${CLAUDE_PLUGIN_ROOT}/agents/plan-engineer.md` and follow it yourself under the same inputs, writing its one plan
file and its report; that report stands in for the reply. After a failed dispatch, before you first save the plan,
look in the folder that file's step 8 saves it to for a plan file written after the dispatch began whose tasks name
one of these targets. When one is there, take it as the `plan path`, name it in the report, and write no second plan.
Amend no other file, since another session wrote it; with no match, pick a new path by step 8's rule.

## 4. Relay the reply

1. Show the Owner the reply's `Report:` line, then its relay block word for word, every row included, before your
   own notes.
2. Ask the Owner once about each `NOT PLANNED` row, spec gap, conflict, and open question the block holds that no
   earlier round asked. Send the round's answers once to the same agent while it is live, else dispatch a new one,
   with step 3's inputs written out again, `targets:` whole and `code target:`, never "unchanged", plus `answers:`,
   and `plan path:` when there is one: the plan the `Plan:` line named, which it amends in place, or the Owner's new
   path. With a new path, `answers:` names any plan already written, which the agent leaves in place and names under
   `Findings:`.
   `Plan: none` names no plan, so it gives no `plan path:`.
3. Relay each amended reply as item 1 says; an item the Owner answered that stays unchanged shows in it and is never
   asked again. Go on to step 5 when a reply holds no item not yet asked, or the Owner has no more answers to send.

## 5. Ask how to run the plan

When the last reply's `Plan:` line reads `none`, tell the Owner no plan was written, pointing at the rows and
`Findings:` you relayed; offer no run skill, and stop.

Else show the Owner the plan the `Plan:` line names. Then find the run skills in your skill list: each skill whose
description says it runs an implementation plan. Judge by that description alone, never by a skill's name or a name
any file of this plugin holds.

- **One or more qualify:** offer every one, each by its name and its description's words, and ask which runs the
  plan. With two or more, pick none for the Owner.
- **The Owner picks one:** load it with `Skill` and hand it the plan's path.
- **None qualifies, or the Owner picks none:** say the plan is ready to run, and name its path.

Run no task yourself, whatever the Owner answers: each task's implementer grounds itself from the docs it names.
