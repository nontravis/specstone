# Write a doc with `specstone set`

The write `specstone-bootstrap-prd` and `specstone-bootstrap-spec` make for each fix.

Bases come from `specstone get <type>:<name> --json` (`bases.title`, `bases.sections.<key>`, `bases.fields.<id>`); each
write prints the new one. Pipe the text to `specstone set <type>:<name>#<key> --base <hash>` (`--field <id>` or
`--title` in place of `#<key>`). A section body leaves out its `## ` line, a list field takes its whole list, and empty
text drops the section or key. The text between the title and the first `##` section is `#_lead`.

Exit 75 `base_mismatch`: read again, merge, retry.

Quote a node label that holds `(`, `)`, `[`, `]`, `{`, or `}`, as in `A["Save (draft)"]`; write `"` in it as
`#quot;`.
