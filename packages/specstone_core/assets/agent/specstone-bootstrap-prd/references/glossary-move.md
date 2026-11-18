# Move the glossary into the glossary doc

The rest batch's steps for a `singular_doc_missing` at `prds/GLOSSARY.md` and for the `section_undeclared` on PROJECT's
glossary section, the glossary move's start. Each write leaves a draft. Ask the Owner nothing.

## 1. A missing glossary doc

Run `specstone new glossary`, then title it as section 2's first step says. With no glossary section left in PROJECT,
stop there: its `terms` section stays empty, and no entry moves.

## 2. Move each entry

Read the glossary doc with `specstone get glossary:glossary --json` first. Unless its title already reads
`Domain glossary`, the one `specstone guide glossary` names, pipe `Domain glossary`, with no `#`, to
`specstone set glossary:glossary --title --base <hash>`, `bases.title` its base. A glossary doc already there takes the
same retitle, empty or holding entries. Then take PROJECT's glossary entries in turn. An entry is one top-level item of
the section with its nested items; its term is the text of its leading `**…**` span, trimmed, compared with case
ignored. An item with no leading bold span has no term and always moves.

- **Kept:** an entry whose term the glossary doc already holds stays in PROJECT, never renamed, and its section keeps
  its finding. List it once under open questions.
- **Moved:** write each other entry verbatim but for its links and joined lines, never shortened. An entry written over
  several lines has its own lines joined into one, words unchanged, so it meets the `terms` section's `max_item_lines`.
  Pipe the `terms` section's whole body to `specstone set glossary:glossary#terms --base <hash>`, the base `get` prints
  for it (the base of empty text for a section the doc lacks): first the entries it already held, verbatim and in
  place, then the moved ones in PROJECT's order. An empty glossary doc takes the same path. An entry over 300
  characters gets `item_over_limit` there and waits as the procedure's size row says.
- **Its in-file links** (`#<anchor>`, no path): one to a heading PROJECT keeps, the glossary section while an entry
  stays in it included, gains `PROJECT.md` as its path, its anchor unchanged; one to the glossary section the move drops
  links to `GLOSSARY.md` with no anchor; one to a goal the batch's goal move moved (`#pg-…`) links to `GOAL.md#pg-…`,
  its anchor unchanged; one to the goals section that move dropped links to `GOAL.md` with no anchor. A link with a path
  keeps it.

## 3. Drop the moved entries, then repoint

1. Run `specstone get project --out "<file>"`, `<file>` a new
   `<folder>/reports/sdd-engineer.bootstrap.batch.<XXXXXX>.txt`, `<folder>` the path `specstone folder` prints. When the
   batch also runs the goal move, finish its drop first: this `get` then holds PROJECT's current base. Delete each moved
   entry, and the glossary section once no entry stays in it. When the section drops, also point each
   `#domain-glossary` link PROJECT keeps at `GLOSSARY.md`, in the same file: `refs` lists no link of PROJECT to itself.
   Then run `specstone set --batch "<file>"`: no other write to PROJECT follows it.
2. Run `specstone refs project`. In each PRD or spec doc it lists, repoint each link to the glossary section to
   `GLOSSARY.md` with no anchor, its path relative to the citing doc, once the section is dropped, in this run or a
   later one. While an entry stays in the section, each link to it stays;
   a link to another heading of PROJECT, or to PROJECT with no anchor, stays.
3. Write a spec doc's link in the code target its DocPath names. Leave the link of an untyped file, such as a design or
   a plan: it is no PRD or spec link.
