Step 1, the gate, already ran in the skill or agent that sent you here.
As `specstone:sdd-engineer`, ask the Owner nothing: each step with the Owner goes into your report. Follow
`specstone:expert-sdd` for every doc you write.

**Code target** (two or more `targets:`): a changed path's target is the `code target:` line, or the `codeTarget` key
under `--json`, of its `context --code` call, covered or not, and a deleted path's is the finding DocPath's; each
`get`, `set`, and `new` of a per-target doc carries `--target <name>`, or addresses the doc by its DocPath. Compare
and fix only that target's record and `covers:` entries.

## 2. Take the work list

Your gate `check` gives it: each `code_suspect`, `code_unconfirmed`, `implements_path_unresolved`,
`implements_symbol_unresolved`, `covers_path_missing`, `code_uncovered`, and `tests_unresolved` finding, never a
`tests_missing` one. A feature named: every code link of it that takes a state instead, a waiting code target's left
out, each keeping its state.

## 3. Find the covering docs

For each listed code path but a `tests_unresolved` line's (step 4.4), run
`specstone context --code <path> --for implement`. It takes its path's code target, prints it, and carries no
`--target`.

- **Warning `no doc covers or implements <path>`:** a `code_uncovered` path. The new side of a rename pair (step 4.3's
  git commands) goes to step 4.3. Else read the file and write nothing for it; report it under `Uncovered:`: its path,
  what it does that no spec states, and whether that needs a new story or FR.
- **64, `code_path_not_found`:** the file moved or is gone. `specstone check` lists the record entries that still name
  it; step 4.3 fixes them.

## 4. Compare, then write

1. Compare the approved text of every covering doc with each link's code, its file; a doc printing `draft: true` is a
   pending draft. A `code_suspect` folder's code is the files changed under it since its stamp:
   `git log -1 --format=%H -S '<recorded>' -- docs/<DocPath>` gives `<base>`, then
   `git diff --name-only <base> -- <prefix>` and `git ls-files --others --exclude-standard -- <prefix>`; with no such
   commit, or on a `code_unconfirmed` folder, every file under the prefix.
2. Write by outcome through step 4.3's `set --field`, which leaves the draft flag as it was. A pending draft among the
   covering docs holds every write of a match and of a `planned` entry's fingerprint: list a match as a waiting
   pointer, written whole once the Owner approves (fingerprint, and on a `planned` entry `implemented`). Else a named
   feature's `clean` link takes no fingerprint, only a `planned` entry's `implemented`:
   - **Match:** the finding's `fingerprint` ending the link's entry, any pointer fix, and for a `planned` entry
     `implemented` in its `statuses`; never `skipped` or `deprecated`.
   - **A `planned` entry's code lacking its planned behavior yet** is no mismatch, no question: the fingerprint alone;
     the entry stays `planned`.
   - **Mismatch**, code behavior the approved text contradicts: nothing for the link; report each point under
     `Mismatches:`: doc and section, what the spec states, what the code does. A fix-the-spec pick sent to you: write
     each stale section as a spec draft (step 5); the fingerprint waits for its approval.
3. Fix each record code-path or `covers:` finding a covering doc holds: pipe the corrected list to
   `specstone set implementation:<feature> --field implements --target <name> --base <hash>` (hash:
   `bases.fields.implements` of `get --json`; or `--field covers` on the spec doc), then run `specstone check` until
   no such finding of those docs is left:
   - moved file: point each record entry that names it at the new side of its rename pair, relative to that target's
     code root; the stories and FRs, which name no code, stay as they are; find the pair with
     `git log -1 -M --diff-filter=R --name-status --format= -- <old path>`, or `git diff -M --name-status HEAD` while
     the move is uncommitted; write no fingerprint;
   - deleted file: drop the entry, or point it at the code that does the work now.
4. A `tests_unresolved` line: repoint it with
   `specstone set implementation:<feature> --field tests --target <name> --base <hash>` to the moved file of step 4.3
   or the test's current name in it; one you cannot place stays as written, among the waiting pointers. Write no
   `tests` line for a test a change adds or moves.
5. Report under `Mismatches:` each rule meaning a changed AGENT.md asset holds that the rule list of the agent-files
   FR lacks, and the file and line of each bare item ID such as `E21`, or number label, in changed code or a test file
   read for step 4.4.

## 5. Spec drafts, pointers after

On the Owner's write-a-spec or fix-the-spec pick sent to you, a story or FR it needs goes to
`specstone:brainstorming-sdd`. Else write the draft: `specstone new <type>` (`--target <name>`, the path's code
target, as the type takes it) for a new doc, or `specstone set <doc>#<section key>` for a section of an existing one;
the Owner approves it with `specstone approve`. Write no record code path or `covers:` entry that names this code
until the Owner approves the draft. Then add the entry at once with the step 4.3 `specstone set --field` write, on the
path's target's record.

## Report to the Owner

After your last write, run one `specstone approve --dry-run --json`, the source of every count, never your own tally.
Your drafts are the docs your own list names: list them with their count, each one's dropped and new sentence counts,
and one sentence on why it changed, never its text; name each other draft it lists, never counted; one of yours it
shows as no draft is a finding. Then list each `Mismatches:` point, each `Uncovered:` file, each pointer fixed, each
behavior handed to `specstone:brainstorming-sdd`, and each pointer that waits on an approval, with its doc, its code
target, and its code path.
