# Run the fix loop

The main session's one loop for every fix step after an audit: a brainstorm's fixes after the builder check, and a
bootstrap round's fixes after its trim audit. A writer is the `specstone-sdd-engineer` that wrote the drafts a finding
names: a brainstorm's group or cross-group writer, or a bootstrap round's batch engineer.

## Enter the loop

- A brainstorm first sorts the builder check and asks the theirs pile once, by
  `../../specstone-brainstorming-sdd/references/rounds.md` section 2. Each answered and minor item, and each Owner
  answer, enters the loop.
- A bootstrap round sends each `Findings:` item of its trim audit into the loop. Each `Outside the drafts:` item stays
  a handed line, by `trim-round.md` Handed lines.
- A finding that conflicts with the change note or an Owner answer enters no fix. Decide it first, and list that call
  under the change note's `Calls made` in a brainstorm, or in your relay to the Owner in a bootstrap round.
- A finding with no `Fix:` line that only the Owner settles enters no fix either: it joins the theirs pile when the
  loop starts, else the approval ask.
- With nothing entering the loop, go straight to After the loop.

## Split by writer

- Send each finding to the writer of the draft it names, so each writer's rounds count apart.
- A finding on a doc outside every writer's drafts goes, in a brainstorm, to the one writer, or with several to the
  cross-group writer, and that doc joins the drafts list. In a bootstrap round it leaves the loop as a handed line, by
  `trim-round.md` Handed lines.

## A round

A round is one fix dispatch per writer with an open finding, then one re-review across every writer's fix. A writer
gets at most 5 rounds, counted from its first fix dispatch. The loop ends with the round whose re-review leaves no
finding open but one the breaker decided. Each dispatch follows `dispatch.md`.

1. **Rounds 1 to 3, resume**: resume the writer with its open findings verbatim, each `Fix:` block as it stands, and
   `report:` its own report file. The message names its mode and that mode's inputs again, bar `bundles`:
   `mode: author`, the change note's path, its `docs` share, and `group reports` for the cross-group writer, or
   `mode: bootstrap`, its `procedure`, and `batch:` the open findings. A host that cannot resume sends a fresh writer
   of the same agent with the same inputs and the same `report:` path, which holds what was tried.
2. **Rounds 4 and 5, fresh writer**: dispatch a fresh writer of the same agent, on a more capable model where the
   host's dispatch takes a model, else on the same one. Send it the same inputs bar `bundles`, the same `report:`
   path, the open findings, and this line, `<N>` the rounds already run: "A prior writer attempted these fixes <N>
   times; you own them now. Read the report file for what was tried."
3. **Fix report**: the writer writes every fix, each `Fix:` block's body as that section's whole text, unchanged, and
   appends a `## Round <n>` part to its report file. It writes only the sections its open findings name and each
   reader of a term a fix changes, and runs no author pass. Confirm each `## Round <n>` part names each changed
   section on a `Changed: <type>:<name>#<key>` line, holds a `Check:` line naming a saved check run after its last
   write, and lists the drafts from one approval dry run. A part missing one goes back to its writer once, in the same
   round, naming what is missing. Still missing one, that writer's round fails and counts toward the 5.
4. **Re-review**: once every writer of the round has reported, dispatch one fresh `specstone-sdd-auditor`,
   `job: re-review`, with `findings:` every finding of the run still open, verbatim, each writer's included,
   breaker-decided ones included, `fix report:` each writer's report path and round number, `drafts:` each draft the
   findings or a `Changed:` line name, `audits:` each earlier audit report of the run, oldest first, in a brainstorm
   the change note's path and the Owner's answers, and `report:` a new
   `<folder>/reports/sdd-auditor.audit.<XXXXXX>.md`.
5. **Next round**: each `- NOT ADDRESSED:` item, bar one the breaker decided, and each new `Findings:` item is an open
   finding of the next round, split by writer as above. Each `Outside the round:` item goes the same way: in a
   brainstorm it counts in its writer's rounds, and in a bootstrap round it leaves the loop as a handed line.
   `Notes:` go to the Owner and never extend the loop.

Write no fix text of your own in the loop. With no subagent, you are the writer for one pass of fixes, by the Main
session rung of `dispatch.md`, and no re-review runs. Each draft with an open finding then goes to Owner confirmation,
its `Why:` naming the change made after the audit.

## The breaker

A finding still open after its writer's round 5, or a new finding on a writer past it, stops the loop for that writer:
no later fix dispatch takes it. Decide each:

- The reviewer is wrong, or the point is contestable: park it, with why the text stands.
- It is real, but nothing builds on it: park it as real and deferred.
- It is real and load-bearing: make it an Owner question.

A parked finding stays `- NOT ADDRESSED:` in each later re-review, so `--auto` still asks its draft. Each call and
question goes beside its draft at the approval ask, as its `Why:`, in one message with no second question round.

## After the loop

Once the loop ends, follow `approve.md`, with `--audit` per audit report of the run, oldest first: the builder check or
trim audit, then each re-review report.
