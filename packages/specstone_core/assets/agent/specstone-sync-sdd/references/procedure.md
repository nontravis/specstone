**Code target** (two or more `targets:`): compare and fix only the synced code target's record and `covers:` entries, plus `root: project` entries.

- A path is from its target's code root (`code_root:` of its `targets:` entry, default `.`); a `root: project` entry's is from the project root.

## 1. Read the group file

- The `group file:` you were given, or the first call's for a group you run yourself.
- Its code part holds each changed code file's diff, or the whole file with no diff base, then each judged link's doc, its contract text.
- Its verdict part follows the `==> verdicts <==` line at column 0; `specstone set --sync` reads only that part, so fill it in place and edit nothing above.
- Judge from the group file; read a test file only at a line it names or for a `tests_unresolved` line.
- A covering doc with `draft: true` is a pending draft.

## 2. Judge each line

Replace the `?` of each `? <doc> <entry> <fingerprint>` line; a line left `?` refuses the file.

- **`match`:** the code contradicts no fact the approved text printed for its link states and adds no `unstated behavior`; a `planned` entry's, a named feature's `clean` link included, also becomes `implemented`.
- **`planned`:** a `planned` entry whose code does not hold its planned behavior yet; it stays `planned`, with no Owner question.
- **`mismatch <doc> <entry>: <point>`:** one line per point where the code holds behavior the spec contradicts, naming the doc, section, what the spec states, and what the code does. Observable behavior the code adds is one more point, named `unstated behavior`, when no decided line states it, nor a PRD doc `specstone context --code <code root>/<path> --for implement --out` saves, nor the FR a story it lists states, which `specstone context <story> --for implement --out` saves; write no draft for it.
- Text ahead of the code, outside a `planned` entry: no match; delete its line and list the link as waiting for its implementer.
- Keep each pre-filled `repoint`, `row`, and `match` line; edit a `repoint` or `row` line only when it is wrong.
- **Moved, with no pre-filled `repoint`** (`implements_path_unresolved`, `covers_path_missing`, `tests_unresolved`): find the new path by `git log -1 -M --diff-filter=R --name-status --format= -- <old path>` (uncommitted: `git diff -M --name-status HEAD`) and write `repoint <doc> <entry> <new path>`.
- A moved file whose fingerprint also differs keeps its verdict line to judge.
- Gone with no new path: repoint it at the code now doing that work; with none, write a `mismatch` line: the spec states behavior no code holds.
- A `tests_unresolved` test you cannot place stays waiting; write no `tests` line for a test a change adds or moves.
- **`root: project` entry:** never repointed; report its `covers_path_missing` as `<doc>: covers path missing: <path>`.
- **`covers_entry_empty`:** write nothing and set no pointer; report `<doc>: covers entry empty: <entry>`.
- Matrix-row lines: follow `matrix-rows.md`; `remove-task` lines: follow `task-refs.md`.
- A plan task's declared `tests` lines, then its `row` lines, go after the verdict lines.
- Report under `Mismatches:`, by file and line, each bare item ID (`E21`) or number label in changed code or a test file you read.

## 3. Write the group in one call

- Run `specstone set --sync <group file>` once, with `--target <name>`, the synced code target, when the project has two or more code targets.
- It writes every doc its lines change, or none.
- Exit 0, a `Waiting:` or `Mismatches:` part included: list each waiting line and its doc; the runner writes it after approval.
- A stderr line `<path>:<line>: <code>: <message>` is a refused line: step 4.
- Else **75, `index_busy`:** rerun; **any other exit:** report the CLI's error and stop.

## 4. Answer each refused line

A refused file writes 0 docs: answer every refused line, then rerun `specstone set --sync`.

- **`stamp_stale`:** its code or FR changed since the group file: judge the line again by step 2 or `matrix-rows.md` and write it again, a `match` or `planned` line taking the `fingerprint` line under its entry's `code_suspect` or `code_unconfirmed` finding, or its row's `suspect` finding, in the file `specstone check <doc> --out "<folder>/reports/check.sync.<XXXXXX>.txt"` saves.
- **`stamp_entry_unresolved`:** repoint the entry by step 2's moved rule, a pre-filled `repoint` line or one you write, but report a `root: project` entry as step 2 does; `file_unreadable`: report the unread code.
- **Any other code**, such as `verdict_unjudged`, `stamp_entry_unknown`, `doc_not_found`, or `argument_invalid`, is your own line error: fix the named line and rerun `specstone set --sync`, at most twice, then report the refused line.

## 5. Spec drafts

On the Owner's fix-the-spec pick sent to you:

- Hand a story or FR it needs to `specstone-brainstorming-sdd`.
- Else draft by `specstone new <type>`, or `specstone set <doc>#<section key> --base <hash>` for a section.
- Until approved, write no record code path or `covers:` entry naming this code; then point the doc at it by `specstone set <doc> --field covers --base <hash>`, or a record's `--field implements`.
- After a fix-the-spec draft, replace the link's `mismatch` lines with one `match` line with the `fingerprint` line under the link's finding in a step 4 `check <doc>` file, then rerun `specstone set --sync`, which lists it under `Waiting:`.

## Report to the Owner

- After your last write, run one `specstone approve --dry-run --json` for all counts.
- Your drafts (docs your list names): count, each one's dropped and new sentence counts, one sentence why, never text.
- Name other listed drafts, uncounted; one of yours shown as no draft is a finding.
- Then list `Mismatches:` points, under `Pointers:` pointers or rows fixed, covers path missing and covers entry empty lines, tasks removed and kept, behaviors handed to `specstone-brainstorming-sdd`, and each waiting line with its code target and the doc it waits for.
