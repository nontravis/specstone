import 'dart:convert';

/// Where a markdown link points, relative to the doc that holds it.
sealed class DocLinkTarget;

/// An `http` or `https` address.
final class WebTarget extends DocLinkTarget;

/// A doc under the docs root.
final class DocTarget extends DocLinkTarget {
  new(this.docPath);

  /// The docPath the link resolves to.
  final String docPath;
}

/// Anything else: another scheme, a rooted path, or a path above the docs root.
final class OutsideTarget extends DocLinkTarget {
  new(this.shown);

  /// The path the span shows.
  final String shown;
}

/// Decodes the percent escapes of [text]: each `%` followed by two hex
/// digits becomes that byte, every other character its UTF-8 bytes, and the
/// bytes decode as UTF-8 with U+FFFD for a sequence that is not UTF-8.
///
/// A `%` not followed by two hex digits stays as written.
String percentDecoded(String text) {
  final firstPercent = text.indexOf('%');
  // A text with no escape decodes to itself, so most hrefs pay nothing.
  if (firstPercent < 0) return text;
  final bytes = <int>[];
  // Literal text is encoded a run at a time: a character outside the BMP is
  // two code units, and encoding each alone would turn it into two U+FFFD.
  var runStart = 0;
  for (var i = firstPercent; i < text.length; i++) {
    if (text.codeUnitAt(i) != 0x25 || i + 2 >= text.length) continue;
    final byte = _hexByteAt(text, i + 1);
    if (byte == null) continue;
    bytes
      ..addAll(utf8.encode(text.substring(runStart, i)))
      ..add(byte);
    i += 2;
    runStart = i + 1;
  }
  bytes.addAll(utf8.encode(text.substring(runStart)));
  return utf8.decode(bytes, allowMalformed: true);
}

/// Returns the byte the two hex digits at [start] and [start] + 1 name, or
/// null when either is not a hex digit.
int? _hexByteAt(String text, int start) {
  var byte = 0;
  for (var i = start; i < start + 2; i++) {
    final digit = text.codeUnitAt(i);
    final value = switch (digit) {
      >= 0x30 && <= 0x39 => digit - 0x30,
      >= 0x41 && <= 0x46 => digit - 0x37,
      >= 0x61 && <= 0x66 => digit - 0x57,
      _ => null,
    };
    if (value == null) return null;
    byte = byte * 16 + value;
  }
  return byte;
}

/// Resolves [href], written in the doc at [docPath], to its target.
///
/// An escape that is not UTF-8 reads as U+FFFD, so such a link resolves like
/// any other path; reading `uri.pathSegments` instead threw a FormatException
/// on its strict UTF-8 decode.
DocLinkTarget resolveDocLink(String href, String docPath) {
  final uri = Uri.tryParse(href);
  if (uri == null) return OutsideTarget(href);
  if (uri.hasScheme) {
    final scheme = uri.scheme;
    return scheme == 'http' || scheme == 'https'
        ? WebTarget()
        : OutsideTarget(href);
  }
  if (uri.hasAuthority || uri.path.startsWith('/')) return OutsideTarget(href);
  // An empty path (`#frag`, `?q`) names the doc itself.
  if (uri.path.isEmpty) return DocTarget(docPath);
  final segments = [
    for (final segment in uri.path.split('/')) percentDecoded(segment),
  ];
  final resolved = _resolveSegments(segments, docPath);
  if (resolved == null || resolved.isEmpty) return OutsideTarget(href);
  return DocTarget(resolved);
}

/// Returns the docPath [segments] reach from [docPath]'s folder, or null when
/// a `..` pops past the docs root or a segment holds a `/`. An empty result
/// names the docs root.
///
/// [segments] are already percent-decoded, so an encoded slash (`%2F`)
/// decoded to one segment cannot name a doc.
String? _resolveSegments(List<String> segments, String docPath) {
  final path = docPath.split('/')..removeLast();
  for (final segment in segments) {
    switch (segment) {
      case '' || '.':
        continue;
      case '..':
        if (path.isEmpty) return null;
        path.removeLast();
      case _ when segment.contains('/'):
        return null;
      default:
        path.add(segment);
    }
  }
  return path.join('/');
}
