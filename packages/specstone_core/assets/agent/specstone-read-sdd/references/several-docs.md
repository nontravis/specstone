# Ground several docs

Read this before your first CLI call when `design` or `query` work reaches more than one doc, or when you must pick
the doc that holds a design change. A plan task names its docs and skips this file.

## Pick the targets

- **One doc in `design`:** the smallest doc that holds the change. A story's bundle holds its sibling stories in
  summary; a feature's holds them whole; add `--summary` on the feature to add a story.
- **Several docs in `design` or `implement`:** name each doc the change reaches in the one `context` call. Each
  further target adds no tool call, and the siblings the call does not name come in summary:

  ```
  specstone context <doc> <doc> … --for <mode> --out
  ```

- **`--summary`:** a target you want in summary takes `--summary` in a call of its own.
- **`query`:** each doc takes a call of its own.
- **A change that adds a story:** ground it as the brainstorm's grounding gives it, with no `structure` call.

## Map first

When the change reaches several stories, FRs, or docs you must pick from the docs tree, make this your first CLI
call, with no `--target`:

```
specstone structure <doc> …
```

It never refuses `argument_missing`, and it is also the project gate: on 78 with `project_not_found`, stop as
`../SKILL.md` gives. Pick from its map each doc the change reaches, then name them all in the one `context` call
above. The `structure` call counts toward the call bound; a plan task runs none.

Then read the files that call saves by its read plan, as `../SKILL.md` gives.
