#!/bin/sh
# Installs the Specstone CLI under ~/.specstone:
#   curl -fsSL https://raw.githubusercontent.com/nontravis/specstone/main/install.sh | sh
# The body sits in functions and `main "$@"` is the last line, so a truncated
# stream runs nothing.
set -eu

release_url='https://github.com/nontravis/specstone/releases/latest/download'
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

# Prints the SHA-256 of the file $1 as lower-case hex.
hash_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d ' ' -f 1 | tr 'A-F' 'a-f'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | cut -d ' ' -f 1 | tr 'A-F' 'a-f'
  else
    fail "no sha256sum or shasum to check $2; the install is unchanged"
  fi
}

# Copies or downloads the file $1 from the archive folder or the release into $tmp.
fetch() {
  if [ -n "${SPECSTONE_ARCHIVE_DIR:-}" ]; then
    cp "$SPECSTONE_ARCHIVE_DIR/$1" "$tmp/$1" 2>/dev/null ||
      fail "download failed for $1; the install is unchanged"
  else
    curl -fsSL -o "$tmp/$1" "$release_url/$1" ||
      fail "download failed for $1; the install is unchanged"
  fi
}

# Downloads archive $1 and SHA256SUMS into $tmp and checks the archive's hash.
fetch_and_verify() {
  fetch "$1"
  fetch SHA256SUMS
  expected=$(awk -v asset="$1" '$2 == asset || $2 == "*" asset { print $1; exit }' "$tmp/SHA256SUMS" |
    tr 'A-F' 'a-f')
  actual=$(hash_of "$tmp/$1" "$1")
  if [ -z "$expected" ] || [ "$expected" != "$actual" ]; then
    fail "checksum mismatch for $1; the install is unchanged"
  fi
}

# Replaces ~/.specstone/bin and lib with the archive's; never writes into an
# existing file, since `specstone upgrade` runs from the binary being replaced.
place() {
  install_dir=$1
  mkdir -p "$install_dir"
  rm -rf "${install_dir:?}/bin" "${install_dir:?}/lib"
  cp -R "$tmp/unpack/bin" "$install_dir/bin"
  cp -R "$tmp/unpack/lib" "$install_dir/lib"
}

add_path_entry() {
  :
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

  tmp=$(mktemp -d)
  trap cleanup EXIT
  trap 'exit 1' HUP INT TERM

  fetch_and_verify "$asset"
  mkdir "$tmp/unpack"
  tar -xzf "$tmp/$asset" -C "$tmp/unpack"

  new_version=$("$tmp/unpack/bin/specstone" --version)
  old_version=$("$install_dir/bin/specstone" --version 2>/dev/null || true)
  if [ -n "$old_version" ] && [ "$old_version" = "$new_version" ]; then
    echo "specstone $new_version is already the latest release"
  else
    place "$install_dir"
    echo "specstone $new_version installed in $install_dir/bin"
  fi

  add_path_entry
  install_plugin
}

main "$@"
