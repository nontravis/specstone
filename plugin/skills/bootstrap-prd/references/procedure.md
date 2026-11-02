Step 1, the gate, already ran in the skill or agent that sent you here.
When you run as `specstone:sdd-engineer`, ask the Owner nothing: each step that asks, confirms, or approves with the
Owner goes into your report instead.

This skill takes `specstone check` findings under `prds/`. Findings under `specs/`, `architecture_missing`,
`code_uncovered`, and those on PROJECT's Tech stack and Naming canonicalization sections go to
`specstone:bootstrap-spec`. Follow `specstone:expert-sdd` for every write: each leaves a draft, a pointer write
(`implements`, `covers`) excepted.

## 2. One finding at a time

Fix the first finding under `prds/` not yet handled, then run `specstone check` again. Stop when each finding left
goes to `specstone:bootstrap-spec`, clears with no write, or waits on the Owner, such as an `unconfirmed` link.

Before the first write to a type, run `specstone guide <type>` (`--json` lists its fields). Bases come from
`specstone get <type>:<name> --json` (`bases.title`, `bases.sections.<key>`, `bases.fields.<id>`); each write prints
the new one. Pipe the text to `specstone set <type>:<name>#<key> --base <hash>` (`--field <id>` or `--title` in place
of `#<key>`); a section body leaves out its `## ` line, and empty text drops the section or key: never edit the file.
Exit 75 `base_mismatch`: read again, merge, retry.

Where the old text lacks what the guide needs, propose it from the project's own text (a vision entry's Why
line backs its `> en:` summary), named in step 6. Ask the Owner only when no text bears on it.

| Finding | Fix |
|---|---|
| `required_section_missing`, `required_field_missing`, `title_missing` | fill it from the doc's old text |
| `section_undeclared` holding several items the guide wants one per file | step 4 |
| `section_undeclared` | merge each statement into the section that takes it, else the closest the guide allows, unless a project doc holds it already (cite where in step 6); a statement whose home is a spec doc, such as PROJECT's Tech stack, waits for `specstone:bootstrap-spec`; then drop the section |
| `field_undeclared` on a feature's `implements` | step 3 |
| `field_undeclared`, any other | move its value into the field that takes it, then drop the key |
| `feature_status_written` | drop the feature's `status` key |
| `untyped_doc` | step 4 |
| any other under `prds/` | rewrite what it names per `specstone guide <type>`; one that clears with no write goes to step 6 |

## 3. Move a feature's code pointers

Give each `implements:` entry of a `FEATURE.md` to the story or FR whose behavior that code does, unless it holds it
already; drop an entry no one doc takes, such as a whole folder, as a proposal named in step 6. Pipe that doc's whole
new list, as YAML `- item` lines, to `specstone set <type>:<name> --field implements`. Then drop the feature's
`implements` key.

## 4. Merge an old file, or split a full one

An `untyped_doc` is an old file the migration left with its old name, such as a group's container `FEATURE.md`.
Merge its content through `specstone set` into the doc that takes it, or into a new one from `specstone new <type>`
(`--parent`, `--slug`, as the type takes them). Write nothing it holds already, and never target the
untyped file: a write refuses it. Add its path to the retire set, a list for this run only.

A typed doc may hold several items its guide wants one per file, such as an old `nf` with a `### NFR-…` block each.
Keep the first; put each other in its own `specstone new <type>` doc under the same parent, named from its heading.
Drop the container and any list of inherited GNFR items (every GNFR item applies to every story), naming in step 6
each item the list left out. End a `relax` item's Rationale with "The Owner approves the waiver by approving this
doc." Repoint each mention of an old item ID, such as `NFR-Sec01`, to its new doc. Name in step 6 each waiver and each
mention in a section kept unchanged.

## 5. Retire the old files

1. Run `specstone refs <path>` per file of the set; each `Inbound`, `Mentions`, or `Untyped mentions` line is a
   referrer.
2. Referrers inside the set never block. An old untyped doc under `prds/` or `specs/` joins the set, as no write
   repoints it; merge it first (`specstone:bootstrap-spec` takes one under `specs/`). On a batch, the set holds only
   files the batch merged: list an untyped referrer outside the batch, with the file it names, for its owner to merge.
   Leave any other untyped file, such as a plan or a ledger, as history. Repoint each other link or mention to the doc
   holding the content, or drop a mention nothing replaces, through `specstone set` on that section.
3. On a batch, delete nothing: hand the set as one `specstone delete` line to `specstone:bootstrap-prd`'s step 3.4,
   which joins the round's lines. With no batch, delete the set in one command once the Owner confirms it per
   `specstone:expert-sdd`, quoting each path with a space:

```
specstone delete <path> <path> …
```

Without the Owner's word the CLI refuses (exit 77). Never run `git rm`: it deletes while links still point in. On
`doc_referenced` (exit 64), repoint the referrers it lists, then ask again.

## 6. Fill the skeletons, then ask for approval

`specstone check` misses an unfilled `<…>` placeholder in a skeleton the migration wrote (`project:project`,
`features:features`, `gnfr:gnfr`): read each with `specstone get` and fill it with the Owner.

Last, name each change per draft, proposal, moved pointer, dropped key, and finding that clears with no write, then
get each draft approved as step 5's Owner confirmation says.

## Red flags

| Thought | Do instead |
|---|---|
| "Merged, so I'll delete the old files." | Delete only after the Owner's `ok` or at their terminal. |
| "Several items fit in one doc for now." | Split them as step 4 says. |
