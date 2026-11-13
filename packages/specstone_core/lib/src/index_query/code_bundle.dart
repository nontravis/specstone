import 'dart:io';

import 'package:specstone_core/src/index_query/bundle.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/templates/code_target.dart';

const _coversField = 'covers';
const _implementsField = 'implements';

/// A file or folder under a code root a `context --code` call names.
final class CodePath {
  const new({required this.path, required this.isFolder, required this.target});

  /// The path relative to [target]'s code root, `/`-separated; `.` for the
  /// root.
  final String path;

  /// Whether the path is a folder.
  final bool isFolder;

  /// The code target whose code root, the longest one that holds the path,
  /// the path lies in.
  final CodeTarget target;
}

/// Resolves [given] from [workingDirectory] to a [CodePath] inside the code
/// root of the target whose code root is the longest that holds it
/// (`index_query/get_task_bundle/bundle_docs_for_code_path`).
///
/// [codeRootOf] answers each target's canonical code root, as
/// `DocsProject.codeRootOf` does. Throws `code_path_not_found` when nothing
/// exists there and `code_path_outside_project` when the canonical path lies
/// inside no target's code root.
CodePath resolveCodePath(
  String given, {
  required Directory workingDirectory,
  required List<CodeTarget> targets,
  required Directory Function(CodeTarget target) codeRootOf,
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
  CodeTarget? holder;
  var root = '';
  for (final target in targets) {
    final candidate = codeRootOf(target).path;
    final prefix = candidate.endsWith(separator)
        ? candidate
        : '$candidate$separator';
    if (canonical != candidate && !canonical.startsWith(prefix)) continue;
    if (candidate.length > root.length) {
      holder = target;
      root = candidate;
    }
  }
  if (holder == null) {
    throw IndexFault(
      IndexFaultCode.codePathOutsideProject,
      'the code path $given lies outside the code root',
    );
  }
  final prefix = root.endsWith(separator) ? root : '$root$separator';
  return CodePath(
    path: canonical == root
        ? '.'
        : canonical.substring(prefix.length).split(separator).join('/'),
    isFolder: type == FileSystemEntityType.directory,
    target: holder,
  );
}

/// Returns the bundle [code] holds for [mode] (`index_query/get_task_bundle/bundle_docs_for_code_path`).
///
/// The spec match is the doc of [code]'s target whose `covers:` entry is the
/// longest prefix of [code]; the traced docs are the stories and FRs whose
/// record entries in that target name [code] or a path under it. Docs of
/// another target never join. `--no-project` drops the docs that join through
/// `bundle:` lists; no match still joins them and warns.
Bundle pickCodeBundle(
  DocIndex index,
  CodePath code,
  BundleMode mode, {
  required bool noProject,
}) {
  final bundle = Bundle(mode, codeTarget: code.target.name);
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
        if (!index.isChainDoc(sibling) && bundle.keepsTarget(sibling)) {
          bundle.docPaths.add(sibling.docPath);
        }
      }
    }
  }
}

/// Returns [code]'s target's docs and the shared docs of [index].
Iterable<IndexedDoc> _docsOf(DocIndex index, CodePath code) => index.docs.where(
  (doc) => doc.target == null || doc.target == code.target.name,
);

List<IndexedDoc> _specMatch(DocIndex index, CodePath code) {
  var longest = 0;
  final matches = <IndexedDoc>[];
  for (final doc in _docsOf(index, code)) {
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
  for (final doc in _docsOf(index, code))
    if (doc.docTypeId != null && _tracesEntry(index, doc, code)) doc,
];

/// Whether [doc] is traced to [code] in its target: its record entry's code
/// paths, or, with no record doc type, its own `implements:` values, name
/// [code] or a path under it.
bool _tracesEntry(DocIndex index, IndexedDoc doc, CodePath code) {
  final entry = index.recordEntryOf(doc, codeTarget: code.target.name);
  if (entry != null) {
    return entry.codePaths.any((path) => _traces(path, code));
  }
  return doc.valuesOf(_implementsField).any((path) => _traces(path, code));
}

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
