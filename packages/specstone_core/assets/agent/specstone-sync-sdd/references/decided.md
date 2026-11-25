The decided-line steps of a sync engineer given a `change note`, at a plan's last sync and its reruns. The note's
decided lines are its `D<n> (decided): <text>` decisions; the procedure's other steps stay as they are.

## 1. Find the decided work

- Read the change note's Decisions once; list each `(decided)` decision.
- A judged link whose work built from the docs does what a decided line states, no spec stating that behavior yet:
  decided work, with no Owner pick and no `Mismatches:` point.
- A `code_uncovered` file whose work does what a decided line states takes the same drafts, with no Owner pick.
- Work that departs from its decided line: one `Mismatches:` point per difference, naming the line's `D<n>`, what the
  line states, and what the work does, with nothing written for that behavior until the Owner's pick. A judged link's
  point is its `mismatch` line.
- A behavior no decided line states keeps the procedure's own route.

## 2. Find the readers

Before your first write, run the reader step of `../../specstone-brainstorming-sdd/references/author.md`
`## 2. Find the readers` once for each decided line you draft, on the line's terms, each reader on one `Readers:` line.

## 3. Draft

- Write each decided line's PRD and spec drafts from the line and the work built from the docs, with no Owner pick and
  by `specstone-expert-sdd`'s rules: `specstone set <doc>#<section key> --base <hash>` for a section, and
  `specstone new <type>` for a story or FR no doc holds yet, as a draft.
- Hand no decided behavior to `specstone-brainstorming-sdd`.
- Write the drafts before procedure step 4. Judge the link's line `match` against them; `specstone set --sync` lists it
  under `Waiting:` until their approval.
- A `code_uncovered` file you drafted: write no pointer to it, and list it under `Pointers:` as waiting on its drafts'
  approval.

## Report

Add these lines, each in the form `../../specstone-brainstorming-sdd/references/author-report.md` gives:

- One `Decision: D<n> -> <type>:<name>#<key>, …` line per decided line you draft, naming each section that took it.
- One `Not landed: D<n>: <why no draft took it>` line per decided line your group's work holds that no draft took.
- The `Readers:` lines of section 2.
