# Rewrite a readability finding

For `words_over_limit`, `sentence_chars_over_limit`, `trace_note_not_last`, `sentences_over_limit`, and
`item_lines_over_limit`; each write leaves a draft.

## An item

Rewrite it in its type's item shape from `specstone guide <type>`, with no Owner naming:

- `item_lines_over_limit`: join or rewrite its lines to fit, never split one off or raise the limit.
- Give each rule split off its section's next free ID; repoint each citation meaning it.
- Put conditions in a nested list.
- Move a trace group to the item's end, merged with any group there.
- Move an ownership clause to the last clause.
- Drop no statement.

## A paragraph with no ID

- A finding with a count of 1 on an ID-less paragraph (an FR Statement, a vision's `**Why:**`, `**Problem:**`, or
  `**Audience:**` line, a Responsibility cell): rewrite it in place into sentences within its language's cap.
- Move its detail to the section of the same doc that owns it, such as the FR's Input / Output or Edge cases; never
  make it a sub-list.

## A finding the rewrite leaves

- No rewrite keeps the meaning, or a size finding is left: give a split proposal or the report's why per
  `size-fix.md`; it waits for the Owner.
