**Helper test** of a `code_uncovered` file, before any report (sync step 3, bootstrap-spec step 3).

- Find its callers by `git grep -l` on its import path or file name in its own code target's roots.
- Find each caller's covering doc by `specstone context --code <code root>/<path> --for implement --out`.
- Helper: code files call it, all under one spec doc's `covers`, and it shows no observable behavior of its own.
- No helper (no caller, callers under two or more docs, under a record's `implements` alone, or in another code target, or a behavior of its own): report it under `Uncovered:`.
- Caller doc not `draft: true`: add its path to that doc's `covers` as a bare entry by sync `procedure.md` step 4.3 (`--field covers`, `--base`, `--target`), then that step's `check --out` rerun.
- Stamp it with its `code_unconfirmed` fingerprint by `specstone set <doc> --stamp <entry>=<fingerprint>`; report it under `Pointers:`; write no spec draft; ask the Owner nothing.
- Caller doc a pending draft: write nothing; list it under `Pointers:` as waiting; once approved, write the entry, rerun `check`, stamp.
