An `untyped_doc` whose content goes into a `prds/` or `measurements/` doc, a `specs/` path or a file whose doc type a pack dropped included:
follow its finding's `fix`, else merge it into the doc that takes it, else a new one from `specstone new <type>`.

- Several old files for one new doc, or one whose doc exists: each into that doc in turn, never a second one.
- A file whose finding's `to` lists a type outside `prd-core` waits for `specstone-bootstrap-spec`.
- Leave each `required_field_missing` and `required_section_missing` of the new doc to this round's fill.

Skip only a sentence its new doc holds word for word; one that differs by a word is merged. Never target the old file.
Add its path to this run's retire set, also when no sentence is left to merge.
