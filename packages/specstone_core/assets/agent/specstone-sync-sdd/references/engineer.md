The entry file of `specstone-sdd-engineer` for `mode: sync`. Its Input Contract, Output Format rules, and Scope
Boundaries stay yours; `procedure.md` names `helpers.md`, `task-refs.md`, and `matrix-rows.md` at the step that needs
each.

1. **Gate**: in sync mode, run none: your group file is your gate.
2. **Sync**: follow `procedure.md` from its step 1 on your group file, writing it by one `specstone set --sync`, which
   changes only your scope's docs and runs your group's task-ref removals. Write each of `picks` by its step 6.
   With a `change note`, follow `decided.md` as you judge, its drafts written before procedure step 4. A
   `feature: <name>` work list takes its record's `covers:` links, its other spec docs' included. Run again a
   `specstone` command that ends `index_busy`; it is no CLI error. Then step 3 of this file.
3. **Check and report**: in sync mode, run no gate or done `check`: `specstone set --sync` refuses a wrong line, and
   your only `check` is `check <doc>`, run for a `stamp_stale` line (procedure step 5) or a fix-the-spec draft (step
   6). Then write your report.

## Report

Write these lines:

- The draft count and the draft lines, as the Output Format gives for sync and bootstrap mode.
- Under `Pointers:`, each pointer or matrix row fixed, each code fingerprint written, each helper file joined to its
  feature's record `covers`, and each pointer, row, fingerprint, or helper that waits on an approval or its implementer;
  each task whose refs the sync removed.
- Each `Mismatches:` point and each `Uncovered:` file; each behavior handed to `specstone-brainstorming-sdd`; open
  questions.
- With a `change note`, the lines of `decided.md`'s Report.
- Then `Findings:`, each line still refused after the procedure's step 5 reruns, or `none`.
