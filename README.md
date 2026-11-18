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

The script installs the CLI in `~/.specstone/bin` and adds that folder to your PATH.

Typing `stn` runs the CLI with fewer keystrokes, unless another tool's `stn` is on your PATH, where you type
`specstone`.

To upgrade, run `specstone upgrade`. It replaces the CLI and, in a project that needs it, prints the command that
fixes the project.

To uninstall, run the line for your system:

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

## Layout

- `packages/specstone_core/`: the library: doc model, index and query, templates and packs, document writing,
  consistency check, setup and migration, and rendering.
- `packages/specstone/`: the `specstone` CLI executable.
- Skills and agents come from `specstone init` and `specstone migrate`, which write them into the project's
  `.claude/`, `.agents/`, `.cursor/`, and `.codex/` folders. The same commands add the `PostToolUse` hook that runs
  `specstone hook post-edit` to `.claude/settings.json`; the hook needs `specstone` on `PATH`.

## Develop

- `dart pub get`
- `dart format --output=none --set-exit-if-changed .`
- `dart analyze --fatal-infos`
- `dart test` inside each package directory
- `dart run packages/specstone/bin/specstone.dart --version`

## License

BSD-3-Clause, see `LICENSE`.
