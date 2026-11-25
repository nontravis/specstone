# The author's report

```
Drafts for the Owner's specstone approve <type>:<name>: <type>:<name>, ...
Decision: D<n> -> <type>:<name>#<key>, …
Not landed: D<n>: <why no doc took it>
Readers: <type>:<name>#<key> changed|linked|unaffected: <why>
Elsewhere: <type>:<name>#<key>: <why>
Move: <plan file path>
Rename: specstone rename <doc> --to <slug>
Delete: <type>:<name>
Open questions: <each point only the Owner's answer settles that a draft must state>
Check: <path>
Counts: <count> drafts; <type>:<name>: <d> dropped, <n> new; ...
Other drafts: <type>:<name>, ..., or none
Findings: <each finding left after step 5, each reason the change note lacks, or none>
```

- One `Decision:` line per decision of your share; a `NOT LANDED` one also gets its `Not landed:` line. Each
  `Not landed: D<n>:` line names one change note decision by its `D<n>`; a builder check fix you cannot apply goes
  under `Findings:`, never `Not landed:`.
- A later round appends to the same report file under `## Round <n>`, never a new file. Its `Decision:` line lands a
  decision an earlier round left `NOT LANDED`, naming each section that took it, another writer's included. Approval
  reads both lines by `D<n>` per report file: the last line in your file decides your file's state, and a decision it
  leaves open stays open until a `Decision:` line in another writer's file lands it.
- One `Readers:` line per reader found; one `Elsewhere:` line per reader in a doc outside your share. As a group
  writer, give a decision only such docs take an `Elsewhere:` line too, its why naming the `D<n>`, and no `Decision:`
  or `Not landed:` line.
- `Move:` for a moved doc, item, or scenario: one line naming the move plan file that holds every move, copied to the
  relay block, at `<folder>/reports/sdd-engineer.author.plan.<XXXXXX>.txt`, its lines per
  `../../specstone-expert-sdd/references/size-fix.md`. Run no `move` except `move --plan-out … --out` into that file.
  `Rename:` one line per doc to rename; run no `rename`. `Delete:` one line per doc to delete.
- `Open questions:` one line per point; main asks them in its one round.
- Drafts: every doc you wrote or confirmed again, named as `approve --dry-run` prints it, no `--target`; a moved doc by
  its old name until its `Move:` runs.
- Counts: from one `specstone approve --dry-run --json` after your last write, for your drafts only; list each other
  draft it shows under `Other drafts:`, never counted. A doc of yours it shows as no draft goes under `Findings:`.
- `Check:` names the saved file of your bare `check` after your last write, never a `--repeats` file.
