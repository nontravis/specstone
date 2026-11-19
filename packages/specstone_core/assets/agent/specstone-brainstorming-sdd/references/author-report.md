# The author's report

`author.md` reads this for its step 5.

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
Findings: <each finding left after step 4, each finding or hit outside the drafts, or none>
```

- **Design**: `<N>`, the last amend or `0`; the relay block's first line too.
- **Drafts**: every doc you wrote or confirmed again; in a later pass, step 1's list less dropped names, plus docs
  added; names only, no `--target`. Moved docs and their children go by new names.
- **Counts**: take each count from one `specstone approve --dry-run --json` after your last write, for your list's docs;
  it names a moved one by its old name until its `Move:` line runs. Name each other draft it lists under `Other
  drafts:`, never counted; one of yours it shows as no draft goes under `Findings:`.
- **Move**: only for a moved doc, item, or scenario: one line per target parent or `--top`, copied to the relay
  block. Run no `move`.
