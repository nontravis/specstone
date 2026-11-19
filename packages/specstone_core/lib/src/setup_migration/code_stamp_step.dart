import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/consistency_check/code_fingerprint.dart'
    show legacyFileCodeFingerprint;
import 'package:specstone_core/src/consistency_check/code_link_rules.dart';
import 'package:specstone_core/src/consistency_check/code_rules.dart'
    show ImplementedWork;
import 'package:specstone_core/src/consistency_check/models/doc_lines.dart';
import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_splice.dart' show withKeyBlock;
import 'package:specstone_core/src/doc_model/doc_type_matcher.dart';
import 'package:specstone_core/src/doc_model/list_block_writer.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/parents.dart'
    show resolveParents;
import 'package:specstone_core/src/index_query/status_tree.dart';
import 'package:specstone_core/src/plan_hash.dart';
import 'package:specstone_core/src/setup_migration/run_plan.dart'
    show UpgradeStepLine;
import 'package:specstone_core/src/templates/code_link_entry.dart';
import 'package:specstone_core/src/templates/code_point_order.dart';
import 'package:specstone_core/src/templates/code_target.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:specstone_core/src/templates/models/record_status.dart';

// MARK: - Types

/// A doc of the run: DocPath, LF text, merged doc type (null when untyped),
/// and the code target whose pattern set matched it (null for a shared doc).
typedef CodeStampDoc = ({
  String docPath,
  String lf,
  MergedDocType? type,
  String? target,
});

/// One value a doc's field takes.
final class _Stamp {
  const new({
    required this.field,
    required this.value,
    required this.stamped,
    required this.target,
  });

  /// The id of the field that holds the value.
  final String field;

  /// The value as written.
  final String value;

  /// The value with its fingerprint.
  final String stamped;

  /// The target whose count the stamp adds to; null for a `root: project`
  /// entry, which counts for no target.
  final CodeTarget? target;
}

// MARK: - CodeStampStep

/// The `stamp_code_fingerprints` step of a pack upgrade: each code link the
/// check reads, but a `planned` entry's, takes its code's current
/// fingerprint, with no compare. In restamp mode, the
/// `restamp_code_fingerprints` step: a link takes it only when it records the
/// fingerprint its code had before comment and blank lines were dropped.
///
/// The docs are read as the index reads them, the links picked by the
/// check's own selection, and the code hashed by its own read, each code
/// file through [readPlanInput], so the plan hash covers the code it stamps.
final class CodeStampStep {
  new _(this.rewrites, this.unreadable, this._entries);

  /// Plans the step over the [docs] of the run, as the steps before it left
  /// them, in each of [targets], their code roots read from [projectRoot].
  ///
  /// A link takes its fingerprint after one space, in place of any it ends
  /// in. A `root: project` entry reads from [projectRoot], whatever its doc's
  /// target, and counts for no target. A `planned` entry, a waiting target's
  /// `covers:` entry, an entry whose path names nothing, and one whose code
  /// cannot be read stay as written and are not counted; no other entry of a
  /// doc changes.
  ///
  /// With [restamp], a link that records no fingerprint, or one that differs
  /// from its code's fingerprint under the earlier rule, stays as written too.
  factory plan(
    List<CodeStampDoc> docs, {
    required Directory projectRoot,
    required MergedSet set,
    required List<CodeTarget> targets,
    bool restamp = false,
  }) {
    final read = _ReadDocs(docs, set, targets);
    final work = ImplementedWork.of(
      read.tree,
      allTargets: targets,
      targets: targets,
    );
    final reader = _CodeReader(projectRoot, targets);
    final rewrites = <String, String>{};
    final entries = {for (final target in targets) target: 0};
    for (final doc in docs) {
      final stamps = _stampsOf(read, work, reader, doc, restamp: restamp);
      final (:lf, :applied) = _withStamps(doc.lf, stamps);
      if (lf != doc.lf) rewrites[doc.docPath] = lf;
      for (final stamp in applied) {
        if (stamp.target case final target?) {
          entries[target] = entries[target]! + 1;
        }
      }
    }
    return CodeStampStep._(
      rewrites,
      reader.unreadable.toList()..sort(compareCodePoints),
      entries,
    );
  }

