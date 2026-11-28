Ask the Owner nothing; list gaps in the report.

In a fix round, run section 1's `--target` rule and its guide save, the save only without a saved guide for the types of
the findings and their readers; section 2 for terms a fix changes alone; section 3 for the findings' sections and their
readers alone; then sections 4 to 6.

## 1. Read

- Read the change note whole; list each decision, `D<n>`. A point it leaves open that a draft must state goes under
  `Open questions:`, one line per point; no doc states a guess at it.
- Ground on `bundles`, read by each read plan line; absent, run one `specstone context <docs> --for design --out` naming
  each doc of your share, else each Reach doc.
- With two or more `targets:`, a per-target doc's `new`, `get`, and `set` take the `--target <name>` the Reach list
  names beside it, or an existing doc's DocPath.
- Before your first write, save `specstone guide <types> --out "<folder>/reports/guide.<XXXXXX>.txt"` and the same call
  with `--json` to `guide.<XXXXXX>.json`, `<types>` every type you write. Your gate's `check` file is the check before
  your first write; run no second.

## 2. Find the readers

Run this step once per decision before your first write, each reader found on one `Readers:` line.

- Each term a decision adds, changes, or supersedes, and each short form (the key noun alone): one
  `specstone search "<term>"`, narrowed by `--type` or `--under` when the term is common.
- Each doc you change: the `Inbound` lines of one `specstone refs` call on it. A reader the step changes gets no `refs`
  call: one hop, no recursion.
- Each feature you touch and each ancestor: its summary sections: `benefit_hypothesis`, `flow`, and `out_of_scope`, and
  each spec doc section that lists the feature's parts or traces its FRs.
- A reader stating a changed rule is changed, or its copy gives way to a link to the owner's item; no copy stays beside
  the link. A `--repeats` check is no part of this step.
- A decision that replaces or narrows a section's rule: first read that section's current text, never by `get`: in the
  saved bundle files, else run one `specstone context <doc> --for design --out` for it and read its file. Then run one
  `specstone search "<phrase>"` per key noun phrase of that text, beside the term searches. Each hit that states the
  replaced rule, in any wording, is a reader.

## 3. Write

Make one name list, run one `specstone get <list> --out "<file>"` of it, then one `specstone set --batch "<file>"`,
`<file>` `<folder>/reports/sdd-engineer.author.batch.<XXXXXX>.txt`. Name each:

- section a decision or a `changed` or `linked` reader changes: `<type>:<name>#<key>`, its items naming what changes;
- rewrite of every section, or new doc: the bare name; a new doc reads nothing before `specstone new <type>`
  (`--parent`, `--slug`), piped in, parents first;
- anchor such as `#input--output`: its words joined by `_`, `input_output`;
- key with an item or note such as `#invariants INV-3`: the key alone;
- key no template defines: `section_not_found` refuses the call; rerun the one `get` with that doc's bare name in place
  of its section names, the key under `Findings:`;
- key the template defines and the doc lacks: its block holds the naming line alone; write the section there.

- Search a block (`==> ` header to the next) for an item's line form (`N. E05 —`, a row's first cell, a node ID; with a
  note, the part before the colon); read its lines alone by offset and limit. Read a block whole only for a bare name or
  a rewritten section.
- Write each doc block with one edit; a ` · unchanged` block counts as no draft. A section needed after edits began
  takes its own `get … --out` and its own `set --batch`.
- A reason (Rationale, "since", "so") is the change note's words; one it lacks goes under `Findings:`.
- Each decision of your share: one `Decision:` line naming each section that took it. One no doc took reads
  `NOT LANDED`, with one `Not landed: D<n>:` line saying why; never force it into a doc or drop it. A builder check fix
  you cannot apply goes under `Findings:`, never `Not landed:`. A `(plan)` decision, or one only docs outside your share
  take, gets neither line; as a group writer, give the latter an `Elsewhere:` line, its why naming the `D<n>`.
- A reader in a doc outside your share: an `Elsewhere:` line and no write. The cross-group writer's merge step closes or
  fixes each `Elsewhere:` line of `group reports` and writes a `Not landed:` line per decision not marked `(plan)` that
  no `Decision:` line of `group reports` names.
- A write that moves the upstream of a tracked link in a doc you did not write: confirm it per `specstone-expert-sdd`,
  that doc joining your drafts; else list it under `Findings:`.
- A change note's move (doc, item, or scenario), rename, or removal: run no `rename` or `delete`, and, bar section 7's
  split, no `move` but `move --plan-out … --out` into one plan file of every move,
  `<folder>/reports/sdd-engineer.author.plan.<XXXXXX>.txt`, its lines per
  `../../specstone-expert-sdd/references/size-fix.md`. For main, give one `Move:` line naming that file, copied to the
  relay block, and one `Rename:` or `Delete:` line per doc.

