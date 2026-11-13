---
name: bootstrap-prd
description: Use when the PRD docs of a Specstone project lag behind its format after `specstone migrate`, a new pack version, or an edited template, such as when `specstone check` reports paths under `prds/` (a missing or leftover section or field, an untyped old file), or when another `specstone:` skill names `specstone:bootstrap-prd`.
---

# Bring the PRD docs up to the new format

This skill takes `specstone check` findings under `prds/`. Findings under `specs/`, `architecture_missing`,
`code_uncovered`, and those on PROJECT's Tech stack and Naming canonicalization sections go to
`specstone:bootstrap-spec`. Follow `specstone:expert-sdd` for every write: each leaves a draft, a pointer write
(`implements`, `covers`) excepted.

## 1. Gate: the first call

```
specstone check
```

- **78, `project_not_found`:** tell the Owner the project stays on the old format until `specstone migrate` moves
  it. Stop: run, read, and write nothing more.
- **0 or 1:** go on, even from a subfolder. Never look for `.specstone/` yourself.
- **Any other exit:** report the CLI's error and stop.

## 2. Hand off in batches

With the `Agent` tool, split the gate's findings this skill takes by doc path: one batch per feature folder, and one for
the rest. In the first round the rest batch always runs, even with no finding, and names `project:project`,
`features:features`, and `gnfr:gnfr`, the skeletons the procedure's step 6 fills; no feature batch fills them. In a
later round it runs only when findings it owns remain. Dispatch one `specstone:sdd-engineer` per batch with
`mode: bootstrap`, `procedure: bootstrap-prd`, `batch:` the batch's paths, and `report:`,
one file `mktemp` makes per batch outside the repository; batches may run at once. Send no doc text, and work no step of
the procedure yourself.

**Code target** (two or more `targets:`, `domain:agent_plugin` INV-25): a finding's code target is its DocPath's, and an
old file whose path names none merges into the first listed one, so a batch never asks the Owner.

An `item_over_limit` finding joins its doc's batch only when the Owner named `item_over_limit` when starting the run;
that batch's `batch:` then names `item_over_limit`, and its agent reshapes the item per `size-fix.md`. In any other
run the finding waits for the Owner.

Without the tool, or when a dispatch fails, read `references/procedure.md` beside this file
(`${CLAUDE_PLUGIN_ROOT}/skills/bootstrap-prd/references/procedure.md`) and follow it yourself: without the tool,
over every finding this skill takes; after a failed dispatch, for each batch no agent took.

## 3. After the reports

When you followed the procedure yourself, its report stands in for item 1; on no batch, its step 5.3 delete stands
in for item 4.

1. Show the Owner each agent's `Report:` line, then its relay block word for word, before your own notes.
2. Get each draft approved through `specstone:expert-sdd`'s Owner confirmation. Ask the Owner to approve each split
   proposal; on ok, run its commands yourself, in run order
   (`${CLAUDE_PLUGIN_ROOT}/skills/expert-sdd/references/size-fix.md`).
3. Ask the Owner each open question; send the answers to that batch's agent while it is live, else dispatch a new one
   for the batch with them.
4. Once every batch of the round has reported, with no open question left, join their `specstone delete` lines into
   one command naming each path once, each still quoted. Leave out each path under `specs/` and each path an untyped
   referrer under `specs/` names: they wait for `specstone:bootstrap-spec`'s delete. Then get the Owner's word on the
   command per `specstone:expert-sdd`. On exit 64, dispatch again each batch whose file a listed referrer names, with
   those referrers.
5. Run `specstone check` again. A finding this skill takes starts another round at step 2 unless it is tagged
   `(waits for the Owner)`, the last reports name it as one that clears with no write, or it waits on
   `specstone:bootstrap-spec`, such as a finding on a path item 4 left out for it. With none left, stop; first, in a
   run that did not name `item_over_limit`, list under `Waits on the Owner:` each `item_over_limit` finding no
   report's `Waits on the Owner:` line named.
