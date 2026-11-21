Ask the Owner nothing; list gaps in the report.

## 1. Read

- **Design document**: read it whole; list each decision, ruling, and Docs to change row.
- **Drafts** (each pass after the first): the drafts list, the first report's drafts plus added docs;
  in a fix round, the audit's `Findings:` lines not tagged `[behavior]` (`[style]` too); in the pass after an
  amend, untagged design-check lines naming a draft; in a fill pass, the split proposal's lines, each new FR whole, the old FR's `edge_cases`. In
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
  `base` of `specstone get <type>:<name>#<key> --json`.
- **A removed decision's stub row**: follow `removal.md` section 2.
- **Several docs**: one name list, step 1's names too, from this pass's rows only (after an amend, its `Amend <N> rows`
  table; a landed table is none): `<key> (<items>)`, `<key> whole`, or a bare `<key>`: that key; a stub row cell
  `take out the D<n> text: <sections>`: each section it names; `#input--output` as `input_output`; a finding's key
  with an item or note: the key alone; `whole` or a new doc: its bare name; a finding naming a doc with no key: its
  bare name, the gap under `Findings:`; key the doc lacks: its naming line, the section written under it.
  `specstone get <list> --out "<file>"`, `<file>`
  `<folder>/reports/sdd-engineer.author.batch.<XXXXXX>.txt`. `section_not_found`: rerun with its doc's bare name, the
  key under `Findings:`; `doc_not_found`: rerun without it, under `Findings:`, or `Not landed:` if never created.
  Search each item not marked `new` inside its doc's block (its `==> ` header to the next) by its line form, such as
  `N. E05 —`, a row's first cell, or a node ID (with a note, the part before the colon), then read only that item's
  lines, to the next item, by offset and limit. Read a block whole only for `whole`, a bare key, or a searched item not
  found (under `Findings:` as moved or gone); never read parts that together cover a block or the file. Write a `new`
  item at its block's end, reading only that end, with no `Findings:` line. Keep naming lines, one write per block; one
  `specstone set --batch "<file>"`. A ` · unchanged` block is no draft. A section found mid-write: its own
  `get … --out` and `set --batch`; one no row names: a row gap under `Findings:`.
- **A refused batch**: follow `refused-batch.md`.

## 3. Sweep each changed rule

Run `specstone search "<term>"`, `--limit` above its hit count, per term in each written form that the Terms item, step 3.1
of `sweep.md`, lists, the short form the key noun alone:

- **First pass, or after an amend** (its decisions only): each added term, key, or literal; each ruling's superseded
  wording; each changed rule's owner item's words and every key or literal of the set the new one joins.
- **Fix round**, or any taken finding after an amend: each taken finding's rule and terms.

A hit stating the rule without the decision's new text is a reader. One in a draft or a Docs to change row's doc: its
section goes in a second name list with its own `get … --out` and `set --batch`, its item searched and read as in
section 2; link the owner's item for a restated copy, rewrite a reader owning a rule. List any other under
`Findings:` only.

## 4. Check

Run `specstone check --out "<folder>/reports/check.author.<XXXXXX>.txt"` before your first write and after your drafts,
searching each for your drafts. Before the second, walk each item you wrote against the saved guide's description lines
(doc part, held sections, `Fields (frontmatter):`) and each type's `==> shared <==` lines, not templates or
`Banned words:`, `Required …`, `Optional …`, or `Limits:` lines. List a line you cannot meet under `Findings:`. Run
`specstone check <feature> --repeats --out "<folder>/reports/check.author.<XXXXXX>.txt"` per feature of your drafts:
link, never repeat, another doc's item.

Fix each second-run finding, even a first-run one, in a section you wrote; list others under `Findings:`,
unfixed. Two kinds:

- **A `suspect` link in another doc:** confirm it again per `specstone-expert-sdd`, that doc joining your drafts, else
  list it.
- **A finding whose `waitsFor` is `owner`**, tagged `(waits for the Owner)` in the text file: leave and list it; never
  write around it. An `item_count_out_of_range` on an FR's edge cases you wrote takes
  `../../specstone-expert-sdd/references/size-fix.md`'s split proposal; run none of its commands.

After any write of this step, run the bare check again; list each finding it adds under
`Findings:`, unfixed. `Check:` names that bare check, never a `--repeats` file.

## 5. Report

Follow `author-report.md`.
