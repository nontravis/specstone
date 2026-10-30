---
name: bootstrap-spec
description: Use when the spec docs of a Specstone project lag behind its format after `specstone migrate`, a new pack version, or an edited template, such as `specstone check` findings under `specs/`, `architecture_missing`, `code_uncovered`, a still-empty `TECH_STACK.md` draft, or another `specstone:` skill naming `specstone:bootstrap-spec`.
---

# Bring the spec docs up to the new format

This skill takes the `specstone check` findings under `specs/`, plus `architecture_missing` and
`code_uncovered`, which a spec doc fixes. Findings under `prds/` go to `specstone:bootstrap-prd`. Follow
`specstone:expert-sdd` for every write: each one leaves a draft, a pointer write (`implements`) excepted.

## 1. Gate: the first call

```
specstone check
```

- **78, `project_not_found`:** tell the Owner this project has not moved to the new format yet; `specstone migrate`
  moves it, or they keep the old skills. Stop: run nothing more, and read or write no doc.
- **0 or 1:** go on, even from a subfolder: the CLI looks for `.specstone/config.yaml` in each folder above. Never
  look for it yourself.
- **Any other exit:** report the CLI's error and stop.

## 2. One finding at a time

Take the first unhandled finding of this skill, fix it, and run `specstone check` again with no target: a
targeted run omits `code_uncovered`. Repeat until the only findings left are those `specstone:bootstrap-prd` takes.

Before the first write to a type, run `specstone guide <type>` (`--json` lists its fields). Bases come from
`specstone get <type>:<name> --json` (`bases.title`, `.sections.<key>`, `.fields.<id>`); each write prints the new
one. Pipe the text to `specstone set <type>:<name>#<key> --base <hash>` (`--field <id>` or `--title` in place of
`#<key>`); a section body leaves out its `## ` line, and a list field takes its whole new list. Exit 75
`base_mismatch`: read again, merge, retry.

| Finding | Fix |
|---|---|
| `required_section_missing`, `required_field_missing`, `title_missing` | fill it from the old text; ask the Owner for the rest |
| `section_undeclared` | merge its text into the section that takes it, then pipe empty text to its key |
| `field_undeclared` on `implements`, `architecture_missing`, `code_uncovered` | step 3 |
| `field_undeclared`, any other | write its value into the field that takes it, then drop the key |
| `covers_path_missing`, `code_root_missing` | fix the entry with the Owner, or drop it from the list |
| `untyped_doc` | step 4 |

To drop a key, pipe empty text to `specstone set <type>:<name> --field <id> --base <hash>`; never edit the file.

## 3. Point and cover code

- **`implements` on a spec doc:** through `specstone set --field implements`, give each entry to the story or FR
  whose behavior that code does; ask the Owner when unsure. A pointer write keeps the draft flag as it was, so name
  it in step 6 too. Then drop the spec doc's `implements` key.
- **`architecture_missing`:** run `specstone new architecture --parent <feature>`, fill it, and list in `covers` the
  code its stories and FRs point at.
- **`code_uncovered`:** add the file or its folder to `covers` on the architecture or topic doc describing it; with
  none, ask the Owner and run `specstone new topic --slug <slug>`.

## 4. Merge an old file

An `untyped_doc` under `specs/` is an old file the migration left as it was:

- old-named spec files of one feature that map to one doc: merge each in turn into the doc
  `specstone new <type> --parent <feature>` makes;
- the files of a folder under `specs/topics/`: merge all into the topic `specstone new topic --slug <folder>` makes;
- `specs/INDEX.md`: its Spec map code paths go to `covers` and the `code` roots (step 6), its source-of-truth table
  to the API docs.

Merge through `specstone set`; write nothing the doc already holds. Never target the old file: a write refuses an
untyped doc, so it keeps its text. Add each file's path to the retire set, a list for this run only, even when the
doc already held its content.

## 5. Retire the old files

1. Run `specstone refs <path>` for each file of the set; its `Inbound` lines name the docs linking in.
2. Links between files inside the set never block. An old untyped referrer joins the set, since no write repoints
   it; merge it first (`specstone:bootstrap-prd` merges one under `prds/`). Point each other referrer's link at the
   doc that now holds the content, with `specstone set` on the section holding it.
3. Print one command listing all the set's paths; the Owner runs it at their own interactive terminal:

```
specstone delete <path> <path> …
```

Never run it yourself: the CLI treats a file without `draft: true` as approved, so it refuses you with
`owner_terminal_required` (exit 77). Never run `git rm`: links into the file would break unseen. When the Owner
reports `doc_referenced` (exit 64), repoint the referrers it lists, then print the command again.

## 6. Fill the tech stack, then ask for approval

The migration's `specs/TECH_STACK.md`, like each doc `specstone new` writes, holds a bare-name title and empty
sections, which `specstone check` never lists. With the Owner, fill `tech_stack:tech_stack`: its title, each section
`specstone guide tech_stack` names, and `code`, each code folder from the project root. Fill each doc step 3 or 4
made the same way. Then run `specstone check` again: new roots can raise `code_uncovered`.

Last, name each change per draft, each moved pointer, and each dropped key. Then ask the Owner to run
`specstone approve` at their own terminal, a yes or no per draft.

## Red flags

| Thought | Do instead |
|---|---|
| "Merged, so I'll delete the old files." | Print the `delete`; the Owner runs it. |
| "`git rm` is quicker." | Never: links break unseen. |
| "`check` is clean, so the tech stack is done." | Fill its values and `code` roots anyway. |
| "Fix the `prds/` findings while I'm here." | `specstone:bootstrap-prd` takes them. |
