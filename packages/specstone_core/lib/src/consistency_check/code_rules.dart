import 'dart:io';

import 'package:specstone_core/src/canonical_path.dart' show pathInside;
import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/consistency_check/implements_entry.dart';
import 'package:specstone_core/src/consistency_check/models/yaml_entry.dart';
import 'package:specstone_core/src/consistency_check/reference_rules.dart'
    show architectureTypeId;
import 'package:specstone_core/src/index_query/code_root_files.dart'
    show filesUnderCodeRoot, isEmptyCodeEntry, normalCodeEntry;
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/status_tree.dart';
import 'package:specstone_core/src/portable_path.dart';
import 'package:specstone_core/src/templates/code_link_entry.dart';
import 'package:specstone_core/src/templates/code_target.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/models/record_status.dart';

const _codeField = 'code';
const _separator = '/';

/// The code targets of one run and the implemented work each holds.
///
/// A target's `covers` entries and `code` roots resolve once the target holds
/// an `implemented` story or FR; this reads that once per target, so
/// each rule stays one pass over the docs.
final class ImplementedWork {
  /// Reads the work of [targets] from the index of a check run.
  new(CheckContext context, List<CodeTarget> targets)
    : this.of(
        context.index.statusTree,
        allTargets: context.targets,
        targets: targets,
      );

  /// Reads the work of [targets] from [tree], [allTargets] being every code
  /// target of the project, in config order.
  new of(
    StatusTree tree, {
    required List<CodeTarget> allTargets,
    required this.targets,
  }) : _tree = tree,
       _allTargets = allTargets,
       _work = {for (final target in targets) target: _workOf(tree, target)};

  final StatusTree _tree;
  final List<CodeTarget> _allTargets;

  /// The targets the run's code rules cover.
  final List<CodeTarget> targets;

  final Map<CodeTarget, _TargetWork> _work;

  /// Returns the target [doc] belongs to, null when it belongs to none of
  /// [targets].
  ///
  /// A per-target doc belongs to the target it names; any other doc to the
  /// project's one target, and to none when the project has several.
  CodeTarget? targetOf(IndexedDoc doc) {
    final owner = ownerTargetOf(doc, _allTargets);
    return targets.contains(owner) ? owner : null;
  }

  /// Whether [target] holds the work that ends the wait of [doc]'s paths.
  ///
  /// An `architecture` doc waits for an entry of its feature, nested features
  /// included; any other doc waits for an entry of the target.
  bool endsWaitOf(IndexedDoc doc, CodeTarget target) {
    final work = _work[target]!;
    final feature = doc.docTypeId == architectureTypeId
        ? _tree.parentOf(doc)
        : null;
    return switch (feature) {
      IndexedDoc(docTypeId: featureType) => work.features.contains(
        feature.name,
      ),
      _ => work.any,
    };
  }
}

/// Returns the target [doc] belongs to among [allTargets], every code target
/// of the project; null when it belongs to none.
///
/// A per-target doc belongs to the target it names; any other doc to the
/// project's one target, and to none when the project has several. The one
/// owner rule `check` and `set --stamp` read a doc's code by.
CodeTarget? ownerTargetOf(IndexedDoc doc, List<CodeTarget> allTargets) =>
    switch (doc.target) {
      final name? =>
        allTargets.where((target) => target.name == name).firstOrNull,
      null => allTargets.length == 1 ? allTargets.single : null,
    };

/// Returns whether [target] holds an implemented story or FR, and the name
/// of each feature that holds one in its subtree.
_TargetWork _workOf(StatusTree tree, CodeTarget target) {
  final features = <String>{};
  var any = false;
  for (final doc in tree.docs) {
    if (doc.docTypeId != storyType && doc.docTypeId != frType) continue;
    if (tree.statusOf(doc, codeTarget: target.name) !=
        RecordStatus.implemented.wire) {
      continue;
    }
    any = true;
    for (var up = tree.parentOf(doc); up != null; up = tree.parentOf(up)) {
      if (up.docTypeId == featureType) features.add(up.name);
    }
  }
  return _TargetWork(any: any, features: features);
}

/// Whether a target holds an implemented story or FR, and the name of each
/// feature that holds one in its subtree.
final class _TargetWork {
  const new({required this.any, required this.features});

  final bool any;
  final Set<String> features;
}

/// Whether the check reads the code a record entry names, [pointer] being its
/// `path[:Symbol]` from [codeRoot].
///
/// An entry of a `skipped` item reads nothing. Any other entry is read once a
/// stat finds a regular file at its path, a `planned` entry's file included.
bool readsEntryCode(Directory codeRoot, RecordStatus status, String pointer) =>
    status != RecordStatus.skipped &&
    ImplementsEntry(pointer).namesFileFrom(codeRoot);

