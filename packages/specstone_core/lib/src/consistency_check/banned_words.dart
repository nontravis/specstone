import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';

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
/// Every line of every section holds one finding per occurrence of each word
/// banned there (INV-9): the doc-level list on every line, and a section's own
/// list on its `linePrefix` lines, both minus the doc-level and the section's
/// allowed words.
Iterable<Finding> checkBannedWords(CheckContext context, IndexedDoc doc) sync* {
  final type = context.typeOf(doc);
  if (type == null) return;
  final docLines = context.linesOf(doc);
  final held = context.contentOf(doc).sections;
  final docBanned = type.lint.bannedWords ?? const <String>[];
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
    for (final (lineIndex, line) in _sectionLines(
      section,
      docLines.lines,
      headerLine,
    )) {
      final onPrefixLine = prefix == null || line.startsWith(prefix);
      for (final (:word, :pattern) in onPrefixLine ? onPrefix : everywhere) {
        if (!pattern.hasMatch(line)) continue;
        for (final _ in pattern.allMatches(line)) {
          yield context.finding(
            doc,
            FindingKind.bannedWord,
            line: lineIndex,
            message: '$word is a banned word in $sectionKey',
            keys: {'word': word, 'section': sectionKey},
          );
        }
      }
    }
  }
}

/// Returns the distinct [words] not in [allowed] with their cached patterns,
/// in order of first appearance.
List<({String word, RegExp pattern})> _patternsOf(
  CheckContext context,
  Iterable<String> words,
  Set<String> allowed,
) => [
  for (final word in {...words})
    if (!allowed.contains(word))
      (word: word, pattern: context.bannedPatternOf(word)),
];

/// Returns the header line and body lines of [section] at [headerLine], from
/// [lines].
Iterable<(int, String)> _sectionLines(
  IndexedSection section,
  List<String> lines,
  int headerLine,
) sync* {
  yield (headerLine, lines[headerLine - 1]);
  final body = section.body.split('\n');
  if (body.last.isEmpty && body.length > 1) body.removeLast();
  for (var j = 0; j < body.length; j++) {
    yield (headerLine + 1 + j, body[j]);
  }
}
