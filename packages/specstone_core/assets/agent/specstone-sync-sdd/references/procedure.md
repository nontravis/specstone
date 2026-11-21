**Code target** (two or more `targets:`):

- A changed path's target: its `context --code --out` call's `code target:` line (`codeTarget` in `--json`); a deleted path's: the finding DocPath's.
- Compare and fix only that target's record and `covers:` entries, plus `root: project` entries.

## 2. Take the work list

- Take your gate file's `code_suspect`, `code_unconfirmed`, `implements_path_unresolved`, `implements_symbol_unresolved`, `covers_path_missing`, `code_uncovered`, `tests_unresolved`, and `waitsFor` `agent` matrix-row findings (step 4.5); never `tests_missing`.
- Feature named: instead its every code link that takes a state, but a waiting code target's.

## 3. Find the covering docs

- A finding's `path` is from its target's code root (`code_root:` per `targets:` entry in `.specstone/config.yaml`, default `.`); from the project root, `--code` and git pathspecs take `<code root>/<path>`.
- A `root: project` entry's path (field `root` in `specstone guide <type> --json`, once per type) is from the project root, unprefixed.
- Per listed code path but `tests_unresolved` lines and matrix rows (steps 4.4, 4.5), run `specstone context --code <code root>/<path> --for implement --out`; a `root: project` entry's: `--code <path>`, its own target, no `--target`.
- Read parts of read-first and refs files per `specstone-read-sdd`.
- **Warning `no doc covers or implements <path>`:** a rename pair's new side: step 4.3; else `helpers.md` first.
- Left by `helpers.md`: read, write nothing; report under `Uncovered:` its path, its observable behavior no spec states, and whether it needs a new story or FR.
- **64, `code_path_not_found`:** moved or gone: step 4.3.
- **75, `index_busy`:** rerun.
- **Any other exit:** report the CLI's error and stop.

## 4. Compare, then write

1. Compare each covering doc's approved text with each link's code; a `draft: true` doc is a pending draft.
   - `code_suspect` code: files changed since the stamp; `git log -1 --format=%H -S '<recorded>' -- docs/<DocPath>` gives `<base>`, then `git diff --name-only <base> -- <prefix>` and `git ls-files --others --exclude-standard -- <prefix>`.
   - No such commit, or `code_unconfirmed`: every file under the prefix.
2. Write by outcome through `set`.
   - A pending covering draft holds every match write and `planned` fingerprint: list the match as waiting, written once approved.
   - A named feature's `clean` link takes no fingerprint, only a `planned` entry's `implemented`.
   - **Match:** code does what approved text states, or a `planned` entry's code lacks its behavior yet (ask nothing; stays `planned`).
   - Text ahead of code, but a `planned` entry's: no match, no stamp; list it as waiting for its implementer.
   - Stamp a match: `set <doc> --stamp <entry>=<fingerprint>` (the finding's, no `get`; `<entry>` as held, `<item>:<path>[:<Symbol>]`), then `--field` pointer fixes.
   - `planned` entry: `implemented` in `statuses`; never `skipped` or `deprecated`.
   - After each stamp or `implemented` write, follow `task-refs.md`.
   - **`stamp_stale`:** rejudge the current code, fresh `check` fingerprint; stamp a match, else report a mismatch.
   - **`stamp_entry_unknown`:** re-read the entry; stamp once more.
   - **`stamp_entry_unresolved`:** `file_unreadable`: report unread code; else step 4.3.
   - **Mismatch** (code contradicts approved text): write nothing for the link; report each under `Mismatches:`: doc and section, spec text, code behavior.
   - Fix-the-spec pick: draft each stale section (step 5); its fingerprint awaits approval.
3. Code-path or `covers:` finding: pipe the corrected list to `specstone set implementation:<feature> --field implements --target <name> --base <hash>`, or `--field covers` on the spec doc.
   - Rerun `specstone check --out "<folder>/reports/check.sync.<XXXXXX>.txt"`, searching its file, until those docs hold none.
   - Moved: repoint each record entry to the rename's new side, from its target's code root, by `git log -1 -M --diff-filter=R --name-status --format= -- <old path>` (uncommitted: `git diff -M --name-status HEAD`); no fingerprint.
   - Deleted: drop the entry, or point it at the code doing that work.
   - `root: project` entry: fingerprint only, never moved; only report its `covers_path_missing`, as `<doc>: covers path missing: <path>`; its loop ends.
   - `covers_entry_empty` (no code-pointer finding): write nothing; only report `<doc>: covers entry empty: <entry>`; its loop ends.
4. `tests_unresolved`: repoint by `specstone set implementation:<feature> --field tests --target <name> --base <hash>` to step 4.3's moved file or the test's current name; an unplaceable one stays waiting.
   - Write no `tests` line for a test a change adds or moves.
5. Matrix-row finding: follow `matrix-rows.md`.
6. Report under `Mismatches:`, by file and line, each bare item ID (`E21`) or number label in changed code or step 4.4 test files.

## 5. Spec drafts

On the Owner's write-a-spec or fix-the-spec pick sent to you:

- Hand a story or FR it needs to `specstone-brainstorming-sdd`.
- Else draft by `specstone new <type>`, or `specstone set <doc>#<section key> --base <hash>` for a section.
- Until approved, write no record code path or `covers:` entry naming this code; then add it by step 4.3 on its target's record.

## Report to the Owner

- After your last write, run one `specstone approve --dry-run --json` for all counts.
- Your drafts (docs your list names): count, each one's dropped and new sentence counts, one sentence why, never text.
- Name other listed drafts, uncounted; one of yours shown as no draft is a finding.
- Then list `Mismatches:` points, `Uncovered:` files, under `Pointers:` pointers or rows fixed, helpers joined, covers path missing and covers entry empty lines, tasks removed, behaviors handed to `specstone-brainstorming-sdd`, and each waiting pointer, row, or helper with its code target, doc and code path, or tasks.
