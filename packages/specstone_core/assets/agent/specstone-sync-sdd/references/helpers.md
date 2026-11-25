**Helper test** of a `code_uncovered` file, before any report (sync procedure step 3, bootstrap-spec step 3).

- Find its callers by `git grep -l` on its import path or file name in its own code target's roots.
- Find each caller's covering doc by `specstone context --code <code root>/<path> --for implement --out`.
- Helper: code files call it, all under one feature's record `covers`, and it shows no observable behavior of its own.
- No helper (no caller, callers under two or more records' `covers`, under a record's `implements` alone, or in another code target, or a behavior of its own): report it under `Uncovered:`, but when a decided line of your `change note` states its behavior, follow `decided.md`, its drafts or a `Mismatches:` point, never `Uncovered:`.
- No doc of the callers' feature spec folder `draft: true`: add the helper's path to the feature's record `covers` as a bare entry with no fingerprint, piping the list to `specstone set <record> --field covers --base <hash>` (`--target <name>` with two or more code targets), `<hash>` the `base` that `specstone get <record>` prints.
- Write no `match` line for it: no sync line kind adds an entry, and the next sync's group file holds it as `code_unconfirmed` for its first stamp.
- Report it under `Pointers:`; write no spec draft; ask the Owner nothing.
- A doc of that spec folder a pending draft: write nothing; list it under `Pointers:` as waiting, written the same way once approved.
