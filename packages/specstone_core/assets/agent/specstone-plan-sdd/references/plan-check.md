# Check a plan against its docs and code

`specstone-sdd-auditor` follows this for `job: plan-check`, after its gate. It reads one plan against the docs its
tasks cite and the code its tasks name, and reports each fault ranked. It writes only its `report:` file, edits no
plan and no doc, and runs no `check`.

## 1. Inputs

Take the inputs the agent file's Input Contract gives `job: plan-check`: `plan`, `targets`, the change note,
`code target`, and `report`.

## 2. Read the plan

1. Read the plan whole, each task's read line and files included.
2. Read the plan rules in `../../../agents/specstone-plan-engineer.md`, and judge the plan by them; restate none of
   them here or in the report.
3. When a `change note` is given, read its Decisions: a task citing a `D<n>` is judged against that decided line,
   never against the doc it will change.
4. No decided line is itself a fault when the change note lacks an `Owner ok:` line or there is no change note; with
   that line, section 5 judges each decided line.

## 3. Ground once

Run one `specstone context <target> … --for implement --out --groups` call naming the targets of the plan's
task read lines, as the planner's Ground does, with `--target <code target>` before `--out` when one is given.
A Build-first plan whose tasks name no story names the change note's Reach targets in their place. When the call prints
`==> group` lines, read the saved files one group at a time, judging that group's tasks before the next. A non-zero
exit stops the check with the CLI's error, as an early stop of the agent file's Output Format. Search the saved files;
open no doc file, and run no second `context` call. Read each doc the saved files hold that a task builds, for the
facts its steps must carry. Keep each refs file path the call prints for section 5's decided-line grep.

## 4. Read the code

Read the code each task names, each file by its path, and compare the task's files, steps, and tests with what the
code does today.

## 5. Judge

Report a fault only when the saved files or the code show it, with its evidence. A fault is a task that contradicts a
doc, a step a builder cannot run as written, a file or symbol the code lacks, a doc fact no task carries, or a plan
rule of the planner file that the plan breaks.

Rank each fault by what it costs the build:

- `Critical`: the build fails or builds the wrong behavior.
- `Important`: the build works but a builder must guess, or a doc fact is left out.
- `Minor`: wording or order that costs a reader a pass.

When the change note holds an `Owner ok:` line, judge each decided line too:

- A decided line that works against a statement of the saved files the note names nowhere as superseded, or against
  a project vision, is one `Critical` item naming its `D<n>`. It is the `Contradiction` of step 4 of
  `../../specstone-brainstorming-sdd/references/audit.md`; its fix lies in the change note, so it takes no `Fix:`
  line.
- An input or state a decided line covers, for which a grounded doc states an outcome and the line states none, is
  one `Important` item naming its `D<n>`, with no `Fix:` line.
- After judging, run one `grep -n -E` joining each decided line's terms, as step 4 of
  `../../specstone-brainstorming-sdd/references/build-first-audit.md` does, over the refs file the call saved, or over
  every group's refs file in the same one command when it printed `==> group` lines. Run no other read after it.
  Each hit not yet reported that a decided line works against is one more `Critical` item, and each stating an
  outcome the line lacks is one more `Important` item. Its evidence is the `<doc>#<key>` of the doc the hit falls
  in, which the refs file's `==> ` header above the hit names, never the refs file's `<path>:<line>`.

## 6. Report

```
Findings:
- Critical: <plan path>:<line> <point> (<doc>#<key> or <path>:<line>)
  Fix: <what the plan should say>
- Critical: D<n> <change note path>:<line> <point> (<doc>#<key> or <vision ID>)
- Important: D<n> <input or state> (<doc>#<key>)
Notes:
- <observation>
```

- Open each item under `Findings:` with `Critical`, `Important`, or `Minor`, ranked by that order, and give the
  plan's `<plan path>:<line>` and its evidence, a doc key or a code `<path>:<line>`.
- Open a decided-line item with its `D<n>` right after its rank, ranked with every other item. It gives the change
  note's `<path>:<line>` for a clash, or the input or state for a missing outcome, where other items give the plan's
  line. A `Critical` or `Important` decided-line item takes no `Fix:` line.
- With no fault, `Findings:` reads `nothing important left`.
- State a fix as a `Fix:` line in plain words, never as a doc edit; the planner applies it.
- Put each observation that is no fault under `Notes:`; write no `Notes:` heading when there is none.
- Write no `Audited:` line.
- The job writes no plan and no doc, only the file named by `report:`.
