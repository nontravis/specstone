Ask the Owner nothing; list gaps in the report.

## 1. Read

- Read the design document whole; list each decision, ruling, and Docs to change row.
- A later pass also reads the drafts list and: in a fix round, the audit's `Findings:` lines not tagged `[behavior]`
  (`[style]` too); after an amend, untagged design-check lines naming a draft; in a fill pass, the split proposal's
  lines, each new FR whole, the old FR's `edge_cases`. Read their sections before the first write; in steps 2 to 4,
  write the amended design and fix them; list each outside them under `Findings:`, unfixed.

## 2. Place each decision

- Write each Docs to change row, one with no decision too, as a `design_references` link and table row.
- Write a reason (Rationale, "since", "so") only in the design's words, whatever a guide line or finding asks; list
  a missing one under `Findings:`.
- First pass: `specstone guide <types> --out "<folder>/reports/guide.<XXXXXX>.txt"`, and with `--json` to
  `guide.<XXXXXX>.json`, `<types>` the rows' types. A later pass takes `guide: <txt path>, <json path>` and saves only
  a type they lack.
- With two or more `targets:`, a per-target spec doc's `new`, `get`, and `set` take its row's `--target <name>`, or
  an existing doc's DocPath.
- New doc: pipe it to `specstone new <type>` (`--parent`, `--slug`), parents first.
- A removed decision's stub row: follow `removal.md` section 2.
- Make one name list from this pass's rows only, step 1's names too (after an amend, its `Amend <N> rows`; a landed
  table gives none). A row's or finding's key, bare or with items, `whole`, or a note: the key;
  `#input--output` as `input_output`; `whole` or a new doc: its bare name; a finding naming a doc but no key:
  its bare name, the gap under `Findings:`; a key the doc lacks: its naming line, the section written under it.
- Run `specstone get <list> --out "<file>"`, `<file>` `<folder>/reports/sdd-engineer.author.batch.<XXXXXX>.txt`.
  `section_not_found`: rerun with its doc's bare name, the key under `Findings:`. `doc_not_found`: rerun without it,
  under `Findings:`, or `Not landed:` if never created.
- Search each item not marked `new` inside its doc's block (`==> ` header to the next) by its line form (`N. E05 —`,
  a row's first cell, a node ID; with a note, the part before the colon); read only its lines by offset and limit.
- Read a block whole only for `whole`, a bare key, or a searched item not found (under `Findings:` as moved or
  gone); never read parts that together cover a block or the file.
- Write a `new` item at its block's end, reading only that end, with no `Findings:` line.
- Keep naming lines, one write per block; one `specstone set --batch "<file>"`. A ` · unchanged` block is no draft.
- A section found mid-write: its own `get … --out` and `set --batch`; one no row names: a row gap under `Findings:`.
- A refused batch (exit 73): first run a write or `get` to end its journal; fix each fault, then rerun. Stale block:
  merge your edit into the reply's block, no `get`. Gone block (doc deleted or moved): re-read by name and section
  key, a moved doc's new block taking the edit; drop a block naming no doc or typeless, its doc under `Findings:`. A
  part twice, or a whole-doc block beside another of its doc: join them, a field or title block into the whole-doc
  one. A removed required section, or a field only the Owner or Specstone sets: restore it; an open fence: close
  it. A refused path or line: rebuild the file from `get` text output alone; any other refusal: fix the part named.

## 3. Sweep each changed rule

Run `specstone search "<term>"`, `--limit` above its hit count, per term in each written form (with and without a
trailing `/`, backticked or not, singular and plural, the short form: the key noun alone):

- **First pass, or after an amend** (its decisions only): each added term, key, or literal; each superseded wording;
  each changed rule's owner item's words and every key or literal of the set the new one joins.
- **Fix round**, or a taken finding after an amend: each taken finding's rule and terms.

A hit stating the rule without the decision's new text is a reader. One in a draft or a row's doc: its section goes
in a second name list, with its own `get … --out` and `set --batch`, searched and read as in section 2; link the
owner's item for a restated copy, rewrite a reader owning a rule. List any other under `Findings:` only.

## 4. Check

- Run `specstone check --out "<folder>/reports/check.author.<XXXXXX>.txt"` before your first write and after your
  drafts; search each for your drafts.
- Before the second, walk each item you wrote against the saved guide's description lines (doc part, held sections,
  `Fields (frontmatter):`) and each type's `==> shared <==` lines, skipping templates and `Banned words:`,
  `Required …`, `Optional …`, `Limits:` lines; list a line you cannot meet under `Findings:`.
- Run `specstone check <feature> --repeats --out "<folder>/reports/check.author.<XXXXXX>.txt"` per feature of your
  drafts: link, never repeat, another doc's item.
- Fix each second-run finding, a first-run one too, in a section you wrote; list others under `Findings:`, unfixed.
- A `suspect` link in another doc: confirm it again per `specstone-expert-sdd`, that doc joining your drafts, else
  list it.
- `item_count_out_of_range` on an FR's edge cases you wrote: take the split proposal of
  `../../specstone-expert-sdd/references/size-fix.md`; run none of its commands.
- After any write of this step, rerun the bare check; list each finding it adds under `Findings:`, unfixed. `Check:`
  names that bare check, never a `--repeats` file.

## 5. Report

Follow `author-report.md`.