/// Whether the check reads the code a `covers:` entry names, [pointer] being
/// its path from [root], a code root or the project root, and [endsWait]
/// whether its wait is over ([ImplementedWork.endsWaitOf]).
bool readsCoversCode(
  Directory root,
  String pointer, {
  required bool endsWait,
}) => endsWait && namesFileOrFolderFrom(root, pointer);

/// Returns the `covers_entry_empty`, `covers_path_missing`, and
/// `code_root_missing` findings of a typed [doc].
///
/// An empty `covers` entry names no path of its own, so it is reported in
/// every run, a waiting target's docs included, and no other rule reads it.
/// A `root: project` entry resolves from the project root in every run. Any
/// other `covers` entry and each `code` root resolve from the code root of
/// the doc's target, once [work] says it holds the work that ends their
/// wait. An entry names something when its path in [normalCodeEntry]'s form
/// is a file or a folder there.
Iterable<Finding> checkCoversAndCodeRoots(
  CheckContext context,
  ImplementedWork work,
  IndexedDoc doc,
) sync* {
  final type = context.typeOf(doc);
  if (type == null) return;
  final isShared = doc.target == null && context.index.hasTwins;
  if (isShared) yield* _sharedDocPaths(context, doc, type);
  final target = isShared ? null : work.targetOf(doc);
  final codeRoot = target != null && work.endsWaitOf(doc, target)
      ? context.codeRootOf(target)
      : null;
  final lines = context.linesOf(doc);
  for (final field in coversFieldsOf(type)) {
    for (final YamlEntry(:value, :line) in lines.entriesOf(field.id)) {
      if (value is! String) continue;
      final entry = CodeLinkEntry(value).pointer;
      if (!isEmptyCodeEntry(entry)) continue;
      yield context.finding(
        doc,
        FindingKind.coversEntryEmpty,
        line: line,
        message:
            '"$entry" names no path of its own, only the whole root; the '
            'Owner sets the path it covers',
        keys: {'entry': entry},
      );
    }
    final base = readsFromProjectRoot(field) ? context.projectRoot : codeRoot;
    if (base == null) continue;
    yield* _missingPaths(
      context,
      doc,
      field.id,
      base,
      FindingKind.coversPathMissing,
      pathOf: (value) => CodeLinkEntry(value).pointer,
      skipsEmpty: true,
    );
  }
  if (codeRoot == null || !context.typeHoldsField(type, _codeField)) return;
  yield* _missingPaths(
    context,
    doc,
    _codeField,
    codeRoot,
    FindingKind.codeRootMissing,
    pathOf: (value) => value,
    skipsEmpty: false,
  );
}

/// Yields a [kind] finding for each entry of [doc]'s [fieldId] whose path,
/// as [pathOf] reads it, names nothing from [base].
///
/// With [skipsEmpty], an empty entry gives none: a `covers` entry that names
/// no path is `covers_entry_empty`'s. A `code` root has no such finding, so it
/// keeps resolving.
Iterable<Finding> _missingPaths(
  CheckContext context,
  IndexedDoc doc,
  String fieldId,
  Directory base,
  FindingKind kind, {
  required String Function(String value) pathOf,
  required bool skipsEmpty,
}) sync* {
  for (final YamlEntry(:value, :line)
      in context.linesOf(doc).entriesOf(fieldId)) {
    if (value is! String) continue;
    final entry = pathOf(value);
    if (skipsEmpty && isEmptyCodeEntry(entry)) continue;
    if (namesFileOrFolderFrom(base, entry)) continue;
    yield context.finding(
      doc,
      kind,
      line: line,
      message: '$entry names nothing on disk',
      keys: {'entry': entry},
    );
  }
}

/// Yields the `shared_doc_code_path` finding of a doc that belongs to no
/// target but carries code-root `covers` entries or `code` roots in a project
/// of several targets.
///
/// One finding per doc, at the line of the first such key; its paths count for
/// no target. A `root: project` field resolves from the project root and covers
/// code there, so its entries give none. An empty `covers` entry counts as no
/// entry; an empty `code` root still does.
Iterable<Finding> _sharedDocPaths(
  CheckContext context,
  IndexedDoc doc,
  MergedDocType type,
) sync* {
  final lines = context.linesOf(doc);
  bool holdsEntry(String fieldId, {required bool skipsEmpty}) => [
    for (final YamlEntry(:value) in lines.entriesOf(fieldId))
      if (value is String &&
          !(skipsEmpty && isEmptyCodeEntry(CodeLinkEntry(value).pointer)))
        value,
  ].isNotEmpty;
  final line = [
    for (final field in coversFieldsOf(type))
      if (!readsFromProjectRoot(field) &&
          holdsEntry(field.id, skipsEmpty: true))
        lines.keyLine(field.id),
    if (context.typeHoldsField(type, _codeField) &&
        holdsEntry(_codeField, skipsEmpty: false))
      lines.keyLine(_codeField),
  ].nonNulls.firstOrNull;
  if (line == null) return;
  yield context.finding(
    doc,
    FindingKind.sharedDocCodePath,
    line: line,
    message:
        'the doc carries code paths but belongs to no target; move them into '
        'a doc of the target they belong to',
  );
}

