`item_count_out_of_range` on an FR's edge cases you wrote, in author or sync mode: write each FR you touch by the edge
case lines of the saved `fr` guide. An FR still over its cap inside its story takes these steps:

1. Run one `specstone new fr --parent <story> --slug <slug>`.
2. Save one plan file by
   `specstone move --plan-out <fr> --out "<folder>/reports/sdd-engineer.<mode>.plan.<XXXXXX>.txt"`; set one
   `<fr>#<edge case ID> -> <new fr>` line per edge case past the cap; run one `specstone move --plan-file "<file>"`.
3. Fill the new FR's sections by `author.md` section 3, your `<mode>` in each file name it gives.
4. Check both FRs: in author mode, the later-write bare check of `author.md` section 5, whose newer file `Check:`
   names; in sync mode, one `specstone check <doc> --out "<folder>/reports/check.sync.<XXXXXX>.txt"` per FR.
5. The old and the new FR both join the drafts list of the one `specstone approve --dry-run --json` after your last
   write.

That plan file is no `Move:` line, since you applied it: name it under `Findings:` in author mode, and in the new FR's
draft line in sync mode, whose `Findings:` holds refused lines alone. An edge case that belongs in another story
or feature takes the split proposal of `../../specstone-expert-sdd/references/size-fix.md` and waits for the Owner's
ok.
