# Specstone

PRD and spec are Specstone docs.

## Rules
- code ⊆ spec ⊆ PRD over observable behavior: specify each behavior users, callers, or features see, only as the
  PRD asks; when code adds or changes one, ask the Owner. Code and tests name no doc, path, or item ID.
- Read docs with `specstone context <target> --for <mode> --out`; search saved files before any `specstone get`; in design work ground a doc they lack with `specstone context <doc> --for design --out`, never `get`; never open doc files.
- With 2+ code targets, add `--target <code target>` (not with `context --code`).
- Change docs only with `specstone set`, `new`, `move`, `rename`; drafts await Owner's `specstone approve` (main session's when clean under `auto`).
- Before writing a doc, have `specstone guide <type>` or this run's saved guide; write items in its shape,
  once, short, complete.
- Before a story's plan, tickets, or tests, run `specstone context <story> --for implement --out`; before editing a covered skill/agent file, run `specstone context --code <path> --for implement --out`.
- Cite by markdown link, never a number label (`F-<nn> US-<nn>`).
- Before reporting done, run `specstone check <doc> --out <folder>/reports/check.done.<XXXXXX>.txt` per changed doc until every finding ends `(waits for the Owner)` (`--json`: `waitsFor` `owner`).
- Off PATH, run `~/.specstone/bin/specstone`.
