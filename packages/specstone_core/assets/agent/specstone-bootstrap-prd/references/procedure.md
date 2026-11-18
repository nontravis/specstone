Step 1, the gate, already ran.
As `specstone-sdd-engineer`, ask the Owner nothing: each Owner step goes in your report.

Findings under `specs/`, `architecture_missing`, `code_uncovered`, and PROJECT's Tech stack and Naming canonicalization
sections go to `specstone-bootstrap-spec`. Follow the `specstone-expert-sdd` skill for every write; before the first,
run `specstone guide <type> …` once, naming every type you write; a type met later gets a call before its first write.

**Code target** (two or more `targets:`): each `new`, `get`, and `set` of a per-target
doc carries `--target <name>`, the finding DocPath's code target, else the first listed.

## 2. One finding at a time

Fix the first unhandled finding under `prds/` or `measurements/`, then rerun `specstone check`. Stop when each
finding left goes to `specstone-bootstrap-spec`, clears with no write, or is tagged `(waits for the Owner)`, except an
unanswered size finding.

Write each fix as `../../specstone-expert-sdd/references/writes.md` says.

Move every old statement to a home; never drop one on judgement. Where the old text lacks a value the guide needs,
write `TBR — <why>` in its field or sub-field, never a value you propose. Ask the Owner only when no text bears on a
whole section.

| Finding | Fix |
|---|---|
| `required_section_missing` on the features doc | step 6 |
| `required_field_missing` on a feature's `summary` | one sentence from the doc's own text on what it does for its persona, per `specstone guide feature`; `set --field summary` |
| `required_section_missing`, `required_field_missing`, `title_missing` | fill it from the old text |
| `singular_doc_missing`; `section_undeclared` on PROJECT's goals or glossary section | `goal-move.md`; `glossary-move.md` for `prds/GLOSSARY.md` and the glossary |
| `section_undeclared` holding several items the guide wants one per file | step 4 |
| `section_undeclared` | move each statement into the section that takes it, else the closest, even if another doc holds it; a statement whose home is a spec doc waits for `specstone-bootstrap-spec`; then drop the section |
| `field_undeclared` on a feature's `implements` | step 3 |
| `field_undeclared`, any other | move its value to the field that takes it, then drop the key |
| `feature_status_written` | drop the feature's `status` key |
| `untyped_doc` | step 4 |
| `chars_over_limit`, `lines_over_limit`, `item_over_limit`, `bundle_over_limit`, `subsections_over_limit` | `../../specstone-expert-sdd/references/size-fix.md` |
| `cite_unlinked`, a repeats batch | `../../specstone-expert-sdd/references/repeats.md` |
| `words_over_limit`, `sentence_chars_over_limit`, `trace_note_not_last`, `sentences_over_limit`, `item_lines_over_limit` | `../../specstone-expert-sdd/references/readability-fix.md` |
| any other under `prds/` or `measurements/` | rewrite what it names per the loaded guide; one clearing with no write goes to step 6 |

## 3. Move a feature's code pointers

Give each `implements:` entry of a `FEATURE.md` to the record entry of the story or FR whose behavior that code does, in
the first listed code target, unless it holds it already; drop an entry no one doc takes as a
proposal named in step 6. Pipe that record's whole new list, as YAML `- item` lines, to
`specstone set implementation:<feature> --field implements --base <hash>`. Then drop the feature's `implements` key.

## 4. Merge an old file, or split a full one

Merge an `untyped_doc` into the doc that takes it, else a new one from
`specstone new <type>`. Skip only a sentence that doc holds word for word. Add its path to this run's retire set.

A typed doc may hold several items its guide wants one per file, such as an old `nf` with a `### NFR-…` block each.
Keep the first; put each other in its own `specstone new <type>` doc under the same parent, named from its heading.
Drop the container and any list of inherited GNFR items, naming in step 6 each item the list left out. End a `relax`
item's Rationale with "The Owner approves the waiver by approving this doc." Repoint each mention of an old item ID to
its new doc. Name in step 6 each waiver and each mention in a section kept unchanged.

## 5. Retire the old files

1. Run `specstone refs <path>` per file of the set; each `Inbound`, `Mentions`, or `Untyped mentions` line is a
   referrer.
2. Referrers inside the set never block. An old untyped doc under `prds/`, `measurements/`, or `specs/` joins the
   set; merge it first (`specstone-bootstrap-spec` takes one under `specs/`). A batch's set
   holds only files it merged; list each untyped referrer outside it, with the file it names, for its owner to
   merge. Leave any other untyped file as history. Repoint each other link or mention to the doc holding the
   content, or drop one nothing replaces.
3. Name the set in one line, `specstone delete <path> …`, quoting each path with a space.

On a batch, delete nothing: hand that line to `specstone-bootstrap-prd`'s step 3.4.
Else, run it through `specstone-expert-sdd`'s Owner confirmation. Never run `git rm`: links break unseen.
Exit 64 `doc_referenced`: repoint the referrers it lists, then ask again.

## 6. Fill the skeletons, then ask for approval

`specstone check` misses an unfilled `<…>` placeholder in a skeleton the migration wrote (the project, features, and
gnfr docs): read each with `specstone get` and fill it with the Owner. Set a goal, glossary, or features doc's title to
its guide's with `--title` when it differs. In the features doc, `set` an empty `## Features` header on the base `get` prints
for it, run `specstone format`.

Last, take every count from one `specstone approve --dry-run --json` after your last write. Your drafts are the docs
your own list names; name each other draft it lists, never counted; one of yours it shows as no draft is a finding. Name
per draft each change, proposal, moved pointer, dropped key, and finding that clears with no write; then get each
approved as step 5 says.
