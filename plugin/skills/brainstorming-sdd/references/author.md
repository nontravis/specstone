`specstone:sdd-engineer` runs this in `mode: author`, its gate already made; so does the runner of
`specstone:brainstorming-sdd` when it has no `Agent` tool or the dispatch failed. As the agent, ask the Owner
nothing: each gap goes into your report.

Write every doc through the CLI, per `specstone:expert-sdd`: each write leaves a draft.

## 1. Read

- **Design document**: the Owner-approved document's path. Read it whole, and list each decision, each ruling, and
  each row of its Docs to change by its ID or label.
- **Drafts** (each pass after the first: a fix round, or the pass after an amend): the drafts list, the first
  author report's drafts plus each doc a fix round or pass added; in a fix round, the audit's `Findings:` lines too.
  Before your first write, re-read the drafts in one `specstone get <drafts list>` call. When it refuses with
  `doc_not_found`, drop each name it names and run it again on the rest; list each dropped name under `Findings:`, or
  as `Not landed:` when listed and never created. After an amend, write the amended design into the drafts through
  steps 2 and 3. Fix only those findings, only in those drafts, as step 2 writes; then go to step 4. List each finding
  outside those drafts under `Findings:`, unfixed.

## 2. Place each decision

Place each decision in a doc, noting the doc and section. A decision no doc can take is not landed: flag it, never
force it. Write each Docs to change row that carries no decision too, such as a `design_references` link.

- **Guide**: before your first write, run `specstone guide <type> …` once, naming every type you write.
- **New doc**: pipe its text to `specstone new <type>` (`--parent <name>`, `--slug <slug>`, as the type takes
  them), parents first.
- **Section**: base from the naming line of `specstone get <type>:<name>#<key>`; pipe the body to
  `specstone set <type>:<name>#<key> --base <hash>`.
- **Field**: base from `bases.fields.<id>` of `specstone get <type>:<name> --json`; pipe the value to
  `specstone set <type>:<name> --field <id> --base <hash>`.
- **Several docs in one step**: run `specstone get <names> > <file>`, `<file>` a `mktemp` file outside the
  repository; edit its blocks with `Edit`, each naming line kept; then run `specstone set --batch <file>`. A block
  printed ` · unchanged` wrote nothing and adds no draft.
- **A refused batch** writes nothing (`document_writing/edit_one_section_or_field/write_a_batch`). Per fault, then
  run it again:
  - Stale block: replace the block with the one the reply prints, your edit merged in; run no `get`.
  - Gone block: re-read its doc by name; a moved doc's new block takes the edit; a name naming no doc drops the
    block, its doc listed under `Findings:`.
  - Untyped block: drop it, its doc listed under `Findings:`.
  - One part twice, or a whole-doc block beside another of its doc: join them.
  - Field or title block: write it inside its doc's whole-doc block.
  - Removed required section: restore it; a field only the Owner or Specstone sets: restore its value; open
    fence: close it.
  - Any other refusal a single `set` of that part makes, such as `field_unknown` or a section block's stray `##`
    line: fix that part as the refusal names.
  - Refused path or line: rebuild the file from `get` text output alone; pass its path, nothing on stdin.

## 3. Sweep each ruling

For each dated ruling that names text it supersedes, run `specstone search "<superseded wording>"`. Rewrite every
hit in a doc the design changes, as step 2 writes. List each hit in any other doc under `Findings:`, and leave it.

## 4. Check

Run a bare `specstone check` before your first write (as the agent, the gate's run is that baseline) and again
after your last. For each finding the second run adds:

- **In one of your drafts:** fix it there.
- **A `suspect` link in a doc you did not write:** your write moved its upstream. Confirm it again per
  `specstone:expert-sdd`; that doc joins your drafts. When you cannot, list it under `Findings:`.
- **A finding whose `waitsFor` is `owner`**, its line ending `(waits for the Owner)`: leave it as it is, never write
  around it, and list it.

## 5. Report

```
Not landed: <decision>: <why no doc took it>
Not landed: <type>:<name>: listed and never created
| Decision | Doc that took it |
|----------|------------------|
| <ID or label> | <type>:<name>#<key>, or NOT LANDED |
Rulings swept: <ruling>: <type>:<name>#<key>, ..., or none
Drafts for the Owner's specstone approve <type>:<name>: <type>:<name>, ...
Counts: <count> drafts; <type>:<name>: <d> dropped, <n> new; ...
Other drafts: <type>:<name>, ..., or none
Move: specstone move <story> … --under <feature>
Move: specstone move <story> … --under <other feature>
Findings: <each finding left after step 4, each finding or hit outside the drafts, or none>
```

- **Rows**: one per decision; in a fix round, one per finding. `Not landed:` lines come first, read before any
  approval.
- **Drafts**: every doc you wrote or confirmed again; in a later pass, the drafts list less each name step 1
  dropped, plus each doc this pass added. The audit and plan modes take this list as it is: names only. Name each
  draft a `Move:` line moves, the story and its FRs, by the name it holds after the move.
- **Counts**: on the `Counts:` line, take every count, of drafts and of sentences dropped and new, from one
  `specstone approve --dry-run --json` after your last write, never your own tally. Your drafts are the docs your own
  list names; the output names a moved one, while its `Move:` line is unrun, by its name before the move; once the
  runner runs it, by its name after. Name each other draft it lists under `Other drafts:`, never counted; one of
  yours it shows as no draft goes under `Findings:`.
- **Move**: only when the design moves stories, one line per target feature; copy each into the relay block. Run no
  `move`: the runner of `specstone:brainstorming-sdd` runs each line's command before the audit.
