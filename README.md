# Specstone

Specstone keeps PRD and spec documents for spec-driven development, with a CLI and an MCP server.

## Status

M0 foundation: a pub workspace, a CLI shell exposing `--version`, an MCP server that lists zero tools, and a plugin
skeleton. No document features exist yet.

## Layout

- `packages/specstone_core/`: shared library code, starting with the shared version constant.
- `packages/specstone/`: the `specstone` CLI executable and its MCP server command.
- `plugin/`: the Claude Code plugin skeleton; its skills and agents are not written yet.
- `.claude-plugin/marketplace.json`: the marketplace entry that points Claude Code at `plugin/`.

## Develop

- `dart pub get`
- `dart format --output=none --set-exit-if-changed .`
- `dart analyze --fatal-infos`
- `dart test` inside each package directory
- `dart run packages/specstone/bin/specstone.dart --version`

## License

BSD-3-Clause, see `LICENSE`.
