---
name: bootstrap-spec
description: Use when the spec docs of a Specstone project lag behind its format after `specstone migrate`, a new pack version, or an edited template, such as `specstone check` findings under `specs/`, `architecture_missing`, `code_uncovered`, a still-empty `TECH_STACK.md` draft, or another `specstone:` skill naming `specstone:bootstrap-spec`.
---

# Bring the spec docs up to the new format

This skill takes `specstone check` findings under `specs/`, plus `architecture_missing` and `code_uncovered`.
Findings under `prds/` go to `specstone:bootstrap-prd`, except the PRD section step 6 moves. Follow
`specstone:expert-sdd` for every write: each one leaves a draft, a pointer write (`implements`) excepted.

## 1. Gate: the first call

```
specstone check
```

- **78, `project_not_found`:** tell the Owner the project has not moved to the new format; `specstone migrate`
  moves it, or they keep the old skills. Stop: run nothing more, and read or write no doc.
- **0 or 1:** go on, even from a subfolder. Never look for `.specstone/` yourself.
- **Any other exit:** report the CLI's error and stop.

## 2. One finding at a time

Take the first unhandled finding of this skill, fix it, and run `specstone check` again with no target (a targeted
run omits `code_uncovered`). Repeat until each finding left is one under `prds/`, one no write clears, or one that
waits on the Owner.

Bases come from `specstone get <type>:<name> --json` (`bases.title`, `bases.sections.<key>`, `bases.fields.<id>`);
each write prints the new one. Pipe the text to `specstone set <type>:<name>#<key> --base <hash>` (`--field <id>` or
`--title` in place of `#<key>`); a section body leaves out its `## ` line, a list field takes its whole list, and
empty text drops the section or key: never edit the file. Exit 75 `base_mismatch`: read again, merge, retry.

For any finding a write clears: write nothing a doc of the project already holds (cite where in step 6); where the
old text lacks what the guide needs, write a proposal from the project's own text, named in step 6; ask the Owner
only when no text bears on it.

| Finding | Fix |
|---|---|
| `required_section_missing`, `required_field_missing`, `title_missing` | fill it from the old text |
| `section_undeclared` | merge each statement into the section that takes it, else the closest; once each stands, drop the section |
| `field_undeclared` on `implements`, `architecture_missing`, `code_uncovered` | step 3 |
| `field_undeclared`, any other | write its value into the field that takes it, then drop the key |
| `covers_path_missing`, `code_root_missing` | fix the entry with the Owner, or drop it |
| `untyped_doc` | step 4 |
| any other of this skill | rewrite the section or field it names per `specstone guide <type>`; one no write clears goes to step 6 |

## 3. Point and cover code

- **`implements` on a spec doc:** write each entry into the `implements` field of the story or FR whose
  behavior that code does; ask the Owner when unsure. Then drop the doc's key.
- **`architecture_missing`:** run `specstone new architecture --parent <feature>`, fill it, and list in `covers` the
  code its stories and FRs point at.
- **`code_uncovered`:** add the file or its folder to `covers` on the architecture or topic doc describing it; with
  none, ask the Owner and run `specstone new topic --slug <slug>`.

## 4. Merge an old file

An `untyped_doc` under `specs/` is an old file the migration left as it was. Merge it into the doc that takes it;
only when none exists, make one with `specstone new`:

- one feature's old-named spec files: their type's doc (`--parent <feature>`);
- an event or message schema: an internal one, such as stdout lines, into the architecture doc's `## Interaction`,
  an outside system's into the integration doc's `## Events`;
- a folder under `specs/topics/`: its topic (`--slug <folder>`);
- `specs/INDEX.md`: each code path in it to `covers` and the `code` roots (step 6), the source-of-truth table to the
  API docs, a cross-cutting statement to the tech stack's `## Constraints` or a topic doc; drop, as a step 6
  proposal, what only describes the old index.

Never target the old file: a write refuses an untyped doc. Add each file's path to the retire set, a list for this
run only, even when the doc held its content.

## 5. Retire the old files

1. Run `specstone refs <path>` per file of the set; its `Inbound` and `Mentions` lines are the referrers.
2. Referrers inside the set never block. An old untyped referrer joins the set, as no write repoints it; merge it
   first (`specstone:bootstrap-prd` takes one under `prds/`). Repoint each other link or mention to the doc now
   holding the content, or drop a mention nothing replaces.
3. Delete the set through `specstone:expert-sdd`'s Owner confirmation (terminal or chat), one command naming every
   path, quoting each path that holds a space:

```
specstone delete <path> <path> …
```

Exit 77: a file without `draft: true` counts as approved and needs the Owner's word. Exit 64 `doc_referenced`:
repoint the referrers it lists, then ask again.

## 6. Fill the tech stack, then ask for approval

The migration's `specs/TECH_STACK.md` holds a bare-name title and empty sections that `specstone check` never lists.
With the Owner, fill `tech_stack:tech_stack`: title, each section `specstone guide tech_stack` names, and
`code`, each code folder from the project root. Write PROJECT's old `## Tech stack` into `## Stack` and its
`## Naming canonicalization` into `## Naming`, then drop each PRD section. Fill each doc step 3 or 4 made the same
way. Then run `specstone check` again: new roots can raise `code_uncovered`.

Last, name each change per draft, each moved pointer, each dropped key or section, and each finding no write clears.
Then get each draft approved through the Owner confirmation step 5 names.

## Red flags

| Thought | Do instead |
|---|---|
| "`git rm` is quicker." | Never: links break unseen. |
