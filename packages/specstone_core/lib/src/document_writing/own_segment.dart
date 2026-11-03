import 'dart:io';

import 'package:specstone_core/src/doc_model/doc_path_shape.dart';
import 'package:specstone_core/src/document_writing/rewrite_refs.dart'
    show PathMove;
import 'package:specstone_core/src/document_writing/write_session.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/merged_set.dart';

final _slugShape = RegExp(r'^[a-z0-9_]+$');

/// Returns [n] zero-padded to two digits; a number past 99 keeps its digits.
String padNumber(int n) => n.toString().padLeft(2, '0');

/// Throws [IndexFault] `argument_invalid` unless [slug] is lowercase letters,
/// digits, and `_`.
void checkSlug(String slug) {
  if (_slugShape.hasMatch(slug)) return;
  throw IndexFault(
    IndexFaultCode.argumentInvalid,
    '$slug is no slug: use lowercase letters, digits, and _',
  );
}

/// Whether [own], an entry that fits [shape]'s own segment, holds the doc.
///
/// A folder with no doc file under it is no sibling: INV-8 counts docs. A
/// file, or a doc file name with placeholders, is taken as is.
bool _holdsDoc(DocPathShape shape, FileSystemEntity own) {
  if (shape.ownIsFile) return true;
  final rest = shape.segments.sublist(shape.ownIndex + 1);
  if (shape.belowOwnHasPlaceholder) return true;
  return File([own.path, ...rest].join(Platform.pathSeparator)).existsSync();
}

/// One folder or file of a doc type's own segment on disk.
final class SiblingEntry {
  const new({required this.name, required this.number, required this.slug});

  /// The folder or file name.
  final String name;

  /// The `{nn}` value; null when the segment holds none.
  final int? number;

  /// The `{slug}` value; null when the segment holds none.
  final String? slug;
}

/// Returns the siblings of [shape]'s own segment under [parentValues], sorted
/// by number, then name.
///
/// They are the folders that hold the doc file, or for a file segment the
/// files, of the container whose name matches the segment. Empty when the
/// container is absent.
/// Throws [RenderFault] `output_not_writable` when the container is unreadable.
List<SiblingEntry> siblingsOnDisk(
  Directory docsRoot,
  DocPathShape shape,
  List<String> parentValues,
) {
  final folder = shape
      .containerOf(parentValues)
      .split('/')
      .where((segment) => segment.isNotEmpty)
      .join(Platform.pathSeparator);
  final container = Directory(
    '${docsRoot.path}${Platform.pathSeparator}$folder',
  );
  if (!container.existsSync()) return const [];
  final entries = <SiblingEntry>[];
  final List<FileSystemEntity> children;
  try {
    children = container.listSync(followLinks: false);
  } on FileSystemException catch (error) {
    throw cannotRead(folder.replaceAll(Platform.pathSeparator, '/'), error);
  }
  for (final entity in children) {
    final isOwn = shape.ownIsFile ? entity is File : entity is Directory;
    if (!isOwn) continue;
    final name = entity.path.split(Platform.pathSeparator).last;
    final match = shape.matchOwn(name);
    if (match == null || !_holdsDoc(shape, entity)) continue;
    entries.add(
      SiblingEntry(name: name, number: match.number, slug: match.slug),
    );
  }
  return entries..sort((a, b) {
    final byNumber = (a.number ?? 0).compareTo(b.number ?? 0);
    return byNumber != 0 ? byNumber : a.name.compareTo(b.name);
  });
}

/// Returns the spec folder moves that follow [docType]'s doc from
/// [oldValues] to [newValues], each folder paired with the one the same child
/// doc type holds after the move, sorted by old folder; a folder that does
/// not change is left out.
List<PathMove> specFolderMovesOf(
  MergedSet set,
  MergedDocType docType,
  List<String> oldValues,
  List<String> newValues,
) {
  final shape = DocPathShape.of(docType, set);
  if (shape == null) return const [];
  final newFolders = {
    for (final (child, folder) in specChildrenOf(
      set,
      docType,
      shape,
      newValues,
    ))
      child.id: folder,
  };
  final moves = <String, PathMove>{};
  for (final (child, from) in specChildrenOf(set, docType, shape, oldValues)) {
    final to = newFolders[child.id];
    if (to == null || to == from) continue;
    moves[from] = (from: from, to: to);
  }
  return [for (final key in moves.keys.toList()..sort()) moves[key]!];
}
