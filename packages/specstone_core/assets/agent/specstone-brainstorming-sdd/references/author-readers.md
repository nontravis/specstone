Author mode's reader step: run it once per decision before your first write.

- Each term a decision adds, changes, or supersedes, and each short form (the key noun alone): one
  `specstone search "<term>"`, narrowed by `--type` or `--under` when the term is common.
- Each doc you change: the `Inbound` lines of one `specstone refs` call on it. A reader the step changes gets no
  `refs` call: one hop, no recursion.
- Each feature you touch, and each of its ancestors: its summary sections: `benefit_hypothesis`,
  `flow`, and `out_of_scope`, and each spec doc section that lists the feature's parts or traces its FRs.
- A reader stating a changed rule is changed, or its copy gives way to a link to the owner's item; no copy stays
  beside the link. A `--repeats` check is no part of this step.
- A decision that replaces or narrows a section's rule: first read that section's current text in the saved bundle
  files, with no `get`. With no saved file holding the section, first run one
  `specstone context <doc> --for design --out` for it, never `get`, then read the section from the file it saves.
  Then run one `specstone search "<phrase>"` per key noun phrase of that text, beside the term searches. Each hit
  that states the replaced rule, in any wording, is a reader.
