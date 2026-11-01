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

# Succeeds when uname names Windows under Git Bash.
is_windows() {
  case $(uname -s 2>/dev/null) in
    MINGW* | MSYS* | CYGWIN*) return 0 ;;
  esac
  return 1
}

# Succeeds when the install folder holds the CLI binary; $1 is 1 on Windows.
installed_off_path() {
  local bin="${HOME:-${USERPROFILE:-}}/.specstone/bin"
  [ -f "$bin/specstone" ] && return 0
  [ "$1" = 1 ] && [ -f "$bin/specstone.exe" ] && return 0
  return 1
}

# Prints the first "version" key of plugin.json; splitting on , { } first
# makes the first match the top-level key of a minified file too.
plugin_version_of() {
  tr ',{}' '\n' <"$1" 2>/dev/null \
    | sed -n 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
    | head -n 1
}

# Prints the first 65 bytes of `specstone --version` and returns the CLI's exit
# status. 65 exceeds the 64-byte version allowlist, so an over-long version
# still fails validation while a flooding CLI cannot fill memory. The CLI runs
# for at most 5 seconds, then gets KILL after a 1 second grace. A watchdog
# signals the CLI's process group on every platform: uutils `timeout` (Ubuntu
# 26.04) kills only the direct child, so a TERM-ignoring grandchild would keep
# the pipe open.
bounded_version() {
  set -m
  (
    specstone --version 2>/dev/null </dev/null | head -c 65
    exit "${PIPESTATUS[0]}"
  ) &
  local child=$! watchdog
  (
    sleep 5 &
    local nap=$!
    trap 'kill "$nap" 2>/dev/null; exit 0' TERM
    wait "$nap"
    kill -TERM -- "-$child" 2>/dev/null
    sleep 1 &
    nap=$!
    wait "$nap"
    kill -KILL -- "-$child" 2>/dev/null
    # Git Bash maps a signal to a native Windows child through TerminateProcess.
    kill -KILL "$child" 2>/dev/null
  ) >/dev/null 2>&1 &
  watchdog=$!
  wait "$child" 2>/dev/null
  local code=$?
  # TERM ends the subshell but not a CLI that ignores it; KILL leftovers now.
  kill -KILL -- "-$child" 2>/dev/null
  kill -TERM "$watchdog" 2>/dev/null
  wait "$watchdog" 2>/dev/null
  return "$code"
}

# Succeeds when $1 is 1 to 64 characters of [0-9A-Za-z._+-] (bytes, C locale).
valid_version() {
  local LC_ALL=C
  [ "${#1}" -ge 1 ] && [ "${#1}" -le 64 ] && [[ $1 =~ ^[0-9A-Za-z._+-]+$ ]]
}

main() {
  local plugin_version cli_version status install_line windows=0

  plugin_version=$(plugin_version_of "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json")

  install_line=$curl_line
  if is_windows; then
    windows=1
    install_line=$irm_line
  fi

  if command -v specstone >/dev/null 2>&1; then
    cli_version=$(bounded_version)
    status=$?
    # Trim leading and trailing whitespace.
    cli_version=${cli_version#"${cli_version%%[![:space:]]*}"}
    cli_version=${cli_version%"${cli_version##*[![:space:]]}"}
    if [ "$status" -ne 0 ] || ! valid_version "$cli_version"; then
      emit "Specstone: the CLI did not report its version. Reinstall it: $install_line"
    elif [ -n "$plugin_version" ] && [ "$cli_version" != "$plugin_version" ]; then
      emit "Specstone: the CLI is $cli_version and the plugin is $plugin_version. Run: specstone upgrade"
    fi
  elif installed_off_path "$windows"; then
    emit 'Specstone: the CLI is installed in ~/.specstone/bin but not on the PATH Claude Code sees. Start Claude Code from a terminal, or add ~/.specstone/bin to the PATH Claude Code gets.'
  else
    emit "Specstone: the CLI is not installed. Install it: $install_line"
  fi
}

main
exit 0
