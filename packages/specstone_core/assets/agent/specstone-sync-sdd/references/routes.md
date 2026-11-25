**Routes of a sync** (SKILL.md step 2): the first call prints one route word per group.

## Routes

| Route word | Group | Who runs it, and when |
|---|---|---|
| `small` | Only `code_suspect` findings on `covers` entries, a record's included, few changed lines, no draft, as the first call judged | You, beside the engineers: fill its group file's verdict part in place and write it in one `specstone set --sync` |
| `engineer` | A top-level feature, or a doc under no feature (a topic, a skill, an agent, a project spec doc, the tech stack) | An engineer, dispatched at once with every other `engineer` group |
| `last` | `uncovered`: each code file no doc covers | One engineer, after every other group's report |

- A record sits in its top feature's group; a group holding a record's `implements` entry is never small.
- A feature the Owner named is one group, never small.

## Small group

- Judge each link of its group file as `procedure.md` judges a group file, from that file alone.
- Fill the verdict part in place, then write the file by one `specstone set --sync`; it writes only that group's docs.
- A mismatch, any doubt, text ahead of the code, a `draft: true` you meet, or any line `specstone set --sync` refuses hands the whole group to an engineer of its route, with the same group file.
- At a plan's last sync, a group whose work holds a decided behavior no spec states hands the whole group to an engineer of its route, which drafts it.

## Order

1. Dispatch every `engineer` group at once; judge each `small` group while they run.
2. After every other group's report, dispatch the `last` group.

- Every later dispatch or walk judges from the first call's group file and runs no second `context --for sync`: the `last` group, a small group handed on, a pick sent back, your walk of a group with no subagent or after a failed dispatch.
- It judges again only the lines `specstone set --sync` refuses `stamp_stale`.
- A pick sent back routes as its group does.
