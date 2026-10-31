import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';

const _headingMarker = '### ';
final _listMarker = RegExp(r'^(?:[-*+]|\d+[.)])\s+');

/// Returns the item ID findings of a typed [doc]; an untyped doc has none.
///
/// A held section whose template writes a `prefix_id` holds items: the `###`
/// headings when it has any, else its top-level list entries, fenced code
/// excluded and `N/A` entries skipped. An item with no ID of that prefix
/// holds an `item_id_missing`; one repeating an ID already held in the doc
/// holds an `item_id_duplicate`.
Iterable<Finding> checkItemIds(CheckContext context, IndexedDoc doc) sync* {
  if (context.typeOf(doc) == null) return;
  final held = context.contentOf(doc).sections;
  final seen = <String, int>{};
  for (var i = 0; i < held.length; i++) {
    final template = context.templateSectionAt(doc, i);
    final prefix = template?.prefixId;
    if (template == null || prefix == null) continue;
    final sectionKey = template.id;
    final idPattern = RegExp('^(?:\\*\\*)?${RegExp.escape(prefix)}(\\d+)');
    final body = [
      for (final line in context.bodyLinesOf(doc, i))
        if (!line.fenced) line,
    ];
    for (final (:text, :line) in _itemsOf(body)) {
      if (text.startsWith('N/A')) continue;
      final match = idPattern.firstMatch(text);
      if (match == null) {
        yield context.finding(
          doc,
          FindingKind.itemIdMissing,
          line: line,
          message: 'the item opens with no $prefix ID',
          keys: {'section': sectionKey, 'prefix': prefix},
        );
        continue;
      }
      final id = '$prefix${match.group(1)}';
      final first = seen[id];
      if (first == null) {
        seen[id] = line;
        continue;
      }
      yield context.finding(
        doc,
        FindingKind.itemIdDuplicate,
        line: line,
        message: '$id is already held at line $first',
        keys: {'id': id, 'section': sectionKey},
      );
    }
  }
}

/// Returns the item texts of [body] with their lines, marker stripped.
List<({String text, int line})> _itemsOf(List<BodyLine> body) {
  final headings = [
    for (final line in body)
      if (line.text.startsWith(_headingMarker))
        (text: line.text.substring(_headingMarker.length), line: line.line),
  ];
  if (headings.isNotEmpty) return headings;
  return [
    for (final line in body)
      if (_listMarker.firstMatch(line.text) case final marker?)
        (text: line.text.substring(marker.end), line: line.line),
  ];
}
