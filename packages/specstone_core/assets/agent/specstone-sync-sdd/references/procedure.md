**Code target** (two or more `targets:`): a changed path's target is the `code target:` line, or the `codeTarget` key
under `--json`, of its `context --code --out` call, covered or not, and a deleted path's is the finding DocPath's; each
`get`, `set`, and `new` of a per-target doc carries `--target <name>`, or addresses the doc by its DocPath. Compare
and fix only that target's record and `covers:` entries, and each `root: project` entry (step 3), of no target.

## 2. Take the work list

Your gate file gives it: each `code_suspect`, `code_unconfirmed`, `implements_path_unresolved`,
`implements_symbol_unresolved`, `covers_path_missing`, `code_uncovered`, `tests_unresolved`, and matrix-row
finding with `waitsFor` `agent` (step 4.5), never a `tests_missing` one. A feature named: every code link of it that takes a state instead, a waiting code target's left
out.

## 3. Find the covering docs

A finding's `path` is from its target's code root (`code_root:` per `targets:` entry in `.specstone/config.yaml`;
default `.`). From the project root, `--code` and each git pathspec take `<code root>/<path>`.

For each listed code path but a `tests_unresolved` line's or a matrix row's (steps 4.4, 4.5), run
`specstone context --code <code root>/<path> --for implement --out`, which takes its path's target and no
`--target`; read parts of its read-first and refs files per `specstone-read-sdd`. A `root: project` entry (its field's
`root` in `specstone guide <type> --json`, once per type) takes none: its path is from the project root, its
covering doc the doc its finding names: `specstone context <doc> --for implement --out`.

- **Warning `no doc covers or implements <path>`:** A rename pair's new side goes to step 4.3. Else read the
  file, write nothing for it; report under `Uncovered:` its path, the observable behavior it adds that no spec
  states, and whether that needs a new story or FR.
- **64, `code_path_not_found`:** the file moved or is gone; step 4.3 fixes the entries naming it.
- **Any other exit:** report the CLI's error and stop.

## 4. Compare, then write

1. Compare the approved text of every covering doc with each link's code file; a doc printing `draft: true` is a
   pending draft. A `code_suspect` folder's code is the files changed under it since its stamp:
   `git log -1 --format=%H -S '<recorded>' -- docs/<DocPath>` gives `<base>`, then
   `git diff --name-only <base> -- <prefix>` and `git ls-files --others --exclude-standard -- <prefix>`; with no such
   commit, or on a `code_unconfirmed` folder, every file under the prefix.
2. Write by outcome through step 4.3's `set --field`, which keeps the draft flag. A pending draft among the covering
   docs holds every write of a match and of a `planned` entry's fingerprint: list a match as a waiting pointer,
   written whole once approved (fingerprint, and on a `planned` entry `implemented`). Else a named feature's
   `clean` link takes no fingerprint, only a `planned` entry's `implemented`:
   - **Match:** the finding's `fingerprint` ending the link's entry, any pointer fix, and for a `planned` entry
     `implemented` in its `statuses`; never `skipped` or `deprecated`. Then `task-refs.md` removes closed tasks' refs.
   - **A `planned` entry's code lacking its planned behavior yet** is no mismatch, no question: the fingerprint
     alone, still `planned`.
   - **Mismatch**, code behavior the approved text contradicts: nothing for the link; report each point under
     `Mismatches:`: doc and section, what the spec states, what the code does. A fix-the-spec pick sent to you: write
     each stale section as a spec draft (step 5); the fingerprint awaits its approval.
3. Fix each record code-path or `covers:` finding of a covering doc: pipe the corrected list to
   `specstone set implementation:<feature> --field implements --target <name> --base <hash>` (hash:
   `bases.fields.<field>` of `get --json`; or `--field covers` on the spec doc), then rerun
   `specstone check --out "<folder>/reports/check.sync.<XXXXXX>.txt"`, searching its file, until those docs hold none:
   - moved file: point each record entry naming it at its rename pair's new side, relative to that target's
     code root; find the pair with
     `git log -1 -M --diff-filter=R --name-status --format= -- <old path>`, or `git diff -M --name-status HEAD` while
     uncommitted; write no fingerprint;
   - deleted file: drop the entry, or point it at the code doing that work;
   - `root: project` entry: fingerprint alone, never moved; its `covers_path_missing` is only reported as
     `<doc>: covers path missing: <path>`, ending its loop.
4. A `tests_unresolved` line: repoint it with
   `specstone set implementation:<feature> --field tests --target <name> --base <hash>` to the moved file of step 4.3
   or the test's current name in it; one you cannot place stays, a waiting pointer. Write no `tests` line for a
   test a change adds or moves.
5. A matrix-row finding: follow `matrix-rows.md`.
6. Report under `Mismatches:`, by file and line, each rule meaning a changed AGENT.md asset holds that the
   agent-files FR's rule list lacks, and each bare item ID (`E21`) or number label in changed code or a test file
   read for step 4.4.

## 5. Spec drafts

Follow `spec-drafts.md` on the Owner's write-a-spec or fix-the-spec pick sent to you.

## Report to the Owner

After your last write, run one `specstone approve --dry-run --json`, the source of every count.
Your drafts are the docs your own list names: list them with their count, each one's dropped and new sentence counts,
and one sentence on why it changed, never its text; name each other draft it lists, never counted; one of yours it
shows as no draft is a finding. Then list each `Mismatches:` point, each `Uncovered:` file, each pointer or row fixed, each
covers path missing line, each task removed, each behavior handed to `specstone-brainstorming-sdd`, and each waiting pointer or row: its code target, and its doc and code path, or its tasks.
