## 1. Inputs

Write from the Owner's answers (decisions in their words where they gave them, the approach picked, open questions)
and the saved bundle files of the skill's own `context --for design --out` calls; for a change from a source, also
follow `## Map the source` in `source.md`.

## 2. Ground each claim

- Ground each claim in a saved file or an Owner answer, citing only that text; the saved files ground a claim about
  the Specstone CLI.
- Ground a claim on how a library, parser, or tool the change calls behaves only by a run of your own: a read-only
  command on the dependency in a scratch folder outside the docs, and the decision cites it in one `Run:` line
  (the command and its output line).
- A claim nothing grounds, or the docs contradict, is an open question: run no `get`, `search`, or `refs` for it.
- Open each code path and symbol the answers or saved files name: a name you cannot find is an open question.
- Cite each story, FR, and section as `<type>:<name>#<section>`, never by file path or line.

## 3. Write the change note

Its path is the brainstorm skill's own design path, else `docs/designs/<YYYY-MM-DD>-<topic>-design.md`. Judge it
before any write by the saved files' `==> ` headers: a doc path's first folder, right under the docs folder, is a
checked folder; a deeper folder of that name is outside. Inside a checked folder, or a PRD or spec doc: write
nothing, the path is an open question, and you write at the Owner's new path in its place.

Write only the change note (and a source's copy, by `source.md`) with the host's file write, and no PRD or spec doc.
A note already at the path: read it whole, then edit it with the host's file write at every place stating text an
Owner decision supersedes. The note holds no Docs to change table, no input table, no amend number, and no
snapshot.

Sections, in order:

1. **Intent**: the change and its why, and the vision IDs (`PV-…`) it advances.
2. **Goals**
3. **Non-goals**
4. **Anti-goals**: what the change must not cause.
5. **Constraints**: what the docs fix that the change keeps, each cited by name, then one line per project vision,
   every vision and not only the ones the change advances: what the decisions must not break, or
   `none bears on this change`.
6. **Approaches**: the one picked, and why each other lost.
7. **Decisions**: `D1`, `D2`, ..., one per thing decided, in the Owner's words where they gave them, scope words
   (`only`, `not`, `never`, `after`) verbatim, naming the text it supersedes. A decision only the plan holds, such as
   a run order, reads `D<n> (plan): <text>`; you write that mark, never a writer. A PRD or spec doc must hold every
   other decision. Try `(decided)` on every settled decision, bar a `(plan)` one, whoever settled it (an Owner
   answer, your own call, or a source map), by both decided-line tests. A decided line reads
   `D<n> (decided): <text>`, a mark you write only when it passes both decided-line tests:
   - it states one observable behavior as `when <input or state>, <outcome>`, specific enough that a writer writes
     its FR with no question ("make it faster" or "clearer" does not)
   - a fact a caller's work breaks on names its exact values
8. **Reach**: the docs the writer starts from, each `<type>:<name>`. With two or more `targets:`, each per-target
   spec doc names its code target, and one with none is an open question. The writer's one `context` call names these
   docs.
9. **Left to the builder**: each code-level point (a class name, the file split): no decision, no open question.
10. **Open questions**: each gap a PRD or spec doc must state that neither the answers nor the saved files settle.
11. **Calls made**: empty until the builder check; each question the runner settles itself goes
    there.

- Decide a point the answers leave open when a PRD or spec doc must state it (a refusal, a name rule); any other
  point goes under Left to the builder.
- A change from a source adds a Source map after Reach, by `source.md`.
- Ask the Owner each open question. No draft is written while one is open.
- Before you report: no placeholder, no contradiction between sections or with a decision, each decision specific
  enough that a writer writes its doc with no question, and no decision on a code-level point.

## 4. Tell the Owner

The path, written or edited; each open question, each claim the saved files could not ground, and each code path or
symbol not found.

Each time an answer changes a decision line, an edit given with the lane answer included, run section 3's
`(decided)` try on the changed lines, then this section again.

Name each settled decision, bar a `(plan)` one, that fails a decided-line test in the chat, with the test it fails.

Ask `class.md` steps 1 and 2 first: a Doc-only, Restore, or Internal change takes its class there, with no lane
question.

When the change goes on to `class.md` step 3, every decision of the note reads `(decided)` or `(plan)`, at least one
reads `(decided)`, and there is no open question, show the Owner its Decisions in the chat and ask the Owner once
which lane the change takes: Decided builds the work first, drafts and audits the docs after the build, and runs no
builder check before it, while Undecided drafts the docs, runs one builder check, and waits for the Owner's approval
before any work.

On Decided, write `Owner ok: <YYYY-MM-DD>` under Decisions.

On Undecided, write no `Owner ok:` line.

Then a change that goes on to `class.md` step 3 takes its class there, before any writer dispatch.
