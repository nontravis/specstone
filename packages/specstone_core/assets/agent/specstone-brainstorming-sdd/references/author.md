Ask the Owner nothing; list gaps in the report.

In a fix round, run section 1's `--target` rule and its guide save, the save only without a saved guide for the types
of the findings and their readers; section 2 for terms a fix changes alone; section 3 for the findings' sections and
their readers alone; then sections 4 to 6.

## 1. Read

- Read the change note whole; list each decision, `D<n>`. A point it leaves open that a draft must state goes under
  `Open questions:`; no doc states a guess at it.
- Ground on `bundles`, read by each read plan line; absent, run one `specstone context <docs> --for design --out`
  naming each doc of your share, else each Reach doc.
- With two or more `targets:`, a per-target doc's `new`, `get`, and `set` take the `--target <name>` the Reach list
  names beside it, or an existing doc's DocPath.
- Before your first write, save `specstone guide <types> --out "<folder>/reports/guide.<XXXXXX>.txt"` and the same
  call with `--json` to `guide.<XXXXXX>.json`, `<types>` every type you write. Your gate's `check` file is the check
  before your first write; run no second.

## 2. Find the readers

Follow `author-readers.md` once per decision before your first write, each reader on one `Readers:` line.

## 3. Write

Make one name list, run one `specstone get <list> --out "<file>"` of it, then one `specstone set --batch "<file>"`,
`<file>` `<folder>/reports/sdd-engineer.author.batch.<XXXXXX>.txt`. Name each:

- section a decision or a `changed` or `linked` reader changes: `<type>:<name>#<key>`, its items naming what changes;
- rewrite of every section, or new doc: the bare name; a new doc reads nothing before `specstone new <type>`
  (`--parent`, `--slug`), piped in, parents first;
- anchor such as `#input--output`: its words joined by `_`, `input_output`;
- key with an item or note such as `#invariants INV-3`: the key alone;
- key no template defines: `section_not_found` refuses the call; rerun the one `get` with that doc's bare name in
  place of its section names, the key under `Findings:`;
- key the template defines and the doc lacks: its block holds the naming line alone; write the section there.

- Search a block (`==> ` header to the next) for an item's line form (`N. E05 —`, a row's first cell, a node ID;
  with a note, the part before the colon); read its lines alone by offset and limit. Read a block whole only for a
  bare name or a rewritten section.
- Write each doc block with one edit, all blocks in the one `set --batch`; a ` · unchanged` block counts as no draft.
  A section needed after edits began takes its own `get … --out` and its own `set --batch`.
- A reason (Rationale, "since", "so") is the change note's words; one it lacks goes under `Findings:`.
- Each decision of your share: a `Decision:` line naming each section that took it. One no doc took reads
  `NOT LANDED`, with a `Not landed:` line saying why; never force it into a doc or drop it. A `(plan)` decision, or
  one only docs outside your share take, gets neither line.
- A reader in a doc outside your share: an `Elsewhere:` line and no write. As a group writer, give a decision only
  docs outside your share take an `Elsewhere:` line too, its why naming the `D<n>`. The cross-group writer's pass, the
  merge step, closes or fixes each `Elsewhere:` line of `group reports` and writes a `Not landed:` line per decision
  not marked `(plan)` that no `Decision:` line of `group reports` names.
- A write that moves the upstream of a tracked link in a doc you did not write: confirm it per
  `specstone-expert-sdd`, that doc joining your drafts; else list it under `Findings:`.
- A change note that moves, renames, or removes a doc: run no `specstone move`, no `specstone rename`, and no
  `specstone delete`; list `Move:`, `Rename:`, `Delete:` lines for main.

## 4. Recover a refused batch

A refused `set --batch`: follow `author-recovery.md`, then rerun the batch.

## 5. Walk and check

- Walk each item you wrote against the rule lines of your saved `guide <type>` output: the description lines of the doc
  part, of each section the draft holds, and of each field in `Frontmatter:`. Templates and the `Banned
  words:`, `Required …`, `Optional …`, and `Limits:` lines are no rule lines. With several types, each type's rule
  lines take its `==> shared <==` lines too. A spec draft's rule lines also take the pack's `spec_scope` and
  `code_detail_home` lines, a design-system draft's `library_spec_scope` and `library_code_detail_home`. List a line you
  cannot meet under `Findings:`.
- After your last write and the walk, run `specstone check --out "<folder>/reports/check.author.<XXXXXX>.txt"`; `Check:`
  names it. Fix each finding of it in a section your writes touched, even one the first run had; list a finding in an
  untouched section under `Findings:`, unfixed.
- A later write, a fix included, takes one more bare check; `Check:` names that newer file, and a finding it adds goes
  under `Findings:`, unfixed.
- `item_count_out_of_range` on an FR's edge cases you wrote: follow `author-size.md`.
- Take the drafts list and every count from one `specstone approve --dry-run --json` after your last write, never from
  a tally.

## 6. Report

Follow `author-report.md`.
