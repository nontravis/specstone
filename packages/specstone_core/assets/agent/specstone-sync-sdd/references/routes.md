**Routes of a sync** (SKILL.md step 2).

- Each group takes one route, in 3 steps: feature engineers at once, your small groups beside them, then the last route.

| Group | Route |
|---|---|
| Small (below) | You: judge it and stamp a match |
| A top-level feature, not small | An engineer, dispatched at once with every other such group |
| A doc under no feature (a topic, a project spec doc, the tech stack), or `uncovered` | An engineer, one at a time, after every feature group's report |

- An `architecture:<feature>` doc sits in its top feature's group.
- A feature the Owner named is never small.

## Small group

Small only when all hold:

- Every finding is a `code_suspect` on a `covers` entry of a doc under `docs/`; a `code_unconfirmed` finding or an `implements` entry is never small.
- Each entry has a base (`procedure.md` step 4.1).
- Files changed under the entries since those bases total at most 40 lines, added plus removed (`git diff --numstat <base> -- <prefix>`), with no untracked file under their prefixes (`git ls-files --others --exclude-standard -- <prefix>`).
- No covering doc prints `draft: true`.
- Judge: run `specstone context <doc> --for implement --out` per covering doc (`procedure.md` step 3), search the entry's sections, read the diff; match per `procedure.md` step 4.2.
- Stamp a match by `specstone set <doc> --stamp <entry>=<fingerprint>`, `<entry>` as the doc holds it, the finding's fingerprint, `--target <name>` when two or more.
- Stamp only that group's docs; after each stamp, follow `task-refs.md` for that link.
- A mismatch, any doubt, text ahead of the code, a `draft: true` you meet, or a refused stamp hands the whole group to its route's engineer, which runs its own check first.

## Order

- Dispatch every feature engineer first, judge small groups while they run, then the last route.
- Each feature engineer takes the gate file.
- Every later dispatch or walk takes no gate file and runs its own check first, `check <scope> --out` for a feature or doc, bare `check --out` for `uncovered`: the last route, a small group handed on, a pick sent back, your walk of a group after its first with no subagent or after a failed dispatch.
- A pick sent back routes as its group does.
