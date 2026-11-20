---
name: specstone-bootstrap-spec
description: Use when the spec docs of a Specstone project lag behind its format after `specstone migrate`, a new pack version, or an edited template, such as `specstone check` findings under `specs/`, `architecture_missing`, `code_uncovered`, a still-empty `TECH_STACK.md` draft, or another Specstone skill naming `specstone-bootstrap-spec`.
---

# Bring the spec docs up to the new format

This skill takes `check` findings under `specs/`, `architecture_missing`, `code_uncovered`, and those on PROJECT's
Tech stack and Naming canonicalization sections, which it moves; `specstone-bootstrap-prd` takes the rest. Follow
`specstone-expert-sdd` for every write.

## 1. Gate: the first call

```
specstone folder
specstone check --out "<folder>/reports/check.gate.<XXXXXX>.txt"
```

`<folder>` and `XXXXXX` are as `specstone-expert-sdd`'s project gate gives.

- **78, `project_not_found`:** tell the Owner `specstone migrate` moves the project to the new format, or they keep
  the old skills. Stop: run, read, and write nothing.
- **0 or 1:** go on. Never look for `.specstone/`.
- **Any other exit:** report the CLI's error and stop.

## 2. Hand off in batches

Dispatch only once no `specstone-bootstrap-prd` batch runs: this skill takes the PRD sections it leaves.

With a subagent, split this skill's findings in the gate file by doc path: one batch per feature folder, each
`architecture_missing` finding in its feature's batch, and one for the rest, `code_uncovered` included except a file
answered this run. A `retrim_due` finding joins its doc's feature folder batch, a trim batch. In the first round
the rest batch always runs and names each target's tech stack doc, which only it fills, by the procedure's step 6.
Later it runs only when findings it owns remain or a write-a-spec pick awaits.
Dispatch one `specstone-sdd-engineer` per batch as `../specstone-expert-sdd/references/dispatch.md` gives, with
`mode: bootstrap`, `procedure: bootstrap-spec`, `batch:` the batch's paths and each line handed to it, `check:` the
latest check file, never a `--repeats` one, with no doc write since, `picks:` step 3's write-a-spec picks for the
batch's files, and `report:` `<folder>/reports/sdd-engineer.bootstrap.<XXXXXX>.md`, a new name per batch; batches run
at once, a rest batch with `code_uncovered` after the feature batches. Work no step of the procedure
yourself while a dispatch can run.

**Code target** (two or more `targets:`): a batch's DocPaths give its code targets, the first listed for an old file
naming none; never ask the Owner.

An `item_over_limit`, or an FR's `item_count_out_of_range` on edge cases or `chars_over_limit` with no `retrim_due`,
joins its doc's batch, named in its `batch:`, only if the Owner named its kind for the run; else it waits for the
Owner.

The main session's procedure is `references/procedure.md`: with no subagent, over every
finding; after a failed dispatch, over its one batch.

## 3. After the reports

When you followed the procedure yourself, its report stands in for item 1; on no batch, its step 5.3 delete stands
in for item 4.

1. Show the Owner each agent's `Report:` line, then its relay block word for word, before your own notes. In a round
   with a trim batch, follow `../specstone-expert-sdd/references/trim-round.md` before item 2 and
   again before you stop.
2. Follow `specstone-expert-sdd`'s "Get the drafts approved", with `--no-audit`, or `--audit` per audit report in a
   round with a trim batch; ask the Owner to approve each proposal, then run its commands in run order
   (`../specstone-expert-sdd/references/size-fix.md`).
3. Ask the Owner each open question; send the answers to that batch's live agent, else to a new one. Ask once per
   batch, in one question, on every file under its `Uncovered:` but a helper: write a spec for it, or change or remove
   the code, which writes nothing. A write-a-spec pick needing a new story or FR goes to
   `specstone-brainstorming-sdd`; any other goes with its file as `picks:` to that batch's next-round agent,
   which writes the draft, reporting the file no more. An answered file is never reported or asked about
   again.
4. Once every batch of the round has reported, with no open question left, join their `specstone delete` lines into
   one command naming each path once, each still quoted, with each path `specstone-bootstrap-prd` left waiting on a
   file this round merged, and get the Owner's word on it per `specstone-expert-sdd`. On exit 64, dispatch again each
   batch whose file a listed referrer names, with those referrers.
5. Run `specstone check --out "<folder>/reports/check.bootstrap.<XXXXXX>.txt"` again and search its file. A finding this
   skill takes starts another round at step 2 unless it is tagged `(waits for the Owner)`, the last reports name it as
   clearing with no write, it is an answered `code_uncovered` file, which starts one only through a
   write-a-spec pick, it is a helper waiting on a draft, or it waits on `specstone-bootstrap-prd`. A
   `Citers outside:` or `Spec moves:` line either skill handed starts a round too when this skill takes its doc;
   else it waits on `specstone-bootstrap-prd`. With none left, go to item 6.
6. Once per run, after the last round and `specstone-bootstrap-prd`'s repeats batch, run
   `specstone check --repeats --out "<folder>/reports/check.bootstrap.<XXXXXX>.txt"`, then dispatch the repeats batch
   (`../specstone-expert-sdd/references/repeats.md`) as in step 2 with `batch: repeats` and each group with an item
   under `specs/`, if any; work items 1 and 2 on its report. A group it keeps stays listed and never starts a round.
   Then stop; first, name once each answered `code_uncovered` file the last `check` still lists, with what it waits on
   (code change, brainstorm, or its draft's approval), and, in a run that did not name `item_over_limit`,
   list under `Waits on the Owner:` each such finding no report's `Waits on the Owner:` line named.
