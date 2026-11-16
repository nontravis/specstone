# Move the goals into the goal doc

The rest batch's steps for a `singular_doc_missing` under `prds/` and for the `section_undeclared` on PROJECT's goals
section, the goal move's start. Each write leaves a draft. Take each goal's horizon from the answers sent with the
batch; working with no batch, get them first as the skill's step 2 asks them.

## 1. A missing singular doc

- **`prds/GOAL.md`:** run `specstone new goal`. With no goals section left in PROJECT, stop there: its three
  sections stay empty, and no goal moves.
- **Any other DocPath**, such as the features doc's: run `specstone new <type>`, then fill it as the procedure's step 6
  fills a skeleton.

## 2. Move each answered goal

Read the goal doc with `specstone get goal:goal --json` first, then take PROJECT's goals in turn:

- **Kept:** a goal with no horizon answered, or whose `PG-` ID the goal doc already holds in any section, stays in
  PROJECT with its ID, never renumbered, and its section keeps its finding. List it once under open questions.
- **Moved:** write its block, ID kept, verbatim but for its links, its fields as the goal template's bullets, into its
  horizon's section, `long_term`, `mid_term`, or `short_term`. Pipe the section's whole body to
  `specstone set goal:goal#<key> --base <hash>`, the base `get` prints for it just before the write (the base of empty
  text for a section the doc lacks): first the goals it already held, verbatim and in place, then the moved ones in
  PROJECT's order. An empty goal doc takes the same path.
- **Its in-file links** (`#<anchor>`, no path): one to a goal that moves too stays as written; one to the goals section
  the move drops links to `GOAL.md` with no anchor; one to any other heading PROJECT keeps, a kept goal's or the goals
  section while a goal stays in it included, gains `PROJECT.md` as its path, its anchor unchanged. A link to another
  file keeps its path.

## 3. Drop the moved blocks, then repoint

1. Run `specstone get project --out "<file>"`, `<file>` a new
   `<folder>/reports/sdd-engineer.bootstrap.batch.<XXXXXX>.txt`, `<folder>` the path `specstone folder` prints.
   Delete each moved goal's block, and the goals section once no goal stays in it, then run
   `specstone set --batch "<file>"`.
2. Run `specstone refs project`. In each PRD or spec doc it lists, repoint each link to a moved goal's heading,
   measurement heads included, to that heading in the goal doc, its path relative to the citing doc and its anchor
   unchanged, so an in-file `#pg-…` link in PROJECT becomes `GOAL.md#pg-…`. A link to a kept goal keeps its target. A
   link to the goals section stays while a goal stays in it, and goes to the goal doc with no anchor once the section
   is dropped, in this run or a later one.
3. Write a spec doc's link in the code target its DocPath names. Leave the link of an untyped file, such as a design or
   a plan: it is no PRD or spec link.
