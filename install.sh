#!/bin/sh
# Installs the Specstone CLI under ~/.specstone:
#   curl -fsSL https://raw.githubusercontent.com/nontravis/specstone/main/install.sh | sh
# The body sits in functions and `main "$@"` is the last line, so a truncated
# stream runs nothing.
set -eu

release_url='https://github.com/nontravis/specstone/releases/latest/download'
tmp=''
install_dir=''

fail() {
  printf 'specstone: %s\n' "$1" >&2
  exit 1
}

cleanup() {
  if [ -n "$tmp" ]; then
    rm -rf "$tmp"
  fi
  if [ -n "$install_dir" ]; then
    rm -rf "${install_dir:?}/.lib.new" "${install_dir:?}/.bin.new"
  fi
}

# Prints the release target for this machine, or refuses before any download.
pick_target() {
  os=$(uname -s)
  arch=$(uname -m)
  case "$os $arch" in
    'Darwin arm64') echo 'macos-arm64' ;;
    'Darwin x86_64') echo 'macos-x64' ;;
    'Linux x86_64') echo 'linux-x64' ;;
    *)
      fail "unsupported machine $os $arch; supported: macOS arm64, macOS x64, Linux x64, Windows x64"
      ;;
  esac
}

# Prints the SHA-256 of the file named $1 in the folder $tmp as lower-case hex.
hash_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    (cd "$tmp" && sha256sum "$1") | cut -d ' ' -f 1 | tr 'A-F' 'a-f'
  elif command -v shasum >/dev/null 2>&1; then
    (cd "$tmp" && shasum -a 256 "$1") | cut -d ' ' -f 1 | tr 'A-F' 'a-f'
  else
    fail "no sha256sum or shasum to check $1; the install is unchanged"
  fi
}

# Copies or downloads the file $1 from the archive folder or the release into $tmp.
fetch() {
  if [ -n "${SPECSTONE_ARCHIVE_DIR:-}" ]; then
    cp "$SPECSTONE_ARCHIVE_DIR/$1" "$tmp/$1" 2>/dev/null ||
      fail "download failed for $1; the install is unchanged"
  else
    curl -fsSL --connect-timeout 30 --speed-limit 1 --speed-time 60 \
      -o "$tmp/$1" "$release_url/$1" ||
      fail "download failed for $1; the install is unchanged"
  fi
}

# Downloads archive $1 and SHA256SUMS into $tmp and checks the archive's hash.
fetch_and_verify() {
  fetch "$1"
  fetch SHA256SUMS
  expected=$(awk -v asset="$1" '$2 == asset || $2 == "*" asset { print $1; exit }' "$tmp/SHA256SUMS" |
    tr 'A-F' 'a-f')
  actual=$(hash_of "$1")
  if [ -z "$expected" ] || [ "$expected" != "$actual" ]; then
    fail "checksum mismatch for $1; the install is unchanged"
  fi
}

# Replaces ~/.specstone/lib and bin with the archive's, bin last. Each folder
# is copied aside first and moved in, so a failed copy leaves the old install
# runnable and no existing file is written (`specstone upgrade` runs from the
# binary being replaced).
place() {
  install_dir=$1
  mkdir -p "$install_dir" || fail "could not place $install_dir: run the install again"
  rm -rf "${install_dir:?}/.lib.new" "${install_dir:?}/.bin.new"
  cp -R "$tmp/unpack/lib" "$install_dir/.lib.new" ||
    fail "could not place $install_dir/lib: run the install again"
  cp -R "$tmp/unpack/bin" "$install_dir/.bin.new" ||
    fail "could not place $install_dir/bin: run the install again"
  rm -rf "${install_dir:?}/lib"
  mv "$install_dir/.lib.new" "$install_dir/lib" ||
    fail "could not place $install_dir/lib: run the install again"
  rm -rf "${install_dir:?}/bin"
  mv "$install_dir/.bin.new" "$install_dir/bin" ||
    fail "could not place $install_dir/bin: run the install again"
}

# Warns that the profile $1 is not written; the CLI is placed, so the run goes on.
warn_unwritten() {
  printf '%s\n' "specstone: could not write $1: add $2 to it yourself" >&2
}

# Appends the line $2 to the file $1 unless a whole line already matches it,
# and says so; a file whose last byte is not a newline gets one first.
add_path_line() {
  grep_status=0
  if [ -e "$1" ]; then
    grep -qxF -- "$2" "$1" 2>/dev/null || grep_status=$?
  else
    grep_status=1
  fi
  case "$grep_status" in
    0) return 0 ;;
    1) ;;
    *)
      warn_unwritten "$1" "$2"
      return 0
      ;;
  esac
  if ! mkdir -p -- "${1%/*}" 2>/dev/null; then
    warn_unwritten "$1" "$2"
    return 0
  fi
  lead=''
  if [ -s "$1" ] && [ -n "$(tail -c 1 "$1")" ]; then
    lead='
'
  fi
  if ! printf '%s%s\n' "$lead" "$2" 2>/dev/null >> "$1"; then
    warn_unwritten "$1" "$2"
    return 0
  fi
  printf '%s\n' "Added ~/.specstone/bin to the PATH in $1. Open a new terminal to use specstone."
}

