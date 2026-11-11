#!/bin/sh
# SessionStart launcher: runs session-start.sh with the bash found on an
# absolute PATH entry. /bin/sh starts it because every host has /bin/sh but not
# every host has /bin/bash (NixOS, Guix). Starts nothing found through an empty,
# ".", or relative PATH entry, and no startup file named by BASH_ENV, which a
# bash would read before the first line of its script.

# Keeps only the absolute entries of PATH, so no program is found in the
# current folder or a relative folder; an empty entry means the current folder.
# With none left, PATH is the system folders, since an empty PATH searches ".".
absolute_path_only() {
  kept=''
  rest=${PATH:-}:
  while [ -n "$rest" ]; do
    entry=${rest%%:*}
    rest=${rest#*:}
    case "$entry" in
      /*) kept=${kept:+$kept:}$entry ;;
    esac
  done
  PATH=${kept:-/usr/bin:/bin}
  export PATH
}

absolute_path_only
unset BASH_ENV

# A host with no bash exits 127 and prints nothing, as the old bare `bash` did.
bash=$(command -v bash) || exit 127
case "$bash" in
  /*) ;;
  *) exit 127 ;;
esac

exec "$bash" "${0%/*}/session-start.sh"
