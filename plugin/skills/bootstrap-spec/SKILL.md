---
name: bootstrap-spec
description: Use when the spec docs of a Specstone project lag behind its format after `specstone migrate`, a new pack version, or an edited template, such as `specstone check` findings under `specs/`, `architecture_missing`, `code_uncovered`, a still-empty `TECH_STACK.md` draft, or another `specstone:` skill naming `specstone:bootstrap-spec`.
---

# Bring the spec docs up to the new format

This skill takes `specstone check` findings under `specs/`, plus `architecture_missing` and `code_uncovered`.
Findings under `prds/` go to `specstone:bootstrap-prd`, except those on PROJECT's Tech stack and Naming
canonicalization sections, which this skill moves.
Follow `specstone:expert-sdd` for every write: each leaves a draft, a pointer write (`implements`, `covers`)
excepted.

## 1. Gate: the first call

```
specstone check
```

- **78, `project_not_found`:** tell the Owner `specstone migrate` moves the project to the new format, or they keep
  the old skills. Stop: run, read, and write nothing more.
- **0 or 1:** go on, even from a subfolder. Never look for `.specstone/` yourself.
- **Any other exit:** report the CLI's error and stop.

## 2. Hand off in batches

Dispatch only once no `specstone:bootstrap-prd` batch is still running: this skill takes PRD sections, such as
PROJECT's Tech stack, that `specstone:bootstrap-prd` leaves for it.

With the `Agent` tool, split the gate's findings this skill takes by doc path: one batch per feature folder, each
`architecture_missing` finding in its feature's batch, and one for the rest, `code_uncovered` included except a file
the Owner answered in this run. In the first round the rest batch always runs, even with no finding, and names each
target's tech stack doc, the doc the procedure's step 6 fills; no feature batch fills it. In a later round it runs only
when findings it owns remain or a write-a-spec pick awaits. Dispatch one `specstone:sdd-engineer` per batch with
`mode: bootstrap`, `procedure: bootstrap-spec`, `batch:` the batch's paths, `picks:` each write-a-spec pick of step 3
for the batch's files, and `report:`, one file `mktemp` makes per batch outside the repository; batches may run at
once. Send no doc text, and work no step of the procedure yourself.

**Code target** (two or more `targets:`): a finding's code target is its DocPath's, and an
old file whose path names none merges into the first listed one, so a batch never asks the Owner.

An `item_over_limit` finding joins its doc's batch only when the Owner named `item_over_limit` when starting the run;
that batch's `batch:` then names `item_over_limit`, and its agent reshapes the item per `size-fix.md`. In any other
run the finding waits for the Owner.

Without the tool, or when a dispatch fails, read `references/procedure.md` beside this file
(`${CLAUDE_PLUGIN_ROOT}/skills/bootstrap-spec/references/procedure.md`) and follow it yourself: without the tool,
over every finding this skill takes; after a failed dispatch, for each batch no agent took.

## 3. After the reports

When you followed the procedure yourself, its report stands in for item 1; on no batch, its step 5.3 delete stands
in for item 4.

1. Show the Owner each agent's `Report:` line, then its relay block word for word, before your own notes.
2. Get each draft approved through `specstone:expert-sdd`'s Owner confirmation. Ask the Owner to approve each split
   proposal; on ok, run its commands yourself, in run order
   (`${CLAUDE_PLUGIN_ROOT}/skills/expert-sdd/references/size-fix.md`).
3. Ask the Owner each open question; send the answers to that batch's agent while it is live, else dispatch a new one
   for the batch with them. Ask once per batch, every file under its `Uncovered:` in one question: write a spec for it,
   or change or remove the code. Change or remove writes nothing. A write-a-spec pick whose behavior needs a new story
   or FR goes to `specstone:brainstorming-sdd`; any other goes with its file to the next round's agent of that batch
   as `picks:`, which writes the draft and does not report the file. Keep each answered file, whatever the pick, for
   the run: no later batch reports it and the Owner is not asked again.
4. Once every batch of the round has reported, with no open question left, join their `specstone delete` lines into
   one command naming each path once, each still quoted, with each path `specstone:bootstrap-prd` left waiting on a
   file this round merged, and get the Owner's word on it per `specstone:expert-sdd`. On exit 64, dispatch again each
   batch whose file a listed referrer names, with those referrers.
5. Run `specstone check` again. A finding this skill takes starts another round at step 2 unless it is tagged
   `(waits for the Owner)`, the last reports name it as one that clears with no write, it is an answered
   `code_uncovered` file, which starts a round only through a write-a-spec pick, or it waits on
   `specstone:bootstrap-prd`, such as a finding on a file that a `prds/` untyped doc it left still names. With none
   left, stop; first, name once each answered `code_uncovered` file the last `check` still lists, with what it waits
   on: the code change, the brainstorm, or the approval of its draft, and, in a run that did not name
   `item_over_limit`, list under `Waits on the Owner:` each `item_over_limit` finding no report's
   `Waits on the Owner:` line named.
