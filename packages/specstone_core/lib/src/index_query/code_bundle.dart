import 'dart:io';

import 'package:specstone_core/src/index_query/bundle.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';

const _coversField = 'covers';
const _implementsField = 'implements';

/// A file or folder of the project a `context --code` call names.
final class CodePath {
  const new({required this.path, required this.isFolder});

  /// The path relative to the project root, `/`-separated; `.` for the root.
  final String path;

  /// Whether the path is a folder.
  final bool isFolder;
}

/// Resolves [given] from [workingDirectory] to a [CodePath] inside
/// [projectRoot], which must be canonical.
///
/// Throws `code_path_not_found` when nothing exists there and
/// `code_path_outside_project` when its canonical path is neither the project
/// root nor below it.
CodePath resolveCodePath(
  String given, {
  required Directory workingDirectory,
  required Directory projectRoot,
}) {
  final separator = Platform.pathSeparator;
  final absolute = File(given).isAbsolute
      ? given
      : '${workingDirectory.path}$separator$given';
  final type = FileSystemEntity.typeSync(absolute);
  if (type == FileSystemEntityType.notFound) {
    throw IndexFault(
      IndexFaultCode.codePathNotFound,
      'the code path $given does not exist',
    );
  }
  final canonical = File(absolute).resolveSymbolicLinksSync();
  final root = projectRoot.path;
  final prefix = root.endsWith(separator) ? root : '$root$separator';
  final isRoot = canonical == root;
  if (!isRoot && !canonical.startsWith(prefix)) {
    throw IndexFault(
      IndexFaultCode.codePathOutsideProject,
      'the code path $given lies outside the project root',
    );
  }
  return CodePath(
    path: isRoot
        ? '.'
        : canonical.substring(prefix.length).split(separator).join('/'),
    isFolder: type == FileSystemEntityType.directory,
  );
}

/// Returns the bundle [code] holds for [mode] (us05 FR-04).
///
/// The spec match is the doc whose `covers:` entry is the longest prefix of
/// [code]; the traced docs are those whose `implements:` entries name [code]
/// or lie under it. `--no-project` drops the docs that join through `bundle:`
/// lists; no match still joins them and warns.
Bundle pickCodeBundle(
  DocIndex index,
  CodePath code,
  BundleMode mode, {
  required bool noProject,
}) {
  final bundle = Bundle(mode);
  final traced = _tracedDocs(index, code);
  final specMatch = _specMatch(index, code);
  if (traced.isEmpty && specMatch.isEmpty) {
    bundle.warnings.add('no doc covers or implements ${code.path}');
  } else if (mode == BundleMode.implement) {
    _addImplement(index, bundle, traced, specMatch);
  } else {
    for (final doc in [...traced, ...specMatch]) {
      bundle.addTarget(index, index.chainOf(doc).last);
    }
  }
  bundle.join(index, noProject: noProject);
  return bundle;
}

void _addImplement(
  DocIndex index,
  Bundle bundle,
  List<IndexedDoc> traced,
  List<IndexedDoc> specMatch,
) {
  for (final doc in traced) {
    bundle.addTarget(index, doc);
  }
  for (final match in specMatch) {
    final parent = index.parentOf(match);
    if (parent == null) {
      bundle.docPaths.add(match.docPath);
    } else if (traced.isEmpty) {
      bundle.addTarget(index, parent);
    } else {
      for (final sibling in index.childrenOf(parent)) {
        final typeId = sibling.docTypeId;
        if (typeId == null || !index.isChainType(typeId)) {
          bundle.docPaths.add(sibling.docPath);
        }
      }
    }
  }
}

List<IndexedDoc> _specMatch(DocIndex index, CodePath code) {
  var longest = 0;
  final matches = <IndexedDoc>[];
  for (final doc in index.docs) {
    if (doc.docTypeId == null) continue;
    for (final entry in doc.valuesOf(_coversField)) {
      final covered = _withoutTrailingSlash(entry);
      if (covered.isEmpty || !_isPrefixOf(covered, code.path)) continue;
      if (covered.length > longest) {
        longest = covered.length;
        matches
          ..clear()
          ..add(doc);
      } else if (covered.length == longest && !matches.contains(doc)) {
        matches.add(doc);
      }
    }
  }
  return matches;
}

List<IndexedDoc> _tracedDocs(DocIndex index, CodePath code) => [
  for (final doc in index.docs)
    if (doc.docTypeId != null &&
        doc.valuesOf(_implementsField).any((e) => _traces(e, code)))
      doc,
];

bool _traces(String entry, CodePath code) {
  final colon = entry.indexOf(':');
  final path = colon < 0 ? entry : entry.substring(0, colon);
  return path == code.path ||
      code.isFolder && (code.path == '.' || path.startsWith('${code.path}/'));
}

bool _isPrefixOf(String prefix, String path) =>
    path == prefix || path.startsWith('$prefix/');

String _withoutTrailingSlash(String value) =>
    value.endsWith('/') ? value.substring(0, value.length - 1) : value;
