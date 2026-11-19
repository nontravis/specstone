import 'dart:io';

import 'package:specstone_core/src/canonical_path.dart'
    show absoluteFrom, pathInside;
import 'package:specstone_core/src/index_query/bundle.dart';
import 'package:specstone_core/src/index_query/code_root_files.dart'
    show normalCodeEntry;
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/refs.dart' show referencedDocsOf;
import 'package:specstone_core/src/templates/code_link_entry.dart';
import 'package:specstone_core/src/templates/code_target.dart';

const _implementsField = 'implements';

/// A file or folder a `context --code` call names.
final class CodePath {
  const new({
    required this.path,
    required this.projectPath,
    required this.isFolder,
    required this.target,
  });

  /// The path relative to [target]'s code root, `/`-separated; `.` for the
  /// root; null when no code root holds the path.
  final String? path;

  /// The path relative to the project root, `/`-separated; `.` for the root;
  /// null when the path lies outside the project root.
  final String? projectPath;

  /// The path as a message names it: [path], else [projectPath].
  String get label => path ?? projectPath!;

  /// Whether the path is a folder.
  final bool isFolder;

  /// The code target whose code root, the longest one that holds the path,
  /// the path lies in; the first target when no code root holds it.
  final CodeTarget target;
}

/// Resolves [given] from [workingDirectory] to a [CodePath] inside the code
/// root of the target whose code root is the longest that holds it.
///
/// [codeRootOf] answers each target's canonical code root, as
/// `DocsProject.codeRootOf` does; [projectRoot] is the canonical project root.
/// A path no code root holds takes the first target when
/// [reachedFromProjectRoot] holds for its path from [projectRoot]. Throws
/// `code_path_not_found` when nothing exists there and
/// `code_path_outside_project` when the canonical path lies inside no target's
/// code root and no `root: project` entry reaches it.
CodePath resolveCodePath(
  String given, {
  required Directory workingDirectory,
  required List<CodeTarget> targets,
  required Directory Function(CodeTarget target) codeRootOf,
  required Directory projectRoot,
  required bool Function(String projectPath) reachedFromProjectRoot,
}) {
  final absolute = absoluteFrom(workingDirectory, given);
  final type = FileSystemEntity.typeSync(absolute);
  if (type == FileSystemEntityType.notFound) {
    throw IndexFault(
      IndexFaultCode.codePathNotFound,
      'the code path $given does not exist',
    );
  }
  final canonical = File(absolute).resolveSymbolicLinksSync();
  ({CodeTarget target, String root, String path})? holder;
  for (final target in targets) {
    final root = codeRootOf(target).path;
    final inside = _pathFrom(root, canonical);
    if (inside == null || root.length <= (holder?.root.length ?? -1)) continue;
    holder = (target: target, root: root, path: inside);
  }
  final projectPath = _pathFrom(projectRoot.path, canonical);
  final isFolder = type == FileSystemEntityType.directory;
  if (holder != null) {
    return CodePath(
      path: holder.path,
      projectPath: projectPath,
      isFolder: isFolder,
      target: holder.target,
    );
  }
  if (projectPath == null || !reachedFromProjectRoot(projectPath)) {
    throw IndexFault(
      IndexFaultCode.codePathOutsideProject,
      'the code path $given lies outside the code root',
    );
  }
  return CodePath(
    path: null,
    projectPath: projectPath,
    isFolder: isFolder,
    target: targets.first,
  );
}

/// Returns [path] relative to [root], `.` for [root] itself; null when [path]
/// lies outside it.
String? _pathFrom(String root, String path) =>
    path == root ? '.' : pathInside(root, path);

