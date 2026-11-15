# Repeated rules and old cites

The `cite_unlinked` fix and the repeats batch of `specstone-bootstrap-prd` and `specstone-bootstrap-spec`. Each link
takes the form of `specstone-expert-sdd` rule 7, and each write leaves a draft.

## A `cite_unlinked` finding

Rewrite the cite as a link to the one doc or item its text means.

## A repeats batch

`batch: repeats` holds the groups `specstone check --repeats` listed with an item in a doc your skill takes: under
`prds/` or `measurements/` for `bootstrap-prd`, under `specs/` for `bootstrap-spec`.

Per group, judge whether its items state one rule. If so, keep the item in the doc that owns the rule's subject,
replace each other copy in a doc your skill takes with a link to that item, and name the owner in each draft's reason.
If not, keep each item and report the group as kept. A statement the procedure moved into a section, which now
repeats another doc's, merges the same way: the move kept it, and this batch links it.
