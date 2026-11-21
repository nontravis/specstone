# Ground the change

Read this before step 1's first call in `../SKILL.md`. Every grounding call keeps `--out` bare and last and passes no
`--budget` and no `--target`: a design read spans every code target.

## Pick the targets

Target the smallest doc that holds the whole change:

- **One story:** the story, for a change inside it.
- **Across stories:** the feature.
- **A new feature:** the project doc.
- **A new story:** the feature with `--summary`.
- **Several docs:** each doc the change reaches, all named in one call; each further target adds no call:

  ```
  specstone context <doc> <doc> … --for design --out
  ```

## Several docs from the map

When the change reaches several stories, FRs, or docs you must pick from the docs tree, make this your first CLI
call, the gate:

```
specstone structure <doc> …
```

On 78 or another non-zero exit, act as step 1 gives; on 0, pick from its map each doc the change reaches, then name
them all in one `context` call.

## A story added

A change that adds a story runs no `structure` call. On its own it takes one call, the feature with `--summary`. When
it also changes existing docs, it takes two calls: the feature's `--summary` call first, the gate, then one naming
each existing doc it reaches:

```
specstone context <feature> --for design --summary --out
specstone context <doc> <doc> … --for design --out
```

## Read the files

Read each call's saved files by the read plan, as the `specstone-read-sdd` skill's read-plan rule gives, before the
brainstorm's first question. Keep each call's read plan line with its saved file paths: the design check and each
sweep take them together as `bundles`.
