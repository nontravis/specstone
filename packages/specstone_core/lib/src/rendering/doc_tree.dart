import 'dart:io';

import 'package:specstone_core/src/doc_model/doc_type_matcher.dart';
import 'package:specstone_core/src/rendering/docs_project.dart';
import 'package:specstone_core/src/templates/code_point_order.dart';

/// One doc file found under a [Target], with its path from the docs root.
final class DocFile {
  new(this.file, this.docPath);

  /// The file on disk.
  final File file;

  /// The path relative to the docs root, `/`-separated.
  final String docPath;
}

/// Returns the docs under [target] in tree order (R-INV-10).
///
/// A file target yields itself. A folder yields every file under it,
/// pre-order: inside one folder the files come before the subfolders, and in
/// each group the entries no `{nn}` pattern numbers come first, by name in
/// code point order, then the numbered entries by number, ties by name. A
/// file or folder whose name starts with `.` is never visited, and links are
/// not followed.
List<DocFile> collectDocFiles(Target target, DocTypeMatcher matcher) {
  final entity = target.entity;
  if (entity is File) return [DocFile(entity, target.docPath)];
  return _walk(entity as Directory, target.docPath, matcher);
}

List<DocFile> _walk(Directory folder, String docPath, DocTypeMatcher matcher) {
  final files = <_Entry>[];
  final folders = <_Entry>[];
  for (final entity in folder.listSync(followLinks: false)) {
    final name = _nameOf(entity);
    if (name.startsWith('.')) continue;
    final entryPath = docPath.isEmpty ? name : '$docPath/$name';
    final entry = _Entry(
      entity,
      name,
      entryPath,
      matcher.entryNumber(entryPath.split('/')),
    );
    switch (entity) {
      case File():
        files.add(entry);
      case Directory():
        folders.add(entry);
      default: // A link: not followed (Plan decision 15).
    }
  }
  return [
    for (final entry in _inTreeOrder(files))
      DocFile(entry.entity as File, entry.docPath),
    for (final entry in _inTreeOrder(folders))
      ..._walk(entry.entity as Directory, entry.docPath, matcher),
  ];
}

/// Returns [entries] unnumbered first by name, then numbered by number and
/// name.
List<_Entry> _inTreeOrder(List<_Entry> entries) {
  final unnumbered = [
    for (final entry in entries)
      if (entry.number == null) entry,
  ]..sort((a, b) => compareCodePoints(a.name, b.name));
  final numbered =
      [
        for (final entry in entries)
          if (entry.number != null) entry,
      ]..sort((a, b) {
        final byNumber = a.number!.compareTo(b.number!);
        return byNumber != 0 ? byNumber : compareCodePoints(a.name, b.name);
      });
  return [...unnumbered, ...numbered];
}

String _nameOf(FileSystemEntity entity) {
  final path = entity.path;
  return path.substring(path.lastIndexOf(Platform.pathSeparator) + 1);
}

final class _Entry {
  new(this.entity, this.name, this.docPath, this.number);

  final FileSystemEntity entity;
  final String name;
  final String docPath;
  final int? number;
}
