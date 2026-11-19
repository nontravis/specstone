`specstone-sdd-engineer` and the `specstone-brainstorming-sdd` runner run it in `mode: author`.
Ask the Owner nothing; list gaps in the report.

## 1. Read

- **Design document**: read it whole; list each decision, ruling, and Docs to change row.
- **Drafts** (each pass after the first): the drafts list, the first report's drafts plus added docs;
  in a fix round, the audit's `Findings:` lines not tagged `[behavior]` (`[style]` too) and untagged design-check
  lines naming a draft; in a fill pass, the split proposal's lines, each new FR whole, the old FR's `edge_cases`. In
  steps 2 to 4, write an amended design and fix those findings in the drafts; list each outside them under `Findings:`,
  unfixed.

## 2. Place each decision

Write each Docs to change row, one with no decision too, as a `design_references` link and table row. Write a
reason (Rationale, "since", "so") only in the design's words, whatever a guide line or finding asks; list
one it lacks under `Findings:`.

- **Guide**: first pass: `specstone guide <types> --out "<folder>/reports/guide.<XXXXXX>.txt"` and with `--json` to
  `guide.<XXXXXX>.json`, `<types>` the design rows' types. Later: take `guide: <txt path>, <json path>`, save only a
  type they lack.
- **Code target** (two or more `targets:`): a per-target spec doc's `new`, `get`, and `set` take the `--target <name>`
  its design row names, or an existing doc's DocPath.
- **New doc**: pipe it to `specstone new <type>` (`--parent`, `--slug`), parents first.
- **Section or field**: pipe it to `specstone set <type>:<name>#<key> --base <hash>` (a field: `--field <id>` for
  `#<key>`; a passage: `--replace` with `==> old <==`, the passage, `==> new <==`, the new one), its hash in
  `bases` of `specstone get <type>:<name> --json`.
- **A removed decision's stub row**: follow `removal.md` section 2.
- **Several docs**: one name list: `<type>:<name>#<key>` per `write_drafts_with_coverage` Name forms row, step 1's too;
  `specstone get <list> --out "<file>"`, `<file>`
  `<folder>/reports/sdd-engineer.author.batch.<XXXXXX>.txt`.
  `section_not_found`: rerun with its doc's bare name, the key under `Findings:`; `doc_not_found`: rerun without it,
  under `Findings:`, or `Not landed:` if never created. Read a block only when you edit it; keep naming lines, one write
  per block; one `specstone set --batch "<file>"`. A ` · unchanged` block is no draft. A later-found section: its
  own `get … --out` and `set --batch`; one no row names: a row gap under `Findings:`.
- **A refused batch**: follow `refused-batch.md`.

## 3. Sweep each changed rule

Run `specstone search "<term>"`, `--limit` above its hit count, per term in each written form step 3 of `design.md`
lists, the short form the key noun alone:

- **First pass, or after an amend** (its decisions only): each added term, key, or literal; each ruling's superseded
  wording; each changed rule's owner item's words and every key or literal of the set the new one joins.
- **Fix round**: each taken finding's rule and terms.

A hit stating the rule without the decision's new text is a reader; add its section to the name list. In a draft or a
Docs to change row's doc, link the owner's item for a restated copy; rewrite a reader owning a rule. List any other
under `Findings:`.

## 4. Check

Run `specstone check --out "<folder>/reports/check.author.<XXXXXX>.txt"` before your first write and after your
drafts, searching each for your drafts. Before the second, walk each item you wrote against the saved guide's description lines (doc part, held sections, `Fields:`) and each type's `==> shared <==` lines, not
templates or `Banned words:`, `Required …`, `Optional …`, or `Limits:` lines. List a line you cannot meet under
`Findings:`. Run `specstone check <feature> --repeats --out "<folder>/reports/check.author.<XXXXXX>.txt"` per
feature of your drafts: link, never repeat, another doc's item.

Fix each second-run finding, even a first-run one, in a section you wrote; list others under `Findings:`, unfixed. Two kinds:

- **A `suspect` link in another doc:** confirm it again per `specstone-expert-sdd`, that doc joining your drafts, else
  list it.
- **A finding whose `waitsFor` is `owner`**: leave and list it; never write around it. An `item_count_out_of_range` on an FR's edge cases you wrote takes
  `../../specstone-expert-sdd/references/size-fix.md`'s split proposal; run none of its commands.

After any write of this step, run the bare check again; list each finding it adds under
`Findings:`, unfixed. `Check:` names that bare check, never a `--repeats` file.

## 5. Report

```
Design: <path>, amend <N>
Not landed: <decision>: <why no doc took it>
Not landed: <type>:<name>: listed and never created, or <why no doc took this row>
| Decision or row | Doc that took it |
|---|---|
| <ID or label, or a row's <type>:<name>> | <type>:<name>#<key>, or NOT LANDED |
Drafts for the Owner's specstone approve <type>:<name>: <type>:<name>, ...
Counts: <count> drafts; <type>:<name>: <d> dropped, <n> new; ...
Other drafts: <type>:<name>, ..., or none
Move: specstone move <target> … --under <parent>, or … --top
Check: <path>
Guide: <txt path>, <json path>
Findings: <each finding left after step 4, each finding or hit outside the drafts, or none>
```

- **Design**: `<N>`, the last amend or `0`; the relay block's first line too.
- **Drafts**: every doc you wrote or confirmed again; in a later pass, step 1's list less dropped names, plus docs
  added; names only, no `--target`. Moved docs and their children go by new names.
- **Counts**: take each count from one `specstone approve --dry-run --json` after your last write, for your
  list's docs; it names a moved one by its old name until its `Move:` line runs. Name each other draft it lists
  under `Other drafts:`, never counted; one of yours it shows as no draft goes under `Findings:`.
- **Move**: only for a moved doc, item, or scenario: one line per target parent or `--top`, copied to the relay
  block. Run no `move`.
