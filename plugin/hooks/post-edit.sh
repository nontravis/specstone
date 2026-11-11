#!/bin/sh
# PostToolUse hook: runs `specstone hook post-edit`, which reads the hook JSON
# on stdin. Starts nothing found through an empty, ".", or relative PATH entry.

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
exec specstone hook post-edit