/// Returns the bundle [code] holds for [mode].
///
/// The spec match is the doc of [code]'s target whose `covers:` entry is the
/// longest prefix of [code]; the traced docs are the stories and FRs whose
/// record entries in that target name [code] or a path under it. Both need a
/// code root that holds [code]. The project-root match joins beside them.
/// Docs of another target never join. `--no-project` drops the docs that join
/// through `bundle:` lists; no match still joins them and warns.
Bundle pickCodeBundle(
  DocIndex index,
  CodePath code,
  BundleMode mode, {
  required bool noProject,
}) {
  final bundle = Bundle(mode, codeTarget: code.target.name);
  final path = code.path;
  final projectPath = code.projectPath;
  final traced = path == null
      ? const <IndexedDoc>[]
      : _tracedDocs(index, code, path);
  final specMatch = path == null
      ? const <IndexedDoc>[]
      : _specMatch(index, code, path);
  final projectMatch = projectPath == null
      ? const <IndexedDoc>[]
      : projectRootMatch(index, projectPath);
  if (traced.isEmpty && specMatch.isEmpty && projectMatch.isEmpty) {
    bundle.warnings.add('no doc covers or implements ${code.label}');
  } else if (mode == BundleMode.implement) {
    _addImplement(index, bundle, traced, specMatch);
  } else {
    for (final doc in [...traced, ...specMatch]) {
      bundle.addTarget(index, index.chainOf(doc).last);
    }
  }
  _addProjectRootMatch(index, bundle, projectMatch);
  bundle.join(index, noProject: noProject);
  if (mode == BundleMode.design) {
    bundle.patternListerPaths.addAll([
      ...bundle.docPaths,
      ...bundle.joinedPaths,
    ]);
  }
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

/// Returns the docs whose `root: project` entry is the longest that reaches
/// [projectPath], a path from the project root, by whole segment.
///
/// Docs of any target and of none compete, and each one picked joins: such an
/// entry belongs to the project root, not to a code target.
List<IndexedDoc> projectRootMatch(DocIndex index, String projectPath) =>
    _longestCover(index, index.docs, projectPath, fromProject: true);

/// Adds the [docs] a project-root match picks, and the feature docs they name
/// through a `doc_ref` field to the `feature` doc type, in every mode.
///
/// The docs trace no story, so no story list follows.
void _addProjectRootMatch(
  DocIndex index,
  Bundle bundle,
  List<IndexedDoc> docs,
) {
  for (final doc in docs) {
    for (final picked in [doc, ...referencedDocsOf(index, doc, featureType)]) {
      bundle.docPaths.add(picked.docPath);
    }
  }
}

/// Returns [code]'s target's docs and the shared docs of [index].
Iterable<IndexedDoc> _docsOf(DocIndex index, CodePath code) =>
    index.docs.where((doc) => doc.inTarget(code.target.name));

/// Returns the docs whose `covers:` entry is the longest prefix of [path], a
/// path from [code]'s code root.
///
/// A field that reads from the project root joins no match, since its entries
/// name no path under a code root.
///
/// With two or more targets only [code]'s target's docs compete, since a
/// shared doc's code paths count for no target.
List<IndexedDoc> _specMatch(DocIndex index, CodePath code, String path) =>
    _longestCover(
      index,
      _docsOf(
        index,
        code,
      ).where((doc) => !index.hasTwins || doc.target != null),
      path,
      fromProject: false,
    );

/// Returns the typed [docs] whose entry in the `covers` fields [fromProject]
/// picks is the longest that reaches [path], by whole segment.
List<IndexedDoc> _longestCover(
  DocIndex index,
  Iterable<IndexedDoc> docs,
  String path, {
  required bool fromProject,
}) {
  var longest = 0;
  final matches = <IndexedDoc>[];
  for (final doc in docs) {
    if (doc.docTypeId == null) continue;
    for (final covered in _coveredPaths(index, doc, fromProject: fromProject)) {
      if (!entryReaches(covered, path)) continue;
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

/// Returns the paths [doc]'s `covers` fields name, in [normalCodeEntry]'s
/// form: the fields that read from the project root when [fromProject], else
/// those that read from a code root.
Iterable<String> _coveredPaths(
  DocIndex index,
  IndexedDoc doc, {
  required bool fromProject,
}) sync* {
  for (final field in coversFieldsOf(index.typeOf(doc))) {
    if (readsFromProjectRoot(field) != fromProject) continue;
    for (final entry in doc.valuesOf(field.id)) {
      yield normalCodeEntry(CodeLinkEntry(entry).pointer);
    }
  }
}

List<IndexedDoc> _tracedDocs(DocIndex index, CodePath code, String path) => [
  for (final doc in _docsOf(index, code))
    if (doc.docTypeId != null && _tracesEntry(index, doc, code, path)) doc,
];

/// Whether [doc] is traced to [code] in its target: its record entry's code
/// paths or test paths name [code] or a path under it; with no record doc
/// type, its own `implements:` values stand in, as a status is read then.
bool _tracesEntry(DocIndex index, IndexedDoc doc, CodePath code, String path) {
  if (index.set.recordDocType == null) {
    return doc
        .valuesOf(_implementsField)
        .any((entry) => _traces(entry, code, path));
  }
  final entry = index.recordEntryOf(doc, codeTarget: code.target.name);
  if (entry == null) return false;
  return entry.codePaths.any((codePath) => _traces(codePath, code, path)) ||
      entry.testPaths.any((testPath) => _traces(testPath, code, path));
}

bool _traces(String entry, CodePath code, String path) {
  final pointer = CodeLinkEntry(entry).pointer;
  final colon = pointer.indexOf(':');
  final entryPath = colon < 0 ? pointer : pointer.substring(0, colon);
  return entryPath == path ||
      code.isFolder && (path == '.' || entryPath.startsWith('$path/'));
}
