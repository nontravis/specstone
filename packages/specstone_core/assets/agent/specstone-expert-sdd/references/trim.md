# Trim a section against its guide

For each section a `retrim_due` finding names, and each FR's edge cases past a cap `size-fix.md` sends here.

- Judge each item by the section's and the type's lines of `specstone guide <type>`, never a rule of your own.
- Write each change per rule 2 of `specstone-expert-sdd`.

## The marks

- One doc's `retrim_due` findings take one draft: trim every section they name, then drop every copy of each trimmed
  id from `retrim`.
- With no id left, drop the field.
- A `retrim_due` on an absent section, or a `field_value_mismatch` on `retrim`, drops that id from `retrim` untrimmed.

## The outcome per item

| Outcome | When | Write |
|---|---|---|
| keep | the guide admits it | leave it word for word |
| cut | the guide admits it but bans some text: a lock, retry, or parser mechanism, message text, or an exit status | cut the banned text |
| move | the guide names another home for it | write it there, then delete it here |
| delete | the guide excludes it | delete it |

- A cut message the guide makes contract moves to the FR's Output row that defines it, when that row lacks it.
- A mechanism still needed moves to the feature's ARCHITECTURE, in a spec batch.
- Drop no other statement on judgement.

## A PRD batch

- A batch under `prds/` writes no spec doc.
- Delete from the FR a case whose home is the domain's `known_limits`; name it under `Spec moves:` for the spec batch
  of its feature folder.
- Mechanism text in an FR: delete it, never move it.
- Only a spec batch writes ARCHITECTURE or `known_limits`, including each `Spec moves:` line handed to it.

## IDs

- Renumber no item; never delete the item holding its section's highest ID: keep it as `kept: top ID`.

## The cites

Run `specstone refs <doc>` for each cite of a deleted or moved item, and rewrite each inside your batch's feature
folder:

| Cite form | Rewrite |
|---|---|
| a one-ID link, such as `[E07](…)` | link the item that now states the rule; with none, drop the link and its clause |
| a multi-ID link text, such as `[E05, E13](…)` | drop the deleted ID; with none left, as a one-ID link |
| a range link, such as `[E13 to E25](…)` | rewrite to the IDs still in the range, as a list or smaller ranges |
| a bare same-doc mention, such as `(E19)` | drop the deleted ID |
| an `overrides` entry and its `Overrides:` line naming a deleted invariant | drop the entry and the line's ID |
| a matrix row `- <fr> E<nn>: …` naming a deleted or moved edge case | drop the row |

- Write no cite outside the folder: name each under `Citers outside:` with its doc and the rewrite; main hands it to
  that doc's batch.
- A batch handed a `Citers outside:` line writes it in the doc it names and reports it as a rewritten cite.

## The report

Name each deleted, moved, and cut item with the guide line that decided it, and each rewritten cite. Then add:

- `kept: top ID`: each item kept for its ID alone;
- `Citers outside:`: each cite outside the folder, its doc, and the rewrite;
- `Spec moves:`: each case a PRD batch deleted for `known_limits`, with its text and feature folder.
