import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'package:specstone_core/src/doc_model/doc.dart';

/// The base of empty text, which `get` prints for a section or field a doc
/// lacks.
const emptyBaseHash = 'e3b0c44298fc';

/// Returns the base of [text]: the first 12 hex characters of the SHA-256 of
/// its UTF-8 bytes.
///
/// A `set` call hands the base back, so it can tell the target changed since
/// `get`. It is a change check, not a security control.
String baseHashOf(String text) =>
    sha256.convert(utf8.encode(text)).toString().substring(0, 12);

/// Returns, for each of [doc]'s sections in order, the index of its header
/// line among the lines of `doc.afterFrontmatter`.
///
/// The count comes from the parsed head and bodies, so a `##` line inside a
/// fence is never taken for a header.
List<int> sectionLineIndexes(Doc doc) {
  final lines = _lines(doc.afterFrontmatter);
  final indexes = <int>[];
  var next = _lines(doc.head).length;
  for (final section in doc.sections) {
    while (next < lines.length && lines[next].trim().isEmpty) {
      next++;
    }
    indexes.add(next);
    next += 1 + _lines(section.body).length;
  }
  return indexes;
}

/// Returns [lfText] with the body of section [section] replaced by [body].
///
/// The header line and the blank lines after the old body stay.
String withSectionBody(String lfText, int section, String body) {
  final doc = Doc.parse(lfText);
  final lines = _lines(doc.afterFrontmatter);
  final header = sectionLineIndexes(doc)[section];
  final bodyEnd = header + 1 + _lines(doc.sections[section].body).length;
  final headerLine = lines[header];
  return _frontmatterOf(lfText, doc) +
      [
        ...lines.sublist(0, header),
        if (headerLine.endsWith('\n')) headerLine else '$headerLine\n',
        _endWithNewline(body),
        ...lines.sublist(bodyEnd),
      ].join();
}

/// Returns [lfText] without section [section]: its header line through the
/// line before the next header, or through the end.
String withoutSection(String lfText, int section) {
  final doc = Doc.parse(lfText);
  final lines = _lines(doc.afterFrontmatter);
  final indexes = sectionLineIndexes(doc);
  final end = section + 1 < indexes.length
      ? indexes[section + 1]
      : lines.length;
  return _frontmatterOf(lfText, doc) +
      [...lines.sublist(0, indexes[section]), ...lines.sublist(end)].join();
}

/// Returns [lfText] with a section added.
///
/// With [before], the section lands ahead of the section at that index,
/// followed by one blank line. Without it, the section lands at the end after
/// one blank line, and the text first gains a final `\n`.
String withSectionAdded(
  String lfText, {
  required String headerLine,
  required String body,
  int? before,
}) {
  final added = '$headerLine\n${_endWithNewline(body)}';
  if (before == null) {
    if (lfText.isEmpty) return added;
    return '${_endWithNewline(lfText)}\n$added';
  }
  final doc = Doc.parse(lfText);
  final lines = _lines(doc.afterFrontmatter);
  final at = sectionLineIndexes(doc)[before];
  return _frontmatterOf(lfText, doc) +
      [...lines.sublist(0, at), '$added\n', ...lines.sublist(at)].join();
}

/// Returns [lfText] with the frontmatter key block [key] set to [blockText].
///
/// An existing block is replaced in place, an absent one is added after the
/// last block, and a null [blockText] removes it. A doc without frontmatter
/// gains one when [blockText] is not null.
String withKeyBlock(String lfText, String key, String? blockText) {
  final doc = Doc.parse(lfText);
  final blocks = doc.frontmatter;
  final block = blockText == null ? null : _endWithNewline(blockText);
  if (blocks == null) {
    return block == null ? lfText : '---\n$block---\n$lfText';
  }
  var start = lfText.indexOf('\n') + 1;
  for (final existing in blocks) {
    if (existing.key == key) {
      final end = start + existing.text.length;
      return lfText.substring(0, start) + (block ?? '') + lfText.substring(end);
    }
    start += existing.text.length;
  }
  if (block == null) return lfText;
  return lfText.substring(0, start) + block + lfText.substring(start);
}

/// Returns [lfText] with its title line set to `# [title]`.
///
/// A doc without a title line gains one as the first line after the
/// frontmatter.
String withTitle(String lfText, String title) {
  final doc = Doc.parse(lfText);
  final lines = _lines(doc.afterFrontmatter);
  final at = doc.titleLineIndex;
  if (at == null) {
    return '${_frontmatterOf(lfText, doc)}# $title\n${doc.afterFrontmatter}';
  }
  final ending = lines[at].endsWith('\n') ? '\n' : '';
  lines[at] = '# $title$ending';
  return _frontmatterOf(lfText, doc) + lines.join();
}

/// The frontmatter of [lfText], opening and closing lines included.
String _frontmatterOf(String lfText, Doc doc) =>
    lfText.substring(0, lfText.length - doc.afterFrontmatter.length);

String _endWithNewline(String text) =>
    text.isEmpty || text.endsWith('\n') ? text : '$text\n';

/// Splits [text] into lines, each keeping its trailing `\n` when it has one.
List<String> _lines(String text) => [
  for (final match in RegExp(r'[^\n]*\n|[^\n]+').allMatches(text))
    match.group(0)!,
];
