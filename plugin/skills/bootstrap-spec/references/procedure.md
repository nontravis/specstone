Step 1, the gate, already ran in the skill or agent that sent you here.
As `specstone:sdd-engineer`, ask the Owner nothing: each step with the Owner goes into your report.

This skill takes `specstone check` findings under `specs/`, plus `architecture_missing` and `code_uncovered`.
Findings under `prds/` go to `specstone:bootstrap-prd`, except the PRD sections step 6 moves. Follow
`specstone:expert-sdd` for every write; before the first, run `specstone guide <type> …` once,
naming every type you write; a type met later gets its own call before its first write.

**Code target** (two or more `targets:`, `domain:agent_plugin` INV-25): each `new`, `get`, and `set` of a per-target
doc carries `--target <name>`, the finding DocPath's code target, else the first listed one.

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
| any other of this skill | rewrite what it names per the guide you loaded; one that clears with no write goes to step 6 |

## 3. Point and cover code

- **`implements` on a spec doc:** move each entry to the record entry of the story or FR that code
  serves, then drop the key.
- **`architecture_missing`:** run `specstone new architecture --parent <feature>`, fill it, and list in `covers` the
  code its record entries name.
- **`code_uncovered`:** add the file or its folder to `covers` on the architecture or topic doc describing it; with
  none, ask the Owner, then `specstone new topic --slug <slug>`.

## 4. Merge an old file

An `untyped_doc` under `specs/`: merge it into the doc that takes it, else a new one:

- one feature's old-named spec files: their type's doc (`--parent <feature>`);
- an event or message schema: an internal one to the architecture doc's `## Interaction`, an
  outside system's to the integration doc's `## Events`;
- a migration or rollout note: the architecture doc's `## Rollout`;
- a folder under `specs/topics/`: its topic (`--slug <folder>`);
- `specs/INDEX.md`: each code path in it to `covers` and the `code` roots (step 6), the source-of-truth table to the
  API docs, a cross-cutting statement to the tech stack's `## Constraints` or a topic doc; quote in step 6 each line
  only about the old index, as a line with no home.

Skip only a sentence its new doc holds word for word, and never target the old file: a write refuses it. Add its path
to this run's retire set.

## 5. Retire the old files

1. Run `specstone refs <path>` per file of the set; each `Inbound`, `Mentions`, or `Untyped mentions` line is a
   referrer.
2. Referrers inside the set never block. An old untyped doc under `prds/` or `specs/` joins the set, as no write
   repoints it: merge it first (`specstone:bootstrap-prd` takes one under `prds/`). A batch's set holds only
   files it merged; list each untyped referrer outside it, with the file it names, for its owner to merge. Leave any
   other untyped file as history. Repoint each other link or mention to the doc holding the content, or drop one
   nothing replaces.
3. Name the set in one `specstone delete` line, quoting each path with a space:

```
specstone delete <path> <path> …
```

On a batch, delete nothing: hand that line to `specstone:bootstrap-spec`'s step 3.4.
With no batch, run it through `specstone:expert-sdd`'s Owner confirmation. Never run `git rm`: links break unseen.
Exit 64 `doc_referenced`: repoint the referrers it lists, then ask again.

## 6. Fill the tech stack, then ask for approval

`specstone check` skips the migration's empty `specs/TECH_STACK.md`. With the Owner, fill `tech_stack:tech_stack` per
the guide you loaded, and `code`, each code folder under that target's code root in the config's `targets:`, or `code_root` for an unnamed one, else the project
root. Write PROJECT's old `## Tech stack` to `## Stack` and its `## Naming canonicalization` to `## Naming`, then drop
each PRD section.

Last, take every count from one `specstone approve --dry-run --json` after your last write. Your drafts are the docs
your own list names; name each other draft it lists, never counted; one of yours it shows as no draft is a finding.
Name per draft each change, moved pointer, dropped key or section, and finding that clears with no write; then get
each approved through step 5's Owner confirmation.
