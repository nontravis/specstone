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
  `.specstone/config.yaml` here and in each folder above. Keep the findings as the baseline.
- **Any other exit:** report the CLI's error and stop.

Never look for `.specstone/` yourself first: a look at the working directory misses a project root above it, and
costs a call the gate already makes.

## 2. Pick the targets

- **From `specstone:brainstorming-sdd`:** its last step invokes this skill with the approved drafts list and the
  design document's path. Take the list whole and filter out no doc type, a `project` or `feature` doc included:
  which docs a task builds is `specstone:plan-engineer`'s call alone, and it gives every other doc a row with no task.
- **Target names given:** each an approved story, FR, NFR, or spec doc. Take them as named.
- **No target, outside a brainstorm:** run the call below. Offer the Owner each story whose `draft` is `false`, by
  name and title, and leave out every draft; the text output marks no draft. Dispatch nothing before the Owner picks.

```
specstone list user_story --status planned --json
```

A target that already has a plan gets a new one at the Owner's word: search for no earlier plan.

## 3. Hand off

With the `Agent` tool, dispatch one `specstone:plan-engineer` with these inputs, and no doc text:

- `targets:` the target names, or the approved drafts list whole;
- `design document:` its path, when a brainstorm passed one;
- `report:` a file `mktemp` makes outside the repository.

Work no step of the plan yourself. Without the tool, or when the dispatch fails, read
`${CLAUDE_PLUGIN_ROOT}/agents/plan-engineer.md` and follow it yourself under the same inputs, writing its one plan
file and its report; that report stands in for the reply.

## 4. Relay the reply

1. Show the Owner the reply's `Report:` line, then its relay block word for word, every row included, before your
   own notes.
2. When the block holds `NOT PLANNED` rows, spec gaps, or open questions, ask the Owner each one. Send the answers to
   the same agent while it is live, else dispatch a new one, with the same inputs plus `answers:` and `plan path:`,
   the plan the report named. It amends that file in place; it writes no second plan file.
3. Relay each amended reply as item 1 says. Go on to step 5 when a reply holds none of them, or the Owner has no
   more answers to send.

## 5. Ask how to run the plan

Show the Owner the plan the `Plan:` line names. Then find the run skills in your skill list: each skill whose
description says it runs an implementation plan. Judge by that description alone, never by a skill's name or a name
any file of this plugin holds.

- **One or more qualify:** offer every one, each by its name and its description's words, and ask which runs the
  plan. With two or more, pick none for the Owner.
- **The Owner picks one:** load it with `Skill` and hand it the plan's path.
- **None qualifies, or the Owner picks none:** say the plan is ready to run, and name its path.

Run no task yourself, whatever the Owner answers: each task names the docs it builds, and its implementer grounds
itself from those names.

## Red flags

| Thought                                            | Do instead                                   |
|----------------------------------------------------|----------------------------------------------|
| "This story may have a plan already; look first."  | Search for none; dispatch for a new plan.    |
| "Paste the story so the agent saves a call."       | Send names only.                             |
| "No task builds the `project` doc; drop it."       | Pass the drafts list whole.                  |
| "Summarize the relay block for the Owner."         | Show it word for word.                       |
| "Two run skills fit; offer the better one."        | Offer every one.                             |
| "The Owner picked; I'll start task 1."             | Load the pick with `Skill`; run no task.     |
