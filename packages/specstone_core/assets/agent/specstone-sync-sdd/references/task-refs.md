# Remove the refs of a task a commit closes

- Run this per match step 4.2 or the small route writes: a link's fingerprint, or a `planned` entry's `implemented`.
- A mismatch, or a `planned` entry whose code lacks its behavior yet, removes nothing.

## 1. Candidates

- The task id of each `task_ref` field entry (`<item>:<task>`, or `<task>` for a whole doc) in the docs of the link's step 3 `context --code` bundle, a `root: project` entry's included.
- Read no other doc.

## 2. Messages

- From the project root, read the messages of commits that changed the link's code, each path `<code root>/<path>`, a `root: project` entry's `<path>` as is:

```
git log --format=%B <base>..HEAD -- <code paths>
```

- `<base>` is step 4.1's commit for the link; with none, drop `<base>..HEAD`.
- Read once per link.

## 3. Closed or mentioned

- An occurrence has no letter, digit, `-`, or `_` right before or after it; match case-sensitively.
- Closed: one occurrence, on one line, in keyword or command form; any other is a mention, closing nothing.
- **Closing words**, any case: `close`, `closes`, `closed`, `fix`, `fixes`, `fixed`, `resolve`, `resolves`, `resolved`; with no candidate after, none closes.
- **Keyword form:** the occurrence starts a token of a list after a whole closing word, an optional `:`, and 1 or more spaces or tabs.
- A token is a run of characters but spaces, tabs, and `,`; tokens part by `,`, `and`, or `, and`, spaced or tabbed.
- The list ends at the line end or any other gap: `Fixes ENG-40 so ENG-42 can start` closes `ENG-40` alone.
- **Command form:** later on the line, `#` plus a closing word or `done`, with no letter, digit, `-`, or `_` right after.

## 4. Remove

With 1 or more closed candidates and no covering doc a pending draft, run once, naming each closed task:

```
specstone set --remove-task <task> [--remove-task <task> ...] [--target <name>]
```

- Pass `--target <name>`, the synced code target, with 2 or more code targets.
- While a covering doc is a pending draft, or with a `check:` file passed, run nothing: list the command as a waiting pointer with its code target, for main to run after approval or the last feature report.
- A rerun finds no candidate left for a removed task.

## 5. Report

- Name each task whose refs you removed in your report, beside the pointers you fixed.
