Step 1, the gate, already ran in the skill or agent that sent you here.
As `specstone:sdd-engineer`, ask the Owner nothing: each step with the Owner goes into your report.

This skill takes `specstone check` findings under `prds/`. Findings under `specs/`, `architecture_missing`,
`code_uncovered`, and those on PROJECT's Tech stack and Naming canonicalization sections go to
`specstone:bootstrap-spec`. Follow `specstone:expert-sdd` for every write; before the first, run
`specstone guide <type> …` once, naming every type you write; a type met later gets its own call before its first
write.

## 2. One finding at a time

Fix the first unhandled finding under `prds/`, then run `specstone check` again. Stop when each finding left
goes to `specstone:bootstrap-spec`, clears with no write, or is tagged `(waits for the Owner)`, except an unanswered
size finding.

Bases come from `specstone get <type>:<name> --json` (`bases.title`, `bases.sections.<key>`, `bases.fields.<id>`);
each write prints the new one. Pipe the text to `specstone set <type>:<name>#<key> --base <hash>` (`--field <id>` or
`--title` in place of `#<key>`); a section body leaves out its `## ` line, and empty text drops the section or key.
The text between the title and the first `##` section is `#_lead`. Exit 75 `base_mismatch`: read again, merge,
retry.

Quote a node label that holds `(`, `)`, `[`, `]`, `{`, or `}`, as in `A["Save (draft)"]`; write `"` in it as
`#quot;`.

Move every old statement to a home; never drop one on judgement. Where the old text lacks a value the guide needs,
write `TBR — <why>` in its field or sub-field, never a value you propose. Ask the Owner only when no text bears on a
whole section.

| Finding | Fix |
|---|---|
| `required_section_missing`, `required_field_missing`, `title_missing` | fill it from the old text |
| `section_undeclared` holding several items the guide wants one per file | step 4 |
| `section_undeclared` | move each statement into the section that takes it, else the closest, even if another doc holds it; a statement whose home is a spec doc, such as PROJECT's Tech stack, waits for `specstone:bootstrap-spec`; then drop the section |
| `field_undeclared` on a feature's `implements` | step 3 |
| `field_undeclared`, any other | move its value to the field that takes it, then drop the key |
| `feature_status_written` | drop the feature's `status` key |
| `untyped_doc` | step 4 |
| `chars_over_limit`, `lines_over_limit`, `item_over_limit` | `${CLAUDE_PLUGIN_ROOT}/skills/expert-sdd/references/size-fix.md` |
| any other under `prds/` | rewrite what it names per the guide you loaded; one that clears with no write goes to step 6 |

## 3. Move a feature's code pointers

Give each `implements:` entry of a `FEATURE.md` to the story or FR whose behavior that code does, unless it holds it
already; drop an entry no one doc takes, such as a whole folder, as a proposal named in step 6. Pipe that doc's whole
new list, as YAML `- item` lines, to `specstone set <type>:<name> --field implements`. Then drop the feature's
`implements` key.

## 4. Merge an old file, or split a full one

An `untyped_doc` is an old file the migration left, such as a group's container `FEATURE.md`.
Merge its content into the doc that takes it, else a new one from `specstone new <type>`
(`--parent`, `--slug`, as the type takes them). Skip only a sentence that doc holds word for word, and never target
the untyped file: a write refuses it. Add its path to the retire set, a list for this run only.

A typed doc may hold several items its guide wants one per file, such as an old `nf` with a `### NFR-…` block each.
Keep the first; put each other in its own `specstone new <type>` doc under the same parent, named from its heading.
Drop the container and any list of inherited GNFR items, naming in step 6 each item the list left out. End a `relax`
item's Rationale with "The Owner approves the waiver by approving this doc." Repoint each mention of an old item ID to
its new doc. Name in step 6 each waiver and each mention in a section kept unchanged.

## 5. Retire the old files

1. Run `specstone refs <path>` per file of the set; each `Inbound`, `Mentions`, or `Untyped mentions` line is a
   referrer.
2. Referrers inside the set never block. An old untyped doc under `prds/` or `specs/` joins the set, as no write
   repoints it; merge it first (`specstone:bootstrap-spec` takes one under `specs/`). On a batch, the set holds only
   files the batch merged: list an untyped referrer outside the batch, with the file it names, for its owner to merge.
   Leave any other untyped file (a plan, a ledger) as history. Repoint each other link or mention to the doc holding
   the content, or drop a mention nothing replaces.
3. Name the set in one `specstone delete` line, quoting each path with a space:

```
specstone delete <path> <path> …
```

On a batch, delete nothing: hand that line to `specstone:bootstrap-prd`'s step 3.4.
With no batch, run it through `specstone:expert-sdd`'s Owner confirmation. Never run `git rm`: links break unseen.
Exit 64 `doc_referenced`: repoint the referrers it lists, then ask again.

## 6. Fill the skeletons, then ask for approval

`specstone check` misses an unfilled `<…>` placeholder in a skeleton the migration wrote (`project:project`,
`features:features`, `gnfr:gnfr`): read each with `specstone get` and fill it with the Owner.

Last, take every count from one `specstone approve --dry-run --json` after your last write. Your drafts are the docs
your own list names; name each other draft it lists, never counted; one of yours it shows as no draft is a finding.
Name per draft each change, proposal, moved pointer, dropped key, and finding that clears with no write; then get
each approved as step 5's Owner confirmation says.

## Red flags

| Thought | Do instead |
|---|---|
| "Merged, so I'll delete the old files." | Delete only as step 5 says. |
| "Several items fit in one doc for now." | Split them as step 4 says. |
