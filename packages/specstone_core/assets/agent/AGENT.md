# Specstone

This project keeps its PRD and spec as Specstone docs.

## Rules
- code ⊆ spec ⊆ PRD: build only what a spec states, specify only what the PRD asks for; when code needs
  something no spec states, stop and ask the Owner. Code and tests name no doc, path, or item ID.
- Read docs with `specstone context <target> --for <mode> --out`; search its saved file before any `specstone get`; never open doc files directly.
- With 2+ code targets, add `--target <code target>`.
- Change docs only with `specstone set`, `new`, `move`, or `rename`; agent drafts stay drafts until the Owner runs `specstone approve`.
- Before writing a doc, read its type's guide with `specstone guide <type>`; write each item in its shape,
  once, short, complete.
- Before writing a plan, tickets, or tests for a story, ground them with `specstone context <story> --for implement --out`.
- Cite a doc by a markdown link, never by a number label (`F-<nn> US-<nn>`).
- Before reporting work done, run `specstone check <doc>` on each doc you changed until every finding ends `(waits for the Owner)` (`--json`: `waitsFor` is `owner`).
- Without specstone on PATH, run `~/.specstone/bin/specstone`.
