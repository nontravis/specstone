# Plan by work groups

Follow this on a reply whose `Plan:` line reads `none (groups)`: a grouping pass, its `Groups:` block naming two or
more work groups. It wrote no plan; one planner per group writes a part, then one merge planner writes the plan.
`<folder>` is the path step 2 took from `specstone folder`.

## 1. Dispatch the planners

1. Dispatch one `specstone-plan-engineer` per group of its `Groups:` block, as
   `../../specstone-expert-sdd/references/dispatch.md` gives, with no doc text. Each takes the first dispatch's inputs
   written out again, its own `report:` in place of the first's, and these:
   - `group: <k> of <n>`, its entry's number;
   - `bundles:` its entry's `targets:` line, file paths, and read plan line, as the block prints them;
   - `check:` the block's `Check:` file;
   - `part:` `<folder>/reports/plan-engineer.part.<XXXXXX>.md`, the file its group's tasks go to.

   Name each `report:` `<folder>/reports/plan-engineer.plan.<XXXXXX>.md` and each `part:`, `XXXXXX` six `a-z0-9`
   characters, picked again while that file exists; each round reuses a group's two paths. The group dispatches may
   run at once, since each writes only its own part and report.
2. After every group planner reports, dispatch one `specstone-plan-engineer` with `parts:`, each part file with its
   report, the first dispatch's inputs written out again, and its own `report:`. It writes the one plan.
3. The merge planner's reply takes the plan check of `fresh-read.md` before the Owner sees its plan. Its findings
   round goes as section 2 gives, its relay left to this item. Then show the Owner the grouping pass's reply, each
   group planner's, then the merge planner's reply, each its latest, as step 3 item 1 gives: a target in no group
   keeps its row in the grouping pass's reply alone. A group planner's `Plan: none` names its part, never the end of
   the plan: step 4 reads the merge planner's `Plan:` line. Then ask as step 3 item 2 gives, each item once across
   those blocks, and send the answers as section 2 gives.

Work no planner's step yourself while a dispatch can run; without one, follow the agent file under each dispatch's
inputs in turn, as step 2 gives.

## 2. Answers after the merge

Send each answers round this way, in place of step 3 item 2's send. After the merge, send an answer on a row to a
fresh planner of that row's group, with its group's inputs written out again, `answers:`, and its `part:` path,
which it amends. A plan check's round goes the same way: each finding goes to a fresh planner of the group whose
part holds the task its plan line sits in, as an answer on a row does, and a finding on no part's line, such as the
header's, goes to the merge planner. Then dispatch the merge planner again, once, with its inputs written out again,
`answers:` holding each other answer of the round, and `plan path:` the plan its `Plan:` line named, or the Owner's
new path, as step 3 item 2 gives; it merges the amended parts into that plan. Relay each amended reply of an Owner's
round as step 3 item 3 gives, and a check round's once, by section 1 item 3.
