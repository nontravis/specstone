`specstone-sdd-engineer` and the `specstone-brainstorming-sdd` runner run it in `mode: author`, the gate passed.
Ask the Owner nothing: list each gap in the report.

## 1. Read

- **Design document**: read it whole; list each decision, ruling, and Docs to change row.
- **Drafts** (each pass after the first): the drafts list, the first author report's drafts plus each doc a later
  pass added; in a fix round, the audit's `Findings:` lines too. Before your first write, re-read the drafts in one
  `specstone get <drafts list>`, rerun without each name a `doc_not_found` refusal names; list each under
  `Findings:`, or `Not landed:` if never created. In steps 2 to 4, write an amended design and fix those findings in
  the drafts; list each outside them under `Findings:`, unfixed.

## 2. Place each decision

Write each Docs to change row, one with no decision too, as a `design_references` link with a table row. Write a
reason (Rationale, "since", "so") only in the design's words, whatever a guide line or `check` finding asks; list
one it lacks under `Findings:`.

- **Guide**: before writing, run `specstone guide <type> … --out` per type you write.
- **Code target** (two or more `targets:`): pass a per-target spec doc's `new`, `get`, and `set` the
  `--target <name>` its design row names, or use an existing doc's DocPath.
- **New doc**: pipe it to `specstone new <type>` (`--parent`, `--slug` as it takes them), parents first.
- **Section or field**: pipe it to `specstone set <type>:<name>#<key> --base <hash>` (a field: `--field <id>` for
  `#<key>`; a passage: `--replace` with `==> old <==`, the passage, `==> new <==`, its replacement), its hash in
  `bases` of `specstone get <type>:<name> --json`.
- **A removed decision's stub row**: follow `removal.md` section 2.
- **Several docs**: edit the blocks of `specstone get <names> --out "<file>"`, `<file>`
  `<folder>/reports/sdd-engineer.author.batch.<XXXXXX>.txt`, naming lines kept, one write per block; run
  `specstone set --batch "<file>"`. A ` · unchanged` block adds no draft.
- **A refused batch**: after exit 73, first run a write or `get` to end its journal. Fix each fault; rerun:
  - Stale block: merge your edit into the reply's block; run no `get`.
  - Gone block: re-read its doc by name, a moved doc's new block taking the edit. Drop a block naming no doc or
    typeless, its doc under `Findings:`.
  - Part twice, or a whole-doc block beside another of its doc: join them, a field or title block into the whole-doc
    one.
  - Removed required section, or a field only the Owner or Specstone sets: restore it; open fence: close it.
  - Refused path or line: rebuild the file from `get` text output alone; any other refusal: fix the part it names.

## 3. Sweep each changed rule

Run `specstone search "<term>"`, `--limit` above its hit count, per term in each written form step 3 of `design.md`
lists, the short form the key noun alone:

- **First pass, or after an amend** (its decisions only): each added term, key, or literal; each ruling's
  superseded wording; each changed rule's owner item's words and every key or literal of the set the new one joins.
- **Fix round**: each taken finding's rule and terms.

A hit stating the rule without the decision's new text is a reader: rewrite it in a draft or a Docs to change row's
doc; list any other under `Findings:`.

## 4. Check

Run a bare `specstone check` before your first write and after your last. Before the second, walk each item you
wrote against the saved guide's description lines (doc part, held sections, `Fields:`), not templates or
`Banned words:`, `Required …`, `Optional …`, or any `Limits:` line; two edge cases of one response break `fr`'s
distinct-response line. List a line you cannot meet under `Findings:`. Then run
`specstone check <feature> --repeats` per feature of your drafts: new draft text repeating another doc's item links
it instead. Save each `check` by `--out`, no redirect.

Fix each second-run finding, even a first-run one, in a section you wrote; list others, such as in a doc you only
confirmed again, under `Findings:`, unfixed. Two kinds differ:

- **A `suspect` link in another doc:** confirm it again per `specstone-expert-sdd`, that doc joining your drafts, else
  list it.
- **A finding whose `waitsFor` is `owner`**, ending `(waits for the Owner)`: leave it and list it; never write around
  it. An `item_count_out_of_range` on the edge cases of an FR you wrote takes
  `../../specstone-expert-sdd/references/size-fix.md`'s split proposal; run none of its commands.

## 5. Report

```
Design: <path>, amend <N>
Not landed: <decision>: <why no doc took it>
Not landed: <type>:<name>: listed and never created
Not landed: <type>:<name>: <why no doc took this row>
| Decision or row | Doc that took it |
|---|---|
| <ID or label, or a row's <type>:<name>> | <type>:<name>#<key>, or NOT LANDED |
Drafts for the Owner's specstone approve <type>:<name>: <type>:<name>, ...
Counts: <count> drafts; <type>:<name>: <d> dropped, <n> new; ...
Other drafts: <type>:<name>, ..., or none
Move: specstone move <target> … --under <parent>
Move: specstone move feature:<name> … --top
Findings: <each finding left after step 4, each finding or hit outside the drafts, or none>
```

- **Design**: `<N>`, the last amend or `0`; the relay block's first line too.
- **Drafts**: every doc you wrote or confirmed again; in a later pass, step 1's list less dropped names, plus docs
  added; names only, no `--target`. Moved docs and their children go by new names.
- **Counts**: take each count from one `specstone approve --dry-run --json` after your last write, your drafts being
  your list's docs; it names a moved one by its old name until its `Move:` line runs. Name each other draft it lists
  under `Other drafts:`, never counted; one of yours it shows as no draft goes under `Findings:`.
- **Move**: only for a moved doc, item, or scenario: one line per target parent or `--top`, copied to the relay
  block. Run no `move`.