  /// The text of each doc the step rewrites, by DocPath.
  final Map<String, String> rewrites;

  /// Each code file the step could not read, as a path from the project
  /// root, in code point order.
  final List<String> unreadable;

  /// The entries stamped in each target, in config order.
  final Map<CodeTarget, int> _entries;

  /// The DocPath of each doc the step rewrites, in code point order.
  List<String> get paths => rewrites.keys.toList()..sort(compareCodePoints);

  /// The step line of the migration entry `from:` [from], [step] naming it.
  ///
  /// The counts read `; <k> entries`, or `; <target>: <k> entries` per target
  /// with two or more, then `; unreadable: <u>` when a file cannot be read.
  /// A `root: project` entry counts in neither form.
  UpgradeStepLine stepLine({required String from, required String step}) {
    final counts = _entries.length > 1
        ? [
            for (final MapEntry(key: target, value: count) in _entries.entries)
              '${target.name}: $count',
          ]
        : ['${_entries.values.fold(0, (sum, count) => sum + count)}'];
    return UpgradeStepLine(
      from: from,
      step: step,
      paths: paths,
      tail: [
        for (final count in counts) '; $count entries',
        if (unreadable.isNotEmpty) '; unreadable: ${unreadable.length}',
      ].join(),
      unreadable: unreadable,
    );
  }
}

/// Returns the value each code link of [doc] that the step stamps takes.
List<_Stamp> _stampsOf(
  _ReadDocs read,
  ImplementedWork work,
  _CodeReader reader,
  CodeStampDoc doc, {
  required bool restamp,
}) {
  final indexed = read.tree.at(doc.docPath);
  final type = doc.type;
  if (indexed == null || type == null) return const [];
  final links = codeLinksOf(
    read.tree,
    work,
    indexed,
    type: type,
    projectRoot: reader.projectRoot,
    codeRootOf: reader.codeRootOf,
    linesOf: () => read.linesOf(doc.docPath),
  );
  return [
    for (final link in links)
      if (link.status != RecordStatus.planned)
        if (_fingerprintToTake(reader, link, restamp: restamp) case final fp?)
          if (_stampedValue(link, fp) case final stamped
              when stamped != link.value)
            _Stamp(
              field: link.field,
              value: link.value,
              stamped: stamped,
              target: link.target,
            ),
  ];
}

/// Returns the fingerprint [link] takes, null when it keeps its entry.
///
/// Stamping takes the current fingerprint of the code. Restamping takes it
/// only when [link] records the fingerprint of the same code under the rule
/// before comment and blank lines were dropped.
String? _fingerprintToTake(
  _CodeReader reader,
  CodeLink link, {
  required bool restamp,
}) {
  final current = reader.fingerprintOf(link);
  if (!restamp || current == null) return current;
  final recorded = link.recorded;
  if (recorded == null) return null;
  final earlier = reader.fingerprintOf(
    link,
    fileHash: (bytes, _) => legacyFileCodeFingerprint(bytes),
  );
  return recorded == earlier ? current : null;
}

/// Returns the value [link] takes with [fingerprint] recorded after it.
String _stampedValue(CodeLink link, String fingerprint) {
  final entry = codeLinkEntryOf(link.pointer, fingerprint);
  return link.item == null ? entry : '${link.item}:$entry';
}

// MARK: - Reading docs and code

/// The docs of the run as the index reads them: each parsed by the indexer,
/// a per-target doc of one named target given that target, and nested by
/// the index's parent rule.
final class _ReadDocs {
  new(List<CodeStampDoc> docs, MergedSet set, List<CodeTarget> targets) {
    final singleTarget = targets.length == 1 ? targets.single.name : null;
    for (final doc in docs) {
      _parsed[doc.docPath] = parseIndexedDoc(
        docPath: doc.docPath,
        bytes: utf8.encode(doc.lf),
        match: switch (doc.type) {
          final type? => MatchedDocType(type, target: doc.target),
          null => const NoDocType(),
        },
        // The approval hash is not read here, so either rule serves.
        statusesOutside: false,
        codeTarget: singleTarget,
      );
    }
    final indexed = [for (final parsed in _parsed.values) parsed.doc];
    tree = StatusTree(
      set,
      indexed,
      targetNames: targetNamesOf(targets),
      parents: resolveParents(indexed, set).parents,
    );
  }

