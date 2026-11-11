import 'package:specstone_core/src/templates/project_config.dart'
    show isCodeRootValue;

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

/// Whether [entry], a `code:`, `covers:`, or `implements:` path, names the same
/// place on every OS: a relative `/` path ([isCodeRootValue]) with no name
/// that [hasWindowsDroppedEnd].
bool isPortableCodeEntry(String entry) =>
    isCodeRootValue(entry) && !hasWindowsDroppedEnd(entry.split(_separator));
