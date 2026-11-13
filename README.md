<img src=".github/assets/banner.png" alt="Specstone" width="100%">

# SPECSTONE

Specstone keeps PRD and spec documents for spec-driven development, with a CLI and an MCP server.

## Install

On macOS or Linux:

```sh
curl -fsSL https://raw.githubusercontent.com/nontravis/specstone/main/install.sh | sh
```

On Windows, in PowerShell:

```powershell
irm https://raw.githubusercontent.com/nontravis/specstone/main/install.ps1 | iex
```

The script installs the CLI in `~/.specstone/bin` and adds that folder to your PATH. When Claude Code's `claude`
command is on your PATH, it also installs the Specstone plugin; otherwise it prints the two commands to run later.

Typing `stn` runs the CLI with fewer keystrokes, unless another tool's `stn` is first on your PATH, where you type
`specstone`.

To upgrade the CLI and the plugin, run `specstone upgrade`, then restart Claude Code.

To uninstall, run the line for your system, then `claude plugin uninstall specstone@specstone`:

```sh
curl -fsSL https://raw.githubusercontent.com/nontravis/specstone/main/uninstall.sh | sh
```

```powershell
irm https://raw.githubusercontent.com/nontravis/specstone/main/uninstall.ps1 | iex
```

Uninstalling keeps your personal packs in `~/.specstone/packs`.

## Status

The CLI sets up a project (`init`, `migrate`), reads docs (`list`, `get`, `search`, `structure`, `context`, `refs`,
`guide`), writes them as drafts (`new`, `set`, `rename`, `reorder`, `move`, `delete`), and leaves approval to the Owner
(`approve`). It also checks a project (`check`, `hook post-edit`) and formats and renders docs (`format`, `build`).
The MCP server still lists no tools.

## Layout

- `packages/specstone_core/`: the library: doc model, index and query, templates and packs, document writing,
  consistency check, setup and migration, and rendering.
- `packages/specstone/`: the `specstone` CLI executable and its MCP server command.
- `plugin/`: the Claude Code plugin, with 8 skills, 2 agents, and two hooks in `hooks/hooks.json`. The `PostToolUse`
  hook runs `specstone hook post-edit`, so `specstone` must be on `PATH`. The `SessionStart` hook warns when the CLI
  and plugin versions differ.
- `.claude-plugin/marketplace.json`: the marketplace entry that points Claude Code at `plugin/`.

## Develop

- `dart pub get`
- `dart format --output=none --set-exit-if-changed .`
- `dart analyze --fatal-infos`
- `dart test` inside each package directory
- `dart run packages/specstone/bin/specstone.dart --version`

## License

BSD-3-Clause, see `LICENSE`.
