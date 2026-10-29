import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/line_facts.dart';
import 'package:specstone_core/src/templates/doc_type_layer.dart';

/// Returns the `doc_ref_unresolved`, `link_unresolved`, and `markdown_unparsed`
/// findings of [doc].
///
/// A typed doc is checked for both references and links, an untyped doc of a
/// checked folder for links only. A doc the markdown parser failed on gets a
/// `markdown_unparsed` finding stating the F-01 warning, since its links go
/// unchecked.
Iterable<Finding> checkDocLinks(CheckContext context, IndexedDoc doc) sync* {
  final unparsed = markdownUnparsedWarning(doc.docPath);
  if (doc.warnings.contains(unparsed)) {
    context.state(unparsed);
    yield context.finding(
      doc,
      FindingKind.markdownUnparsed,
      line: 1,
      message:
          'the markdown parser failed on this doc; its links are not checked',
    );
  }
  if (doc.isTyped) yield* _unresolvedDocRefs(context, doc);
  yield* _unresolvedLinks(context, doc);
}

/// Yields a finding per `doc_ref` value that no doc of the field's doc types
/// carries as its Name; any doc counts when the field names no doc type.
Iterable<Finding> _unresolvedDocRefs(
  CheckContext context,
  IndexedDoc doc,
) sync* {
  final fields = context.typeOf(doc)?.fields ?? const [];
  for (final field in fields) {
    if (field.type != FieldType.docRef) continue;
    final docTypes = field.docTypes;
    for (final (:value, :line, text: _)
        in context.linesOf(doc).entriesOf(field.id)) {
      if (value is! String) continue;
      final named = context.index.docs.any(
        (other) =>
            other.name == value &&
            (docTypes == null || docTypes.contains(other.docTypeId)),
      );
      if (named) continue;
      yield context.finding(
        doc,
        FindingKind.docRefUnresolved,
        line: line,
        message: '${field.id} value $value names no doc',
        keys: {'field': field.id, 'value': value},
      );
    }
  }
}

/// Yields a finding per link of [doc] whose target is indexed nowhere.
///
/// The index stores each link's line and destination as written, so no doc
/// text is read here.
Iterable<Finding> _unresolvedLinks(CheckContext context, IndexedDoc doc) sync* {
  for (final place in context.linesOf(doc).links) {
    if (context.index.at(place.target) != null) continue;
    yield context.finding(
      doc,
      FindingKind.linkUnresolved,
      line: place.line,
      message: 'link target ${place.shown} is no doc',
      keys: {'target': place.shown},
    );
  }
}
