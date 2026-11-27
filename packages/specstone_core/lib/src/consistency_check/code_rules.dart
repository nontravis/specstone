import 'dart:io';

import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/exact_case_path.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/consistency_check/implements_entry.dart';
import 'package:specstone_core/src/consistency_check/models/yaml_entry.dart';
import 'package:specstone_core/src/index_query/code_root_files.dart'
    show isEmptyCodeEntry, normalCodeEntry;
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/status_tree.dart';
import 'package:specstone_core/src/templates/code_link_entry.dart';
import 'package:specstone_core/src/templates/code_target.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/models/record_status.dart';

const _codeField = 'code';

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
        recordTypeId: context.set.recordDocType?.id,
      );

  /// Reads the work of [targets] from [tree], [allTargets] being every code
  /// target of the project, in config order, and [recordTypeId] the id of its
  /// record doc type, null when it has none.
  new of(
    StatusTree tree, {
    required List<CodeTarget> allTargets,
    required this.targets,
    required String? recordTypeId,
  }) : _tree = tree,
       _allTargets = allTargets,
       _recordTypeId = recordTypeId,
       _work = {for (final target in targets) target: _workOf(tree, target)};

  final StatusTree _tree;
  final List<CodeTarget> _allTargets;
  final String? _recordTypeId;

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
  /// A record doc waits for an entry of its feature, nested features
  /// included; any other doc waits for an entry of the target.
  bool endsWaitOf(IndexedDoc doc, CodeTarget target) {
    final work = _work[target]!;
    final feature = doc.docTypeId == _recordTypeId ? _tree.parentOf(doc) : null;
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

/// Returns the path the check reads for a record entry, [pointer] being its
/// `path[:Symbol]` from [codeRoot], as the disk spells it; null when it reads
/// nothing.
///
/// An entry of a `skipped` item reads nothing. Any other entry is read once
/// [paths] finds a regular file at its path, a `planned` entry's file included.
/// A path that differs from the disk's by letter case, or holds a `..`, names
/// nothing. A reader opens the returned spelling, never the entry's own, so a
/// disk that compares bytes finds a file written in another Unicode form.
String? readsEntryCode(
  ExactCasePaths paths,
  Directory codeRoot,
  RecordStatus status,
  String pointer,
) {
  if (status == RecordStatus.skipped) return null;
  final verdict = paths.resolve(codeRoot, ImplementsEntry(pointer).path);
  return verdict.kind == CodePathKind.file ? verdict.diskPath : null;
}

/// Returns the path the check reads for a `covers:` entry, [pointer] being
/// its path from [root], a code root or the project root, as the disk spells
/// it; null when it reads nothing. [endsWait] is whether its wait is over
/// ([ImplementedWork.endsWaitOf]).
///
/// An entry that holds a `..` reads nothing.
String? readsCoversCode(
  ExactCasePaths paths,
  Directory root,
  String pointer, {
  required bool endsWait,
}) {
  if (!endsWait) return null;
  final verdict = paths.resolve(root, pointer);
  return verdict.exists ? verdict.diskPath : null;
}

/// The field a code path entry is read from.
enum CodePathField { covers, code, implements }

/// Returns the finding kind [verdict] gives an entry of [field]; null when the
/// entry names what the field needs.
///
/// A `covers` entry names a file or a folder; a `code` root, the same, or the
/// whole root; an `implements` path, a file.
FindingKind? codePathFindingOf(CodePathField field, CodePathVerdict verdict) =>
    switch ((field, verdict.kind)) {
      (_, CodePathKind.file) => null,
      (CodePathField.covers || CodePathField.code, CodePathKind.folder) => null,
      (CodePathField.code, CodePathKind.empty) => null,
      (CodePathField.covers, CodePathKind.empty) =>
        FindingKind.coversEntryEmpty,
      (CodePathField.covers, CodePathKind.parentSegment) =>
        FindingKind.coversPathOutside,
      (CodePathField.covers, _) => FindingKind.coversPathMissing,
      (CodePathField.code, _) => FindingKind.codeRootMissing,
      (CodePathField.implements, _) => FindingKind.implementsPathUnresolved,
    };

/// Returns the message of the finding [verdict] gives [entry] of [field], the
/// text of [codePathFindingOf]'s kind.
String codePathMessageOf(
  CodePathField field,
  String entry,
  CodePathVerdict verdict,
) => switch (verdict) {
  CodePathVerdict(kind: CodePathKind.empty)
      when field == CodePathField.covers =>
    '"$entry" names no path of its own, only the whole root; the Owner sets '
        'the path it covers',
  CodePathVerdict(kind: CodePathKind.empty) => 'the code path is empty',
  CodePathVerdict(kind: CodePathKind.parentSegment) =>
    '"$entry" holds a `..` segment, which no code path may hold',
  CodePathVerdict(kind: CodePathKind.wrongCase, :final diskPath?)
      when field == CodePathField.implements =>
    '$entry is spelled $diskPath on disk',
  _ when field == CodePathField.implements => '$entry is no file',
  _ => '$entry names nothing on disk',
};

/// Returns the `covers_entry_empty`, `covers_path_outside`,
/// `covers_path_missing`, and `code_root_missing` findings of a typed [doc].
///
/// An empty `covers` entry names no path of its own, and one holding a `..`
/// is refused, so each is reported in every run, a waiting target's docs
/// included. No path or fingerprint rule reads either; only the shared-doc rule
/// still counts an outside entry.
/// A `root: project` entry resolves from the project root in every run. Any
/// other `covers` entry and each `code` root resolve from the code root of
/// the doc's target, once [work] says it holds the work that ends their
/// wait. An entry names something when [ExactCasePaths.resolve] finds a file
/// or a folder there.
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
  for (final field in coversFieldsOf(type)) {
    final base = readsFromProjectRoot(field) ? context.projectRoot : codeRoot;
    yield* _pathFindings(
      context,
      doc,
      CodePathField.covers,
      field.id,
      base,
      pathOf: (value) => CodeLinkEntry(value).pointer,
    );
  }
  if (codeRoot == null || !context.typeHoldsField(type, _codeField)) return;
  yield* _pathFindings(
    context,
    doc,
    CodePathField.code,
    _codeField,
    codeRoot,
    pathOf: (value) => value,
  );
}

