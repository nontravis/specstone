import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/templates/pattern_entry.dart';

final _codeSpan = RegExp(r'`[^`\n]*`');

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
      (text: held[i].headerLine, line: headerLine, fenced: false),
      ...context.bodyLinesOf(doc, i),
    ].where((line) => !line.fenced).toList();
    for (final (:text, :line, fenced: _) in lines) {
      final onPrefix = prefix == null || text.startsWith(prefix);
      for (final entry in [...docBanned, if (onPrefix) ...sectionBanned]) {
        for (final matched in _bannedMatches(context, entry, text)) {
          yield context.finding(
            doc,
            FindingKind.patternBanned,
            line: line,
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
      final regExp = context.patternOf(entry);
      if (lines.any((line) => regExp.hasMatch(_maskCode(line.text)))) continue;
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

/// Returns the non-excepted, non-empty matches of [entry] on [text].
Iterable<String> _bannedMatches(
  CheckContext context,
  PatternEntry entry,
  String text,
) sync* {
  final regExp = context.patternOf(entry);
  final searched = switch (entry.scope) {
    PatternScope.text => [_maskCode(text)],
    PatternScope.code => [
      for (final span in _codeSpan.allMatches(text))
        span.group(0)!.substring(1, span.group(0)!.length - 1),
    ],
    PatternScope.all => [text],
  };
  for (final haystack in searched) {
    for (final match in regExp.allMatches(haystack)) {
      final matched = match.group(0)!;
      if (matched.isEmpty || context.isExcepted(entry, matched)) continue;
      yield matched;
    }
  }
}

/// Returns [text] with each inline code span replaced by spaces of equal
/// length, so match positions and neighbours stay put.
String _maskCode(String text) =>
    text.replaceAllMapped(_codeSpan, (m) => ' ' * m.group(0)!.length);
