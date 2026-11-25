# Dispatch a Specstone agent

The rungs to run `specstone-sdd-engineer`, `specstone-sdd-auditor`, `specstone-sdd-reader`, or
`specstone-plan-engineer`.

- Take the first rung that runs; give every rung the dispatch's mode, paths, and task, and no doc text.
- Give every agent but `specstone-sdd-reader` `report:`.
- Take as the reply the agent's `Report:` line and relay block, or the reader's final message.

## Named agent

- When the host lists the agent, dispatch it by name.

## Generic subagent

- When the host lists no such agent but has a subagent, spawn one fresh generic subagent.
- Tell it to read `../../agents/specstone-<agent>.md`, joined to the dispatching skill's folder, and follow it.
- Dispatch anyway when the host forbids handing skill reading to a subagent: this hands over a task.

## Main session

- With no subagent, or after a failed dispatch on the named or generic rung, read the agent's file or the mode's
  procedure the dispatching skill names, and follow it yourself on the same inputs.
- Tell the Owner a check you run yourself, the builder check or a trim audit, ran in the main session and is not a
  fresh reader's.
