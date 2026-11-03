`specstone:sdd-engineer` runs this in `mode: plan`, its gate already made; so does the runner of
`specstone:brainstorming-sdd` when it has no `Agent` tool or the dispatch failed. As the agent, ask the Owner
nothing: each gap goes into your report as an open question.

Write the plan from the drafts the Owner approved, not from the design document's promises: the document names what
changes, and the docs say what each change now is.

## 1. Check the inputs

- **Design document**: the approved document's path. Read it whole.
- **Plan**: the file to write, under `docs/superpowers/plans/`. When it exists, read it whole: you amend it with
  `Edit` and never write a second file.
- **A plan path outside `docs/superpowers/plans/`, or a PRD or spec doc named as the file:** write nothing; report
  the path as an open question.

## 2. Read the stories

For each story the document changes or adds, run `specstone context <story> --for implement`. Each bundle holds the
story's FRs: their IDs and their present text are what the tasks build. Any non-zero exit: report the CLI's error and
stop.

## 3. Write the plan

- **`superpowers:writing-plans` in your skill list:** load it with `Skill` and follow it for the header, the file
  map, the task size, and the steps; where they differ, the rules below win. When it reaches its execution
  hand-off, stop: offer no way to run the plan and invoke nothing; go to step 4.
- **Not in your skill list:** write a header (the goal, the design document's path, the constraints every task
  keeps), then numbered tasks. Each task names the files it creates or changes, then its steps: write the failing
  test, run it and see it fail, write the code, run it and see it pass, commit.

Either way, every task:

- Names the story and FR IDs it builds, and nothing of their text: no statement, scenario, edge case, or table.
- Tells its implementer to read each one fresh with `specstone context <target> --for implement`
  (`specstone:read-sdd`) before writing code, since the doc may change before the task runs.

Write the file with `Write`, or the change with `Edit` when it exists. Write no other file and no PRD or spec doc.

## 4. Check before you report

- Each FR that the document adds or changes is built by a task.
- No task quotes a doc's text; each cites IDs only.
- Each cited ID is one that a step 2 bundle printed.

## 5. Report

```
Plan: <path>, written | amended
| Story or FR | Task |
|-------------|------|
| <ID> | <task number>, or NOT PLANNED |
Open questions:
- <a gap neither the document nor any doc bears on>
Findings: <each ID no bundle printed, or none>
```

Stop there: the main session shows the plan and asks the Owner how to run it.
