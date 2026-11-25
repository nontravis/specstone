const _separator = '/';

/// Whether a name of [segments] ends in a space or a dot, `.` and `..` aside.
///
/// Windows drops those characters from the end of a name before it reaches the
/// disk, so `API.md ` finds `API.md` there and only there. A rule that checks
/// the disk refuses such a name first, so it answers alike on every OS.
bool hasWindowsDroppedEnd(Iterable<String> segments) => segments.any(
  (segment) =>
      segment != '.' &&
      segment != '..' &&
      (segment.endsWith(' ') || segment.endsWith('.')),
);

/// Whether the `/`-separated [path] names the same place on every OS.
///
/// A `\` is a separator on Windows alone, and a name ending in a space or a
/// dot ([hasWindowsDroppedEnd]) is found there alone. A rule that checks a name
/// from a doc or the config on disk refuses a path this rejects, so `check` and
/// a run give the same answer on every OS.
bool isPortablePath(String path) =>
    !path.contains(r'\') && !hasWindowsDroppedEnd(path.split(_separator));
