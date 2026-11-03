`specstone:sdd-engineer` runs this in `mode: author`, its gate already made; so does the runner of
`specstone:brainstorming-sdd` when it has no `Agent` tool or the dispatch failed. As the agent, ask the Owner
nothing: each gap goes into your report.

Write every doc through the CLI, per `specstone:expert-sdd`: each write leaves a draft.

## 1. Read

- **Design document**: the Owner-approved document's path. Read it whole, and list each decision and each ruling by
  its ID or label.
- **Audit findings and drafts** (a fix round): the audit's `Findings:` lines and the `<type>:<name>` drafts the
  first author report listed. Fix only those findings, and only in those drafts, as step 2 writes; then go to step 4.
  List each finding that points outside those drafts under `Findings:`, unfixed.

## 2. Place each decision

Place each decision in a doc, noting the doc and section. A decision no doc can take is not landed: flag it, never
force it.

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

Run `specstone check <target>` once per doc you wrote, and fix each finding your writes added. An `unconfirmed`
link on a draft waits for the Owner's approval: leave it.

## 5. Report

```
Main session: show this report to the Owner whole before you act on it.
Not landed: <decision>: <why no doc took it>
| Decision | Doc that took it |
|----------|------------------|
| <ID or label> | <type>:<name>#<key>, or NOT LANDED |
Rulings swept: <ruling>: <type>:<name>#<key>, ..., or none
Drafts for the Owner's specstone approve <type>:<name>: <type>:<name>, ...
Findings: <step 4's lines, each finding or hit outside the drafts, or none>
```

- **Rows**: one per decision; in a fix round, one per finding. `Not landed:` lines come first, read before any
  approval.
- **Drafts**: every doc you wrote, a fix round's included; the audit and plan modes take this list.
