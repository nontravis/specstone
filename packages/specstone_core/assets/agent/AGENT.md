# Specstone

PRD and spec are Specstone docs.

## Rules
- Project vision sets product direction: rank choices by vision served; for work serving none, against one, or in PROJECT's Out-of-scope, ask Owner, or flag and go on if asked.
- PRD owns product behavior; each spec type owns the facts its guide lists. Work built from the docs (code, tests, content) that adds or changes either: ask the Owner. It names no doc, path, or item ID. A plan task citing its okayed decided line builds unasked.
- Before editing, tell Owner `Class: <class> — <why>`, no wait; route by `specstone-brainstorming-sdd`'s class test: Doc-only, `specstone-update-sdd`; Restore or Internal, edit work built from the docs, no doc step, then `specstone-sync-sdd`; observable behavior, `specstone-brainstorming-sdd` (Build-first or Docs-first); Owner-named class wins.
- Read docs with `specstone context <target> --for <mode> --out`; search saved files before any `specstone get`; in design work ground a doc they lack with `specstone context <doc> --for design --out`, never `get`; never open doc files.
- With 2+ code targets, add `--target <code target>` (not with `context --code`).
- Change docs only with `specstone set`, `new`, `move`, `rename`; drafts await Owner's `specstone approve` (main session's when clean under `auto`).
- Before writing a doc, have `specstone guide <type>` or this run's saved guide; write items in its shape, once, short, complete: only what a plan needs that built work cannot show (a decision and why, a contract others rely on, a constraint); code detail goes in the plan.
- Before a story's plan, tickets, or tests, run `specstone context <story> --for implement --out`; before editing a file a doc's `covers:` names outside a grounded story, run `specstone context --code <path> --for implement --out`.
- Cite by markdown link, never a number label (`F-<nn> US-<nn>`).
- Before reporting done, run `specstone check <doc> --out <folder>/reports/check.done.<XXXXXX>.txt` per changed doc until every finding ends `(waits for the Owner)` (`--json`: `waitsFor` `owner`).
- Off PATH, run `~/.specstone/bin/specstone`.
