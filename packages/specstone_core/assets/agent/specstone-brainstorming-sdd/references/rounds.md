## 1. Run the writers' deletes and moves

After the writers' reports and before the builder check:

- **Dry runs**: give each `Delete:` line, each `Move:` plan file, and each `Rename:` line one `--dry-run` first.
- **Refused delete**: a delete dry run refused with `doc_referenced` first sends its citers to the writers, each citer
  to the writer of its group. A citer outside every group goes to the one writer when one took the change, else to the
  cross-group writer. Send them as the rounds 1 to 3 resume of `../../specstone-expert-sdd/references/fix-loop.md`
  gives, outside its round count and with no re-review, since the builder check follows. After the citers' round, run
  the refused delete's dry run again; its plan is the one shown and run.
- **Moves**: apply each `Move:` plan file with one `specstone move --plan-file "<file>"`, and run each `Rename:` line;
  each new name a command prints replaces the old one in the drafts list.
- **Deletes**: show each delete's plan, then run the delete with `--yes --plan <hash>` after the Owner's ok, per
  `specstone-expert-sdd`.
- The builder check runs only after each delete succeeds.

## 2. Sort the builder check and ask once

Read the `Findings:` lines of the fresh `specstone-sdd-auditor`'s builder check (`Guess`, `Contradiction`,
`Stale reader`, `Not carried`, `Misplaced`) and each writer's `Open questions:` lines and split proposal. Sort each
check question into one pile:

- **answered**: the change note or the docs answer it, and it enters the fix loop.
- **minor**: you settle it, listed under the change note's `Calls made`, and it enters the fix loop.
- **theirs**: only the Owner's answer changes what gets built.

A fix in a doc outside the drafts list adds that doc to the list, so it is approved with the others.

Ask the theirs pile and the writers' `Open questions:` lines in one message, most important first. A split proposal in
a writer's report rides in the same message.

- A builder check reading `nothing important left`: only the writers' open questions go to the Owner, when there are
  any.
- Write the Owner's answers into the change note. Then the answered and minor items and the Owner's answers enter
  `../../specstone-expert-sdd/references/fix-loop.md`, which hands the drafts to the approval step once it ends.
- After the Owner's ok on a split proposal, apply its plan file with one `specstone move --plan-file "<file>"`, then
  dispatch a fresh writer with the same inputs bar `bundles`, `report:` the proposing writer's file, to fill the new
  FRs, with no resume and no check after.
  Each new FR joins the drafts list by that writer's report, so it is approved with the others.

## 4. Take an Owner change after the check

An Owner change asked for at the approval ask or in an answer:

- A change that needs a new state, input, output, edge case, error, or reader of a rule adds behavior: run the reader
  step of `author.md` section 2 for its terms before the edit.
- A change that only words or corrects text takes no reader step.
- A change given in an answer to the theirs pile goes into the change note and enters
  `../../specstone-expert-sdd/references/fix-loop.md` by section 2, and its writer writes it.
- A change at the approval ask is yours: edit each draft it reaches through `specstone set`, and the change note at
  each place the change supersedes. Then return to the approval ask with no new check and no amend number.
- Under the Owner's `auto` mode, an Owner change at the approval ask takes no re-check and no re-review. It comes after
  the second `--auto` call, and a re-review would take a third call past the cap of 2. The edited draft goes back to
  Owner confirmation, which shows the Owner the change.
