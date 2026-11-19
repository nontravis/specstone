import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/doc_lines.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/index_query/banned_matches.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';

const _edge = r'[\p{L}\p{N}_-]';
const _space = r'[ \t]+';
final _spaceRun = RegExp(_space);

/// Returns the whole-word pattern of [word], letter case ignored.
///
/// The words of a phrase match across spaces or tabs; no letter, digit, `_`,
/// or `-` may touch the phrase on either side.
RegExp bannedWordPattern(String word) => RegExp(
  '(?<!$_edge)'
  '${word.split(_spaceRun).map(RegExp.escape).join(_space)}'
  '(?!$_edge)',
  caseSensitive: false,
  unicode: true,
);

/// Returns the banned-word findings of a typed [doc]; an untyped doc has none.
///
/// Every prose line of every section holds one finding per occurrence of each
/// word banned there: the doc-level list on every line, and a
/// section's own list on its `linePrefix` lines, both minus the doc-level and
/// the section's allowed words. Inline code spans, fenced code, and closed
/// generated blocks are not prose, so a word inside one is never reported.
/// A prose field's string value takes the doc-level list alone.
Iterable<Finding> checkBannedWords(CheckContext context, IndexedDoc doc) sync* {
  final type = context.typeOf(doc);
  if (type == null) return;
  final docLines = context.linesOf(doc);
  final held = context.contentOf(doc).sections;
  final docBanned = type.lint.bannedWords ?? const <String>[];
  yield* _fieldFindings(context, doc, type, docBanned);
  for (var i = 0; i < held.length; i++) {
    final section = held[i];
    final template = context.templateSectionAt(doc, i);
    final allowed = {...?type.lint.allowedWords, ...?template?.allowedWords};
    final everywhere = _patternsOf(context, docBanned, allowed);
    final onPrefix = _patternsOf(context, [
      ...docBanned,
      ...?template?.bannedWords,
    ], allowed);
    if (onPrefix.isEmpty) continue;
    final prefix = template?.linePrefix;
    final headerLine = docLines.sectionLines[i];
    final sectionKey = template?.id ?? section.key;
    final lines = _sectionLines(
      section,
      headerLine,
      docLines,
      (line) => context.isGeneratedLine(doc, line),
    );
    for (final searched in lines) {
      final onPrefixLine = prefix == null || searched.raw.startsWith(prefix);
      final prose = searched.prose;
      for (final _BannedPattern(:word, :pattern)
          in onPrefixLine ? onPrefix : everywhere) {
        if (!pattern.hasMatch(prose)) continue;
        for (final _ in pattern.allMatches(prose)) {
          yield context.finding(
            doc,
            FindingKind.bannedWord,
            line: searched.line,
            message: '$word is a banned word in $sectionKey',
            keys: {'word': word, 'section': sectionKey},
          );
        }
      }
    }
  }
}

Iterable<Finding> _fieldFindings(
  CheckContext context,
  IndexedDoc doc,
  MergedDocType type,
  List<String> docBanned,
) sync* {
  final patterns = _patternsOf(context, docBanned, {
    ...?type.lint.allowedWords,
  });
  if (patterns.isEmpty) return;
  final docLines = context.linesOf(doc);
  final stored = context.contentOf(doc).itemFacts.fieldItems;
  for (final field in type.fields) {
    final line = docLines.keyLine(field.id);
    final value = docLines.writtenValueOf(field.id);
    if (!stored.containsKey(field.id) || line == null || value == null) {
      continue;
    }
    for (final text in value.split('\n')) {
      final prose = SearchLine(text, line).prose;
      for (final _BannedPattern(:word, :pattern) in patterns) {
        for (final _ in pattern.allMatches(prose)) {
          yield context.finding(
            doc,
            FindingKind.bannedWord,
            line: line,
            message: '$word is a banned word in ${field.id}',
            keys: {'word': word, 'field': field.id},
          );
        }
      }
    }
  }
}

/// Returns the distinct [words] not in [allowed] with their cached patterns,
/// in order of first appearance.
List<_BannedPattern> _patternsOf(
  CheckContext context,
  Iterable<String> words,
  Set<String> allowed,
) => [
  for (final word in {...words})
    if (!allowed.contains(word))
      _BannedPattern(word: word, pattern: context.bannedPatternOf(word)),
];

/// A banned word and its cached pattern.
final class _BannedPattern {
  const new({required this.word, required this.pattern});

  final String word;
  final RegExp pattern;
}

/// Returns the header line and the unfenced body lines of [section], which
/// starts at file line [headerLine], less each line [isGenerated] marks.
Iterable<SearchLine> _sectionLines(
  IndexedSection section,
  int headerLine,
  DocLines docLines,
  bool Function(int line) isGenerated,
) sync* {
  yield SearchLine(section.headerLine, headerLine);
  final body = section.body.split('\n');
  if (body.last.isEmpty && body.length > 1) body.removeLast();
  for (var j = 0; j < body.length; j++) {
    final line = headerLine + 1 + j;
    if (!docLines.isFenced(line) && !isGenerated(line)) {
      yield SearchLine(body[j], line);
    }
  }
}
