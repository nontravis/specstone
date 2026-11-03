Step 1, the gate, already ran in the skill or agent that sent you here.
When you run as `specstone:sdd-engineer`, ask the Owner nothing: each step that asks, confirms, or approves with the
Owner goes into your report instead.

`specstone check` tests only that code pointers resolve; it never reads what a function now does. So start from the
paths the task changed, not from findings. Follow `specstone:expert-sdd` for every doc you write.

## 2. Collect the changed paths

1. Take the files the task lists as touched (a plan task's files, an implementer's report).
2. No list: run `git diff --name-only <base>`, where `<base>` is the commit the task started from or
   `git merge-base HEAD <base branch>`. While the work is uncommitted, add `git ls-files --others --exclude-standard`.
3. Drop each path under `docs/` in the project root, the folder that holds `.specstone/`: those are docs, and this
   sync starts from code.

## 3. Find the covering docs

For each path, run:

```
specstone context --code <path> --for implement
```

- **Warning `no doc covers or implements <path>`:** no spec covers it, whatever project docs print beside the
  warning. When `git diff --name-status -M <base>` lists the path as the new side of an `R` (rename) pair, the file
  moved: go to step 4.3. Any other such path is new code: go to step 5.
- **0, no such warning:** the printed specs and requirements cover the path. Go to step 4.
- **64, `code_path_not_found`:** the task deleted the file, so `context` has nothing for it. `specstone check` lists
  the `implements:` entries that still name it; step 4.3 fixes them.
- **Any other non-zero exit:** report the CLI's error and stop.

## 4. Update the covering docs

1. Compare each section and field of each covering doc with the changed code. Leave a doc alone when it already
   matches the code.
2. Rewrite each stale section or field; `<target>` is the doc's `<type>:<name>`. Take a section's base hash from the
   naming line of `specstone get <target>#<section key>`, a field's from `bases.fields.<id>` in
   `specstone get <target> --json`. Then pipe the new text to `specstone set <target>#<section key> --base <hash>` (a
   field: `--field <id>` in place of `#<section key>`). Each such write turns the doc into a draft; only the Owner's
   `specstone approve` clears it.
3. Run `specstone check`. Take each finding on an `implements:` or `covers:` entry that a covering doc holds or that
   names a changed path, and fix it through `specstone set --field`: pipe the corrected list to
   `specstone set <target> --field implements --base <hash>` (or `--field covers`), the hash from
   `bases.fields.implements` (or `bases.fields.covers`) in `specstone get <target> --json`:
   - moved file: point the entry at the new side of its rename pair;
   - deleted file: drop the entry, or point it at the code that does the work now.

   A pointer write leaves the draft flag untouched: an approved doc keeps its approval.
4. Repeat step 3 until those docs show no pointer finding.

## 5. Draft first: behavior no spec holds

Take this step for a path no spec covers, and for new behavior in a covered path that no section states. Spec text
comes first; the pointer follows it.

- **Needs a new story or FR:** leave it out of this sync and hand it to `specstone:brainstorming-sdd`.
- **Else:** write a spec draft: `specstone new <type>` (`--parent <name>`, `--slug <slug>`, as the type takes them)
  for a new doc, or `specstone set` for a section of one that exists. Then get it approved through
  `specstone:expert-sdd`'s Owner confirmation (terminal or chat).
- Write no `implements:` or `covers:` entry that names this code until the Owner approves the draft. Then add the
  entry at once with the step 4.3 `specstone set --field` write: no `check` finding will ask for it.

## Report to the Owner

List each draft waiting for `specstone approve <type>:<name>`, each pointer fixed, each behavior handed to
`specstone:brainstorming-sdd`, and each pointer that waits on an approval.

## Red flags

| Thought                                           | Do instead                                                  |
|---------------------------------------------------|-------------------------------------------------------------|
| "`check` is clean, so the docs match the code."   | Compare each covering doc with the changed code (step 4.1). |
| "The moved file is new code; draft a spec."       | Point the old entry at the new path (step 4.3).             |
| "Add the `implements:` entry now; approve later." | The pointer waits for the Owner's approval (step 5).        |
