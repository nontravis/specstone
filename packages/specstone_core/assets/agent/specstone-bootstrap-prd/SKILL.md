---
name: specstone-bootstrap-prd
description: Use when the PRD docs of a Specstone project lag behind its format after `specstone migrate`, a new pack version, or an edited template, such as when `specstone check` reports paths under `prds/` or `measurements/` (a missing or leftover section or field, an untyped old file), or when another Specstone skill names `specstone-bootstrap-prd`.
---

# Bring the PRD docs up to the new format

This skill takes `check` findings under `prds/` or `measurements/`. Findings under `specs/`,
`architecture_missing`, `code_uncovered`, and those on PROJECT's Tech stack and Naming canonicalization sections go
to `specstone-bootstrap-spec`. Follow the `specstone-expert-sdd` skill for every write: each leaves a draft, a pointer
write (`implements`, `covers`) excepted.

## 1. Gate: the first call

```
specstone folder
specstone check --out "<folder>/reports/check.gate.<XXXXXX>.txt"
```

`<folder>` is the path `folder` prints, `XXXXXX` six `a-z0-9` characters, picked again while that file exists.

- **78, `project_not_found`:** tell the Owner the project stays on the old format until `specstone migrate` moves
  it. Stop: run, read, and write nothing more.
- **0 or 1:** go on, even from a subfolder. Never look for `.specstone/` yourself. Search the file for this skill's
  findings.
- **Any other exit:** report the CLI's error and stop.

## 2. Hand off in batches

With a subagent, split the gate file's findings this skill takes by doc path: one batch per feature folder, and one for
the rest. In the first round the rest batch always runs, even with no finding, and names the project, goal, glossary,
features, and gnfr docs, the skeletons the procedure's step 6 fills; no feature batch fills them. In a later round it
runs only when findings it owns remain. When it holds the `section_undeclared` on PROJECT's goals section, first ask the
Owner each goal's horizon, long-, mid-, or short-term, one question per goal showing its `**By:**`, and send the
answers with the batch; its glossary section asks the Owner nothing. Dispatch one `specstone-sdd-engineer` per batch as
`../specstone-expert-sdd/references/dispatch.md` gives, with `mode: bootstrap`, `procedure: bootstrap-prd`, `batch:`
the batch's paths, `check:` the latest check file, and `report:`
`<folder>/reports/sdd-engineer.bootstrap.<XXXXXX>.md`, a new name per batch; batches may run at once. Send no doc text, and work no step of the procedure yourself while a dispatch can run. Take
`<folder>` and `XXXXXX` as the gate does.

**Code target** (two or more `targets:`): a finding's code target is its DocPath's, and an
old file whose path names none merges into the first listed one, so a batch never asks the Owner.

An `item_over_limit` finding joins its doc's batch only when the Owner named `item_over_limit` when starting the run;
that batch's `batch:` then names `item_over_limit`, and its agent reshapes the item. In any other
run the finding waits for the Owner.

The procedure for the main session is `references/procedure.md` beside this file: with no subagent at all, over every
finding this skill takes; after a failed dispatch, over that dispatch's one batch.

## 3. After the reports

When you followed the procedure yourself, its report stands in for item 1; on no batch, its step 5.3 delete stands
in for item 4.

1. Show the Owner each agent's `Report:` line, then its relay block word for word, before your own notes.
2. Get each draft approved through `specstone-expert-sdd`'s Owner confirmation; ask the Owner to approve each
   proposal, then run each of its commands in run order
   (`../specstone-expert-sdd/references/size-fix.md`).
3. Ask the Owner each open question; send the answers to that batch's agent while it is live, else dispatch a new one
   for the batch with them. Show the Owner the question on a goal that a goal move kept in PROJECT, or an entry that a
   glossary move kept there, without asking it, and count it settled for item 4.
4. Once every batch of the round has reported, with no open question left, join their `specstone delete` lines into
   one command naming each path once, each still quoted. Leave out each path under `specs/` and each path an untyped
   referrer under `specs/` names: they wait for `specstone-bootstrap-spec`'s delete. Then get the Owner's word on the
   command per `specstone-expert-sdd`. On exit 64, dispatch again each batch whose file a listed referrer names, with
   those referrers.
5. Run `specstone check --out "<folder>/reports/check.bootstrap.<XXXXXX>.txt"` again and search its file. A finding this
   skill takes starts another round at step 2 unless it is tagged `(waits for the Owner)`, the last reports name it as
   one that clears with no write, it is the `section_undeclared` on PROJECT's goals section after a goal move kept a
   goal there, the one on its glossary section after a glossary move kept an entry there, or it waits on
   `specstone-bootstrap-spec`, such as a finding on a path item 4 left out for it. For the rest of the run, no batch
   holds that goals finding, no batch holds that glossary finding, and no question, item 3's included, asks a kept
   goal's horizon again. With none left, go to item 6.
6. Once per run, after the last round, run
   `specstone check --repeats --out "<folder>/reports/check.bootstrap.<XXXXXX>.txt"`, then dispatch the repeats batch
   (`../specstone-expert-sdd/references/repeats.md`) as in step 2 with `batch: repeats` and each group with an item
   under `prds/` or `measurements/`, if any; work items 1 and 2 on its report. A group it keeps stays listed and never
   starts a round. Then stop; first, in a run that did not name `item_over_limit`, list under `Waits on the Owner:` each
   `item_over_limit` finding no report's `Waits on the Owner:` line named.
