Step 1, the gate, already ran in the skill or agent that sent you here.
As `specstone:sdd-engineer`, ask the Owner nothing: each step with the Owner goes into your report.

`specstone check` finds code changed since its docs were compared, never what that code now does: compare it
yourself (step 4). Follow `specstone:expert-sdd` for every doc you write.

**Code target** (two or more `targets:`): a changed path's target is the `code target:`
line, or the `codeTarget` key under `--json`, of its `context --code` call, covered or not, and a deleted path's is the
finding DocPath's, so ask the Owner nothing; each `get`, `set`, and `new` of a per-target doc carries `--target <name>`,
or addresses the doc by its DocPath.

## 2. Take the work list

Your gate `check` gives it, whoever wrote the code: each `code_suspect`, `code_unconfirmed`,
`implements_path_unresolved`, `implements_symbol_unresolved`, `covers_path_missing`, `code_uncovered`, and
`tests_unresolved` finding, never a `tests_missing` one. Take no list of paths from the task, and never ask whether a
plan wrote the code.

A feature named: take instead every code link of it that takes a state, findings or not, a waiting code target's left
out. `specstone context <feature> --for implement` prints its record's `implements` and its specs' `covers:` entries.
Each link keeps its state.

## 3. Find the covering docs

For each listed code path but a `tests_unresolved` line's (step 4), run:

```
specstone context --code <path> --for implement
```

It takes its path's code target, prints it, and carries no `--target`.

- **Warning `no doc covers or implements <path>`:** no spec covers it. A `code_uncovered` path: go to step 5.
- **0, no such warning:** the printed specs and requirements cover it. Go to step 4.
- **64, `code_path_not_found`:** the file moved or is gone, so `context` has nothing for it. `specstone check` lists
  the record entries that still name it; step 4.3 fixes them.
- **Any other non-zero exit:** report the CLI's error and stop.

## 4. Update the covering docs

1. Compare each section and field of each covering doc with the code of each link; leave a matching doc alone. A
   link's code is its file; a `code_suspect` folder's files changed under it since its stamp:
   `git log -1 --format=%H -S '<recorded>' -- docs/<DocPath>` gives `<base>`, then `git diff --name-only <base> --
   <prefix>` and `git ls-files --others --exclude-standard -- <prefix>`; with no such commit, or on a
   `code_unconfirmed` folder, every file under the prefix.
2. Rewrite each stale section or field (`<doc>`: `<type>:<name>`). Take a section's base hash from the
   naming line of `specstone get <doc>#<section key>`, a field's from `bases.fields.<id>` in
   `specstone get <doc> --json`. Pipe the new text to `specstone set <doc>#<section key> --base <hash>` (a
   field: `--field <id>` in place of `#<section key>`). Each such write turns the doc into a draft; only the Owner's
   `specstone approve` clears it.
3. Run `specstone check`. Take each finding on a record code path or `covers:` entry that a covering doc holds or
   that names a changed path, and fix it through `specstone set --field`: pipe the corrected list to
   `specstone set implementation:<feature> --field implements --target <name> --base <hash>` (or
   `specstone set <doc> --field covers --base <hash>`), the hash from `bases.fields.implements` (or
   `bases.fields.covers`) in the same doc's `get --json`:
   - moved file: point each record entry that names it at the new side of its rename pair, relative to that target's
     code root; the stories and FRs, which name no code, stay as they are;
   - deleted file: drop the entry, or point it at the code that does the work now.

   A changed path's target alone: compare and fix its record and `covers:` entries, never another target's.
   A record code-path or `covers:` write leaves the draft flag untouched: an approved doc keeps its approval.
4. A test the task adds or moves for an FR: write a `tests` line `<item>:<test file path>` on that FR's record entry,
   as in step 3 (`--field tests`, hash from `bases.fields.tests`).
5. A changed AGENT.md asset: compare each rule meaning it holds with the rule list of the FR that writes agent files;
   draft a missing rule into that FR or report it as code beyond the spec.
6. A bare item ID such as `E21`, or a number label, in changed code: report its file and line.
7. Repeat step 3 until those docs show no pointer finding.

## 5. Draft first: behavior no spec holds

Take this step for a path no spec covers, and for new behavior in a covered path no section states. Spec text
first, pointer after.

- **Needs a new story or FR:** leave it out of this sync; hand it to `specstone:brainstorming-sdd`.
- **Else:** write a spec draft: `specstone new <type>` (`--parent <name>`, `--slug <slug>`, `--target <name>`, the
  path's code target, as the type takes them) for a new doc, or `specstone set` for a section of an existing one. Get
  it approved through `specstone:expert-sdd`'s Owner confirmation.
- Write no record code path or `covers:` entry that names this code until the Owner approves the draft. Then add the
  entry at once with the step 4.3 `specstone set --field` write, on the path's target's record: no `check` finding will
  ask for it.

## Report to the Owner

After your last write, run one `specstone approve --dry-run --json`, the source of every count, never your own tally.
Your drafts are the docs your own list names, those whose text you wrote: list them with their count and each one's
dropped and new sentence counts; name each other draft it lists, never counted; one of yours it shows as no draft is a
finding. Then list each pointer fixed, each behavior handed to `specstone:brainstorming-sdd`, and each pointer that
waits on an approval, with its doc, its code target, and its code path.
