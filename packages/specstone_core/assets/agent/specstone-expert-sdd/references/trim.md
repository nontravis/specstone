# Trim a section against its guide

The trim of each section a pack upgrade marked, which a `retrim_due` finding names, and of an FR's edge cases past a
cap, which `size-fix.md` sends here. Judge each item by the section's and the type's lines of `specstone guide <type>`,
never by a rule of your own. Write each change as `writes.md` says.

## The marks

The `retrim_due` findings of one doc take one draft: trim every section they name, then drop every copy of each
trimmed id from `retrim`. With no id left, drop the field. A `retrim_due` on an absent section, or a
`field_value_mismatch` on `retrim`, drops that id from `retrim` with no trim.

## The outcome per item

Each item takes one outcome:

| Outcome | When | Write |
|---|---|---|
| keep | the guide admits it | leave it word for word |
| cut | the guide admits it but bans some of its text: a lock, retry, or parser mechanism, a skill's or agent's steps, message text, or an exit status | cut the banned text |
| move | the guide names another home for it | write it there, then delete it here |
| delete | the guide excludes it | delete it |

A message the guide makes part of the contract, once cut, moves to the FR's Output row that defines it when that row
lacks it. A mechanism still needed moves to the feature's ARCHITECTURE, in a spec batch. Drop no other statement on judgement.

## The guide lines per section

Trim each section by its type's guide lines below, and delete each item they exclude, except a Components row, which
the next section cuts to its role:

| Section | Guide lines |
|---|---|
| `fr` Input / Output and Behavior | the item shape line, its skill and agent sentences included, and the `behavior` section line |
| `fr` Edge cases | the four edge-case lines |
| `fr` Verification | the `verification` section lines |
| `architecture` Components, Component details, and Interaction | the `architecture` description line on code samples and steps, and the section's own lines |
| `domain` and `project_domain` Invariants | the `invariants` section lines |
| Value objects | the `value_objects` section line |

## A skill's or agent's steps

Outside a Components row and a diagram, cut a skill's or agent's steps and move them nowhere: the skill's or agent's
own files hold them. Delete an item that states only steps, unless it holds the top ID, kept as `kept: top ID`. In a
Components row, cut the Responsibility to the component's role, and never delete the row: its box stays in the
unmarked component diagram.

The parts the `fr` guide's item shape line names for a skill or agent are its contract: when it asks, what it takes,
what it reports, its limits, and what it may write. An audit restores a removed contract part no other doc states, and
never a removed step.

In a Behavior diagram, keep only the contract nodes, each stating a part the `fr` guide's item shape line names for a
skill or agent. Join each removed node's in-edges to its out-edges, and drop from a joined edge the labels of a
removed decision node. In an Interaction sequence diagram, keep only the contract messages: a question to the Owner,
a dispatch's inputs, a report, a CLI write call with its flags, or a limit. Drop a CLI read call unless it states a
limit, such as one call with no `--budget`. Drop a read or a step order between the plugin's own parts. A diagram
trim that leaves no node or message deletes the diagram's optional section.

## A PRD batch

A batch under `prds/` writes no spec doc. Delete from the FR a case whose home is the domain's `known_limits`, and
name it under `Spec moves:` for the spec batch of its feature folder. Mechanism text in an FR is implementation
detail: delete it, never move it. Only a spec batch writes ARCHITECTURE or `known_limits`; it writes each
`Spec moves:` line it is handed into `known_limits`.

## IDs

Renumber no item: a kept item keeps its ID. The next write takes the highest ID present plus one, and IDs are never
reused, so never delete the item holding its section's highest ID: keep it, named as `kept: top ID`.

## The cites

Run `specstone refs <doc>`: it lists each cite of a deleted or moved item, range links and matrix rows included.
Rewrite each cite inside your batch's feature folder, in the batch:

| Cite form | Rewrite |
|---|---|
| a one-ID link, such as `[E07](…)` | link the item that now states the rule; with none, drop the link and its clause |
| a multi-ID link text, such as `[E05, E13](…)` | drop the deleted ID from the text; with none left, as a one-ID link |
| a range link, such as `[E13 to E25](…)` | rewrite to the IDs still in the range, as a list or smaller ranges |
| a bare same-doc mention, such as `(E19)` | drop the deleted ID from the mention |
| an `overrides` entry and its `Overrides:` line naming a deleted invariant | drop the entry and the line's ID |
| a matrix row `- <fr> E<nn>: …` naming a deleted or moved edge case | drop the row |

Write no cite outside the folder: name each under `Citers outside:`, with its doc and the rewrite. The main session
hands it to that doc's batch (its feature folder's, else the rest batch), a record's matrix row to that feature's spec
batch. A batch handed a `Citers outside:` line writes its rewrite in the doc it names and reports it as a rewritten
cite.

## The report

Name each deleted, moved, and cut item with the guide line that decided it, and each rewritten cite. Then add:

- `kept: top ID`: each item kept for its ID alone;
- `Citers outside:`: each cite outside the folder, its doc, and the rewrite;
- `Spec moves:`: each case a PRD batch deleted for `known_limits`, with its text and feature folder.
