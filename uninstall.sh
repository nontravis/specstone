#!/bin/sh
# Removes the Specstone CLI from ~/.specstone and its PATH entry:
#   curl -fsSL https://raw.githubusercontent.com/nontravis/specstone/main/uninstall.sh | sh
# Personal packs, ~/.specstone itself, and every project's .specstone stay. The
# body sits in functions and `main "$@"` is the last line, so a truncated
# stream runs nothing.
set -eu

tmp=''

fail() {
  printf 'specstone: %s\n' "$1" >&2
  exit 1
}

cleanup() {
  if [ -n "$tmp" ]; then
    rm -rf "$tmp"
  fi
}

# Deletes the folder $1 when it is there, and says so.
remove_dir() {
  if [ -e "$1" ] || [ -L "$1" ]; then
    rm -rf -- "${1:?}"
    printf '%s\n' "Removed $1"
    removed_any=1
  fi
}

# Writes the lines of file $1 other than the whole line $2 to file $3, keeping
# every kept line byte for byte; the last kept line ends in a newline unless it
# was the unterminated last line of $1.
keep_other_lines() {
  terminated=0
  if [ -z "$(tail -c 1 "$1")" ]; then
    terminated=1
  fi
  entry=$2 terminated=$terminated awk '
    BEGIN { entry = ENVIRON["entry"]; terminated = ENVIRON["terminated"] }
    $0 == entry { lastKept = 0; next }
    { if (kept++) printf "\n"; printf "%s", $0; lastKept = 1 }
    END { if (kept && (terminated == 1 || !lastKept)) printf "\n" }
  ' "$1" > "$3"
}

# Drops the whole line $2 from the file $1 when it holds it, and says so.
# Writes back through the same path, so a symlinked profile keeps its link and
# its mode. Deletes the file when $3 is "delete" and nothing is left.
remove_path_line() {
  if [ ! -f "$1" ] || ! grep -qxF -- "$2" "$1" 2>/dev/null; then
    return 0
  fi
  keep_other_lines "$1" "$2" "$tmp/kept"
  if [ "${3:-}" = 'delete' ] && [ ! -s "$tmp/kept" ]; then
    rm -f -- "$1" 2>/dev/null || {
      warn_unwritten "$1"
      return 0
    }
  elif ! { cat "$tmp/kept" > "$1"; } 2>/dev/null; then
    warn_unwritten "$1"
    return 0
  fi
  printf '%s\n' "Removed the PATH entry from $1"
  removed_any=1
}

# Warns that the profile $1 is not changed; the rest of the removal goes on.
warn_unwritten() {
  printf '%s\n' "specstone: could not write $1: remove the specstone line from it yourself" >&2
}

main() {
  home_dir=${HOME:-${USERPROFILE:-}}
  if [ -z "$home_dir" ]; then
    fail 'no home folder: HOME and USERPROFILE are unset'
  fi

  trap cleanup EXIT
  trap 'exit 1' HUP INT TERM
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/specstone.XXXXXX")

  # shellcheck disable=SC2016  # the profile holds a literal $HOME and $PATH
  posix_line='export PATH="$HOME/.specstone/bin:$PATH"'
  # shellcheck disable=SC2016  # same: the line is written unexpanded
  fish_line='set -gx PATH "$HOME/.specstone/bin" $PATH'
  removed_any=0

  remove_dir "$home_dir/.specstone/bin"
  remove_dir "$home_dir/.specstone/lib"
  for name in .zshrc .bashrc .bash_profile .bash_login .profile; do
    remove_path_line "$home_dir/$name" "$posix_line"
  done
  remove_path_line "$home_dir/.config/fish/conf.d/specstone.fish" "$fish_line" delete

  if [ "$removed_any" -eq 0 ]; then
    printf '%s\n' 'specstone: nothing to remove'
  fi
  printf '%s\n' 'claude plugin uninstall specstone@specstone'
}

main "$@"
