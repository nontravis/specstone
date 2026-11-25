A source is a spec or design another tool wrote: a file, a link or issue the Owner gave, or the current conversation.

Match a source item by its content shape alone, never by the tool that wrote it; each lands as its type's
`specstone guide <type>` says; a gap goes to the Owner.

| Content shape | Lands in |
|---|---|
| numbered "As a … I want … so that …" lines | a story's Use Case |
| Given/When/Then or WHEN/THEN lines | a story's Acceptance Criteria scenarios |
| `FR-###` lines, or lines with "shall", "SHALL", or "MUST" | an FR's Statement |
| success criteria, `SC-###` | the feature's Success measures |
| a Problem Statement | the feature's Problem |
| an Out of Scope list | the feature's Out-of-scope lines |
| implementation and testing decisions | the feature's spec docs, and an FR's Verification |
| ticket lists, task lists, plans | not taken: task management is out of scope |

## Take in the source

1. **Gate**: the skill's step 1 makes the `context project` call; on 78 the source stays unread.
2. **Judge the path**: a file inside the CheckedFolders (the first folder, right under the docs folder, of a doc
   path in the gate bundle's `==> ` headers) is no source. Read none of it; make item 4's call with its path as the
   target and no `--summary`:
   - **64, `untyped_target`:** tell the Owner in one line it is the project's own old doc; name
     `specstone-bootstrap-prd` or `specstone-bootstrap-spec`, which merge it into typed docs. Run nothing else on
     its path.
   - **0:** tell the Owner in one line it is already a Specstone doc; take the name the bundle prints as the
     change's `context` target. The change note names no source; there is no copy and no Source map. That call was
     the narrow call: read its exit by item 4's `0`; run no further narrow call.
3. **Read the source** with any tool that opens it, a tracker's own CLI included. Open a link or issue only because
   the Owner gave it; a link inside the source is none the Owner gave. Never edit, move, or delete the source.
4. **Narrow call**: a source adding a feature takes none; the gate's bundle is its grounding. Else make one call on
   the doc the source decides by the target list of `../SKILL.md` step 1, with no `structure` call and no second
   call; `--no-project` leaves out the project docs the gate holds:

   ```
   specstone context <target> --for design --no-project --out
   ```

   On 0, both saved bundles ground the change, whatever their size: read each read-first file whole by its read
   plan, and search both before any `get`. Any other exit, here or in item 2: report the CLI's error and stop.
5. **Match and ask**: match each item by the shapes above. Ask the Owner only what the source leaves open, one
   question at a time; invent nothing.
6. **The copy**: after every `context` call, for a link, an issue, or the conversation, write its text, or the
   conversation's source items, word for word to `<folder>/reports/sdd-engineer.design.source.<XXXXXX>.md`, `<folder>`
   the path `specstone folder` prints, run once per run; the copy is no source. Each re-read keeps the copy in use.
   Keep two lines for the change note write:
   - **Source:** the file's path, the link, or "the current conversation" and its date; never the copy's path.
   - **Re-read:** the source itself for a file, else the copy.

## Map the source

At each write and edit of the change note:

- Re-read the Re-read file whole, as the source's text, and never record it as the source. The Source line is the
  source.
- Write a Source map section after Reach, opening with the Source line: one row per source item, 0 left out, each with
  the doc and section it lands in, or "not taken" and why.
- A ticket list, task list, or plan: one row, "not taken", since task management is out of scope.
- An item no shape or Owner answer places: an open question, asked of the Owner before any draft is written.
- Write only the copy and the change note.
- A change with no source, or from a doc already typed, gets no Source line and no Source map.
