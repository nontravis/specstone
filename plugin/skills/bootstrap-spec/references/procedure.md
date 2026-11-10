Step 1, the gate, already ran in the skill or agent that sent you here.
As `specstone:sdd-engineer`, ask the Owner nothing: each step with the Owner goes into your report.

This skill takes `specstone check` findings under `specs/`, plus `architecture_missing` and `code_uncovered`.
Findings under `prds/` go to `specstone:bootstrap-prd`, except the PRD sections step 6 moves. Follow
`specstone:expert-sdd` for every write; before the first, run `specstone guide <type> …` once,
naming every type you write.

## 2. One finding at a time

Fix this skill's first unhandled finding, then run a bare `specstone check` again (a targeted run omits
`code_uncovered`). Stop when each finding left is under `prds/`, clears with no write, or is tagged
`(waits for the Owner)`, except an unanswered size finding.

Bases come from `specstone get <type>:<name> --json` (`bases.title`, `bases.sections.<key>`, `bases.fields.<id>`);
each write prints the new one. Pipe the text to `specstone set <type>:<name>#<key> --base <hash>` (`--field <id>` or
`--title` in place of `#<key>`); a section body leaves out its `## ` line, a list field takes its whole list, and
empty text drops the section or key. The text between the title and the first `##` section is `#_lead`. Exit 75
`base_mismatch`: read again, merge, retry.

Quote a node label that holds `(`, `)`, `[`, `]`, `{`, or `}`, as in `A["Save (draft)"]`; write `"` in it as
`#quot;`.

Where the old text lacks a value the guide needs, write `TBR — <why>` in its place, never a value you propose. Ask
the Owner only when no text bears on a whole section.

| Finding | Fix |
|---|---|
| `required_section_missing`, `required_field_missing`, `title_missing` | fill it from the old text |
| `section_undeclared` | move each statement into the section that takes it, else the closest, even if another doc holds it; then drop the section |
| `field_undeclared` on `implements`, `architecture_missing`, `code_uncovered` | step 3 |
| `field_undeclared`, any other | move its value to the field that takes it, then drop the key |
| `covers_path_missing`, `code_root_missing` | fix the entry with the Owner, or drop it |
| `untyped_doc` | step 4 |
| `chars_over_limit`, `lines_over_limit`, `item_over_limit` | `${CLAUDE_PLUGIN_ROOT}/skills/expert-sdd/references/size-fix.md` |
| any other of this skill | rewrite what it names per its guide; one that clears with no write goes to step 6 |

## 3. Point and cover code

- **`implements` on a spec doc:** move each entry to the `implements` of the story or FR whose behavior that code
  does (ask the Owner when unsure), then drop the doc's key.
- **`architecture_missing`:** run `specstone new architecture --parent <feature>`, fill it, and list in `covers` the
  code its stories and FRs point at.
- **`code_uncovered`:** add the file or its folder to `covers` on the architecture or topic doc describing it; with
  none, ask the Owner, then `specstone new topic --slug <slug>`.

## 4. Merge an old file

An `untyped_doc` under `specs/` is an old file the migration left. Merge it into the doc that takes it, else a new one:

- one feature's old-named spec files: their type's doc (`--parent <feature>`);
- an event or message schema: an internal one, such as stdout lines, to the architecture doc's `## Interaction`, an
  outside system's to the integration doc's `## Events`;
- a migration or rollout note: the architecture doc's `## Rollout`;
- a folder under `specs/topics/`: its topic (`--slug <folder>`);
- `specs/INDEX.md`: each code path in it to `covers` and the `code` roots (step 6), the source-of-truth table to the
  API docs, a cross-cutting statement to the tech stack's `## Constraints` or a topic doc; quote in step 6 each line
  only about the old index, as a line with no home.

Skip only a sentence its new doc holds word for word, and never target the old file: a write refuses it. Add its path
to the retire set, a list for this run only.

## 5. Retire the old files

1. Run `specstone refs <path>` per file of the set; each `Inbound`, `Mentions`, or `Untyped mentions` line is a
   referrer.
2. Referrers inside the set never block. An old untyped doc under `prds/` or `specs/` joins the set, as no write
   repoints it; merge it first (`specstone:bootstrap-prd` takes one under `prds/`). On a batch, the set holds only
   files the batch merged: list an untyped referrer outside the batch, with the file it names, for its owner to merge.
   Leave any other untyped file (a plan, a ledger) as history. Repoint each other link or mention to the doc
   holding the content, or drop a mention nothing replaces.
3. Name the set in one `specstone delete` line, quoting each path with a space:

```
specstone delete <path> <path> …
```

On a batch, delete nothing: hand that line to `specstone:bootstrap-spec`'s step 3.4.
With no batch, run it through `specstone:expert-sdd`'s Owner confirmation. Exit 64 `doc_referenced`: repoint the
referrers it lists, then ask again.

## 6. Fill the tech stack, then ask for approval

`specstone check` skips the migration's empty `specs/TECH_STACK.md`. With the Owner, fill `tech_stack:tech_stack` per
its guide, and `code`, each code folder under `code_root` in `.specstone/config.yaml`, else the project root. Write
PROJECT's old `## Tech stack` to `## Stack` and its `## Naming canonicalization` to `## Naming`, then drop each PRD
section. Fill each doc step 3 or 4 made the same way. Then rerun `specstone check`: new roots can raise
`code_uncovered`.

Last, take every count from one `specstone approve --dry-run --json` after your last write. Your drafts are the docs
your own list names; name each other draft it lists, never counted; one of yours it shows as no draft is a finding.
Name per draft each change, moved pointer, dropped key or section, and finding that clears with no write; then get
each approved through step 5's Owner confirmation.

## Red flags

| Thought | Do instead |
|---|---|
| "`git rm` is quicker." | Never: links break unseen. |
