`specstone-sdd-auditor`, its gate made, runs this for `job: trim-audit`. Write only the agent's `report:` file, no
fix; ask the Owner nothing.

## Trim audit

`job: trim-audit` takes `targets`, the round's drafts, and `trims`, the paths of the round's bootstrap reports. Main
sends its `Findings:` lines into the fix loop of `../../specstone-expert-sdd/references/fix-loop.md`, whose re-reviews
follow `re-review.md`, never a second trim audit.

1. **Hashes**: run one `specstone approve <targets> --dry-run --json`, no `--target`: its `base` per draft is the
   `Audited:` hash. On `doc_not_found`, drop each name it names and run it again on the rest. A named doc it does not
   list is no draft; its hash is the whole-doc `base` of `specstone get <doc> --json`.
2. **Ground**: run one `specstone context <draft> <draft> --for design --out` naming each target, each target read
   whole.
3. **Trim lens**: read each deleted, moved, and cut item against the guide line its `trims` report names, and each
   rewritten cite against the cite table of `../../specstone-expert-sdd/references/trim.md`. A removed item stating
   behavior no other doc states is a `Findings:` line whose fix restores it. A contract part the `fr` guide names for
   a skill or agent is behavior to restore, and a removed step, per trim.md, is none.

```
Findings:
- <type>:<name>#<section>: <gap>
Outside the drafts:
- <doc whose fix it is>: <gap whose fix lies in no draft of the round>
Notes:
- <observation>
Audited: <type>:<name>@<hash>
```

- `Findings:` holds each wrong citer or trimmed item, which the fix loop takes. A gap in a draft goes under
  `Findings:`, never under `Outside the drafts:`.
- `Outside the drafts:` holds each gap whose fix lies in no draft of the round, such as a `Citers outside:` line a
  bootstrap report hands on.
- Each item under `Outside the drafts:` opens with the name of the doc where its fix lies, never a draft of the round.
- Put each observation that is no gap under `Notes:`, which the judge never reads and main relays to the Owner.
  Write no `Notes:` heading when there is none.
- Write one `Audited:` line per target, its hash the `base` of step 1.
- Write `none` under an empty heading, `Notes:` excepted.
