**Routes of a sync** (SKILL.md step 2): the first call prints one route word per group.

## Routes

| Route word | Group | Who runs it, and when |
|---|---|---|
| `small` | Only `code_suspect` findings on `covers` entries, a record's included, few changed lines, no draft, as the first call judged | You, beside the engineers: fill its group file's verdict part in place and write it in one `specstone set --sync` |
| `engineer` | A top-level feature, or a doc under no feature | An engineer, dispatched at once with every other `engineer` group |

- A record sits in its top feature's group; a group holding a record's `implements` entry is never small.
- A feature the Owner named is one group, never small.

## Small group

- Judge each link of its group file as `engineer.md` steps 1 and 2 judge a group file, from that file.
- Fill the verdict part in place, then write the file by `engineer.md` step 3's one `specstone set --sync`; it writes only that group's docs.
- A mismatch, any doubt, text ahead of the code, a `draft: true` you meet, or any line `specstone set --sync` refuses hands the whole group to an engineer of its route, with the same group file.
- At a plan's last sync, a group whose work holds a decided behavior no spec states hands the whole group to an engineer of its route, which judges the group's links against the decided line; the decided engineer of SKILL.md step 1 holds the draft.

## Order

1. Dispatch every `engineer` group at once; judge each `small` group while they run.

- At a plan's last sync the decided engineer is already dispatched by SKILL.md step 1, before every `engineer` group.
- Every later dispatch or walk judges from the first call's group file and runs no second `context --for sync`: a small group handed on, a pick sent back, your walk of a group with no subagent or after a failed dispatch.
- It judges again only the lines `specstone set --sync` refuses `stamp_stale`.
- A pick sent back routes as its group does.
