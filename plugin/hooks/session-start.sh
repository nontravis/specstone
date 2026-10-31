#!/usr/bin/env bash
# SessionStart hook: warn when the specstone CLI and this plugin differ in
# version, or when the CLI is missing. Reads no stdin, opens no network,
# writes no file, and exits 0 on every path (a hook must never block a session).

curl_line='curl -fsSL https://raw.githubusercontent.com/nontravis/specstone/main/install.sh | sh'
irm_line='irm https://raw.githubusercontent.com/nontravis/specstone/main/install.ps1 | iex'

# Prints $1 as the body of a JSON string. Runs in a subshell under LC_ALL=C so
# the loop walks bytes and the control-character class matches only ASCII.
json_escape() {
  (
    LC_ALL=C
    text=$1
    out=''
    i=0
    while [ "$i" -lt "${#text}" ]; do
      char=${text:$i:1}
      case $char in
        "\\") out="$out\\\\" ;;
        '"') out="$out\\\"" ;;
        $'\n') out="$out\\n" ;;
        $'\r') out="$out\\r" ;;
        $'\t') out="$out\\t" ;;
        [[:cntrl:]])
          printf -v code '%d' "'$char"
          printf -v escaped '\\u%04x' "$code"
          out="$out$escaped"
          ;;
        *) out="$out$char" ;;
      esac
      i=$((i + 1))
    done
    printf '%s' "$out"
  )
}

# Prints the one JSON object Claude Code shows the Owner and gives the Agent.
emit() {
  local text
  text=$(json_escape "$1")
  printf '{"systemMessage":"%s","hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' \
    "$text" "$text"
}

# Sets install_line from the OS name: irm under Git Bash on Windows, else curl.
pick_install_line() {
  case $(uname -s 2>/dev/null) in
    MINGW* | MSYS* | CYGWIN*)
      windows=1
      install_line=$irm_line
      ;;
    *)
      windows=0
      install_line=$curl_line
      ;;
  esac
}

# Succeeds when the install folder holds the CLI binary.
installed_off_path() {
  local bin="${HOME:-$USERPROFILE}/.specstone/bin"
  [ -f "$bin/specstone" ] && return 0
  [ "$windows" = 1 ] && [ -f "$bin/specstone.exe" ] && return 0
  return 1
}

main() {
  local plugin_json="${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json"
  local plugin_version cli_version status

  plugin_version=$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
    "$plugin_json" 2>/dev/null | head -n 1)

  pick_install_line

  if command -v specstone >/dev/null 2>&1; then
    cli_version=$(specstone --version 2>/dev/null </dev/null)
    status=$?
    # Trim leading and trailing whitespace.
    cli_version=${cli_version#"${cli_version%%[![:space:]]*}"}
    cli_version=${cli_version%"${cli_version##*[![:space:]]}"}
    if [ "$status" -ne 0 ] || [ -z "$cli_version" ]; then
      emit "Specstone: the CLI did not report its version. Reinstall it: $install_line"
    elif [ -n "$plugin_version" ] && [ "$cli_version" != "$plugin_version" ]; then
      emit "Specstone: the CLI is $cli_version and the plugin is $plugin_version. Run: specstone upgrade"
    fi
  elif installed_off_path; then
    emit 'Specstone: the CLI is installed in ~/.specstone/bin but not on the PATH Claude Code sees. Start Claude Code from a terminal, or add ~/.specstone/bin to the PATH Claude Code gets.'
  else
    emit "Specstone: the CLI is not installed. Install it: $install_line"
  fi
}

main
exit 0
