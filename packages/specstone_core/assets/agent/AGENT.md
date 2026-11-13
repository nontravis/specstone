# Specstone

This project keeps its PRD and spec as Specstone docs.

## Rules
- code ⊆ spec ⊆ PRD: build only what a spec states, and specify only what the PRD asks for. When code needs
  something no spec states, stop and ask the Owner.
- Read docs with `specstone context <target> --for <mode>` or `specstone get <name>`; never open doc files directly.
- With 2+ code targets, add `--target <code target>`.
- Change docs only with `specstone set`, `new`, `move`, or `rename`. What an agent writes stays a draft until the
  Owner runs `specstone approve`.
- Before writing a doc, read its type's guide with `specstone guide <type>`; write each item in the shape it gives,
  each thing said once, short enough for one pass, nothing left out.
- Before writing a plan, tickets, or tests for a story, ground them with `specstone context <story> --for implement`.
- Cite a doc by its name (`<feature>/<story>`), never by a number label (`F-<nn> US-<nn>`).
- Before reporting work done, run `specstone check <doc>` on each doc you changed until every finding ends `(waits for the Owner)` (`--json`: `waitsFor` is `owner`).
- If `specstone` is not on PATH, run `~/.specstone/bin/specstone`.
