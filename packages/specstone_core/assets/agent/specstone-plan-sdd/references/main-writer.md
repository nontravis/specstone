# Write the plan in main

Read this at step 2, before any dispatch. The main session writes the plan itself only when all three conditions of
section 1 hold; section 2 gives the dispatch for every other case. A host with no subagent skips the test, as step 2 of
`SKILL.md` gives.

## 1. The test

Each condition is a fact read from this session's history or from CLI output, never from a doc file.

1. This session ran a `specstone context … --out` call naming every target (each story of an approved drafts list,
   or, for a Build-first change sent with no targets, each story its decided lines change), and has run no `set`, `new`,
   `move`, `rename`, or writer dispatch since.
2. The Ground call, `specstone context … --for implement --out --groups`, you run as the agent file's Ground source 1
   and Workflow step 2 give, exits 0 and prints no `==> group` line.
3. No target's record entry and no `covers:` entry in that bundle names a code path.

Check the conditions in order: condition 2's call runs only when condition 1 holds, and condition 3 reads that call's
bundle. A failing condition 1 runs no `context` call. Your condition 2 call stands as the agent file's Ground source 1
call, so a passing test runs no second one.

A non-zero exit, or a Build-first change whose decided lines change no story to name, fails condition 2.

When all three hold, follow `../../../agents/specstone-plan-engineer.md` under the same inputs and `report:` path a
dispatch would get, writing its one plan file and its report. When following it would open a code file, stop and
dispatch as section 2 gives.

## 2. A failed condition

When a condition fails, dispatch `specstone-plan-engineer` as step 2 of `SKILL.md` gives, and let it run its own Ground
call.

While a dispatch can run, read no more of the bundle you saved than its `==> ` headers and its implementation lines.

## 3. Answer rounds

When you wrote the plan, the relay, the answer rounds, and the run question go as for a dispatched plan, and the plan
takes the fresh check of `fresh-read.md` before the Owner sees it.

The agent that answered the last round takes the next one.

A round needs a code read when an answer names a code path, or when that round's Ground call fails condition 2 or 3.

When an answer round needs no code read, you answer it, unless the agent that
answered the last round is live.

You follow the agent file again under step 2's inputs plus `answers:` and `plan path:` as step 3 item 2 gives, then
relay its report as step 3 item 3 gives.

When an answer round needs a code read, a fresh `specstone-plan-engineer` takes it by the same send.
