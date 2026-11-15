import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';

const _patternsFieldId = 'patterns';
const _outOfScopeSectionId = 'out_of_scope';

/// A bullet that opens with the code span `<pattern>/<item>`, then ` — `.
final _skipLine = RegExp('^[-*] `([^`/]+)/([^`/]+)` — ');

/// One skip line of an `out_of_scope` section: the item a doc leaves out of
/// the feature pattern it lists.
///
/// `span` is the code span's text as written, without its backticks.
typedef SkipLine = ({int line, String pattern, String item, String span});

/// Returns the skip lines of [doc]'s `out_of_scope` section, keyed by file
/// line.
///
/// A bullet counts only when it names a pattern [doc] lists in `patterns:`.
/// Empty for a doc whose type carries no `patterns` field.
Map<int, SkipLine> skipLinesOf(CheckContext context, IndexedDoc doc) {
  if (!context.typeHoldsField(context.typeOf(doc), _patternsFieldId)) {
    return const {};
  }
  final section = context.heldIndexOf(doc, _outOfScopeSectionId);
  if (section == null) return const {};
  final listed = {for (final entry in _patternEntries(context, doc)) entry.id};
  return {
    for (final line in context.bodyLinesOf(doc, section))
      if (!line.fenced)
        if (_skipLine.firstMatch(line.text) case final match?)
          if (listed.contains(match.group(1)))
            line.line: (
              line: line.line,
              pattern: match.group(1)!,
              item: match.group(2)!,
              span: '${match.group(1)}/${match.group(2)}',
            ),
  };
}

/// Whether [written], a doc-name mention at [line], is the span of a skip line.
bool isSkipSpan(Map<int, SkipLine> skips, int line, String written) =>
    skips[line]?.span == written;

/// Yields a finding per `patterns:` value of [doc] that names no merged
/// feature pattern, and per skip line whose item that pattern does not hold.
Iterable<Finding> checkFeaturePatterns(
  CheckContext context,
  IndexedDoc doc,
) sync* {
  if (!context.typeHoldsField(context.typeOf(doc), _patternsFieldId)) return;
  final set = context.index.set;
  for (final (:id, :line) in _patternEntries(context, doc)) {
    if (set.featurePattern(id) != null) continue;
    yield context.finding(
      doc,
      FindingKind.featurePatternMissing,
      line: line,
      message: 'patterns value $id names no feature pattern',
      keys: {'pattern': id},
    );
  }
  for (final skip in skipLinesOf(context, doc).values) {
    final pattern = set.featurePattern(skip.pattern);
    if (pattern == null || pattern.items.any((item) => item.id == skip.item)) {
      continue;
    }
    yield context.finding(
      doc,
      FindingKind.featurePatternItemMissing,
      line: skip.line,
      message:
          'skip line names item ${skip.item}, which feature pattern '
          '${skip.pattern} does not hold',
      keys: {'pattern': skip.pattern, 'item': skip.item},
    );
  }
}

/// Returns each string value of [doc]'s `patterns:` with its line; a value of
/// any other type is the field check's to report.
List<({String id, int line})> _patternEntries(
  CheckContext context,
  IndexedDoc doc,
) => [
  for (final entry in context.linesOf(doc).entriesOf(_patternsFieldId))
    if (entry.value case final String id) (id: id, line: entry.line),
];
