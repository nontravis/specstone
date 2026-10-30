# Specstone

Specstone keeps PRD and spec documents for spec-driven development, with a CLI and an MCP server.

## Status

The CLI sets up a project (`init`, `migrate`), reads docs (`list`, `get`, `search`, `structure`, `context`, `refs`,
`guide`), writes them as drafts (`new`, `set`, `rename`, `reorder`, `delete`), and leaves approval to the Owner
(`approve`). It also checks a project (`check`, `hook post-edit`) and formats and renders docs (`format`, `build`).
The MCP server still lists no tools.

## Layout

- `packages/specstone_core/`: the library: doc model, index and query, templates and packs, document writing,
  consistency check, setup and migration, and rendering.
- `packages/specstone/`: the `specstone` CLI executable and its MCP server command.
- `plugin/`: the Claude Code plugin, with 8 skills, 2 agents, and a `PostToolUse` hook (`hooks/hooks.json`) that runs
  `specstone hook post-edit`, so `specstone` must be on `PATH`.
- `.claude-plugin/marketplace.json`: the marketplace entry that points Claude Code at `plugin/`.

## Develop

- `dart pub get`
- `dart format --output=none --set-exit-if-changed .`
- `dart analyze --fatal-infos`
- `dart test` inside each package directory
- `dart run packages/specstone/bin/specstone.dart --version`

## License

BSD-3-Clause, see `LICENSE`.
