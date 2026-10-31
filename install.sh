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

# Appends the line $2 to the file $1 unless a whole line already matches it,
# and says so; a file whose last byte is not a newline gets one first.
add_path_line() {
  if [ -f "$1" ] && grep -qxF -- "$2" "$1"; then
    return 0
  fi
  mkdir -p "${1%/*}" || fail "could not create ${1%/*}: add $2 to $1 yourself"
  if [ -s "$1" ] && [ -n "$(tail -c 1 "$1")" ]; then
    printf '\n' >> "$1" || fail "could not write $1: add $2 to it yourself"
  fi
  printf '%s\n' "$2" >> "$1" || fail "could not write $1: add $2 to it yourself"
  printf '%s\n' "Added ~/.specstone/bin to the PATH in $1. Open a new terminal to use specstone."
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
        add_path_line "$home_dir/.bash_profile" "$posix_line"
      fi
      ;;
    */fish | fish) add_path_line "$home_dir/.config/fish/conf.d/specstone.fish" "$fish_line" ;;
    *) add_path_line "$home_dir/.profile" "$posix_line" ;;
  esac
}

install_plugin() {
  :
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
