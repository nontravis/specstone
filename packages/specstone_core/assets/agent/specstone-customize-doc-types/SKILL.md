---
name: specstone-customize-doc-types
description: Use when a task in a Specstone project needs a doc type, section, field, lint value, or list entry that the project's merged doc types lack or hold otherwise, such as a new doc type, an extra section on a shipped one, or a stricter lint value. Not for writing a doc's content, nor for `specstone check` findings after a migration or a pack upgrade with no layer file change, which `specstone-bootstrap-prd` and `specstone-bootstrap-spec` take.
---

# Customize the project's doc types

This skill writes a sparse layer file: only the entries that change, never a full copy of a doc type. Every key and
merge rule comes from the file format printout alone.

## 1. Gate: the first call

Run `specstone folder`; keep the folder it prints as `<folder>`.

- **`project_not_found`:** tell the Owner no Specstone project is found here; `specstone init` starts one.
  Stop: run, read, write nothing.
- **0:** go on.
- **Any other exit:** report the CLI's error and stop.

## 2. Read the format

1. Run `specstone guide --file-format --out`.
2. For each existing doc type the change reaches, run `specstone guide <type> --out`.
3. Read each file the header lines name with the host's file read; never open a doc file.

Each `specstone guide` run, here and in step 4:

- **0:** go on.
- **78:** go to step 5.
- **Any other exit:** report the CLI's error and stop.

## 3. Draft the layer file and ask the Owner

1. Draft one layer file per doc type the change reaches, holding only the entries that change, each matched to its
   entry in the layer below by the merge's id, as the printout gives.
2. Show the Owner the draft text and one question: the project layer `.specstone/templates/<doc_type>.yaml`, which
   git keeps, or a personal pack `~/.specstone/packs/<pack>/`, which git does not keep.
3. For a new personal pack, the same ask also shows its `pack.yaml`, with `name`, `version`, and `extends` when it
   changes a shipped doc type, and the `packs:` pin line in `.specstone/config.yaml`.
4. Write no file before the Owner's ok.

## 4. Write the files

On the Owner's ok, write the files with the host's file write. Then run `specstone guide <type> --out` for each doc
type they touch.

## 5. On exit 78, fix and rerun

Fix the file and key the fault names, then rerun that `specstone guide <type> --out`. After two failed fixes of one
fault code and key, stop and show the Owner the fault.

## 6. Check and route

Once every `specstone guide` exits 0, run `specstone check --out "<folder>/reports/check.done.<XXXXXX>.txt"`:
`<folder>` is the path step 1 kept, `XXXXXX` six `a-z0-9` characters, picked again while that file exists.

- **0 or 1:** search the file by path, never reading it whole, and route:
  - **Findings under `prds/` or `measurements/`:** follow the `specstone-bootstrap-prd` skill.
  - **Findings under `specs/`:** follow the `specstone-bootstrap-spec` skill.
  - **None:** report the change done.
- **Any other exit:** report the CLI's error and stop.
