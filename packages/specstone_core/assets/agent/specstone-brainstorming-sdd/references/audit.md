`specstone-sdd-auditor`, its gate made, runs this for `job: builder-check`. Write only the agent's `report:` file, no
fix.

## Builder check

`job: builder-check` reads the drafts in 1 pass. Run no `check`, `check --repeats`, or lens walk; no second check
follows.

1. **Hashes**: run one `specstone approve <drafts> --dry-run --json`, no `--target`: it gives each draft's `base`. On
   `doc_not_found`, drop each name it names, run it again on the rest. A dropped name gets no report or `Audited:` line.
   A named doc it does not list is no draft; its hash is the whole-doc `base` of `specstone get <doc> --json`.
2. **Ground**: run one `specstone context <draft> <draft> --for review --out` naming every draft step 1 keeps. A feature
   or doc the Owner names takes `specstone context <it> --for design --out` instead. Ground again; main's files predate
   the writes. In a check of drafts, besides step 1's calls, this call, and step 6's one `grep -n -E` over the refs
   file, run no other doc read, `search`, `refs`, or `context` call.
3. **Read**: the change note, each writer report's `Decision:`, `Readers:`, and open question lines, and the review
   read-first file by its read plan, with its changed, removed, citer, summary, and pattern parts. A doc the Owner
   names, no draft, is read whole.
4. **Judge**: report each point of these five labels.
   - `Guess`: a planner or implementer must guess, and a wrong guess changes the build. A code-level point left to the
     builder is no guess.
   - `Contradiction`: two docs contradict once the drafts land. A draft restating a rule another doc owns is one, naming
     the owner doc and the item, its fix an item link. So is a citer that a size-fix move repointed, or kept, that means
     the part it no longer links: name it and the item to link. So is a decision or draft against any project vision,
     advanced or not, naming the draft or the doc the Reach list gives it, and the vision's ID.
   - `Stale reader`: a reader still states the old rule.
   - `Not carried`: a decision of the change note no draft carries, or a draft departing from it, one line in each doc
     it misses, naming the decision and the draft, or the doc its Reach list gives it. A `(plan)` decision stating
     behavior a PRD or spec doc must hold is one too, and its line names that doc.
   - `Misplaced`: a line a draft adds to or changes in a shared FR states a rule only one member holds. The item reads
     `- Misplaced: <shared FR>#<key>: <rule> belongs in <member FR>`, or `belongs in a new FR for <member>` with no
     member FR yet. So is an internal code-level fact a spec draft states, which the guide's `code_detail_home` or
     `library_code_detail_home` line leaves to the code or the plan: it belongs in the plan. A shared FR line no draft
     adds or changes, a rule two or more members take, or a contract outsiders rely on, such as a command's flags, gets
     no `Misplaced` line.
5. **Feature pattern**: an item counts covered when a story, FR, edge case, or spec doc covers it by its text, or a skip
   line in the `out_of_scope` of the doc that lists the pattern names it. In a check of drafts, take each item from the
   read-first file's `pattern` parts, each naming that doc by `<type>:<name>`, and search in step 6's grep over that
   doc, the docs under it, and the spec folder of its feature: itself when a feature, else the feature whose subtree
   holds it; a doc in no feature's subtree, alone with the docs under it. An item no `pattern` part holds,  gets no
   line. For an Owner-named feature or doc, take each item of a pattern part a target feature or sub-feature lists,
   search the saved files over those docs, and skip a non-target feature's item. Else write `- Not carried:
   <type>:<name>#out_of_scope: <pattern>/<item> neither covered nor skipped`, `<type>:<name>` that doc, typed as the
   `pattern` part, or for an Owner-named target the bundle line it follows, names it.
6. **Siblings**: in a check of drafts, after judging, run one `grep -n -E` over the refs file joining every point's
   wording, the rule or term it breaks, and step 5's search. For an Owner-named target, search the saved files for the
   same. Give each hit its own line. A sibling only in a story the refs file holds in summary is out of reach.

A point of wording or shape, which `check` owns, or one a builder can settle, gets no line.

```
Findings:
- Guess: <doc>#<key>: <point>
  Fix: <type>:<name>#<key>
- Contradiction: <doc>#<key>: <point>
- Stale reader: <doc>#<key>: <point>
- Not carried: <doc>#<key>: <point>
- Misplaced: <doc>#<key>: <point>
Notes:
- <observation>
Audited: <type>:<name>@<hash>
```

- `<doc>` is the full `<type>:<name>` or the DocPath. List every line under one `Findings:` line, ranked by importance
  across the labels, no label or count line inside.
- Under an item whose fix you can state, write one `Fix: <type>:<name>#<key>` line per section the fix changes, indented
  two spaces, then that section's whole new body in a bare fence, indented the same, of three or more backticks, longer
  than any run at a line start in the body. State a fix only as `Fix:` lines, never in prose; an Owner-only question
  gets none.
- **Dry run**: before each `Fix:` line, run `specstone set <doc>#<key> --dry-run`, no `--base`, the fenced body on
  stdin. Fix in the body each finding it prints, a doc-level one too, and each refusal it causes, such as an open fence;
  dry-run again, then write the line. One you cannot fix in the body leaves no `Fix:` line.
- Put every labeled point under `Findings:`, one on a doc outside the drafts too (the fix loop adds it). Write no
  `Outside the drafts:` section.
- Put each non-gap observation under `Notes:`, which the judge never reads and main relays to the Owner. With none,
  write no `Notes:` heading.
- With no point, `Findings:` reads `nothing important left`.
- Write one `Audited:` line per doc of the drafts list alone, its hash the `base` of step 1.
