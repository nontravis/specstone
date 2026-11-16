import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/override_lines.dart';
import 'package:specstone_core/src/doc_model/doc_path_shape.dart';
import 'package:specstone_core/src/index_query/cited_by.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/item_links.dart'
    show citedSectionsOf;
import 'package:specstone_core/src/index_query/models/cited_by.dart';

const _splitSuffix = '; group stories into sub-features first';

/// The keys and message suffix a doc-level size finding takes to name what can
/// move out of a spec doc.
final class MoveHint {
  const new({required this.keys, required this.suffix});

  /// The finding keys: `candidates`, or `split`.
  final Map<String, Object> keys;

  /// The text that follows the finding's message, `; ` first.
  final String suffix;
}

/// Returns the hint for the size finding of spec doc [doc]; null when [doc]
/// takes neither key.
///
/// A feature with sub-features gives `candidates`: the items of [doc] that
/// one sub-feature's tree alone cites and no `Overrides:` line links. A
/// feature with stories and no sub-feature gives `split: sub_features`.
MoveHint? moveHintsOf(CheckContext context, IndexedDoc doc) {
  final index = context.index;
  final feature = index.parentOf(doc);
  if (feature == null ||
      feature.docTypeId != featureType ||
      !_isSpecDoc(index, doc)) {
    return null;
  }
  final children = index.childrenOf(feature);
  final subFeatures = [
    for (final child in children)
      if (child.docTypeId == featureType) child,
  ];
  if (subFeatures.isNotEmpty) {
    return _candidatesHint(context, doc, subFeatures);
  }
  if (children.any((child) => child.docTypeId == storyType)) {
    return const MoveHint(
      keys: {'split': 'sub_features'},
      suffix: _splitSuffix,
    );
  }
  return null;
}

/// Whether [doc] is a feature's spec doc: its path holds no placeholder of
/// its own, so its parent names the folder it sits in.
bool _isSpecDoc(DocIndex index, IndexedDoc doc) {
  final type = index.typeOf(doc);
  final shape = type == null
      ? null
      : DocPathShape.ofDoc(type, index.set, doc.docPath, target: doc.target);
  return shape != null && isSpecDocShape(shape);
}

MoveHint? _candidatesHint(
  CheckContext context,
  IndexedDoc doc,
  List<IndexedDoc> subFeatures,
) {
  final index = context.index;
  final owner = {
    for (final sub in subFeatures)
      for (final member in index.subtreeOf(sub))
        _keyOf(member.docTypeId, member.name): sub.name,
  };
  final content = context.contentOf(doc);
  final sections = citedSectionsOf(content, index.typeOf(doc));
  final cited = citedByIndex(index);
  final found = <({String id, String under})>[];
  for (final (at, section) in sections.indexed) {
    for (final item in citedItemsIn(cited, doc, content, section, at)) {
      final under = _soleOwner(item.by, owner);
      if (under != null && item.item != null) {
        found.add((id: item.item!, under: under));
      }
    }
  }
  if (found.isEmpty) return null;
  final overridden = _overriddenIds(context, doc);
  final candidates = [
    for (final candidate in found)
      if (!overridden.contains(candidate.id)) candidate,
  ];
  if (candidates.isEmpty) return null;
  final idsUnder = <String, List<String>>{};
  for (final (:id, :under) in candidates) {
    (idsUnder[under] ??= []).add(id);
  }
  return MoveHint(
    keys: {
      'candidates': [
        for (final (:id, :under) in candidates) {'id': id, 'under': under},
      ],
    },
    suffix: [
      for (final MapEntry(key: under, value: ids) in idsUnder.entries)
        '; ${ids.join(', ')} are cited only under $under',
    ].join(),
  );
}

String _keyOf(String? docTypeId, String name) => '$docTypeId:$name';

/// Returns the name of the one sub-feature whose tree holds every doc of
/// [by]; null when a citer sits outside them or in two.
String? _soleOwner(List<CitedBy> by, Map<String, String> owner) {
  final names = {for (final cite in by) owner[_keyOf(cite.docType, cite.name)]};
  return names.length == 1 ? names.single : null;
}

/// Returns the IDs of the items of [doc] that any `Overrides:` line links.
Set<String> _overriddenIds(CheckContext context, IndexedDoc doc) => {
  for (final other in context.index.docs)
    for (final line in overrideLinesOf(context, other))
      if (line.upstream == doc.docPath) ?line.itemId,
};
