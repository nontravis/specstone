Your Input Contract, Output Format, and Scope Boundaries bind.

- **Gate**: none; run only step 4's `check <doc>`. A `decided` brief's decided-only run has no group file, so it runs
  no gate `check` and gives no `Check:` line; it follows `decided.md` `## Decided-only run`, then `## Report`.
- With a `change note`, also judge by `decided.md` `## 1`.

## 1. Read the group file

- The `group file:` you were given, or the first call's for a group you run yourself. A `feature: <name>` work list takes its record's `covers:` links, its other spec docs' included.
- **Code target** (two or more `targets:`): compare and fix only the synced target's record and `covers:` entries, plus `root: project` entries; a path is from its target's `code_root:` (default `.`), a `root: project` entry's from the project root.
- Its code part holds each changed code file's diff (the whole file with no diff base), then each judged link's doc, its contract text.
- Its verdict part follows the `==> verdicts <==` line at column 0; `specstone set --sync` reads only that part; edit nothing above.
- Judge from the group file; read a test file only at a line it names or for `tests_unresolved`.
- A covering doc with `draft: true` is a pending draft.

## 2. Judge each line

Replace the `?` of each `? <doc> <entry> <fingerprint>` line; a line left `?` refuses the file.

- **`match`:** the code contradicts no fact the approved text printed for its link states and adds no `unstated behavior`; a `planned` entry's, a named feature's `clean` link included, also becomes `implemented`.
- **`planned`:** a `planned` entry whose code lacks its planned behavior yet; it stays `planned`, no Owner question.
- **`mismatch <doc> <entry>: <point>`:** one line per point where the code holds behavior the spec contradicts, naming the doc, section, what the spec states, and what the code does. Observable behavior the code adds is one more point, `unstated behavior`, unless a decided line, a PRD doc `specstone context --code <code root>/<path> --for implement --out` saves, or the FR of a story it lists, by `specstone context <story> --for implement --out`, states it; write no draft for it.
- Text ahead of the code, outside a `planned` entry: no match; delete its line; the link waits for its implementer.
- Keep each pre-filled `repoint`, `row`, `match`, and `remove-task` line; edit a `repoint` or `row` line only when it is wrong.
- **Moved, with no pre-filled `repoint`** (`implements_path_unresolved`, `covers_path_missing`, `tests_unresolved`): find the new path by `git log -1 -M --diff-filter=R --name-status --format= -- <old path>` (uncommitted: `git diff -M --name-status HEAD`) and write `repoint <doc> <entry> <new path>[:<new symbol>]`.
- A moved file whose fingerprint also differs keeps its verdict line to judge.
- Gone with no new path: repoint it at the code now doing that work; with none, a `mismatch` line: the spec states behavior no code holds.
- A `tests_unresolved` test you cannot place stays waiting; write no `tests` line for a test a change adds or moves.
- **`root: project` entry:** never repointed; report its `covers_path_missing` as `<doc>: covers path missing: <path>`.
- **`covers_entry_empty`, `covers_path_outside`:** write nothing, never repoint or drop; report `<doc>: covers entry empty: <entry>` or `<doc>: covers path outside: <entry>`.
- Matrix-row lines: `## Matrix rows`.
- A pre-filled `remove-task <task> <doc> <entry>` line names a task a commit to that link closes. Write none: the CLI removes a task only when each line naming it names a link the call writes as `match` or `planned`, else keeps it under `Kept:`. A `<task> · no refs` line: an earlier group removed that task; do nothing.
- A plan task's declared `tests` lines, then its `row` lines, go after the verdict lines.
- Report under `Mismatches:`, by file and line, each bare item ID (`E21`) or number label in changed code or a test file you read.

## 3. Write the group in one call

- Run `specstone set --sync <group file>` once; with two or more code targets add `--target <name>`, the synced one.
- It writes every doc its lines change, only your scope's, or none.
- Exit 0, even with a `Waiting:` or `Mismatches:` part: the runner writes each waiting line after approval.
- A stderr line `<path>:<line>: <code>: <message>` is a refused line: step 4.
- Else **75, `index_busy`** (any `specstone` command): rerun, no CLI error; **any other exit:** report the CLI's error and stop.

## 4. Answer each refused line

A refused file writes 0 docs: answer every refused line, then rerun `specstone set --sync`.

- **`stamp_stale`:** its code or FR changed since the group file: judge the line again by step 2 or `## Matrix rows`; a `match` or `planned` line takes the `fingerprint` line under its entry's `code_suspect` or `code_unconfirmed` finding, or its row's `suspect` finding, in the file `specstone check <doc> --out "<folder>/reports/check.sync.<XXXXXX>.txt"` saves.
- **`stamp_entry_unresolved`:** repoint the entry by step 2's moved rule (pre-filled or yours), a `root: project` entry reported as step 2 says; `file_unreadable`: report the unread code.
- **Any other code**, such as `verdict_unjudged` or `doc_not_found`, is your own line error: fix the named line and rerun, at most twice; then report it.

