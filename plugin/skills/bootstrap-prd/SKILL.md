---
name: bootstrap-prd
description: Use when the PRD docs of a Specstone project lag behind its format after `specstone migrate`, a new pack version, or an edited template, such as when `specstone check` reports paths under `prds/` (a missing or leftover section or field, an untyped old file, a feature holding `implements:`), or when another `specstone:` skill names `specstone:bootstrap-prd`.
---

# Bring the PRD docs up to the new format

This skill takes the `specstone check` findings on paths under `prds/`. Findings under `specs/`, and those a spec doc
fixes (`architecture_missing`, `code_uncovered`), go to `specstone:bootstrap-spec`. Follow `specstone:expert-sdd` for
every write: each one leaves a draft.

## 1. Gate: the first call

```
specstone check
```

- **78, `project_not_found`:** tell the Owner this project has not moved to the new format yet; `specstone migrate`
  moves it, or they keep the old skills. Stop: run nothing more, and read or write no doc.
- **0 or 1:** go on, even from a subfolder: the CLI looks for `.specstone/config.yaml` in each folder above. Never
  look for `.specstone/` yourself first.
- **Any other exit:** report the CLI's error and stop.

## 2. One finding at a time

Take the first finding under `prds/` not yet handled, fix it, and run `specstone check` again. Repeat until only
findings this skill leaves stay: those `specstone:bootstrap-spec` takes, and the keys named below the table.

Before the first write to a type, run `specstone guide <type>` (`--json` lists its fields). Bases come from
`specstone get <type>:<name> --json` (`bases.title`, `bases.sections.<key>`, `bases.fields.<id>`); each write prints
the new one. Pipe the text to `specstone set <type>:<name>#<key> --base <hash>` (`--field <id>` or `--title` in place
of `#<key>`); a section body leaves out its `## ` line. Exit 75 `base_mismatch`: read again, merge, retry.

| Finding | Fix |
|---|---|
| `required_section_missing`, `required_field_missing`, `title_missing` | fill it from the doc's old text; ask the Owner for what it lacks |
| `section_undeclared` | merge its text into the section that takes it, then pipe empty text to its own key to drop it |
| `field_undeclared` on a feature's `implements` | step 3 |
| `field_undeclared`, any other | write its value into the field that takes it |
| `untyped_doc` | step 4 |

No command drops a leftover field (`field_unknown`, exit 64) or a feature's `status` (`feature_status_written`):
leave the key, never edit the file by hand, and name it in step 6.

## 3. Move a feature's code pointers

Through `specstone set --field implements`, give each `implements:` entry of a `FEATURE.md` to the story or FR whose
behavior that code does; ask the Owner when unsure. Pipe that doc's whole new list to
`specstone set <type>:<name> --field implements --base <hash>`. A pointer write keeps the draft flag as it was, so
name it in step 6 too, with the `implements:` key left on the feature.

## 4. Merge an old file

An `untyped_doc` is an old file the migration left with its old name, a group's container `FEATURE.md` among
them. Merge its content through `specstone set` into the doc that takes it; with no such doc yet, run
`specstone new <type>` (`--parent <name>`, `--slug <slug>`) and fill it. Write nothing that doc already holds.
Never target the old file: a write refuses an untyped doc, so it keeps its text. Merge several old files that map
to one doc in turn. Add each file's path to the retire set, a list for this run only.

## 5. Retire the old files

1. Run `specstone refs <path>` for each file of the set; its `Inbound` lines name the docs linking in.
2. Links between files inside the set never block. An old untyped referrer joins the set, since no write repoints
   it; merge it first (`specstone:bootstrap-spec` merges one under `specs/`). Point each other referrer's link at the
   doc that now holds the content, with `specstone set` on the section holding it.
3. Print one command listing all the set's paths; the Owner runs it at their own interactive terminal:

```
specstone delete <path> <path> …
```

Never run it yourself: the CLI treats a file without `draft: true` as approved, so it refuses you with
`owner_terminal_required` (exit 77). Never run `git rm`: it deletes while links still point in, and they show broken
only at the next check. When the Owner reports `doc_referenced` (exit 64), repoint the referrers it lists, then
print the command again.

## 6. Fill the skeletons, then ask for approval

`specstone check` lists no unfilled `<…>` placeholder in a skeleton the migration wrote, such as `project:project`,
`features:features`, or `gnfr:gnfr`. Read each with `specstone get <type>:<name>` and fill each placeholder with the
Owner.

Last, name each change per draft, each moved pointer, and each key left from step 2. Then ask the Owner to run
`specstone approve` at their own terminal: it shows each draft for a yes or no.

## Red flags

| Thought | Do instead |
|---|---|
| "Merged, so I'll delete the old files." | Print the `delete`; the Owner runs it. |
| "`git rm` is quicker." | Never: links break unseen. |
| "Fix the old file's link in place." | Add the file to the set. |
| "Hand-edit the feature to drop the key." | Leave it; name it to the Owner. |
| "Fix the `specs/` findings while I'm here." | `specstone:bootstrap-spec` takes them. |