## 4. Recover a refused batch

A refused `set --batch`: on `output_not_writable`, first run a write command or a `get`; fix each fault the refusal
names, then rerun the batch:

- Stale block: merge your edit into its printed text; no `get`.
- Gone block (doc deleted or moved): read again by its name and the block's section key; a moved doc's new block takes
  the edit. A name that names no doc, or an untyped block: drop it, its doc under `Findings:`.
- One part twice, or a whole-doc block beside another of its doc: join them; a field or title block goes inside it.
- A removed required section, a field only the Owner or Specstone sets, or an open fence: restore the section or the
  field's value, or close the fence.
- An undeclared section `check` reports: fix it in its draft as the finding names.
- A refused path or line: rebuild the file from `get` text output alone, and pass its path.

## 5. Walk and check

- Walk each item you wrote against the rule lines of your saved `guide <type>` output: the description lines of the doc
  part, of each section the draft holds, and of each field in `Frontmatter:`. Templates and the `Banned words:`,
  `Required …`, `Optional …`, and `Limits:` lines are no rule lines. With several types, each type's rule lines take its
  `==> shared <==` lines too. A spec draft's rule lines also take the pack's `spec_scope` and `code_detail_home` lines,
  a design-system draft's `library_spec_scope` and `library_code_detail_home`. List a line you cannot meet under
  `Findings:`.
- After your last write and the walk, run `specstone check --out "<folder>/reports/check.author.<XXXXXX>.txt"`; `Check:`
  names it, never a `--repeats` file. Fix each finding of it in a section your writes touched, even one the first run
  had; list a finding in an untouched section under `Findings:`, unfixed.
- A later write, a fix included, takes one more bare check; `Check:` names that newer file, and a finding it adds goes
  under `Findings:`, unfixed.
- `item_count_out_of_range` on an FR's edge cases you wrote: section 7.

## 6. Report

```
Drafts for the Owner's specstone approve <type>:<name>: <type>:<name>, ...
Decision: D<n> -> <type>:<name>#<key>, …
Not landed: D<n>: <why no doc took it>
Readers: <type>:<name>#<key> changed|linked|unaffected: <why>
Elsewhere: <type>:<name>#<key>: <why>
Move: <plan file path>
Rename: specstone rename <doc> --to <slug>
Delete: <type>:<name>
Open questions: <each point only the Owner's answer settles that a draft must state>
Check: <path>
Counts: <count> drafts; <type>:<name>: <d> dropped, <n> new; ...
Other drafts: <type>:<name>, ..., or none
Findings: <each finding left after step 5, each reason the change note lacks, or none>
```

- Take drafts and counts from one `specstone approve --dry-run --json` after your last write, never a tally. Drafts:
  every doc you wrote or confirmed again, named as it prints it, no `--target`; a moved doc by its old name until its
  `Move:` runs. Counts: your drafts only; each other draft it shows goes under `Other drafts:`, uncounted. A doc of
  yours it shows as no draft goes under `Findings:`.
- A later round appends to the same report file under `## Round <n>`, never a new file. Its `Decision:` line lands a
  decision an earlier round left `NOT LANDED`, naming each section that took it, another writer's included. Approval
  reads both lines by `D<n>` per report file: your file's last line for it decides your file's state, and a decision
  left open there stays open until another writer's `Decision:` line lands it.

## 7. Split an FR past its edge-case cap

In author or sync mode, write each FR you touch by the edge case lines of the saved `fr` guide. An FR still over its cap
inside its story takes these steps:

1. Run one `specstone new fr --parent <story> --slug <slug>`.
2. Save one plan file by
   `specstone move --plan-out <fr> --out "<folder>/reports/sdd-engineer.<mode>.plan.<XXXXXX>.txt"`; set one
   `<fr>#<edge case ID> -> <new fr>` line per edge case past the cap; run one `specstone move --plan-file "<file>"`.
3. Fill the new FR's sections by section 3, your `<mode>` in each file name it gives.
4. Check both FRs: in author mode, section 5's later-write bare check; in sync mode, one
   `specstone check <doc> --out "<folder>/reports/check.sync.<XXXXXX>.txt"` per FR.
5. The old and the new FR both join your drafts list.

That plan file is no `Move:` line, since you applied it: name it under `Findings:` in author mode, and in the new FR's
draft line in sync mode, whose `Findings:` holds refused lines alone. An edge case that belongs in another story or
feature takes the split proposal of `../../specstone-expert-sdd/references/size-fix.md` and waits for the Owner's ok.
