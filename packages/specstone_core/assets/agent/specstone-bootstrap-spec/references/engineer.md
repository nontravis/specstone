The entry file of `specstone-sdd-engineer` for `procedure: bootstrap-spec`. Its Input Contract, Output Format rules, and
Scope Boundaries stay yours; `procedure.md` names `merge-untyped.md` at the step that needs it.

1. **Gate**: Workflow step 1 of `specstone-sdd-engineer` ran it; in bootstrap mode with `check` passed it ran none:
   your `check` file is your gate. Start at step 2.
2. **Bootstrap**: follow `procedure.md` from its step 2 on `batch`'s lines of your gate file, its step 6 only for docs
   `batch` names, each write through `--base`; list other findings. Then step 3 of
   this file.
   - A `batch: repeats` follows `../../specstone-expert-sdd/references/repeats.md` in place of the procedure, then step
     3 of this file.
   - Trim each section a `retrim_due` or `code_blocks_over_limit` line names, and each FR
     `../../specstone-expert-sdd/references/size-fix.md` sends to a trim, and apply each handed `Citers outside:` line, by
     `../../specstone-expert-sdd/references/trim.md`, which writes each moved statement to the home its guide line names,
     in the same batch.
   - A fix round of `../../specstone-expert-sdd/references/fix-loop.md` fixes each open finding's gap in the doc it
     names, each write through `--base`, then step 3 of this file.
3. **Check and report**: after writing, run `specstone check --out "<folder>/reports/check.done.<XXXXXX>.txt"`; search
   its file and fix each finding your writes added, but leave each tagged `(waits for the Owner)`. Then write your
   report.

## Report

Write these lines:

- The draft count and the draft lines, as the Output Format gives for sync and bootstrap mode; proposals and waivers;
  split proposals, each with its move plan file path
  (`<folder>/reports/sdd-engineer.bootstrap.plan.<XXXXXX>.txt`), or why none applies.
- For a trim batch, each deleted, moved, and cut item with the guide line that decided it, each rewritten cite, and the
  `Citers outside:` line of `trim.md`'s report.
- For an FR whose trim left a gap in its edge case numbers, a keep plan file in the run's reports
  folder, `sdd-engineer.bootstrap.plan.<XXXXXX>.txt`, written after the trim by
  `specstone move --plan-out <fr> --out "<folder>/reports/sdd-engineer.bootstrap.plan.<XXXXXX>.txt"`. The main
  session applies it with one `specstone move --plan-file "<file>"` and no Owner ok.
- Open questions; one
  `specstone delete …` line; each repeat group kept.
- Findings outside `batch`, and each untyped referrer outside it with the file it names; `Waits on the Owner:`, each
  `item_over_limit` finding on a `batch` path when `batch` does not name `item_over_limit`.
- Then `Findings:`, each finding left in `batch` or added by your writes, or `none`.
- A fix round appends its `## Round <n>` part in the shape the engineer's Output Format gives a fix round, its
  `Check:` line naming step 3's file.
