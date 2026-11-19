# Remove the refs of a task a commit closes

Run this for each match step 4.2 or the small route writes: a link's fingerprint, or a `planned` entry's `implemented` status. A mismatch,
and a `planned` entry whose code lacks its planned behavior yet, take no removal: every ref stays until a later match.

## 1. Candidates

A candidate is the task id of each task ref in the docs the link's `context --code` bundle of step 3 holds: an entry of
a field of type `task_ref`, written `<item>:<task>`, or `<task>` alone for a whole doc. For a `root: project` entry,
they are those in the doc its finding names, read in step 3. Read no other doc.

## 2. Messages

Read the messages of the commits that changed the link's code, from the project root, each path `<code root>/<path>`,
or a `root: project` entry's `<path>` as is, with no `<code root>/` prefix:

```
git log --format=%B <base>..HEAD -- <code paths>
```

`<base>` is the commit step 4.1 finds for the link. With none, read the messages of every commit that touched the
paths: drop `<base>..HEAD`. This is one read per link.

## 3. Closed or mentioned

A candidate occurs in a message where no letter, digit, `-`, or `_` stands right before or right after it, matched
case-sensitively: `ENG-42.` holds `ENG-42`; `ENG-421` and `eng-42` do not.

A candidate is closed when one occurrence, on one line, takes keyword form or command form. Any other occurrence is a
mention and closes nothing, as in `ENG-42`, `Refs ENG-42`, or `Part of ENG-42`.

- **Closing words**, in any letter case: `close`, `closes`, `closed`, `fix`, `fixes`, `fixed`, `resolve`, `resolves`,
  and `resolved`. A closing word with no candidate after it, as in `Fixes the parser`, closes nothing.
- **Keyword form:** the occurrence starts a token of a list that follows a closing word standing as a whole word, an
  optional `:`, and 1 or more spaces or tabs. A token is a run of characters other than spaces, tabs, and `,`. Two
  tokens part by `,`, by the word `and`, or by `, and`, with spaces or tabs around it. The list ends at the line end or
  at any other gap: `Fixes ENG-40, ENG-41, and ENG-42.` closes all three, and `Fixes ENG-40 so ENG-42 can start`
  closes `ENG-40` alone.
- **Command form:** later on the same line, `#` and then a closing word or `done` follow the occurrence, with no
  letter, digit, `-`, or `_` right after it: `ENG-42 #resolve` and `ENG-42 #done` close; `ENG-42 #resolved-later` does
  not.

## 4. Remove

With 1 or more closed candidates and no covering doc a pending draft, run once, naming each closed task:

```
specstone set --remove-task <task> [--remove-task <task> ...] [--target <name>]
```

Pass `--target <name>`, the synced code target, when the project has 2 or more code targets, so a ref on another
target's doc stays. A task no doc holds prints `<task> · no refs` and exits 0.

While a covering doc is a pending draft, run nothing: list the command as a waiting pointer, with its code target, to
run once the Owner approves. With a `check:` file passed, you run beside other feature engineers, and the command
writes every doc of the target: run nothing, list it the same way, for the main session to run after the last feature
report. A rerun finds no candidate left for a removed task.

## 5. Report

Name each task whose refs you removed in your report to the Owner, beside the pointers you fixed.
