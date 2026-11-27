The decided-line steps of a sync run given a `change note`, at a plan's last sync and its reruns. The note's decided
lines are its `D<n> (decided): <text>` decisions. One decided engineer drafts every one; each group engineer only
judges its links against them. The procedure's other steps stay as they are.

## 1. Judge against the decided lines

For a group engineer with a `change note`.

- Read the change note's Decisions once.
- A judged link whose work built from the docs does what a decided line states, no spec stating that behavior yet:
  `match`, with no Owner pick and no `Mismatches:` point. Its line waits on the decided engineer's drafts, which
  `set --sync` lists under `Waiting:`.
- Work that departs from a line: one `Mismatches:` point per difference, naming the line's `D<n>`, what the line
  states, and what the work does, with nothing written for that behavior until the Owner's pick. A judged link's point
  is its `mismatch` line.
- A behavior no decided line states keeps the procedure's own route.
- Write no decided draft and no decided report line; the decided engineer owns both.

## Decided-only run

A brief with `decided` and no group file; it runs in place of `procedure.md`. It is the decided engineer's whole run,
sent once per sync run before the group engineers.

- Draft each `decided` id's decision from its decided line alone; no judged link, work list, or Owner pick. Read code
  only where a doc's own link names it.
- Run the reader step of `../../specstone-brainstorming-sdd/references/author.md` `## 2. Find the readers` once for
  each id, across the whole project with no scope narrowing, before your first write; each reader on one `Readers:`
  line.
- Ground each doc a decided line or a reader reaches: one `specstone context <doc> … --for design --out` per
  `specstone-read-sdd`, before your first write, so each write has its `--base` hash.
- Write each id's PRD and spec drafts from the line, by `specstone-expert-sdd`'s rules:
  `specstone set <doc>#<section key> --base <hash>` for a section, and `specstone new <type>` for a story or FR no doc
  holds yet, as a draft.
- Hand no decided behavior to `specstone-brainstorming-sdd`.
- A line an approved section already carries gets a `Decision:` line naming that section and no draft. A line the
  decided line is too thin to draft gets a `Not landed:` line.
- Write no pointer, record line, or fingerprint, and run no `context --for sync`.

## Report

The decided engineer's lines only, each in the form
`../../specstone-brainstorming-sdd/references/author-report.md` gives:

- One `Decision: D<n> -> <type>:<name>#<key>, …` line per id a draft took or an approved section carries, naming each
  section.
- One `Not landed: D<n>: <missing fact>` line per id no draft took and no section carries.
- The `Readers:` lines of the reader step.
