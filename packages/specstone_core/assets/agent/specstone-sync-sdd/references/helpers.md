**Helper test** of a `code_uncovered` file, before any report (sync step 3, bootstrap-spec step 3). Find its callers
with `git grep -l` on its import path or file name inside its own code target's roots, and each caller's covering doc
with `specstone context --code <code root>/<path> --for implement --out`.

| The file | Result |
|---|---|
| One or more code files call it, every one under one spec doc's `covers`; reading it shows no observable behavior of its own | A helper |
| No caller, callers under two or more docs, callers under a record's `implements` alone, callers in another code target, or a behavior of its own | No helper: report it under `Uncovered:` |

A helper whose caller doc prints no `draft: true`: add its path to that doc's `covers` as a bare entry, written as
`procedure.md` step 4.3 gives (`--field covers`, `--base`, `--target`); rerun `check`; its `code_unconfirmed`
finding gives the fingerprint, which `specstone set <doc> --stamp <entry>=<fingerprint>` writes. Report it under
`Pointers:`; write no spec draft; ask the Owner nothing.

A helper whose caller doc is a pending draft: write nothing; list it under `Pointers:` as waiting, written once that
draft is approved.
