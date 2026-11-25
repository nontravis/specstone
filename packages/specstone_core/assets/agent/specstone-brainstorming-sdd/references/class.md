# Give the change its class

In a brainstorm, come here from section 4 of `design.md`, which asks the lane before step 3.

Once the change note is written, and before any writer dispatch, give the change one of five classes by this test,
asked in order:

1. Does the change touch only one section or field of one doc, and none of the work built from the docs? Yes:
   Doc-only.
2. Else, does any doc statement become false or missing after the change? No: Restore or Internal.
3. Yes: are the new statements decided lines the Owner approved, by the note's `Owner ok:` line? Yes: Decided, and
   no: Undecided.

| Class | The change | Its lane |
|---|---|---|
| Doc-only | one section or field of one doc changes | follow the `specstone-update-sdd` skill |
| Restore | the work built from the docs, such as code, tests, or content, departs from an approved doc | the fix changes that work only, and no doc |
| Internal | no observable behavior changes, only the record entries' paths and `covers:` entries | those change through the `specstone-sync-sdd` skill |
| Undecided | observable behavior is added or changed that the Owner has not stated as decided lines | docs first: go on to the skill's step 4 |
| Decided | observable behavior is added or changed that the Owner stated as decided lines | the work first: dispatch no writer, run no builder check, question round, or fix loop, and follow `specstone-plan-sdd` with the change note's path |

A change not shown Decided is Undecided, docs first:

- its class is in doubt
- one decision is neither `(decided)` nor `(plan)`, such as one that fails a decided-line test of `design.md`
- its `(decided)` decisions have no `Owner ok:` line in the note
