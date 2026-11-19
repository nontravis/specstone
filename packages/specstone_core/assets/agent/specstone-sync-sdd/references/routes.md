**Routes of a sync** (SKILL.md step 2). Each group takes one route, run in 3 steps: the feature engineers at once,
your small groups beside them, then the last route.

| Group | Route |
|---|---|
| Small (below) | You: judge it and stamp a match |
| A top-level feature, not small | An engineer, dispatched at once with every other such group |
| A doc under no feature (a topic, a project spec doc, the tech stack), or `uncovered` | An engineer, one at a time, after every feature group's report |

Each `architecture:<feature>` doc sits in its top feature's group. A feature the Owner named is never small.

## Small group

All of these hold, else the group goes to its route above:

- Every finding is a `code_suspect` one on a `covers` entry of a doc under `docs/`. A `code_unconfirmed` finding and a
  record's `implements` entry have no base, so their groups are never small.
- Each entry has a base by `procedure.md` step 4.1 (`git log -1 --format=%H -S '<recorded>' -- docs/<DocPath>`).
- The files changed under the entries since those bases total at most 40 lines, added plus removed
  (`git diff --numstat <base> -- <prefix>`), and no untracked file lies under their prefixes
  (`git ls-files --others --exclude-standard -- <prefix>`).
- No covering doc prints `draft: true`.

Judge it: run `specstone context <doc> --for implement --out` per covering doc, as `procedure.md` step 3 gives, search
the entry's sections, and read the diff. A match is code that does what the approved text states today; approved text
ahead of the code is no match. Stamp a match with
`specstone set <doc> --stamp <entry>=<fingerprint>`, the `<entry>` as the doc holds it before its fingerprint, the
`<fingerprint>` the finding's, and `--target <name>` when the project has two or more. A stamp touches only that
group's docs.

A mismatch, any doubt, a `draft: true` you meet, or any refused stamp hands the whole group to an engineer of its
route. That engineer runs its own check first.

## Order

- Dispatch every feature engineer first, then judge the small groups while they run, then the last route. Each feature
  engineer takes the gate file, since it writes only its own scope's docs while they run.
- Every later dispatch or walk takes no gate file and runs its own check first, `check <scope> --out` for a feature or
  a doc, a bare `check --out` for `uncovered`: the last route, a small group handed on, a pick sent back, and your own
  walk of a group after its first on a host with no subagent or after a failed dispatch.
- A pick sent back routes as its group does.
