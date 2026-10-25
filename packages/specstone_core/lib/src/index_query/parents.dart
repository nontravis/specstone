import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/merged_set.dart';

final _slugPlaceholder = RegExp(r'\{slug\}');

/// Resolves the parent doc of each doc in [docs] from the `parent` of its doc
/// type in [set].
///
/// Returns each resolved parent by child docPath. A doc with two or more
/// candidate parents has no parent and gets a warning by its docPath instead.
/// A parent type whose path has no `{slug}` never takes a child, because its
/// name is its doc type id (INV-7).
({Map<String, String> parents, Map<String, String> warnings}) resolveParents(
  Iterable<IndexedDoc> docs,
  MergedSet set,
) {
  final typeById = {for (final type in set.docTypes) type.id: type};
  final docPathsByName = <(String, String), List<String>>{};
  for (final doc in docs) {
    if (doc.docTypeId case final typeId?) {
      (docPathsByName[(typeId, doc.name)] ??= []).add(doc.docPath);
    }
  }
  final parents = <String, String>{};
  final warnings = <String, String>{};
  for (final doc in docs) {
    final parentType = _parentTypeOf(doc, typeById);
    if (parentType == null) continue;
    final nameSegments = doc.name.split('/');
    final slugCount = _slugCountOf(parentType);
    if (slugCount == 0 || nameSegments.length < slugCount) continue;
    final parentName = nameSegments.take(slugCount).join('/');
    final candidates = docPathsByName[(parentType.id, parentName)] ?? const [];
    if (candidates.length == 1) {
      parents[doc.docPath] = candidates.single;
    } else if (candidates.length > 1) {
      // Sorted, because `ord` is stale after a full rebuild but not after an
      // incremental refresh, and both must print the same warning.
      final listed = [...candidates]..sort();
      warnings[doc.docPath] =
          '${doc.docPath} has ${countWord(candidates.length)} candidate '
          'parent docs: ${listed.join(', ')}; it has no parent doc';
    }
  }
  return (parents: parents, warnings: warnings);
}

MergedDocType? _parentTypeOf(
  IndexedDoc doc,
  Map<String, MergedDocType> typeById,
) {
  final typeId = doc.docTypeId;
  final parentId = typeId == null ? null : typeById[typeId]?.parent;
  return parentId == null ? null : typeById[parentId];
}

int _slugCountOf(MergedDocType type) =>
    _slugPlaceholder.allMatches(type.path ?? '').length;