## 5. Spec drafts

On a fix-the-spec pick of `picks`:

- Hand a story or FR it needs to `specstone-brainstorming-sdd`.
- Else draft by `specstone new <type>`, or `specstone set <doc>#<section key> --base <hash>` for a section.
- Until approved, write no record code path or `covers:` entry naming this code; then point the doc at it by `specstone set <doc> --field covers --base <hash>`, or a record's `--field implements`.
- After the draft, replace the link's `mismatch` lines with one `match` line taking the `fingerprint` line under the link's finding in a step 4 `check <doc>` file, and rerun `specstone set --sync`.

## Matrix rows

- Mode: top-level `verification_coverage` of `.specstone/config.yaml`: off (absent, null, `false`), `fr` (`true`, `fr`), or `edge_case`.
- Off and `fr` read per-FR rows, ``- <item>: `<literal>`[, `<literal>` ...][ <fingerprint>]``; `edge_case` per-edge-case rows, ``- <item> <edge case>: `<literal>`[ <fingerprint>]``.
- The group file prints each row to judge with its FR's current contract text, each literal with its test file and line, and the FR or edge-case fingerprint a `match` line copies; compare no code.
- Leave a `waitsFor` `owner` row as written, never stamped: a pending FR draft's, waiting for its approval, or a per-edge-case row under off or `fr`, which only the Owner's `specstone migrate` folds.
- Write a row by `row <record> <item>[ <edge case>]: <sign><literal>[ <sign><literal>]…`: `+` adds a literal and `-` removes one, each `<literal>` in one code span, copied from the test file as it stands, its first literal when the name is split, interpolations kept; it holds no fingerprint.
- Stamp a row by `match <record> <item>[ <edge case>] <fingerprint>`, after the `row` line that writes it, if any.
- Stamp only when its tests still prove the upstream block: under `fr` the FR's contract, under `edge_case` its edge case; under off, stamp no row.
- Write no row for a new test; its implementer does.

- **Declared row**, a pre-filled `match` line: no re-read.
- **`suspect` row whose tests prove its block:** replace its `?` with `match`.
- **Tests proving none of the change:** replace its `?` with `mismatch <record> <item>[ <edge case>]: <point>`, naming its literals; it waits for its implementer.
- **`matrix_test_unresolved`, test renamed or moved into a file the item's `tests` lines name:** keep or edit the pre-filled `row` line; off or `fr` keep the row's fingerprint, and under `edge_case` a `match` line follows it.
- **Test in no such file:** delete the pre-filled `row` line; the row waits for its implementer.
- **`edge_case` alone, a `suspect` row whose test proves a split ID instead:** in place of its `?` line, write `row <record> <item> <edge case>: -<literal>`, then `row <record> <item> <split ID>: +<literal>` for the lowest proven split ID and its `match` line; when a row of that split ID and literal stands, only the `-` line.
- A test also proving the row's own edge case keeps it, stamped by `match`; other proven split IDs wait for the implementer.
- Under `fr`, a split moves no row: stamp or report the FR's row as above.
- **`edge_case`, a per-FR row's `matrix_row_malformed`:** read the FR's edge cases the group file prints and each literal's test; per edge case a literal's test proves, write `row <record> <item> <edge case>: +<literal>` and its `match` line.
- A literal proving none: a `mismatch` line naming row, FR, and literal; once each literal is placed or reported, one `row <record> <item>: -<literal> …` line removes the per-FR row.
- Name a waiting row by item, edge case under `edge_case`, and literals.

## Report

- Your drafts (docs your list names), from one `specstone approve --dry-run --json` after your last write: count, each one's dropped and new sentence counts and one sentence why, never text; other drafts it lists, uncounted; one of yours it shows as no draft is a finding.
- Under `Pointers:`, none for a decided-only run; else each pointer or matrix row fixed, each code fingerprint written, step 2's `covers` report lines, each line, link, or row waiting on an approval or its implementer, with its code target and the doc it waits for, each task removed, and each `Kept:` task with the link that kept it. The call lists none removed: one is a `remove-task` task no `Waiting:`, `Kept:`, or `<task> · no refs` output line names.
- Each `Mismatches:` point; each behavior handed to `specstone-brainstorming-sdd`; open questions.
- A group engineer with a `change note` gives no `Decision:` or `Not landed:` line; the decided engineer gives the lines of `decided.md`'s Report.
- Then `Findings:`, each line still refused after step 4's reruns, or `none`.
