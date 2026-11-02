---
name: bootstrap-spec
description: Use when the spec docs of a Specstone project lag behind its format after `specstone migrate`, a new pack version, or an edited template, such as `specstone check` findings under `specs/`, `architecture_missing`, `code_uncovered`, a still-empty `TECH_STACK.md` draft, or another `specstone:` skill naming `specstone:bootstrap-spec`.
---

# Bring the spec docs up to the new format

This skill takes `specstone check` findings under `specs/`, plus `architecture_missing` and `code_uncovered`.
Findings under `prds/` go to `specstone:bootstrap-prd`, except the PRD section step 6 moves. Follow
`specstone:expert-sdd` for every write: each leaves a draft, a pointer write (`implements`, `covers`) excepted.

## 1. Gate: the first call

```
specstone check
```

- **78, `project_not_found`:** tell the Owner `specstone migrate` moves the project to the new format, or they keep
  the old skills. Stop: run, read, and write nothing more.
- **0 or 1:** go on, even from a subfolder. Never look for `.specstone/` yourself.
- **Any other exit:** report the CLI's error and stop.

## 2. One finding at a time

Fix the first unhandled finding of this skill, then run `specstone check` again with no target (a targeted run
omits `code_uncovered`). Stop when each finding left is under `prds/`, no write clears it, or it waits on the Owner.

Bases come from `specstone get <type>:<name> --json` (`bases.title`, `bases.sections.<key>`, `bases.fields.<id>`);
each write prints the new one. Pipe the text to `specstone set <type>:<name>#<key> --base <hash>` (`--field <id>` or
`--title` in place of `#<key>`); a section body leaves out its `## ` line, a list field takes its whole list, and
empty text drops the section or key: never edit the file. Exit 75 `base_mismatch`: read again, merge, retry.

For a finding a write clears: write nothing a project doc holds already (cite where in step 6); where the old text
lacks what the guide needs, propose it from the project's own text, named in step 6; ask the Owner only when no
text bears on it.

| Finding | Fix |
|---|---|
| `required_section_missing`, `required_field_missing`, `title_missing` | fill it from the old text |
| `section_undeclared` | merge each statement into the section that takes it, else the closest, then drop the section |
| `field_undeclared` on `implements`, `architecture_missing`, `code_uncovered` | step 3 |
| `field_undeclared`, any other | move its value to the field that takes it, then drop the key |
| `covers_path_missing`, `code_root_missing` | fix the entry with the Owner, or drop it |
| `untyped_doc` | step 4 |
| any other of this skill | rewrite what it names per `specstone guide <type>`; one no write clears goes to step 6 |

## 3. Point and cover code

- **`implements` on a spec doc:** move each entry to the `implements` of the story or FR whose behavior that code
  does (ask the Owner when unsure), then drop the doc's key.
- **`architecture_missing`:** run `specstone new architecture --parent <feature>`, fill it, and list in `covers` the
  code its stories and FRs point at.
- **`code_uncovered`:** add the file or its folder to `covers` on the architecture or topic doc describing it; with
  none, ask the Owner, then `specstone new topic --slug <slug>`.

## 4. Merge an old file

An `untyped_doc` under `specs/` is an old file the migration left. Merge it into the doc that takes it, else one
from `specstone new`:

- one feature's old-named spec files: their type's doc (`--parent <feature>`);
- an event or message schema: an internal one, such as stdout lines, to the architecture doc's `## Interaction`, an
  outside system's to the integration doc's `## Events`;
- a migration or rollout note: the architecture doc's `## Rollout`;
- a folder under `specs/topics/`: its topic (`--slug <folder>`);
- `specs/INDEX.md`: each code path in it to `covers` and the `code` roots (step 6), the source-of-truth table to the
  API docs, a cross-cutting statement to the tech stack's `## Constraints` or a topic doc; drop, as a step 6
  proposal, what only describes the old index.

Never target the old file: a write refuses it. Add its path to the retire set, a list for this run only, even when
the doc held its content.

## 5. Retire the old files

1. Run `specstone refs <path>` per file of the set; each `Inbound`, `Mentions`, or `Untyped mentions` line is a
   referrer.
2. Referrers inside the set never block. An old untyped doc under `prds/` or `specs/` joins the set, as no write
   repoints it; merge it first (`specstone:bootstrap-prd` takes one under `prds/`). Leave any other untyped file,
   such as a plan or a ledger, as history. Repoint each other link or mention to the doc holding the content, or
   drop a mention nothing replaces.
3. Delete the set through `specstone:expert-sdd`'s Owner confirmation, one command naming every path, quoting each
   path with a space:

```
specstone delete <path> <path> …
```

Exit 77: a file without `draft: true` is approved and needs the Owner's word. Exit 64 `doc_referenced`:
repoint the referrers it lists, then ask again.

## 6. Fill the tech stack, then ask for approval

The migration's `specs/TECH_STACK.md` holds a bare-name title and empty sections that `specstone check` skips.
With the Owner, fill `tech_stack:tech_stack`: title, each section `specstone guide tech_stack` names, and `code`,
each code folder from the code root (`code_root` in `.specstone/config.yaml`, else the project root). Write
PROJECT's old `## Tech stack` to `## Stack` and its `## Naming canonicalization` to `## Naming`, then drop each PRD
section. Fill each doc step 3 or 4 made the same way. Then rerun `specstone check`: new roots can raise
`code_uncovered`.

Last, name per draft each change, moved pointer, dropped key or section, and finding no write clears; then get each
draft approved through step 5's Owner confirmation.

## Red flags

| Thought | Do instead |
|---|---|
| "`git rm` is quicker." | Never: links break unseen. |
