---
name: init
description: Use when the Owner wants a new Specstone project in a folder that holds no code, no docs, and no `.specstone/config.yaml`, such as starting a product from nothing.
---

# Create a project, then fill its four starting drafts

This skill creates the project, so it has no project gate: there is no project yet for a gate to find. With the
Owner, you fill the four drafts the CLI writes; then the Owner approves each one.

## 1. Create the project: the first call

Run this first, from the folder that becomes the project root, before any other command or file read:

```
specstone init
```

Run no `specstone check` and no look for `.specstone/` before it: `specstone init` refuses on its own in a folder
that is already a project.

- **0:** it printed the four drafts and the config it created. Go on, and follow `specstone:expert-sdd` from here:
  its gate now passes, and its rules govern every write below.
- **64, `config_exists`:** tell the Owner this folder is already a Specstone project, and stop. The CLI changed no
  file; run nothing more.
- **Any other exit:** report the CLI's error and stop.

## 2. Fill each draft with the Owner

Take the drafts one at a time, in this order: `project:project`, `features:features`, `gnfr:gnfr`,
`tech_stack:tech_stack`. For each one:

1. Run `specstone guide <type>` for its title and sections, and `specstone guide <type> --json` for its fields.
2. Ask the Owner for the title, each section, and each field the guide describes, such as `owner` on `project` and
   `code` on `tech_stack`; or propose a value and let them correct it. Write only what they gave or agreed to.
3. Read every base at once with `specstone get <type>:<name> --json`: `bases.title`, `bases.sections.<key>`,
   `bases.fields.<id>`.
4. Pipe each value in through the matching call:

```
specstone set <type>:<name> --title --base <hash>
specstone set <type>:<name>#<section key> --base <hash>
specstone set <type>:<name> --field <id> --base <hash>
```

Exit 75, `base_mismatch`: read the target again and merge before you retry. Any other non-zero exit: report it and
stop.

The tech stack's `code` field lists the folders the code will live in, relative to the root. Fill it before you ask
for approval: while it is empty, `specstone check` reports no uncovered code at all. Until a listed folder exists,
`specstone check` reports `code_root_missing` for it; that is expected in a new project, so keep the entry.

## 3. Ask the Owner to approve

Tell the Owner the four drafts are filled, then ask them to run, at their own terminal:

```
specstone approve
```

It shows each draft and approves the ones they answer `y` to. Never run it yourself: it refuses any caller but an
interactive terminal (exit 77).

## 4. Features go to brainstorming

This skill writes no feature doc. A feature the Owner names during setup waits until the four drafts are written;
then, and for every later feature, hand it to `specstone:brainstorming-sdd`, one feature at a time.

## Red flags

| Thought                                          | Do instead                                         |
|--------------------------------------------------|----------------------------------------------------|
| "Check for a project first, as other skills do." | Run `specstone init` first; it refuses on its own. |
| "Already a project: I'll migrate it."            | Say it is a project already, and stop.             |
| "No code yet, so the code roots can wait."       | Fill `code` before asking for approval.            |
| "`code_root_missing`: clear the `code` field."   | Keep it; the folder comes with the code.           |
| "The Owner named a feature: `specstone new`."    | Note it; `specstone:brainstorming-sdd` takes it.   |
| "I'll run `specstone approve` to finish."        | Ask the Owner to run it.                           |
