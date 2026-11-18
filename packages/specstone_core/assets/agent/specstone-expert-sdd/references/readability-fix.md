# Rewrite a readability finding

This covers the five readability findings `specstone check` raises: `words_over_limit`, `sentence_chars_over_limit`,
`trace_note_not_last`, `sentences_over_limit`, and `item_lines_over_limit`. Each write leaves a draft.

## An item

Rewrite the item in its doc type's item shape, as `specstone guide <type>` gives it, with no Owner naming:

- an `item_lines_over_limit` item has its own lines joined or rewritten to fit the line cap, never split off or given a
  raised limit;
- each rule split off takes the next free ID of its section, and each citation that means the moved rule is repointed;
- conditions go in a nested list;
- a trace group before the item's end moves to the end, merged with any other group there into one group;
- an ownership clause before the last clause moves to be the last clause;
- no statement is dropped.

## A paragraph with no ID

A finding on a paragraph with no ID and a count of 1, such as an FR Statement, a vision's `**Why:**`, `**Problem:**`,
or `**Audience:**` line, or a Responsibility cell: rewrite it in place into sentences within their language's cap.

- its detail moves to the section of the same doc that owns it, such as the FR's Input / Output or Edge cases;
- it never turns into a sub-list.

## A finding the rewrite leaves

Give a split proposal or the report's why, as `size-fix.md` gives it, when no rewrite keeps the meaning or a size
finding is left. The finding waits for the Owner.
