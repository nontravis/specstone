---
name: bootstrap-spec
description: Use when the spec docs of a Specstone project lag behind its format after `specstone migrate`, a new pack version, or an edited template, such as `specstone check` findings under `specs/`, `architecture_missing`, `code_uncovered`, a still-empty `TECH_STACK.md` draft, or another `specstone:` skill naming `specstone:bootstrap-spec`.
---

# Bring the spec docs up to the new format

This skill takes `specstone check` findings under `specs/`, plus `architecture_missing` and `code_uncovered`.
Findings under `prds/` go to `specstone:bootstrap-prd`, except the PRD section step 6 moves. Follow
`specstone:expert-sdd` for every write: each leaves a draft, a pointer write (`implements`, `covers`) excepted.

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
PROJECT's Tech stack, that `bootstrap-prd` leaves for it.

With the `Agent` tool, split the gate's findings this skill takes by doc path: one batch per feature folder, and one
for the rest, the project-level docs, `code_uncovered`, and `architecture_missing` included. Dispatch one
`specstone:sdd-engineer` per batch with `mode: bootstrap`, `procedure: bootstrap-spec`, and `batch:` the batch's
paths; batches may run at once. Send no doc text, and work no step of the procedure yourself. Without the tool, or
when a dispatch fails, read `${CLAUDE_PLUGIN_ROOT}/skills/bootstrap-spec/references/procedure.md` and follow it.

## 3. After the reports

When you followed the procedure yourself, its report stands in for item 1.

1. Relay each `sdd-engineer` report to the Owner whole.
2. Get each draft approved through `specstone:expert-sdd`'s Owner confirmation.
3. Ask the Owner each open question; send the answers to that batch's agent while it is live, else dispatch a new one
   for the batch with them.
4. Get the Owner's word on each `specstone delete` line per `specstone:expert-sdd`, then run it.
5. Run `specstone check` again; findings this skill takes start another round at step 2.
