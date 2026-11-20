import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/consistency_check/frontmatter_rules.dart'
    show definesSectionId;
import 'package:specstone_core/src/consistency_check/required_sections.dart'
    show isBlankAt;
import 'package:specstone_core/src/index_query/indexed_doc.dart';

const _retrimKey = 'retrim';
const _sectionKey = 'section';
const _waitsMessage = 'waits for a trim against its guide';
const _absentMessage = 'is absent; drop the mark';

/// Returns one `retrim_due` finding per distinct defined section id the
/// `retrim` field of a typed [doc] lists.
///
/// A section the doc holds reports at its header; one absent, empty, or
/// disabled reports at the `retrim` line. An id no layer defines, a scalar or
/// non-list value, and a list item that is not a string stay to the
/// frontmatter rule alone, so no bad value gives two findings.
Iterable<Finding> checkRetrimMarks(CheckContext context, IndexedDoc doc) sync* {
  final type = context.typeOf(doc);
  if (type == null) return;
  final retrim = doc.frontmatter[_retrimKey];
  // The field is locked to a string list, so this is its one fit test.
  if (retrim is! List || retrim.any((item) => item is! String)) return;
  final lines = context.linesOf(doc);
  final retrimLine = lines.keyLine(_retrimKey) ?? 1;
  final reported = <String>{};
  for (final id in retrim.cast<String>()) {
    if (!reported.add(id)) continue;
    if (!definesSectionId(type, id)) continue;
    final index = context.heldIndexOf(doc, id);
    if (index != null && !isBlankAt(context, doc, index)) {
      yield context.finding(
        doc,
        FindingKind.retrimDue,
        line: lines.sectionLines[index],
        message: '$id $_waitsMessage',
        keys: {_sectionKey: id},
      );
    } else {
      yield context.finding(
        doc,
        FindingKind.retrimDue,
        line: retrimLine,
        message: '$id $_absentMessage',
        keys: {_sectionKey: id},
      );
    }
  }
}
