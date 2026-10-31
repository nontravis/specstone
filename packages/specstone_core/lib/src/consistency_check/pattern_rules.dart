import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/templates/pattern_entry.dart';

/// Returns the pattern findings of a typed [doc]; an untyped doc has none.
///
/// A `banned_patterns` entry holds one finding per match on a line of a held
/// section, fenced code excluded; the doc-level entries apply on every line,
/// a section's own on its `linePrefix` lines. A `required_patterns` entry with
/// no matching line in its held section holds one finding at the header.
Iterable<Finding> checkPatterns(CheckContext context, IndexedDoc doc) sync* {
  final type = context.typeOf(doc);
  if (type == null) return;
  final docLines = context.linesOf(doc);
  final held = context.contentOf(doc).sections;
  final docBanned = type.lint.bannedPatterns ?? const <PatternEntry>[];
  for (var i = 0; i < held.length; i++) {
    final template = context.templateSectionAt(doc, i);
    final sectionBanned = template?.bannedPatterns ?? const <PatternEntry>[];
    final required = template?.requiredPatterns ?? const <PatternEntry>[];
    if (docBanned.isEmpty && sectionBanned.isEmpty && required.isEmpty) {
      continue;
    }
    final prefix = template?.linePrefix;
    final headerLine = docLines.sectionLines[i];
    final sectionKey = template?.id ?? held[i].key;
    final lines = [
      _SearchLine(held[i].headerLine, headerLine),
      for (final (:text, :line, :fenced) in context.bodyLinesOf(doc, i))
        if (!fenced) _SearchLine(text, line),
    ];
    for (final searched in lines) {
      final onPrefix = prefix == null || searched.raw.startsWith(prefix);
      for (final entry in [...docBanned, if (onPrefix) ...sectionBanned]) {
        for (final matched in _bannedMatches(entry, searched)) {
          yield context.finding(
            doc,
            FindingKind.patternBanned,
            line: searched.line,
            message: '${entry.message}: $matched',
            keys: {
              'pattern': entry.id,
              'section': sectionKey,
              'match': matched,
            },
          );
        }
      }
    }
    for (final entry in required) {
      final regExp = entry.regExp;
      if (lines.any((line) => regExp.hasMatch(line.prose))) continue;
      yield context.finding(
        doc,
        FindingKind.patternMissing,
        line: headerLine,
        message: entry.message,
        keys: {'pattern': entry.id, 'section': sectionKey},
      );
    }
  }
}

/// Returns the non-excepted, non-empty matches of [entry] on [line].
Iterable<String> _bannedMatches(PatternEntry entry, _SearchLine line) sync* {
  final regExp = entry.regExp;
  final searched = switch (entry.scope) {
    PatternScope.text => [line.prose],
    PatternScope.code => line.code,
    PatternScope.all => [line.raw],
  };
  for (final haystack in searched) {
    for (final match in regExp.allMatches(haystack)) {
      final matched = match.group(0)!;
      if (matched.isEmpty || entry.isExcepted(matched)) continue;
      yield matched;
    }
  }
}

/// One unfenced line the patterns search, split at its inline code spans once.
///
/// A span runs from a backtick to the next one; a last unpaired backtick
/// opens none.
final class _SearchLine {
  new(this.raw, this.line);

  /// The line as written; it holds no line end.
  final String raw;

  /// The 1-based file line.
  final int line;

  /// [raw] with each code span, backticks included, blanked to spaces of
  /// equal length, so match positions and neighbours stay put.
  late final String prose = _blankSpans();

  /// The text inside each code span, backticks dropped.
  late final List<String> code = [
    for (final (start, end) in _spans) raw.substring(start + 1, end - 1),
  ];

  /// The start and end offset of each code span, backticks included.
  late final List<(int, int)> _spans = _codeSpansOf(raw);

  String _blankSpans() {
    if (_spans.isEmpty) return raw;
    final blanked = StringBuffer();
    var from = 0;
    for (final (start, end) in _spans) {
      blanked
        ..write(raw.substring(from, start))
        ..write(' ' * (end - start));
      from = end;
    }
    return (blanked..write(raw.substring(from))).toString();
  }
}

/// Returns the start and end offset of each code span of [line].
List<(int, int)> _codeSpansOf(String line) {
  // indexOf, not a RegExp: the regex engine tries every offset of a pattern
  // that opens with one character.
  final spans = <(int, int)>[];
  var open = line.indexOf('`');
  while (open >= 0) {
    final close = line.indexOf('`', open + 1);
    if (close < 0) break;
    spans.add((open, close + 1));
    open = line.indexOf('`', close + 1);
  }
  return spans;
}
