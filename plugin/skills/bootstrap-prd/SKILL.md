---
name: bootstrap-prd
description: Use when the PRD docs of a Specstone project lag behind its format after `specstone migrate`, a new pack version, or an edited template, such as when `specstone check` reports paths under `prds/` (a missing or leftover section or field, an untyped old file, a feature holding `implements:`), or when another `specstone:` skill names `specstone:bootstrap-prd`.
---

# Bring the PRD docs up to the new format

This skill takes the `specstone check` findings on paths under `prds/`. Findings under `specs/`, and those a spec doc
fixes (`architecture_missing`, `code_uncovered`), go to `specstone:bootstrap-spec`. Follow `specstone:expert-sdd` for
every write: each one leaves a draft, a pointer write (`implements`) excepted.

## 1. Gate: the first call

```
specstone check
```

- **78, `project_not_found`:** tell the Owner this project has not moved to the new format yet; `specstone migrate`
  moves it, or they keep the old skills. Stop: run nothing more, and read or write no doc.
- **0 or 1:** go on, even from a subfolder. Never look for `.specstone/` yourself.
- **Any other exit:** report the CLI's error and stop.

## 2. One finding at a time

Take the first finding under `prds/` not yet handled, fix it, and run `specstone check` again. Repeat until each
finding left is one `specstone:bootstrap-spec` takes, one no write clears, or one that waits on the Owner, such as an
`unconfirmed` link that `waits for the Owner's approve`.

Before the first write to a type, run `specstone guide <type>` (`--json` lists its fields). Bases come from
`specstone get <type>:<name> --json` (`bases.title`, `bases.sections.<key>`, `bases.fields.<id>`); each write prints
the new one. Pipe the text to `specstone set <type>:<name>#<key> --base <hash>` (`--field <id>` or `--title` in place
of `#<key>`); a section body leaves out its `## ` line. Exit 75 `base_mismatch`: read again, merge, retry.

For any finding a write clears: where the old text lacks what the guide needs, write a proposal from the project's
own text (a vision entry's Why line backs its `> en:` summary), named in step 6. Ask the Owner only when no text
bears on it.

| Finding | Fix |
|---|---|
| `required_section_missing`, `required_field_missing`, `title_missing` | fill it from the doc's old text |
| `section_undeclared` | merge each statement into the section that takes it, else the closest the guide allows, unless a doc of the project already holds it (cite where in step 6); a statement whose home is a spec doc, such as PROJECT's Tech stack or Naming, stays until `specstone:bootstrap-spec` writes it there and drops this section; once each other statement stands, pipe empty text to its key to drop it |
| `field_undeclared` on a feature's `implements` | step 3 |
| `field_undeclared`, any other | write its value into the field that takes it, then drop the key |
| `feature_status_written` | drop the feature's `status` key |
| `untyped_doc` | step 4 |
| any other under `prds/` | rewrite the section or field it names through `specstone set` per `specstone guide <type>`; one no write clears goes to step 6 |

To drop a key, pipe empty text to `specstone set <type>:<name> --field <id> --base <hash>`, the base from
`bases.fields.<id>`. Never drop a key by editing the file.

## 3. Move a feature's code pointers

Through `specstone set --field implements`, give each `implements:` entry of a `FEATURE.md` to the story or FR whose
behavior that code does, unless it already holds it; an entry no one story or FR takes, such as a whole folder, is
dropped as a proposal named in step 6. Pipe that doc's whole new list, as YAML `- item` lines, to
`specstone set <type>:<name> --field implements --base <hash>`. A pointer write keeps the draft flag as it was, so
name it in step 6 too. Then drop the feature's `implements` key as step 2 says.

## 4. Merge an old file

An `untyped_doc` is an old file the migration left with its old name, a group's container `FEATURE.md` among
them. Merge its content through `specstone set` into the doc that takes it; with no such doc yet, run
`specstone new <type>` (`--parent <name>`, `--slug <slug>`, as the type takes them) and fill it. Write nothing that
doc already holds. Never target the old file: a write refuses an untyped doc, so it keeps its text. Add each file's
path to the retire set, a list for this run only.

## 5. Retire the old files

1. Run `specstone refs <path>` per file of the set; its `Inbound` and `Mentions` lines are the referrers.
2. Referrers inside the set never block. An old untyped referrer joins the set, as no write repoints it; merge it
   first (`specstone:bootstrap-spec` takes one under `specs/`). Repoint each other link or mention to the doc now
   holding the content, or drop a mention nothing replaces, through `specstone set` on that section.
3. Delete the set through `specstone:expert-sdd`'s Owner confirmation (terminal or chat), one command naming every
   path, quoting each path that holds a space:

```
specstone delete <path> <path> …
```

The CLI treats a file without `draft: true` as approved, so without the Owner's word it refuses (exit 77). Never run
`git rm`: it deletes while links still point in. On `doc_referenced`
(exit 64), repoint the referrers it lists, then ask again.

## 6. Fill the skeletons, then ask for approval

`specstone check` lists no unfilled `<…>` placeholder in a skeleton the migration wrote, such as `project:project`,
`features:features`, or `gnfr:gnfr`. Read each with `specstone get <type>:<name>` and fill each placeholder with the
Owner.

Last, name each change per draft, each proposal, each moved pointer, each dropped key, and each finding no write
clears. Then get each draft approved through the Owner confirmation step 5 names.

## Red flags

| Thought | Do instead |
|---|---|
| "Merged, so I'll delete the old files." | Delete only after the Owner's `ok` or at their terminal. |
| "Fix the old file's link in place." | Add the file to the set. |
