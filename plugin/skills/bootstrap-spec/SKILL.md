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
`architecture_missing` finding in its feature's batch, and one for the rest, `code_uncovered` included. In the first
round the rest batch always runs, even with no finding, and names `tech_stack:tech_stack`, the doc the procedure's step
6 fills; no feature batch fills it. In a later round it runs only when findings it owns remain. Dispatch one
`specstone:sdd-engineer` per batch with `mode: bootstrap`, `procedure: bootstrap-spec`, `batch:` the batch's paths, and
`report:`, one file `mktemp` makes per batch outside the repository; batches may run at once. Send no doc text, and work
no step of the procedure yourself.

Without the tool, or when a dispatch fails, read `references/procedure.md` beside this file
(`${CLAUDE_PLUGIN_ROOT}/skills/bootstrap-spec/references/procedure.md`) and follow it yourself: without the tool,
over every finding this skill takes; after a failed dispatch, for each batch no agent took.

## 3. After the reports

When you followed the procedure yourself, its report stands in for item 1; on no batch, its step 5.3 delete stands
in for item 4.

1. Show the Owner each agent's `Report:` line, then its relay block word for word, before your own notes.
2. Get each draft approved through `specstone:expert-sdd`'s Owner confirmation.
3. Ask the Owner each open question; send the answers to that batch's agent while it is live, else dispatch a new one
   for the batch with them.
4. Once every batch of the round has reported, with no open question left, join their `specstone delete` lines into
   one command naming each path once, each still quoted, with each path `specstone:bootstrap-prd` left waiting on a
   file this round merged, and get the Owner's word on it per `specstone:expert-sdd`. On exit 64, dispatch again each
   batch whose file a listed referrer names, with those referrers.
5. Run `specstone check` again. A finding this skill takes starts another round at step 2 unless the last reports
   name it as one that clears with no write or waits on the Owner, or it waits on `specstone:bootstrap-prd`, such as
   a finding on a file that a `prds/` untyped doc it left still names. With none left, stop.
