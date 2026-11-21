# The author's report

```
Design: <path>, amend <N>
Not landed: <decision>: <why no doc took it>
Not landed: <type>:<name>: listed and never created, or <why no doc took this row>
| Decision or row | Doc that took it |
|---|---|
| <ID or label, or a row's <type>:<name>> | <type>:<name>#<key>, or NOT LANDED |
Drafts for the Owner's specstone approve <type>:<name>: <type>:<name>, ...
Counts: <count> drafts; <type>:<name>: <d> dropped, <n> new; ...
Other drafts: <type>:<name>, ..., or none
Move: specstone move <target> … --under <parent>, or … --top
Check: <path>
Guide: <txt path>, <json path>
Sections: <type>:<name>#<key>, …
Findings: <each finding left after step 4, each finding or hit outside the drafts, or none>
```

- `Design:` `<N>` is the last amend or `0`; it is also the relay block's first line.
- Drafts: every doc you wrote or confirmed again; a later pass: step 1's list less dropped names, plus added docs;
  names only, no `--target`; moved docs and their children by new names.
- Counts: from one `specstone approve --dry-run --json` after your last write, for your list's docs; it names a
  moved doc by its old name until its `Move:` runs. List each other draft it shows under `Other drafts:`, never
  counted; one of yours it shows as no draft, under `Findings:`.
- `Move:` only for a moved doc, item, or scenario: one line per target parent or `--top`, copied to the relay block.
  Run no `move`.
- `Sections:` one `<type>:<name>#<key>` per section this pass wrote: step 2's name list, each section found needed
  after edits began, and each sweep list together; a whole doc, one per section written. The re-audit reads them.