/// Yields a finding for each entry of [doc]'s [fieldId] whose path, as
/// [pathOf] reads it, [codePathFindingOf] faults from [base].
///
/// A null [base] is a target still waiting: no disk is read, so only an empty
/// or `..` entry is faulted.
Iterable<Finding> _pathFindings(
  CheckContext context,
  IndexedDoc doc,
  CodePathField field,
  String fieldId,
  Directory? base, {
  required String Function(String value) pathOf,
}) sync* {
  for (final YamlEntry(:value, :line)
      in context.linesOf(doc).entriesOf(fieldId)) {
    if (value is! String) continue;
    final entry = pathOf(value);
    final verdict = base == null
        ? ExactCasePaths.writtenVerdictOf(entry)
        : _verdictOf(context.exactPaths, field, base, entry);
    if (verdict == null) continue;
    final isWrittenFault =
        verdict.kind == CodePathKind.empty ||
        verdict.kind == CodePathKind.parentSegment;
    if (base == null && !isWrittenFault) continue;
    final kind = codePathFindingOf(field, verdict);
    if (kind == null) continue;
    yield context.finding(
      doc,
      kind,
      line: line,
      message: codePathMessageOf(field, entry, verdict),
      keys: {'entry': entry},
    );
  }
}

/// Returns what [entry] names from [base]; a `code` root that names the whole
/// root is a folder only when [base] exists.
CodePathVerdict _verdictOf(
  ExactCasePaths paths,
  CodePathField field,
  Directory base,
  String entry,
) {
  final verdict = paths.resolve(base, entry);
  if (field != CodePathField.code || verdict.kind != CodePathKind.empty) {
    return verdict;
  }
  return CodePathVerdict(
    kind: base.existsSync() ? CodePathKind.folder : CodePathKind.missing,
  );
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

/// Returns [written], the path an entry gives, or [diskPath], where the disk
/// spells it in another Unicode form, so a reader opens a name the disk holds.
///
/// [written] stays when it is already [diskPath] in [normalCodeEntry]'s form,
/// so a final `/` of a folder entry shows as the Owner wrote it.
String readPathOf(String written, String diskPath) =>
    normalCodeEntry(written) == diskPath ? written : diskPath;