/// Returns a `code_uncovered` finding for each code file no `covers` entry
/// reaches.
///
/// A code-root entry of the same target reaches a file by its code-root path.
/// A `root: project` entry of any doc reaches it by its project-root path, and
/// never one under a code root outside the project root.
///
/// Each code root of a target's doc that defines `code` is listed without
/// following links and without reading a file. A file under two roots is
/// reported once, under the first root that lists it. A file under the code
/// root of another target nested in this one belongs to that target. A folder
/// that cannot be listed is a warning, not a finding.
Iterable<Finding> uncoveredCode(
  CheckContext context,
  ImplementedWork work,
) sync* {
  final projectCovers = _projectCoversOf(context);
  for (final target in work.targets) {
    final docs = [
      for (final doc in context.index.docs)
        if (work.targetOf(doc) == target) doc,
    ];
    final covers = _coversOf(context, docs);
    final projectPrefix = _projectPrefixOf(context, target);
    final nested = context.nestedRootsOf(target);
    final reported = <String>{};
    for (final doc in docs) {
      if (!context.typeHoldsField(context.typeOf(doc), _codeField)) continue;
      for (final YamlEntry(:value, :line)
          in context.linesOf(doc).entriesOf(_codeField)) {
        if (value is! String) continue;
        final paths = filesUnderCodeRoot(
          context.codeRootOf(target),
          value,
          skipFolders: nested,
          onUnlistable: (folder) => context.warn(
            '$folder: cannot list the folder; files under it are not '
            'checked for covers or fingerprints',
          ),
        );
        for (final path in paths) {
          if (_isCovered(covers, path) ||
              _isCoveredFromProject(projectCovers, projectPrefix, path) ||
              !reported.add(path)) {
            continue;
          }
          yield context.finding(
            doc,
            FindingKind.codeUncovered,
            line: line,
            message:
                '$path is under the code root $value and no covers entry '
                'reaches it',
            keys: {'path': path},
          );
        }
      }
    }
  }
}

/// Returns every code-root `covers` entry of the typed [docs] in
/// [normalCodeEntry]'s form, the form the lister gives its paths in.
///
/// A `root: project` entry is read by [_projectCoversOf].
List<String> _coversOf(CheckContext context, List<IndexedDoc> docs) => [
  for (final doc in docs)
    for (final field in coversFieldsOf(context.typeOf(doc)))
      if (!readsFromProjectRoot(field))
        for (final YamlEntry(:value)
            in context.linesOf(doc).entriesOf(field.id))
          if (value is String) ?reachablePathOf(value),
];

/// Returns every `root: project` `covers` entry of every typed doc of the
/// project in [normalCodeEntry]'s form.
///
/// A doc of no target counts: such an entry belongs to the project root, not to
/// a target.
List<String> _projectCoversOf(CheckContext context) => [
  for (final doc in context.index.docs)
    for (final field in coversFieldsOf(context.typeOf(doc)))
      if (readsFromProjectRoot(field))
        for (final YamlEntry(:value)
            in context.linesOf(doc).entriesOf(field.id))
          if (value is String) ?reachablePathOf(value),
];

/// Returns the path of [target]'s code root from the project root, `''` for
/// the project root itself; null when the code root lies outside it.
String? _projectPrefixOf(CheckContext context, CodeTarget target) {
  final project = context.projectRoot.path;
  final root = context.codeRootOf(target).path;
  return root == project ? '' : pathInside(project, root);
}

/// Whether a `root: project` entry of [projectCovers] reaches [path], a path
/// from the code root that lies [projectPrefix] below the project root.
bool _isCoveredFromProject(
  List<String> projectCovers,
  String? projectPrefix,
  String path,
) {
  if (projectPrefix == null) return false;
  final fromProject = projectPrefix.isEmpty
      ? path
      : '$projectPrefix$_separator$path';
  return projectCovers.any((entry) => entryReaches(entry, fromProject));
}

/// Whether an entry equals [path] or names a folder that holds it.
bool _isCovered(List<String> covers, String path) =>
    covers.any((entry) => entryReaches(entry, path));

/// Whether [entry], in [normalCodeEntry]'s form, is a file or a folder from
/// [base].
///
/// An [entry] that is no [isPortablePath] as written names nothing, as the code
/// file lister reads it: `\` is a separator on Windows alone, and the disk
/// finds a trimmed name there alone.
///
/// The one rule `check` and the migrate's `code_root` count resolve a
/// `covers` or `code` entry by.
bool namesFileOrFolderFrom(Directory base, String entry) {
  final normal = normalCodeEntry(entry);
  return isPortablePath(entry) &&
      FileSystemEntity.typeSync('${base.path}$_separator$normal') !=
          FileSystemEntityType.notFound;
}
