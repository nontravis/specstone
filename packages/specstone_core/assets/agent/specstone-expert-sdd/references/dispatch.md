# Dispatch a Specstone agent

The rungs to run `specstone-sdd-engineer`, `specstone-sdd-sweeper`, `specstone-sdd-auditor`, `specstone-sdd-reader`,
or `specstone-plan-engineer`.

- Take the first rung that runs, a fix round's author pass alone trying the resume rung first; give every rung the
  dispatch's mode, paths, and task, and no doc text.
- Give every agent but `specstone-sdd-reader` `report:`.
- Take as the reply the agent's `Report:` line and relay block, or the reader's final message.

## Resumed author

- For a fix round's author pass alone, resume the first author's agent with one message naming the fix file.
- Take the rungs below instead, as a normal author dispatch on the fix file's inputs, when the host cannot resume an
  agent, the first author's agent has ended, or the resumed one answers with no tool call and its old report.

## Named agent

- When the host lists the agent, dispatch it by name.

## Generic subagent

- When the host lists no such agent but has a subagent, spawn one fresh generic subagent.
- Tell it to read `../../agents/specstone-<agent>.md`, joined to the dispatching skill's folder, and follow it.
- Dispatch anyway when the host forbids handing skill reading to a subagent: this hands over a task.

## Main session

- With no subagent, or after a failed dispatch on the named or generic rung, read the agent's file or the mode's
  procedure the dispatching skill names, and follow it yourself on the same inputs.
- A sweep takes no main-session rung: no sweep runs, and the next dispatch goes on.
- Tell the Owner an audit you run yourself is not a fresh reader's.
