# A refused batch

`author.md` reads this when `specstone set --batch` refuses a batch.

After exit 73, first run a write or `get` to end its journal. Fix each fault; rerun:

- Stale block: merge your edit into the reply's block; run no `get`.
- Gone block: re-read its doc by name, a moved doc's new block taking the edit. Drop a block naming no doc or
  typeless, its doc under `Findings:`.
- Part twice, or a whole-doc block beside another of its doc: join them, a field or title block into the whole-doc
  one.
- Removed required section, or a field only the Owner or Specstone sets: restore it; open fence: close it.
- Refused path or line: rebuild the file from `get` text output alone; any other refusal: fix the part it names.
