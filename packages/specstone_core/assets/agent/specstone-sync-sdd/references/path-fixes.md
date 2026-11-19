**Path fixes** (procedure.md step 4.3). Write each by the `set` and `check` rerun that step gives:

- moved file: point each record entry naming it at its rename pair's new side, relative to that target's
  code root; find it with
  `git log -1 -M --diff-filter=R --name-status --format= -- <old path>`, or `git diff -M --name-status HEAD` while
  uncommitted; write no fingerprint;
- deleted file: drop the entry, or point it at the code doing that work;
- `root: project` entry: fingerprint alone, never moved; its `covers_path_missing` is only reported as
  `<doc>: covers path missing: <path>`, ending its loop.
