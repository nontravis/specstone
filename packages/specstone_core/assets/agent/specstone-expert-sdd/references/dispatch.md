# Dispatch a Specstone agent

The rungs a skill takes to run `specstone-sdd-engineer`, `specstone-sdd-reader`, or `specstone-plan-engineer`. Every
skill that dispatches an agent points here and restates none of it.

Take the first rung that runs. Every rung gets the same inputs: the dispatch's mode, paths, and task, and no doc text.
`specstone-sdd-engineer` and `specstone-plan-engineer` also get `report:`; `specstone-sdd-reader` gets none. Every
rung's reply is the engineer's or plan engineer's `Report:` line and relay block, or the reader's final message.

## Named agent

When the host lists the agent by name, dispatch it by name.

## Generic subagent

When the host lists no such agent but has a subagent, spawn one fresh generic subagent. A Codex project the Owner has
not trusted lists no project agent; so does a host whose agent folder the Owner emptied.

Tell the subagent to read the agent's file, `../../agents/specstone-<agent>.md` joined to the dispatching skill's
folder, and follow it. Its reply comes back as the named agent's does.

A host may tell its main agent not to hand the reading of skill instructions to a subagent. Dispatch the agent anyway,
for design, author, and audit mode: this hands over a task, not the instructions.

## Main session

With no subagent at all, or after a dispatch that fails on either rung above, read the agent's file, or the mode's
procedure the dispatching skill names, and follow it yourself, on the failed dispatch's own inputs.

An audit you run this way is not a fresh reader's: tell the Owner so.
