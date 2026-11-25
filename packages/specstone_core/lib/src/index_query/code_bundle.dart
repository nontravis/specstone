import 'dart:io';

import 'package:specstone_core/src/canonical_path.dart'
    show absoluteFrom, pathInside;
import 'package:specstone_core/src/consistency_check/code_link_rules.dart'
    show CodeLink;
import 'package:specstone_core/src/index_query/bundle.dart';
import 'package:specstone_core/src/index_query/bundle_join.dart';
import 'package:specstone_core/src/index_query/code_root_files.dart'
    show normalCodeEntry;
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
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
/// longest prefix of [code], read as its spec folder; the traced docs are the
/// stories and FRs whose record entries in that target name [code] or a path
/// under it. Both need a code root that holds [code]. The project-root match
/// joins beside them, and each doc a matched doc's `bundle_with` fields name
/// joins by `joinLinkedDocs`.
///
/// `design` picks each traced doc and each spec match doc as its own target;
/// `query` maps each match's top doc. In `implement` and `design` the matched
/// docs are must parts of a split bundle.
/// Docs of another target never join. `--no-project` drops the docs that join
/// through `bundle:` lists; no match still joins them and warns.
/// [importedPaths] are the DocPaths the host already holds; the bundle marks
/// them.
Bundle pickCodeBundle(
  DocIndex index,
  CodePath code,
  BundleMode mode, {
  required bool noProject,
  Set<String> importedPaths = const {},
}) {
  final bundle = Bundle(mode, codeTarget: code.target.name);
  final picks = <TargetPicks>[];
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
  } else {
    switch (mode) {
      case BundleMode.implement:
        _addImplement(index, bundle, traced, specMatch);
      case BundleMode.query:
        for (final doc in [...traced, ...specMatch]) {
          picks.add(
            bundle.pickTarget(index, index.chainOf(doc).last, forCode: true),
          );
        }
      case BundleMode.design:
        final targets = {
          for (final doc in traced) doc.docPath: doc,
          for (final doc in _specMatchDocs(index, bundle, specMatch))
            doc.docPath: doc,
        };
        for (final doc in targets.values) {
          picks.add(bundle.pickTarget(index, doc, forCode: true));
        }
      case BundleMode.sync || BundleMode.review:
        throw StateError('${mode.wire} bundles no docs');
    }
  }
  final projectPaths = [for (final doc in projectMatch) doc.docPath];
  bundle.docPaths.addAll(projectPaths);
  if (mode != BundleMode.query) bundle.targetSubtreePaths.addAll(projectPaths);
  bundle.join(index, noProject: noProject);
  joinLinkedDocs(index, bundle, picks);
  joinNamedBy(index, bundle, projectMatch);
  bundle.markImported(
    importedPaths,
    named: {
      for (final doc in [
        ...traced,
        ...specMatch,
        if (mode != BundleMode.query)
          ..._specMatchDocs(index, bundle, specMatch),
        ...projectMatch,
      ])
        doc.docPath,
    },
  );
  if (mode == BundleMode.design) {
    bundle.patternListerPaths.addAll([
      ...bundle.docPaths,
      ...bundle.joinedPaths,
      ...bundle.linkedDocs.keys,
    ]);
  }
  return bundle;
}

/// Returns the docs whose `implements` or `covers:` entry names [link]'s code:
/// the traced docs, the spec match, and the project-root match, as `context
/// --code` finds them, without that bundle's chain, subtree, or joins.
///
/// A `root: project` link has no target, so only the project-root match reads
/// it.
List<IndexedDoc> coveringDocsOf(DocIndex index, CodeLink link) {
  final entry = normalCodeEntry(link.path);
  final path = entry.isEmpty ? '.' : entry;
  final target = link.target;
  if (target == null) return projectRootMatch(index, path);
  final absolute = path == '.' ? link.root.path : '${link.root.path}/$path';
  final projectPath = _pathFrom(index.projectRoot.path, absolute);
  final code = CodePath(
    path: path,
    projectPath: projectPath,
    isFolder: FileSystemEntity.isDirectorySync(absolute),
    target: target,
  );
  return {
    for (final doc in _tracedDocs(index, code, path)) doc.docPath: doc,
    for (final doc in _specMatch(index, code, path)) doc.docPath: doc,
    if (projectPath != null)
      for (final doc in projectRootMatch(index, projectPath)) doc.docPath: doc,
  }.values.toList();
}

