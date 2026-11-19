Merge an `untyped_doc` under `specs/` into the doc that takes it, else a new one:

- one feature's old-named spec files: their type's doc;
- an event or message schema: an internal one to the architecture doc's `## Interaction`, an
  outside system's to the integration doc's `## Events`;
- a migration or rollout note: the architecture doc's `## Rollout`;
- a folder under `specs/topics/`: its topic (`--slug <folder>`);
- `specs/INDEX.md`: each code path in it to `covers` and the `code` roots (procedure step 6), the source-of-truth table to the
  API docs, a cross-cutting statement to the tech stack's `## Constraints` or a topic doc; quote in step 6 each line
  only about the old index, as a line with no home.

Skip only a sentence its new doc holds word for word; never target the old file. Add its path to this run's
retire set.
