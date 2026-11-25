---
name: specstone-bootstrap-prd
description: Use when the PRD docs of a Specstone project lag behind its format after `specstone migrate`, a new pack version, or an edited template, such as when `specstone check` reports paths under `prds/` or `measurements/` (a missing or leftover section or field), or an old file for such a doc, or when another Specstone skill names `specstone-bootstrap-prd`.
---

# Bring the PRD docs up to the new format

This skill takes `check` findings under `prds/` or `measurements/`, and an `untyped_doc` on an old file whose
content goes into a `prds/` or `measurements/` doc, a `specs/` path included. A leftover goes by the doc that holds it.
A leftover on a PRD doc whose every `to` type lies outside `prd-core` goes to `specstone-bootstrap-spec`, as does an old
file whose finding's `to` lists such a type. So do other findings under `specs/`. Follow
`specstone-expert-sdd` for every write.

## 1. Gate: the first call

```
specstone folder
specstone check --out "<folder>/reports/check.gate.<XXXXXX>.txt"
```

`<folder>` and `XXXXXX` are as `specstone-expert-sdd`'s project gate gives.

- **78, `project_not_found`:** tell the Owner no Specstone project is found here; `specstone init` starts
  one. Stop: run, read, write nothing.
- **0 or 1:** go on, even from a subfolder. Never look for `.specstone/`. Search it for this skill's
  findings.
- **Any other exit:** report the CLI's error and stop.

## 2. Hand off in batches

With a subagent, split the gate file's findings this skill takes by doc path: one batch per feature folder, and one for
the rest. A `retrim_due` or `code_blocks_over_limit` finding joins its doc's feature folder batch, or the rest batch, a
trim batch. In the first round the rest batch always runs, even with no finding, and names the project, goal, glossary,
features, and gnfr docs, which only it fills, by the procedure's step 6. Later it runs only when findings it owns
remain. When it holds the `section_undeclared` on PROJECT's goals section, first ask the Owner as
`references/goal-move.md` gives, and send the answers with the batch. Dispatch one `specstone-sdd-engineer` per batch as
`../specstone-expert-sdd/references/dispatch.md` gives, with `mode: bootstrap`, `procedure: bootstrap-prd`, `batch:` the
batch's paths and each line handed to it, `check:` the latest check file, never a `--repeats` one, with no doc write
since, and `report:` `<folder>/reports/sdd-engineer.bootstrap.<XXXXXX>.md`, a new name per batch; batches may run at
once. Work no procedure step yourself while a dispatch can run.

**Code target** (two or more `targets:`): a finding's code target is its DocPath's, the first listed for an old file
naming none; never ask the Owner.

An `item_over_limit`, or an FR's `item_count_out_of_range` on edge cases or `chars_over_limit` with no `retrim_due`,
joins its doc's batch, named in its `batch:`, only if the Owner named its kind for the run; else it waits for the
Owner.

The main session's procedure is `references/procedure.md`: with no subagent, over every finding this skill takes;
after a failed dispatch, over that batch.

## 3. After the reports

When you followed the procedure yourself, its report stands in for item 1; on no batch, its step 5.3 delete stands
in for item 4.

1. Show the Owner each agent's `Report:` line, then its relay block word for word, before your own notes. In a round
   with a trim batch, follow `../specstone-expert-sdd/references/trim-round.md`: its audit and
   `../specstone-expert-sdd/references/fix-loop.md` before item 2, its handed lines in item 5, and its waits and sync
   before you stop.
2. Follow `../specstone-expert-sdd/references/approve.md`, with `--no-audit`, or `--audit` per audit report
   in a round with a trim batch; ask the Owner to approve each proposal, then run its commands in run order
   (`../specstone-expert-sdd/references/size-fix.md`).
3. Ask the Owner each open question; send each answer to that batch's live agent, else to a new one.
   Show the Owner, without asking, the question on a goal or entry its move kept in PROJECT, and count it settled
   for item 4.
4. Once every batch has reported, with no open question left, join their `specstone delete` lines into
   one command naming each path once, each still quoted. Leave out each path under `specs/` this round did not merge
   and each path an untyped referrer under `specs/` names: they wait for `specstone-bootstrap-spec`'s delete. Then
   get the Owner's word on it per `specstone-expert-sdd`. On exit 64, dispatch again each batch whose file a listed
   referrer names, with those referrers.
5. Run `specstone check --out "<folder>/reports/check.bootstrap.<XXXXXX>.txt"` again and search it. A finding this
   skill takes starts another round at step 2 unless it is tagged `(waits for the Owner)`, the last reports name it as
   one that clears with no write, it is the `section_undeclared` on PROJECT's goals or glossary section after a
   move kept an entry there, or it waits on `specstone-bootstrap-spec`, such as a finding on a path item 4 left out.
   A handed `Citers outside:` line starts a round too when this skill takes its doc, and waits on
   `specstone-bootstrap-spec` when it names a doc under `specs/`. No later batch holds that finding, and no question asks a
   kept goal's horizon again. With none left, go to item 6.
6. Once per run, after the last round, run
   `specstone check --repeats --out "<folder>/reports/check.bootstrap.<XXXXXX>.txt"`, then dispatch the repeats batch
   (`../specstone-expert-sdd/references/repeats.md`) as in step 2 with `batch: repeats` and each group with an item
   under `prds/` or `measurements/`, if any; work items 1 and 2 on its report. A group it keeps stays listed, starts no
   round. Then stop; first, in a run that did not name `item_over_limit`, list under `Waits on the Owner:` each
   `item_over_limit` finding no report's `Waits on the Owner:` line named.
