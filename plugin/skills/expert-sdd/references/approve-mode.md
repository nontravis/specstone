# Approve under the auto mode

The steps of the `approve` item in `## Owner confirmation` for the drafts of this run. The dry run reads the mode;
under `ask`, every draft takes Owner confirmation, and the rest is for `auto` only.

## Dry run

1. Run `specstone approve <type>:<name> … --dry-run --json`, naming each draft of the run's own list: your own list,
   or the drafts the engineer's report names as its own (an author report's `Drafts for the Owner's specstone approve`
   line, a sync or bootstrap report's drafts lines), never its other drafts. Never run a bare `approve`: it would name
   a draft another session wrote.
2. Read `approveMode`, and each draft's `name`, `docPath`, and `hash`.
3. `ask`: take every draft through Owner confirmation, and stop here.
4. `auto`: run one bare `specstone check --json` after your last write, and judge each draft by the tests below.

## Clean-draft tests

A draft is clean when every test its flow takes holds; the first test that fails sends it to the Owner confirmation
that `ask` uses. Read the keys of each finding (`docPath`, `kind`, `waitsFor`), never its message text.

1. The draft is in the run's own list.
2. No finding names its `docPath`, except one of `kind` `unconfirmed` with `waitsFor` `owner`: the approval itself
   clears that one. Any other kind, an `unconfirmed` finding that waits for the agent, or a size finding makes the
   draft not clean.
3. With an audit: the last audit's `Audited:` line names the draft with a hash equal to its dry-run `hash`.
4. With an audit: no `Findings:` or `Outside the drafts:` line of the last audit names its `<type>:<name>`.
5. With an author pass: no author reply of the run, the first pass or a later one, holds a `Not landed:` line other
   than `Not landed: none`. One such line fails this test for every draft of the run at once, even when a later pass
   landed what it flagged.

Without an audit, a flow takes tests 1 and 2 alone: one edit of `update-sdd`, `sync-sdd`, `bootstrap-prd`,
`bootstrap-spec`, and each of the four first drafts of `init`. `brainstorming-sdd` hands its last audit's relay block to
tests 3 and 4 and every author reply to test 5. Its `Waits on the Owner:` lines are not read: test 2 judges the same
findings.

## Approve call

Run one `specstone approve <type>:<name>@<hash> … --yes` naming every clean draft, each hash the `hash` of the dry run,
written literally in the command; run none when no draft is clean. Ask no `ok`. Take each draft that is not clean
through Owner confirmation as under `ask`, after the approved list.

## Exit 75

Exit 75 approves nothing: `base_mismatch` names each changed draft, `index_busy` names none.

- First 75: retry once. Run the dry run and the check again, judge each draft again (a draft that changed after its
  audit carries a hash its `Audited:` line does not name, so it is asked), and make one `--yes` call for the drafts still
  clean.
- 75 from the retry: ask each draft either refusal named, or every draft of the call when the refusal names none. Make
  one last `--yes` call for the call's other drafts, still clean by the retry's judgment, with the retry's hashes. That
  call is never retried: on any refusal, ask every draft it names. Never try a draft a refusal named a third time.

## Approved list

After the approve call, with no wait for an answer, write in the chat each approved draft: `<type>:<name>`, its
`docPath`, and one sentence on why it changed, the sentence the `Why:` line of Owner confirmation would give. For a
confirmation written again, name the upstream change it was checked against. A runner that shows each author and audit
reply still shows it, with no wait.

## Still the Owner's

Under both modes the Owner answers the design document's approval, a question met mid-flow, an open question in a
report, a split proposal, a sync pick, `delete` of a guarded doc, `migrate`, `init` on a legacy tree, and each `--plan`.
A subagent runs `approve` only with `--dry-run`: it puts its drafts in its report, and the runner gets them approved.
