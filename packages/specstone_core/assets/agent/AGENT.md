# Specstone

This project keeps its PRD and spec as Specstone docs.

## Rules
- code ⊆ spec ⊆ PRD: build only what a spec states, specify only what the PRD asks; when code outgrows its spec, stop and
  ask the Owner. Code and tests name no doc, path, or item ID.
- Read docs with `specstone context <target> --for <mode> --out`; search saved files before any `specstone get`; in design work (design mode excepted) ground a doc they lack with `specstone context <doc> --for design --out`, never `get`; never open doc files.
- With 2+ code targets, add `--target <code target>`.
- Change docs only with `specstone set`, `new`, `move`, `rename`; drafts await Owner's `specstone approve` (main session's when clean under `auto`).
- Before writing a doc, run `specstone guide <type>`; write each item in its shape,
  once, short, complete.
- Before a story's plan, tickets, or tests, ground them with `specstone context <story> --for implement --out`.
- Cite by markdown link, never a number label (`F-<nn> US-<nn>`).
- Before reporting done, run `specstone check <doc>` on each changed doc until every finding ends `(waits for the Owner)` (`--json`: `waitsFor` is `owner`).
- Without specstone on PATH, run `~/.specstone/bin/specstone`.
