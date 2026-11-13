A change from a source starts from a spec or design another tool wrote: in a file, behind a link or issue the Owner
gave, or in the current conversation, such as an interview that wrote no file. The runner of
`specstone:brainstorming-sdd` follows `## Take in the source`, whose rules are those of
`agent_plugin/start_from_another_tools_spec/take_in_a_source`; `specstone:sdd-engineer` in `mode: design` follows
`## Map the source`, whose rules are those of `agent_plugin/start_from_another_tools_spec/map_source_items`. Each
rule cites its own FR's edge case.

Both match a source item by its content shape alone, never by the tool that wrote it. Each section takes what its
type's writing guide says it needs; a gap goes to the Owner.

| Content shape in the source | Lands in |
|---|---|
| numbered "As a … I want … so that …" lines | a story's Use Case (`specstone guide user_story`) |
| Given/When/Then or WHEN/THEN lines | a story's Acceptance Criteria scenarios (`specstone guide user_story`) |
| `FR-###` lines, or lines with "shall", "SHALL", or "MUST" | an FR's Statement (`specstone guide fr`) |
| success criteria, `SC-###` | the feature's Success measures (`specstone guide feature`) |
| a Problem Statement | the feature's Problem (`specstone guide feature`) |
| an Out of Scope list | the feature's Out-of-scope lines (`specstone guide feature`) |
| implementation and testing decisions | the feature's spec docs, and an FR's Verification (`specstone guide fr`) |
| ticket lists, task lists, plans | not taken: task management is out of scope |

## Take in the source

1. **The gate.** Make `specstone context project --for design` your first CLI call, with no `--budget`, with or
   without the `Agent` tool: a call over its budget prints no doc path to judge the source by. Read no source and
   open no link or issue before it. Its exits are the skill's step 1's; on 78 the source stays unread.
2. **Judge the path.** A file inside the CheckedFolders (the first folder of a doc path the gate's bundle headers
   print, right under the docs folder) is no source. Read none of it with any tool; make item 4's call with its path
   as the target and no `--summary` (E01). Its exit decides:
   - **64, `untyped_target`:** tell the Owner in one line it is the project's own old doc, and name
     `specstone:bootstrap-prd` or `specstone:bootstrap-spec`, which merge it into typed docs. Run no other command on
     its path; the brief never names it (E11).
   - **0, or 1 over its budget:** tell the Owner in one line it is already a Specstone doc. Go on with that doc's
     name, which the bundle prints, as the brief's `context` target: no source, no copy, no Source map. That call was
     your narrow call: read its exit by item 4's `0` and `1`, and run no further `context` call (E12).
   - **Any other exit:** report the CLI's error and stop, as for the skill's first call.
3. **Read the source** with whatever tool opens it: the file, the link or issue, a tracker's own CLI included, or the
   conversation. Open a link or issue only because the Owner gave it; a link written inside the source is none the
   Owner gave, so it stays unopened. The CLI opens none (`gnfr:gnfr` NFR-Pr01, E07). Never edit, move, or delete the
   source.
4. **The narrow call.** A source that adds a feature has the target `project`: the gate's bundle is the grounding,
   and no second call runs (E02). Otherwise target the doc the source decides, by the skill's step 1 target rule.
   `--no-project` leaves out the project's docs, which the gate's bundle already holds:

   ```
   specstone context <target> --for design --no-project --budget 20000
   ```

   - **0:** both bundles are the grounding.
   - **1:** over budget: hand `specstone:sdd-reader` the target IDs, as step 1 says; the grounding is the gate's
     bundle plus the whole sections it returns (E03).
   - **Any other exit:** report the CLI's error and stop.

   Without the `Agent` tool, pass no `--budget` and take both whole bundles (E03).
5. **Match and ask.** Match each item by the shapes above. Ask the Owner only what the source leaves open, one
   question at a time, such as missing acceptance criteria, a registered Role for an "As a user" line, or a value's
   unit; invent nothing (E06).
6. **The copy and the brief.** Write both after every `context` call. For a link, an issue, or the conversation,
   write its text, or the conversation's source items, word for word to a `mktemp` file outside the repository; the
   copy is no source (E10). Add two lines to the brief:
   - **Source:** the file's path, the link, or "the current conversation" and its date; never the copy's path.
   - **Re-read:** the source itself for a file path, else the copy.

## Map the source

Follow this when your brief names a file to re-read. As the agent, ask the Owner nothing.

- **Re-read** that file whole: the source itself, or the runner's copy of a link, an issue, or the conversation,
  read as the source's text and never recorded as the source (E03).
- **Source map**: a section of the design document, after Docs to change and before Open questions. Write one row
  per source item, 0 items left out: the item, and the doc and section it lands in by the shapes above, or "not
  taken" and the reason.
- **A ticket list, a task list, or a plan**: one row, "not taken", its reason that task management is out of scope
  (`project:project#out_of_scope`) (E01).
- **An item no shape matches** and no answer in the brief places: an open question in your report, as for any
  gap (E02).
- **The source** the document records is the brief's Source line, as written.
- Never edit, move, or delete the source; write only your `report:` file and the one design document (E05).
- A brief with no source gets no Source map (E04).