  final _parsed = <String, ParsedDoc>{};

  /// The statuses and parent tree of the run's docs.
  late final StatusTree tree;

  /// Returns the lines of the doc at [docPath].
  DocLines linesOf(String docPath) => DocLines.from(_parsed[docPath]!.content);
}

/// Reads each code file once, through [readPlanInput], and keeps each file
/// it could not read.
final class _CodeReader {
  new(this.projectRoot, List<CodeTarget> targets)
    : _codeRoots = {
        for (final target in targets)
          target: codeRootFolderOf(projectRoot, target),
      } {
    _nestedRoots = nestedRootsByTarget(_codeRoots);
  }

  /// The project root the code roots resolve from.
  final Directory projectRoot;

  final Map<CodeTarget, Directory> _codeRoots;
  late final Map<CodeTarget, List<String>> _nestedRoots;
  // A null target keys a read from the project root.
  final _bytes = <(CodeTarget?, String), List<int>?>{};

  /// Each code file a read failed on, as a path from the project root.
  final unreadable = <String>{};

  /// Returns the code root of [target], resolved once.
  Directory codeRootOf(CodeTarget target) =>
      _codeRoots[target] ?? (throw _unknownTarget(target));

  /// Returns the fingerprint of [link]'s code, read from its root as the
  /// check reads it under [fileHash] (its current rule when null), null when
  /// its code cannot be read.
  String? fingerprintOf(
    CodeLink link, {
    String Function(List<int> bytes, String path)? fileHash,
  }) {
    final target = link.target;
    return currentCodeFingerprint(
      link.path,
      codeRoot: link.root,
      nestedRoots: target == null
          ? const []
          : _nestedRoots[target] ?? (throw _unknownTarget(target)),
      bytesOf: (file) => _read(target, link.root, file),
      onUnlistable: (_) {},
      fileHash: fileHash,
    );
  }

  ArgumentError _unknownTarget(CodeTarget target) =>
      ArgumentError.value(target, 'target', 'is not a target of the run');

  List<int>? _read(CodeTarget? target, Directory root, String file) =>
      _bytes.putIfAbsent((target, file), () {
        final read = File('${root.path}/$file');
        try {
          return readPlanInput(read);
        } on FileSystemException {
          unreadable.add(pathFromRoots(read.absolute.path, [projectRoot.path]));
          return null;
        }
      });
}

// MARK: - Writing

/// Returns [lf] with each value of [stamps] rewritten in its field through
/// the list writer, and the stamps that landed.
({String lf, List<_Stamp> applied}) _withStamps(
  String lf,
  List<_Stamp> stamps,
) {
  var text = lf;
  final applied = <_Stamp>[];
  final byField = <String, List<_Stamp>>{};
  for (final stamp in stamps) {
    (byField[stamp.field] ??= []).add(stamp);
  }
  for (final MapEntry(key: field, value: fieldStamps) in byField.entries) {
    final block = Doc.parse(text).frontmatter
        ?.where((candidate) => candidate.name == field)
        .firstOrNull;
    final entries = block == null ? null : listEntriesOf(block);
    if (block == null || entries == null) continue;
    final byValue = {for (final stamp in fieldStamps) stamp.value: stamp};
    final landed = <_Stamp>[];
    final stamped = <Object?>[];
    for (final entry in entries) {
      final stamp = byValue[entry];
      if (stamp != null) landed.add(stamp);
      stamped.add(stamp?.stamped ?? entry);
    }
    if (landed.isEmpty) continue;
    applied.addAll(landed);
    text = withKeyBlock(
      text,
      field,
      listBlockOf(field, stamped, onDisk: block),
    );
  }
  return (lf: text, applied: applied);
}
