Step 1, the gate, runs in `engineer.md`'s workflow, so this file starts at step 2.
Your batch's findings are in the `check:` file, else in your gate's file.
As `specstone-sdd-engineer`, ask the Owner nothing: each Owner step goes in your report.

Findings under `prds/` or `measurements/`, or on an old file whose content goes into such a doc, go to
`specstone-bootstrap-prd`, except a leftover on a PRD doc whose every `to` type lies outside `prd-core`.
Follow `specstone-expert-sdd` for every write; before the first, run `specstone guide <type> …` once,
naming every type you write; a later type gets its call before its first write.

**Code target** (two or more `targets:`): each `new`, `get`, and `set` of a per-target
doc carries `--target <name>`, the finding DocPath's code target, else the first listed.

## 2. One finding at a time

Fix the first unhandled finding of your batch, then run
`specstone check --out "<folder>/reports/check.bootstrap.<XXXXXX>.txt"` again and search it.
Stop when each left goes to `specstone-bootstrap-prd`, clears with no write, or is tagged `(waits for the Owner)`, except an unanswered size finding.

Write each fix as rule 2 of `../../specstone-expert-sdd/SKILL.md` says.

Where the old text lacks a value the guide needs, write `TBR — <why>`, never a value you propose. Ask
the Owner only when no text bears on a whole section.

| Finding | Fix |
|---|---|
| `required_section_missing`, `required_field_missing`, `title_missing` | fill it from the old text |
| `singular_doc_missing` | `specstone new <type>`, then step 6 |
| `section_undeclared` | move each statement to the home the finding's `fix` names, else into the section that takes it, else the closest, even if another doc holds it, so none is lost, then drop the section |
| `field_undeclared` on `implements` | step 3 |
| `field_undeclared`, any other | move its value to the field that takes it, then drop the key |
| `covers_path_missing`, `code_root_missing` | fix the entry with the Owner, or drop it |
| `untyped_doc` whose content goes into a `specs/` doc | step 4 |
| `chars_over_limit`, `lines_over_limit`, `item_over_limit`, `bundle_over_limit` | `../../specstone-expert-sdd/references/size-fix.md` |
| `retrim_due`, `code_blocks_over_limit`, `field_value_mismatch` on `retrim` | `../../specstone-expert-sdd/references/trim.md` |
| `cite_unlinked`, a repeats batch | `../../specstone-expert-sdd/references/repeats.md` |
| `words_over_limit`, `sentence_chars_over_limit`, `trace_note_not_last`, `sentences_over_limit`, `item_lines_over_limit` | `../../specstone-expert-sdd/references/readability-fix.md` |
| any other of this skill | rewrite what it names per the loaded guide; one clearing with no write goes to step 6 |

## 3. Point and cover code

- **`implements` on a spec doc:** move each entry to the record entry of the story or FR it serves
  with `specstone set <record address> --field implements --base <hash>`, per
  `../../specstone-expert-sdd/references/write.md`, then drop the key.

## 4. Merge an old file

That `untyped_doc`: follow `merge-untyped.md`; its step 6 is this file's.

## 5. Retire the old files

1. Run `specstone refs <path>` per file of the set; each `Inbound`, `Mentions`, or `Untyped mentions` line is a
   referrer.
2. Referrers inside the set never block. An old untyped doc this skill takes joins the set: merge it first.
   A batch's set holds only files it merged; list each untyped referrer outside it, with the file it names, for its
   owner to merge. Leave any other untyped file as history. Repoint each other link or mention to the doc holding the
   content, or drop one nothing replaces.
3. Name the set in one line, `specstone delete <path> …`, quoting each path with a space.

On a batch, delete nothing: hand that line to `specstone-bootstrap-spec`'s step 3.4.
Else, run it through `specstone-expert-sdd`'s Owner confirmation. Never run `git rm`.
Exit 64 `doc_referenced`: repoint the referrers it lists, then ask again.

## 6. Fill the empty drafts, then ask for approval

With the Owner, fill each spec draft the migration left empty per the guide you loaded, each `code` entry a code
folder under that target's code root in the config's `targets:`, or `code_root` for an unnamed one, else the project
root.

Last, take every count from one `specstone approve --dry-run --json` after your last write. Your drafts are the docs
your own list names; name each other draft it lists, never counted; one of yours it shows as no draft is a finding.
Name per draft each change, moved pointer, dropped key or section, and finding that clears with no write; then get each approved through step 5's Owner confirmation.
