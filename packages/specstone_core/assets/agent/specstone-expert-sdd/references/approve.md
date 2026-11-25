# Get the drafts approved

The main session's steps once a run reaches approval, after the fix loop of `fix-loop.md` ends and ahead of Owner
confirmation in `SKILL.md`.

1. In a bootstrap round passing `--audit` that hands a citer on as `Citers outside:`, write
   `<folder>/reports/sdd-auditor.audit.queued.<XXXXXX>.md`, one `Queued: <name>` line per lead name of the round's
   audit items naming such a citer, bar a draft of the call, passed as the call's last `--audit`; edit no auditor's
   report. For a Decided change's drafts, write each `Fix:` block of the Decided audit on a doc outside the drafts
   through `specstone set` as that section's whole text, unchanged, and that doc joins the call.
2. Run one `specstone approve <type>:<name> … --auto --json` naming each draft of the run's own list, never a bare
   `approve`. In `specstone-brainstorming-sdd` add `--audit <path>` per audit report of the run, the builder check,
   then each loop re-review, oldest first, and `--author <path>` once per writer, its one report file holding every
   round of that writer; in a bootstrap round with a trim batch, its fix loop included, `--audit <path>` per audit
   report of the round, the trim audit, then each loop re-review, oldest first; for a Decided change's drafts at a
   plan's last sync, before the branch lands, the Decided audit's report as the one `--audit <path>` and
   `--author <path>` once per sync engineer report; else `--no-audit`.
3. Exit 75 on the first or second call: rerun it once; a second sends its drafts to Owner confirmation.
4. After each call, list each `approved` entry's `doc`, `path`, and `Why:`, with no wait, and each finding of its
   `carried` key beside it; for a reconfirmation, the upstream change. In a brainstorm, show the change note's
   Decisions with the approved list, also when no draft is asked.
5. Send every `asked` entry of the first call with `waitsFor` `audit`, or asked `no audit report names it`, or
   `named in Findings of` an audit report for an item with a `Fix:` line, bar a Decided change's drafts, to one fresh
   `specstone-sdd-auditor`, `job: re-review`, with `findings:` each audit item still open that names those drafts,
   verbatim, or `none`, no `fix report:`, `drafts:` those drafts, `audits:` every first-call audit report path, the
   `Queued:` file aside, oldest first, in a brainstorm the change note's path and the Owner's answers, and `report:` a
   new `<folder>/reports/sdd-auditor.audit.<XXXXXX>.md`. A draft asked for an item with no `Fix:` line that only the Owner
   settles, or for a finding the fix loop's breaker decided, goes to the Owner, not to the re-review. In a bootstrap
   round, `drafts:` adds each listed draft awaiting approval the `Inbound` lines of `refs <draft>` show citing one,
   marked `citer of <type>:<name>`, the draft it cites. With no such entry, no re-review runs.
6. Write each `Fix:` block of the re-review's report through `specstone set` as that section's whole text, unchanged,
   before the second call; its findings enter no fix loop. With no subagent or a failed dispatch, no re-review runs:
   those drafts go to Owner confirmation with no second call, each `Why:` naming the change made after the audit;
   never read your own fixes.
7. After the re-review and its blocks, run a second `--auto --json` call naming each draft sent to it, no citer, with
   every first-call `--audit` path plus the new report, oldest first, and the same `--author` paths.
8. Send each `asked` entry with `waitsFor` `owner` to Owner confirmation; after a second call, Owner confirmation
   starts once, for the first call's `owner` entries no re-review took and every entry the second asks. Ask them in
   one message, each `Why:` naming the change made after the audit. A draft with a call or question of the fix
   loop's breaker shows it beside the draft as its `Why:`. A Decided change's drafts take no re-review and no other
   call: each `asked` entry goes to Owner confirmation, and each other Decided audit item goes to the Owner at the
   approval ask with its `Fix:` lines when it has them.
