# Remove the refs of a task a commit closes

- The group file pre-fills one `remove-task <task> <doc> <entry>` line per task that a commit to the link `<doc> <entry>` closes; the CLI finds those commits.
- Keep each pre-filled `remove-task` line as is, for the group's own `specstone set --sync` to run.
- Of these lines, delete none and write none: the CLI removes a task only when each line naming it names a link the call writes as `match` or `planned`, else it keeps the task under `Kept:`.
- While a covering doc is a pending draft, the call lists the line under `Waiting:`; the runner's rerun of the same group file writes it once the Owner approves.
- A `<task> · no refs` line: an earlier group removed that task; do nothing.

## Report

- The call lists no removed task: a removed task is a task of the group's `remove-task` lines that no `Waiting:` line, `Kept:` line, or `<task> · no refs` line of the call's output names.
- Name each removed task, and each task under `Kept:` with the link that kept it.