/// Adds the implement bundle of each traced doc, its printed story subtree and
/// the chain above it marked, and each spec folder, its spec match docs
/// marked.
///
/// With no traced doc, a spec match with a parent adds that parent's bundle,
/// its chain marked.
void _addImplement(
  DocIndex index,
  Bundle bundle,
  List<IndexedDoc> traced,
  List<IndexedDoc> specMatch,
) {
  for (final doc in traced) {
    bundle.addTarget(index, doc, marksTarget: true);
  }
  for (final match in specMatch) {
    final parent = index.parentOf(match);
    if (parent != null && traced.isEmpty) {
      bundle
        ..addTarget(index, parent)
        ..chainAbovePaths.addAll([
          for (final doc in index.chainOf(parent))
            if (bundle.keepsTarget(doc)) doc.docPath,
        ]);
    }
    for (final doc in _specFolderOf(index, bundle, match)) {
      bundle.docPaths.add(doc.docPath);
      if (_isSpecMatchDoc(index, doc)) {
        bundle.targetSubtreePaths.add(doc.docPath);
      }
    }
  }
}

/// Returns the spec folder [match] gives: its parent's children of no chain
/// type in [bundle]'s target, or [match] alone when it has no parent.
List<IndexedDoc> _specFolderOf(
  DocIndex index,
  Bundle bundle,
  IndexedDoc match,
) {
  final parent = index.parentOf(match);
  if (parent == null) return [match];
  return [
    for (final sibling in index.childrenOf(parent))
      if (!index.isChainDoc(sibling) && bundle.keepsTarget(sibling)) sibling,
  ];
}

/// Returns the spec match docs of each spec folder [specMatch] gives.
List<IndexedDoc> _specMatchDocs(
  DocIndex index,
  Bundle bundle,
  List<IndexedDoc> specMatch,
) => [
  for (final match in specMatch)
    for (final doc in _specFolderOf(index, bundle, match))
      if (_isSpecMatchDoc(index, doc)) doc,
];

/// Whether [doc] of a spec folder is a spec match doc: a Record never is.
bool _isSpecMatchDoc(DocIndex index, IndexedDoc doc) =>
    !(index.typeOf(doc)?.isRecordType ?? false);

/// Returns the docs whose `root: project` entry is the longest that reaches
/// [projectPath], a path from the project root, by whole segment.
///
/// Docs of any target and of none compete, and each one picked joins: such an
/// entry belongs to the project root, not to a code target.
List<IndexedDoc> projectRootMatch(DocIndex index, String projectPath) =>
    _longestCover(index, index.docs, projectPath, fromProject: true);

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

/// Returns the paths [doc]'s `covers` fields name, in `normalCodeEntry`'s
/// form, an empty entry left out: the fields that read from the project root
/// when [fromProject], else those that read from a code root.
List<String> _coveredPaths(
  DocIndex index,
  IndexedDoc doc, {
  required bool fromProject,
}) => _codePathsOf(index).covered.putIfAbsent(
  _docKey(doc.docPath, '$fromProject'),
  () => [
    for (final field in coversFieldsOf(index.typeOf(doc)))
      if (readsFromProjectRoot(field) == fromProject)
        for (final entry in doc.valuesOf(field.id)) ?reachablePathOf(entry),
  ],
);

List<IndexedDoc> _tracedDocs(DocIndex index, CodePath code, String path) => [
  for (final doc in _docsOf(index, code))
    if (doc.docTypeId != null &&
        _tracedPaths(
          index,
          doc,
          code.target.name,
        ).any((entryPath) => _traces(entryPath, code, path)))
      doc,
];

/// Returns the paths [doc] is traced to in [codeTarget]: its record entry's
/// code paths and test paths; with no record doc type, its own `implements:`
/// values stand in, as a status is read then.
List<String> _tracedPaths(DocIndex index, IndexedDoc doc, String? codeTarget) =>
    _codePathsOf(index).traced.putIfAbsent(
      _docKey(doc.docPath, codeTarget == null ? '' : 'target $codeTarget'),
      () {
        final entries = index.set.recordDocType == null
            ? doc.valuesOf(_implementsField)
            : switch (index.recordEntryOf(doc, codeTarget: codeTarget)) {
                final entry? => [...entry.codePaths, ...entry.testPaths],
                null => const <String>[],
              };
        return [for (final entry in entries) _entryPathOf(entry)];
      },
    );

String _entryPathOf(String entry) {
  final pointer = CodeLinkEntry(entry).pointer;
  final colon = pointer.indexOf(':');
  return colon < 0 ? pointer : pointer.substring(0, colon);
}

bool _traces(String entryPath, CodePath code, String path) =>
    entryPath == path ||
    code.isFolder && (path == '.' || entryPath.startsWith('$path/'));

String _docKey(String docPath, String part) => '$part\u0000$docPath';

/// The code paths each doc of an index names, each read once per index.
///
/// A sync asks which docs cover each of many code paths, and each ask walks
/// every doc.
final class _DocCodePaths {
  final Map<String, List<String>> covered = {};
  final Map<String, List<String>> traced = {};
}

final Expando<_DocCodePaths> _codePathsByIndex = Expando('doc code paths');

_DocCodePaths _codePathsOf(DocIndex index) =>
    _codePathsByIndex[index] ??= _DocCodePaths();
