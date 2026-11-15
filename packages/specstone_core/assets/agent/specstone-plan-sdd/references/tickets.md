# Name the ticket tools and write each ticket's ref

Run this beside the run question of step 5, after the plan is shown. Specstone makes no ticket: a ticket tool does.

## 1. Find the ticket tools

Look in your skill list and your tool list for each plugin, skill, or MCP whose description says it breaks work into
tickets. Judge by that description alone, never by a name, and name no tool that a file of this plugin holds.

- **One or more qualify:** name each to the Owner beside the run question, by its name and its description's words.
- **None qualifies:** name none, and say nothing about tickets.

## 2. Write a ref for each ticket

For each ticket a tool makes for an item of a spec doc, add its ref to that doc's `tasks` field. A ref is
`<item>:<task>`, or `<task>` alone for the whole doc, `<task>` the id the tool gives the ticket.

1. Read the base: run `specstone get <type>:<name> --json` and take `bases.fields.tasks`.
2. Write the whole list as YAML `- <entry>` lines: the refs the doc already holds, then each new one. Quote an entry
   YAML reads as a comment or a number, such as `- "#123"`. Pipe it to
   `specstone set <type>:<name> --field tasks --base <hash>`.

One item takes several refs: write one entry per task, `INV-4:ENG-42` and `INV-4:ENG-43` side by side. With two or more
code targets, pass `--target <name>`, the target the doc belongs to, on the `get` and the `set`.

## 3. Commits

Name the task id in the message of each commit of a ticket's work. The commit that finishes that work closes the
ticket: put `Closes <task>` on its own line of the message, as `Closes ENG-42`.

A synced commit that closes a task has `specstone-sync-sdd` remove its refs; this skill removes none.
