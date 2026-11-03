`specstone:sdd-engineer` runs this in `mode: author`, its gate already made; so does the runner of
`specstone:brainstorming-sdd` when it has no `Agent` tool or the dispatch failed. As the agent, ask the Owner
nothing: each gap goes into your report.

Write every doc through the CLI, per `specstone:expert-sdd`: each write leaves a draft.

## 1. Read

- **Design document**: the Owner-approved document's path. Read it whole, and list each decision, each ruling, and
  each row of its Docs to change by its ID or label.
- **Audit findings and drafts** (a fix round): the audit's `Findings:` lines and the drafts list, the first author
  report's drafts plus each doc a fix round added, as `<type>:<name>`. Fix only those findings, and only in those
  drafts, as step 2 writes; then go to step 4.
  List each finding that points outside those drafts under `Findings:`, unfixed.

## 2. Place each decision

Place each decision in a doc, noting the doc and section. A decision no doc can take is not landed: flag it, never
force it. Write each Docs to change row that carries no decision too, such as a `design_references` link.

- **Guide**: run `specstone guide <type>` before the first write of each type.
- **New doc**: pipe its text to `specstone new <type>` (`--parent <name>`, `--slug <slug>`, as the type takes
  them), parents first.
- **Section**: base from the naming line of `specstone get <type>:<name>#<key>`; pipe the body to
  `specstone set <type>:<name>#<key> --base <hash>`.
- **Field**: base from `bases.fields.<id>` of `specstone get <type>:<name> --json`; pipe the value to
  `specstone set <type>:<name> --field <id> --base <hash>`.

## 3. Sweep each ruling

For each dated ruling that names text it supersedes, run `specstone search "<superseded wording>"`. Rewrite every
hit in a doc the design changes, as step 2 writes. List each hit in any other doc under `Findings:`, and leave it.

## 4. Check

Run a bare `specstone check` before your first write (as the agent, the gate's run is that baseline) and again
after your last. For each finding the second run adds:

- **In one of your drafts:** fix it there.
- **A `suspect` link in a doc you did not write:** your write moved its upstream. Confirm it again per
  `specstone:expert-sdd`; that doc joins your drafts. When you cannot, list it under `Findings:`.
- **An `unconfirmed` link on a draft:** it waits for the Owner's approval; leave it.

## 5. Report

```
Not landed: <decision>: <why no doc took it>
| Decision | Doc that took it |
|----------|------------------|
| <ID or label> | <type>:<name>#<key>, or NOT LANDED |
Rulings swept: <ruling>: <type>:<name>#<key>, ..., or none
Drafts for the Owner's specstone approve <type>:<name>: <type>:<name>, ...
Findings: <each finding left after step 4, each finding or hit outside the drafts, or none>
```

- **Rows**: one per decision; in a fix round, one per finding. `Not landed:` lines come first, read before any
  approval.
- **Drafts**: every doc you wrote or confirmed again; in a fix round, the first author report's drafts plus each doc
  a fix round added, this one's included. The audit and plan modes take this list.
