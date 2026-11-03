import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:specstone_core/src/templates/nested_paths.dart';

final _slugPlaceholder = RegExp(r'\{slug\}');

/// Resolves the parent doc of each doc in [docs] from the `parent` of its doc
/// type in [set], or from the nesting type for a nested doc of that type.
///
/// Returns each resolved parent by child docPath. A doc with two or more
/// candidate parents has no parent and gets a warning by its docPath instead.
/// A parent type whose path has no `{slug}` never takes a child, because its
/// name is its doc type id (INV-7).
({Map<String, String> parents, Map<String, String> warnings}) resolveParents(
  Iterable<IndexedDoc> docs,
  MergedSet set,
) {
  final docPathsByName = <(String, String), List<String>>{};
  for (final doc in docs) {
    if (doc.docTypeId case final typeId?) {
      (docPathsByName[(typeId, doc.name)] ??= []).add(doc.docPath);
    }
  }
  final parents = <String, String>{};
  final warnings = <String, String>{};
  for (final doc in docs) {
    final type = _typeOf(doc, set);
    final parentType = type == null ? null : _parentTypeOf(doc, type, set);
    if (type == null || parentType == null) continue;
    final parentSlugCount = _slugCountOf(parentType);
    final parentLength =
        doc.name.split('/').length - _ownSlugCount(type, parentType);
    if (parentSlugCount == 0 || parentLength < parentSlugCount) continue;
    final parentName = doc.name.split('/').take(parentLength).join('/');
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

/// Returns the doc type of [doc]'s parent doc, or null when it takes none.
///
/// The doc type's `parent` type; for a doc of the nesting type whose name holds
/// more segments than its base `path` holds `{slug}`s, the nesting type itself.
MergedDocType? parentTypeOf(IndexedDoc doc, MergedSet set) {
  final type = _typeOf(doc, set);
  return type == null ? null : _parentTypeOf(doc, type, set);
}

MergedDocType? _typeOf(IndexedDoc doc, MergedSet set) =>
    switch (doc.docTypeId) {
      final id? => set.lookup(id),
      null => null,
    };

MergedDocType? _parentTypeOf(
  IndexedDoc doc,
  MergedDocType type,
  MergedSet set,
) {
  if (type.parent case final parentId?) return set.lookup(parentId);
  final isNested =
      type.id == set.nestingType?.id &&
      _nestingSlugCount(type) > 0 &&
      doc.name.split('/').length > _slugCountOf(type);
  return isNested ? type : null;
}

/// Counts the `{slug}` segments a doc of [type] adds to its parent's name.
///
/// A nested doc of the nesting type adds those of its nesting segment; any
/// other doc, the `{slug}`s its base `path` holds beyond [parentType]'s.
int _ownSlugCount(MergedDocType type, MergedDocType parentType) =>
    parentType.id == type.id
    ? _nestingSlugCount(type)
    : _slugCountOf(type) - _slugCountOf(parentType);

int _nestingSlugCount(MergedDocType nesting) {
  final path = nesting.path;
  final segment = path == null ? null : nestingSegmentOf(path, nesting);
  return _slugPlaceholder.allMatches(segment?.text ?? '').length;
}

int _slugCountOf(MergedDocType type) =>
    _slugPlaceholder.allMatches(type.path ?? '').length;
