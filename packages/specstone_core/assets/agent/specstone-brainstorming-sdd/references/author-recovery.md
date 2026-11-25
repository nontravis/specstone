`output_not_writable`: run a write command or a `get` first. Fix each fault the refusal names, then rerun the batch:

- Stale block: merge your edit into its printed text; no `get`.
- Gone block (doc deleted or moved): read again by its name and the block's section key; a moved doc's new block takes
  the edit. A name that names no doc, or an untyped block: drop it, its doc under `Findings:`.
- One part twice, or a whole-doc block beside another of its doc: join them; a field or title block goes inside it.
- A removed required section, a field only the Owner or Specstone sets, or an open fence: restore the section, give the
  field back its value, close the fence.
- An undeclared section `check` reports: fix it in its draft as the finding names.
- A refused path or line: rebuild the file from `get` text output alone, and pass its path.
- Any other refusal: fix the part it names. An unchanged block counts as no draft.
