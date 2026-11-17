`specstone-sdd-engineer` and the `specstone-brainstorming-sdd` runner run it in `mode: author`, the gate passed.
Ask the Owner nothing: list each gap in the report.

## 1. Read

- **Design document**: read it whole; list each decision, ruling, and Docs to change row.
- **Drafts** (each pass after the first): the drafts list, the first author report's drafts plus each doc a later
  pass added; in a fix round, the audit's `Findings:` lines too.
  Before your first write, re-read the drafts in one `specstone get <drafts list>` call. When it refuses with
  `doc_not_found`, drop each name it names and run it again on the rest; list each dropped name under `Findings:`, or
  as `Not landed:` when listed and never created. After an amend, write the amended design into the drafts through
  steps 2 and 3. Fix those findings in those drafts as step 2 writes, then sweep each one's terms as step 3 says; go
  to step 4. List each finding outside those drafts under `Findings:`, unfixed.

## 2. Place each decision

Save long `check`, `guide`, or `get` output with `--out`, not a redirect.

A decision no doc can take is not landed: flag it, never force it. Write each Docs to change row, one with no
decision too, as a `design_references` link, and give each a table row.

- **Guide**: before your first write, run `specstone guide <type> …` once, naming every type you write.
- **Code target** (two or more `targets:`): pass `--target <name>`, the one its design document's row names, on each
  `new`, `get`, and `set` of a per-target spec doc, or address an existing doc by its DocPath.
- **New doc**: pipe its text to `specstone new <type>` (`--parent`, `--slug` as it takes them), parents first.
- **Section**: base from the naming line of `specstone get <type>:<name>#<key>`; pipe the body to
  `specstone set <type>:<name>#<key> --base <hash>`; for a passage add `--replace` and pipe `==> old <==`, the
  passage, `==> new <==`, its replacement.
- **Field**: base from `bases.fields.<id>` of `specstone get <type>:<name> --json`; pipe the value to
  `specstone set <type>:<name> --field <id> --base <hash>`.
- **Several docs in one step**: run `specstone get <names> --out "<file>"`, `<file>`
  `<folder>/reports/sdd-engineer.author.batch.<XXXXXX>.txt`, `<folder>` the path `specstone folder` prints; edit its
  blocks, each naming line kept, all of a block's edits in one file write; then run `specstone set --batch "<file>"`.
  A block printed ` · unchanged` wrote nothing and adds no draft.
- **A refused batch** writes nothing, but exit 73 leaves docs half written until a write command ends its journal:
  run one, or `get`, first. Fix each fault; run it again:
  - Stale block: use the reply's block, your edit merged in; run no `get`.
  - Gone block: re-read its doc by name, a moved doc's new block taking the edit. Drop a block naming no doc or
    typeless, its doc under `Findings:`.
  - One part twice, or a whole-doc block beside another of its doc: join them.
  - Field or title block: write it inside its doc's whole-doc block.
  - Removed required section, or a field only the Owner or Specstone sets: restore it; open fence: close it.
  - Any other refusal a single `set` of one part makes: fix that part as it names.
  - Refused path or line: rebuild the file from `get` text output alone.

## 3. Sweep each changed rule

After step 2, run `specstone search "<term>"` with `--limit` above its hit count for each term:

- **First pass**: each added term, key, or literal; each ruling's superseded wording; each changed rule's existing
  terms: its owner item's words and the sibling key or literal the new one joins.
- **Fix round**: each taken finding's rule and terms.
- **Pass after an amend**: the amend's decisions' terms, as in a first pass.

A hit stating the rule without the decision's new text is a reader. Rewrite each in a draft or a Docs to change
row's doc, as step 2 writes; list each other under `Findings:`.

## 4. Check

Run a bare `specstone check` before your first write and again after your last. Fix each second-run finding, even one
the first run had, in a section your writes touched. List each in an untouched section, such as a doc you only
confirmed again, under `Findings:`, unfixed. Two kinds differ:

- **A `suspect` link in another doc:** confirm it again per `specstone-expert-sdd`; that doc joins your
  drafts, or list it under `Findings:` when you cannot.
- **A finding whose `waitsFor` is `owner`**, its line ending `(waits for the Owner)`: leave it, never write
  around it; list it.

## 5. Report

```
Not landed: <decision>: <why no doc took it>
Not landed: <type>:<name>: listed and never created
Not landed: <type>:<name>: <why no doc took this row>
| Decision or row | Doc that took it |
|---|---|
| <ID or label, or a row's <type>:<name>> | <type>:<name>#<key>, or NOT LANDED |
Drafts for the Owner's specstone approve <type>:<name>: <type>:<name>, ...
Counts: <count> drafts; <type>:<name>: <d> dropped, <n> new; ...
Other drafts: <type>:<name>, ..., or none
Move: specstone move <target> … --under <parent>
Move: specstone move feature:<name> … --top
Findings: <each finding left after step 4, each finding or hit outside the drafts, or none>
```

- **Drafts**: every doc you wrote or confirmed again; in a later pass, step 1's list less each name dropped, plus each
  doc added; names only, no `--target`. A moved doc and its children go by their new name.
- **Counts**: take every count from one `specstone approve --dry-run --json` after your last write, never your own
  tally. Your drafts are the docs your own list names; the output names a moved one by its name before the move while
  its `Move:` line is unrun, by its name after the runner runs it. Name each other draft it lists under
  `Other drafts:`, never counted; one of yours it shows as no draft goes under `Findings:`.
- **Move**: only for a moved doc, item, or scenario: one line per target parent or `--top`; copy each
  into the relay block. Run no `move`.
