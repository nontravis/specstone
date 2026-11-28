Your batch's findings are in the `check:` file, else in your gate's file.
As `specstone-sdd-engineer`, ask the Owner nothing: each Owner step goes in your report.

Other findings under `specs/` and a PRD doc leftover whose every `to` type lies outside
`prd-core` go to `specstone-bootstrap-spec`. Follow
`specstone-expert-sdd` for every write; before the first, run `specstone guide <type> …` once, naming every type you
write; a later type gets its call before its first write.

**Code target** (two or more `targets:`): each `new`, `get`, and `set` of a per-target
doc carries `--target <name>`, the finding DocPath's code target, else the first listed.

## 1. One finding at a time

Fix your batch's first unhandled finding, then rerun
`specstone check --out "<folder>/reports/check.bootstrap.<XXXXXX>.txt"` and search its file. Stop when each finding left
goes to `specstone-bootstrap-spec`, clears with no write, or is tagged `(waits for the Owner)`, except an unanswered
size finding.

Move every old statement to a home. Where old text lacks a value the guide needs,
write `TBR — <why>`, never your own value. Ask the Owner only when no text bears on a
whole section.

| Finding | Fix |
|---|---|
| `required_section_missing` on the features doc | step 5 |
| `required_field_missing` on a feature's `summary` | one sentence from the doc's text on what it does for its persona, per `specstone guide feature`; `set --field summary` |
| `required_section_missing`, `required_field_missing`, `title_missing` | fill it from the old text |
| `singular_doc_missing`; `section_undeclared` on PROJECT's goals or glossary section | `goal-move.md`; `glossary-move.md` for `prds/GLOSSARY.md` and the glossary |
| `section_undeclared` holding several items the guide wants one per file | step 3 |
| `untyped_doc` whose content goes into a `prds/` or `measurements/` doc | step 3 |
| `section_undeclared` | move each statement to the home the finding's `fix` names, else into the section that takes it, else the closest, even if another doc holds it, then drop the section |
| `field_undeclared` on a feature's `implements` | step 2 |
| `field_undeclared`, any other | move its value to the field that takes it, then drop the key |
| `feature_status_written` | drop its `status` key |
| `chars_over_limit`, `lines_over_limit`, `item_over_limit`, `bundle_over_limit`, `subsections_over_limit`, `item_count_out_of_range` on FR edge cases | `../../specstone-expert-sdd/references/size-fix.md` |
| `retrim_due`, `code_blocks_over_limit`, `field_value_mismatch` on `retrim` | `../../specstone-expert-sdd/references/trim.md` |
| `cite_unlinked`, a repeats batch | `../../specstone-expert-sdd/references/repeats.md` |
| `words_over_limit`, `sentence_chars_over_limit`, `trace_note_not_last`, `sentences_over_limit`, `item_lines_over_limit` | `../../specstone-expert-sdd/references/readability-fix.md` |
| any other under `prds/` or `measurements/` | rewrite what it names per its guide; one clearing with no write goes to step 5 |

## 2. Move a feature's code pointers

Give each `implements:` entry of a `FEATURE.md` to the record entry of the story or FR whose behavior it codes,
unless it holds it; drop an entry no one doc takes as a proposal named in step 5. Pipe that record's whole new list,
as `- item` lines, to `specstone set <record address> --field implements --base <hash>`, per `../../specstone-expert-sdd/references/write.md`,
then drop the feature's `implements` key.

## 3. Merge an old file, or split a full one

An `untyped_doc` whose content goes into a `prds/` or `measurements/` doc, a file whose doc type a pack dropped included: follow `merge-untyped.md`.

A typed doc may hold several items its guide wants one per file, such as an old `nf` with a `### NFR-…` block each.
Keep the first; put each other in its own `specstone new <type>` doc under the same parent, named from its heading.
Drop the container and any list of inherited GNFR items, naming in step 5 each item the list left out. End a `relax`
item's Rationale with "The Owner approves the waiver by approving this doc." Repoint each mention of an old item ID to
its new doc. Name in step 5 each waiver and each mention in a section kept unchanged.

## 4. Retire the old files

1. Run `specstone refs <path>` per file of the set; each `Inbound`, `Mentions`, or `Untyped mentions` line is a
   referrer.
2. Referrers inside the set never block. An old untyped doc this skill takes
   joins the set, a `specs/` path it merged included; merge it first. A batch's set
   holds only files it merged; list each untyped referrer outside it, with the file it names, for its owner to
   merge. Leave any other untyped file as history. Repoint each other link or mention to the doc holding the
   content, or drop one nothing replaces.
3. Name the set in one line, `specstone delete <path> …`, quoting each path with a space.

On a batch, delete nothing: hand that line to `specstone-bootstrap-prd`'s step 3.4.
Else, run it through `specstone-expert-sdd`'s Owner confirmation. Never run `git rm`.
Exit 64 `doc_referenced`: repoint the referrers it lists, then ask again.

## 5. Fill the skeletons, then ask for approval

`check` misses an unfilled `<…>` placeholder in a migration skeleton: read each with `specstone get`, fill it with the Owner. Set a goal, glossary, or features doc's title to
its guide's with `--title` when it differs. In the features doc, `set` an empty `## Features` header on the base `get` prints, then
run `specstone format`.

Last, take every count from one `specstone approve --dry-run --json` after your last write. Your drafts are the docs
your own list names; name each other draft it lists, never counted; one of yours it shows as no draft is a finding. Name
per draft each change, proposal, moved pointer, dropped key, and finding that clears with no write; then get each
approved as step 4 says.