# Prints the file a macOS bash login shell reads first, or ~/.bash_profile when none exists.
bash_login_file() {
  for name in .bash_profile .bash_login .profile; do
    if [ -e "$home_dir/$name" ]; then
      printf '%s\n' "$home_dir/$name"
      return 0
    fi
  done
  printf '%s\n' "$home_dir/.bash_profile"
}

# Puts ~/.specstone/bin first on the PATH of new shells, once per profile file.
add_path_entry() {
  # shellcheck disable=SC2016  # the profile must hold a literal $HOME and $PATH
  posix_line='export PATH="$HOME/.specstone/bin:$PATH"'
  # shellcheck disable=SC2016  # same: the line is written unexpanded
  fish_line='set -gx PATH "$HOME/.specstone/bin" $PATH'
  case "${SHELL:-}" in
    */zsh | zsh) add_path_line "$home_dir/.zshrc" "$posix_line" ;;
    */bash | bash)
      add_path_line "$home_dir/.bashrc" "$posix_line"
      if [ "$(uname -s)" = 'Darwin' ]; then
        add_path_line "$(bash_login_file)" "$posix_line"
      fi
      ;;
    */fish | fish) add_path_line "$home_dir/.config/fish/conf.d/specstone.fish" "$fish_line" ;;
    *) add_path_line "$home_dir/.profile" "$posix_line" ;;
  esac
}

# Runs `claude` with the arguments given and keeps its stdout in $claude_out.
# On a non-zero exit names the command and its first stderr line, then returns 1.
run_claude() {
  claude_status=0
  # stdin comes from /dev/null so claude cannot swallow the rest of a piped script
  claude_out=$(claude "$@" 2>"$tmp/claude.err" </dev/null) || claude_status=$?
  if [ "$claude_status" -eq 0 ]; then
    return 0
  fi
  claude_reason=$(head -n 1 "$tmp/claude.err")
  if [ -z "$claude_reason" ]; then
    claude_reason="exit $claude_status"
  fi
  printf 'specstone: claude %s failed: %s; run it by hand\n' "$*" "$claude_reason" >&2
  return 1
}

# Succeeds when the marketplace list $1 names a marketplace "specstone".
marketplace_added() {
  printf '%s\n' "$1" |
    grep -Eq '"name"[[:space:]]*:[[:space:]]*"specstone"'
}

# Succeeds when one entry of the plugin list $1 holds both the id
# specstone@specstone and the scope user; project and local entries never count.
plugin_installed_for_user() {
  printf '%s\n' "$1" | tr '\n' ' ' | tr '}' '\n' |
    grep -E '"id"[[:space:]]*:[[:space:]]*"specstone@specstone"' |
    grep -Eq '"scope"[[:space:]]*:[[:space:]]*"user"'
}

# Adds the marketplace and installs the plugin through claude, skipping what is
# there, or prints the two commands when claude is not on the PATH. Never fails
# the script: the CLI install stands.
install_plugin() {
  if ! command -v claude >/dev/null 2>&1; then
    printf '%s\n' \
      'To add the Specstone plugin to Claude Code, run:' \
      '  claude plugin marketplace add nontravis/specstone' \
      '  claude plugin install specstone@specstone'
    return 0
  fi
  run_claude plugin marketplace list --json || return 0
  marketplaces=$claude_out
  run_claude plugin list --json || return 0
  plugins=$claude_out
  if ! marketplace_added "$marketplaces"; then
    run_claude plugin marketplace add nontravis/specstone || return 0
  fi
  if ! plugin_installed_for_user "$plugins"; then
    run_claude plugin install specstone@specstone || return 0
  fi
}

main() {
  target=$(pick_target)
  home_dir=${HOME:-${USERPROFILE:-}}
  if [ -z "$home_dir" ]; then
    fail 'no home folder: HOME and USERPROFILE are unset'
  fi
  install_dir="$home_dir/.specstone"
  asset="specstone-$target.tar.gz"

  trap cleanup EXIT
  trap 'exit 1' HUP INT TERM
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/specstone.XXXXXX")

  fetch_and_verify "$asset"
  mkdir "$tmp/unpack"
  tar -xzf "$tmp/$asset" -C "$tmp/unpack" 2>/dev/null ||
    fail "could not unpack $asset; the install is unchanged"

  probe_status=0
  new_version=$("$tmp/unpack/bin/specstone" --version 2>/dev/null) || probe_status=$?
  if [ "$probe_status" -ne 0 ]; then
    fail "the downloaded specstone does not run (exit $probe_status); if TMPDIR is mounted noexec, set TMPDIR to another folder; the install is unchanged"
  fi
  old_version=$("$install_dir/bin/specstone" --version 2>/dev/null || true)
  if [ -n "$old_version" ] && [ "$old_version" = "$new_version" ]; then
    printf '%s\n' "specstone $new_version is already the latest release"
  else
    place "$install_dir"
    printf '%s\n' "specstone $new_version installed in $install_dir/bin"
  fi

  add_path_entry
  install_plugin
}

main "$@"
