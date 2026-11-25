# Trim a section against its guide

For each section a `retrim_due` or `code_blocks_over_limit` finding names, and each FR's edge cases past a cap
`size-fix.md` sends here.

- Judge each item by the section's and the type's lines of `specstone guide <type>`, never a rule of your own.
- Write each change per rule 2 of `specstone-expert-sdd`.

## The marks

- One doc's `retrim_due` and `code_blocks_over_limit` findings take one draft: trim every section they name, then drop
  every copy of each trimmed id from `retrim`.
- A `code_blocks_over_limit` section has no mark: cut its examples to the cap, nothing else.
- With no id left, drop the field.
- A `retrim_due` on an absent section, or a `field_value_mismatch` on `retrim`, drops that id from `retrim` untrimmed.

## The outcome per item

| Outcome | When | Write |
|---|---|---|
| keep | the guide admits it | leave it word for word |
| cut | the guide admits it but bans some text: a skill's or agent's steps, message text, or an exit status | cut the banned text |
| move | the guide names another home for it | write it there, then delete it here |
| delete | the guide excludes it | delete it |

- A cut message the guide makes contract moves to the FR's Output row that defines it, when that row lacks it.
- Drop no other statement on judgement.

## The guide lines per section

Trim each section by its type's guide lines below, and delete each item they exclude, except a Components row, which
the next section cuts to its role:

| Section | Guide lines |
|---|---|
| `fr` Input / Output and Behavior | the item shape line, its skill and agent sentences included, and the `behavior` section line |
| `fr` Input / Output, also | the `input_output` section lines on product words and wire attributes |
| `fr` Edge cases | the four edge-case lines |
| `fr` Verification | the `verification` section lines |
| Components and Technical diagram | the type's description line on code samples and steps, and the section's own lines |
| Errors and Error model | the section's own lines |

## A skill's or agent's steps

Outside a Components row and a diagram, cut a skill's or agent's steps and move them nowhere: the skill's or agent's
own files hold them. Delete an item that states only steps. In a Components row,
cut the Responsibility to the component's role, and never delete the row: its box stays in the unmarked component
diagram.

The parts the `fr` guide's item shape line names for a skill or agent are its contract: when it asks, what it takes,
what it reports, its limits, and what it may write. An audit restores a removed contract part no other doc states, and
never a removed step.

In a Behavior diagram and in any `flowchart` view of a Technical diagram, such as a deployment or a data flow view,
keep only the contract nodes, each stating a contract part. Join each removed node's in-edges to its out-edges, and
drop from a joined edge the labels of a removed decision node. In a Technical diagram sequence view, keep only the
contract messages: a question to the Owner, a dispatch's inputs, a report, a CLI write call with its flags, or a
limit. Drop a CLI read call unless it states a limit, such as one call with no `--budget`. Drop a read or a step
order between the plugin's own parts. A diagram trim that leaves no node or message deletes the diagram: an emptied
Behavior diagram takes its optional section with it, and an emptied Technical diagram view leaves the section, which
keeps its component diagram.

## A moved statement

- Write each moved statement to the home its guide line names, as a draft in the same batch, before it leaves the FR.
- Delete a case with no designed response from the FR, and write it in the same batch to the feature's Out-of-scope as
  `<case> — not planned`.
- Mechanism text in an FR: write it to the home its guide line names; delete it when no line names one.
- Name no spec doc type of your own: the guide lines name each home.

## IDs

- Renumber no item: a gap in an FR's edge case numbers goes to the keep plan your batch's report names.
- An ID the trim removes from another kind of item is the CLI's to add to `retired_ids`, never yours.

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

- Write no cite outside the folder: name each under `Citers outside:` with its doc and the rewrite, naming each edge
  case the rewrite cites by the number the keep plan leaves it; main hands it to that doc's batch.
- A batch handed a `Citers outside:` line writes it in the doc it names and reports it as a rewritten cite.

## The report

Name each deleted, moved, and cut item with the guide line that decided it, and each rewritten cite. Then add:

- `Citers outside:`: each cite outside the folder, its doc, and the rewrite in final numbers.
