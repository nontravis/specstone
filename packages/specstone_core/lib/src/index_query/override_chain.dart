import 'package:specstone_core/src/doc_model/doc_items.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/item_links.dart';
import 'package:specstone_core/src/index_query/link_places.dart' show LinkText;
import 'package:specstone_core/src/templates/merged_doc_type.dart';

/// Id of the doc type whose `overrides` field is one NFR id, no override line.
const nfTypeId = 'nf';

const _overridesField = 'overrides';

/// The text that opens an `Overrides:` list item.
const overridesMarker = 'Overrides:';

/// Whether a doc of [type] can hold override lines: it declares the
/// `overrides` field and is not an `nf` or a type built on it, whose field is
/// one NFR id.
bool carriesOverrides(MergedDocType? type) =>
    type != null &&
    !type.buildsOn(nfTypeId) &&
    type.fields.any((field) => field.id == _overridesField);

/// Returns the DocPaths of the docs above [doc], the only docs an `Overrides:`
/// line of [doc] may link.
///
/// They are the project spec docs of [doc]'s code target and, for a feature's
/// spec doc, that target's spec docs under each ancestor feature of its
/// feature. An ancestor's doc counts only when its type carries `overrides`.
/// `check` and `move` both read this chain.
Set<String> overrideChainOf(DocIndex index, IndexedDoc doc) {
  bool inTarget(IndexedDoc other) => other.target == doc.target;
  final paths = {
    for (final other in index.docs)
      if (other.isTyped && inTarget(other))
        if (index.set.isProjectSpecType(index.typeOf(other)!)) other.docPath,
  };
  final feature = index.parentOf(doc);
  var ancestor = feature == null ? null : index.parentOf(feature);
  for (; ancestor != null; ancestor = index.parentOf(ancestor)) {
    for (final spec in index.childrenOf(ancestor)) {
      if (inTarget(spec) && carriesOverrides(index.typeOf(spec))) {
        paths.add(spec.docPath);
      }
    }
  }
  return paths;
}

/// Whether [doc] can hold override lines: its type carries `overrides` and it
/// is no project spec doc, the top of every chain.
bool holdsOverrideLines(DocIndex index, IndexedDoc doc) {
  final type = index.typeOf(doc);
  return type != null &&
      carriesOverrides(type) &&
      !index.set.isProjectSpecType(type);
}

/// Whether [item] opens with [overridesMarker] as a list item.
bool isOverrideLine(SectionItem item) =>
    item.kind == SectionItemKind.listItem &&
    item.head.startsWith(overridesMarker);

/// Returns the offset of the first character after [overridesMarker] and its
/// spaces in [raw], the file line of an override line.
int overrideTextStart(String raw) {
  var at = raw.indexOf(overridesMarker) + overridesMarker.length;
  while (at < raw.length && raw[at] == ' ') {
    at++;
  }
  return at;
}

/// Returns the link of [content] that opens at [column] of [line], or null.
LinkText? overrideLinkAt(DocContent content, int line, int column) => content
    .lineFacts
    .linkTexts
    .where((link) => link.line == line && link.column == column)
    .firstOrNull;

/// What an override line's link names in the doc it reaches.
final class OverrideLinkRead {
  const new({
    required this.target,
    required this.cite,
    required this.anchorTarget,
    required this.sections,
  });

  /// The doc the link reaches.
  final IndexedDoc target;

  /// How the link reads against [target].
  final LinkCite cite;

  /// The part of [target] the link's anchor names; null for no anchor.
  final AnchorTarget? anchorTarget;

  /// The held sections of [target], as [classifyLink] reads them.
  final List<CitedSection> sections;
}

/// Reads [link], the first link of an override line, against the doc it
/// reaches; null when that doc is not indexed.
OverrideLinkRead? readOverrideLink(DocIndex index, LinkText link) {
  final target = index.at(link.target);
  if (target == null) return null;
  final content = index.contentOf(target);
  final anchor = link.anchor;
  final anchorTarget = anchor == null || anchor.isEmpty
      ? null
      : anchorTargetOf(content.lineFacts, anchor);
  final sections = citedSectionsOf(content, index.typeOf(target));
  return OverrideLinkRead(
    target: target,
    cite: classifyLink(
      link,
      target: anchorTarget,
      sectionAt: (at) => at < sections.length ? sections[at] : null,
    ),
    anchorTarget: anchorTarget,
    sections: sections,
  );
}
