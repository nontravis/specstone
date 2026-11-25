# Owner confirmation of a delete or a migrate

Items 1 and 3 of `specstone-expert-sdd`'s "Owner confirmation" when the item is not a draft.

- The view is the list or plan and the `plan <hash>` line of `specstone delete <path> … --dry-run` or of
  `specstone migrate --dry-run`, and why each file goes.
- The command, after `ok`, is one of these, with the shown `<hash>`:
  - `specstone delete <path> … --yes --plan <hash>`
  - `specstone migrate --yes --plan <hash>`
