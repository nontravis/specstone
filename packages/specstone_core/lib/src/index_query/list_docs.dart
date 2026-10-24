import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';
import 'package:specstone_core/src/templates/template_fault.dart';

/// The filters `specstone list` applies; a doc must pass every one given.
final class ListFilters {
  const new({
    this.status,
    this.draft = false,
    this.under,
    this.cites,
    this.slug,
    this.noImplements = false,
  });

  /// Keeps docs whose status, computed for a feature, equals this.
  final String? status;

  /// Keeps docs whose `draft` is `true`.
  final bool draft;

  /// Keeps the subtrees of the docs this name addresses.
  final String? under;

  /// Keeps docs whose frontmatter holds this value, equal as text.
  final String? cites;

  /// Keeps docs whose `slug` aliases hold this value.
  final String? slug;

  /// Keeps docs whose `implements` field holds no entry.
  final bool noImplements;
}

/// Returns the docs of [docTypeId] that pass [filters], in tree order.
///
/// Throws a [TemplateFault] for a doc type id the set lacks, and an
/// `IndexFault` when `under` addresses no doc. Untyped docs never match.
ReadAnswer answerList(DocIndex index, String docTypeId, ListFilters filters) {
  if (index.set.lookup(docTypeId) == null) {
    throw TemplateFault(
      FaultCode.docTypeUnknown,
      'Could not find a doc type named "$docTypeId".',
    );
  }
  final under = filters.under;
  final scope = under == null
      ? null
      : {for (final doc in index.under(under)) doc.docPath};
  final docs = [
    for (final doc in index.docs)
      if (doc.docTypeId == docTypeId && _passes(index, doc, filters, scope))
        doc,
  ];
  return ReadAnswer(
    text: [for (final doc in docs) '${docLine(index, doc)}\n'].join(),
    json: {
      'docs': [for (final doc in docs) docJson(index, doc)],
    },
  );
}

bool _passes(
  DocIndex index,
  IndexedDoc doc,
  ListFilters filters,
  Set<String>? scope,
) {
  final status = filters.status;
  final cites = filters.cites;
  final slug = filters.slug;
  return (status == null || index.statusOf(doc) == status) &&
      (!filters.draft || doc.isDraft) &&
      (scope == null || scope.contains(doc.docPath)) &&
      (cites == null || _cites(doc, cites)) &&
      (slug == null || doc.valuesOf('slug').contains(slug)) &&
      (!filters.noImplements || doc.valuesOf('implements').isEmpty);
}

bool _cites(IndexedDoc doc, String value) =>
    doc.frontmatter.keys.any((key) => doc.valuesOf(key).contains(value));
