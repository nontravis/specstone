import 'package:specstone_core/src/doc_model/doc_link.dart'
    show DocTarget, resolveDocLink;
import 'package:specstone_core/src/doc_model/reference_grammar.dart'
    show RelativeLink, readItemIdAt, readLinkTarget;
import 'package:specstone_core/src/index_query/cite_resolution.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/models/bare_item_id.dart';
import 'package:specstone_core/src/index_query/models/cite_candidate.dart';

/// The doc that owns a bare item ID, and whether it is the ID's own doc.
final class OwnerDoc {
  const new({required this.doc, required this.isOwnDoc});

  final IndexedDoc doc;

  /// Whether the ID's own doc owns it, not the doc its citation names.
  final bool isOwnDoc;
}

/// Returns the owner doc of [id], or null when it has none.
///
/// [holderDocPath] is the doc whose text holds [id], which a link destination
/// resolves against. [ownDoc] is the doc the own-doc test reads.
OwnerDoc? ownerDocOf(
  DocIndex index,
  BareItemId id, {
  required String holderDocPath,
  required IndexedDoc ownDoc,
}) {
  OwnerDoc? ownOwner() => _holdsPrefix(index, ownDoc, id.id)
      ? OwnerDoc(doc: ownDoc, isOwnDoc: true)
      : null;
  final citation = id.citation;
  if (citation == null || _isBareAnchor(citation)) return ownOwner();
  final cited = _citedDocOf(index, citation, holderDocPath);
  if (cited == null || cited.docTypeId == null) return null;
  return _holdsPrefix(index, cited, id.id)
      ? OwnerDoc(doc: cited, isOwnDoc: false)
      : ownOwner();
}

bool _isBareAnchor(BareIdCitation citation) =>
    citation is LinkCitation &&
    switch (readLinkTarget(citation.destination)) {
      RelativeLink(:final segments) => segments.isEmpty,
      _ => false,
    };

/// Returns the doc [citation] names from [holderDocPath], or null when it
/// names none or several.
IndexedDoc? _citedDocOf(
  DocIndex index,
  BareIdCitation citation,
  String holderDocPath,
) {
  final docPath = switch (citation) {
    LinkCitation(:final destination) => switch (resolveDocLink(
      destination,
      holderDocPath,
    )) {
      DocTarget(:final docPath) => docPath,
      _ => null,
    },
    CiteCitation(:final written) => switch (resolveCite(
      _citeTreeOf(index),
      holderDocPath,
      CiteCandidate(
        line: _noLine,
        written: written,
        sectionKey: null,
        itemIds: const [],
      ),
    )) {
      CiteLink(:final docPath) => docPath,
      _ => null,
    },
  };
  return docPath == null ? null : index.at(docPath);
}

const _noLine = 0;

final _citeTrees = Expando<IndexCiteTree>();

IndexCiteTree _citeTreeOf(DocIndex index) =>
    _citeTrees[index] ??= IndexCiteTree(index);

bool _holdsPrefix(DocIndex index, IndexedDoc doc, String itemId) {
  final prefixes = _prefixesOf(index)[doc.docTypeId];
  return prefixes != null &&
      prefixes.any((prefix) => readItemIdAt(itemId, 0, prefix) != null);
}

final _prefixesByType = Expando<Map<String, Set<String>>>();

/// The `prefix_id`s of each doc type of [index], built once per index.
Map<String, Set<String>> _prefixesOf(DocIndex index) =>
    _prefixesByType[index] ??= {
      for (final type in index.set.docTypes)
        type.id: {for (final section in type.sections) ?section.prefixId},
    };
