# Check a written plan with a fresh reader

A plan is written by the planner or by you; a fresh reader checks it before the Owner sees it. `<folder>` is the path
step 2 of `SKILL.md` took from `specstone folder`.

## 1. Dispatch the check

Follow this on the first reply whose `Plan:` line names a written plan, even after a `Plan: none` round, such as
the merge planner's in a run by groups; a `none` or `none (groups)` line, and a group planner's reply, take no check.

Dispatch one `specstone-sdd-auditor` with `job: plan-check` and `plan:` the path the `Plan:` line names, as
`../../specstone-expert-sdd/references/dispatch.md` gives, with no doc text.

Give it step 2's `targets:`, `change note:`, and `code target:` lines, each when step 2 sends it, and `report:`
`<folder>/reports/sdd-auditor.audit.<XXXXXX>.md`, `XXXXXX` six `a-z0-9` characters, picked again while that file
exists.

Run it before step 3 item 1 of `SKILL.md` shows the Owner the plan.

An answers round or an amended reply takes no second plan check once a check has run.

A plan you wrote takes the same dispatch, since the session that wrote it did not come to it fresh.

A host with no subagent, or a failed dispatch, takes the main-session rung of `dispatch.md`; tell the Owner the check
ran in the main session and is not a fresh reader's.

## 2. Act on the check

When the check's reply holds no `Findings:` line, as after an `OPEN QUESTIONS:` stop, the check did not run: tell the
Owner so and why, never relay the plan as a clean one, and go on to step 3 item 1 with no second check.

When its `Findings:` holds a `Critical` or `Important` item, first show the Owner the check's `Report:` line and its
relay block word for word, so the Owner sees every fault before the plan changes.

Then send every finding once, `Minor` ones too, as step 3 item 2 sends answers: step 2's inputs written out again,
`targets:` whole, `answers:` holding the findings, and `plan path:` the plan the `Plan:` line named.

In a run by groups, send the round as `groups.md` section 2 gives, and relay and ask as its section 1 item 3 gives.

For a plan you wrote, send it as `main-writer.md` section 3 gives.

Outside a run by groups, relay the amended reply as step 3 item 1 gives, and ask the Owner's own items of step 3
item 2 on that reply, so each is asked once.

When the check finds none of those, show the Owner its relay block with the plan as it stands, `Minor` findings
included, as step 3 item 1 gives.
