import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/consistency_check/code_link_rules.dart';
import 'package:specstone_core/src/consistency_check/code_rules.dart'
    show ImplementedWork;
import 'package:specstone_core/src/consistency_check/doc_lines.dart';
import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_splice.dart' show withKeyBlock;
import 'package:specstone_core/src/doc_model/doc_type_matcher.dart';
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
import 'package:specstone_core/src/templates/doc_type_layer.dart'
    show RecordStatus;
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:yaml/yaml.dart';

// MARK: - Types

/// A doc of the run: DocPath, LF text, merged doc type (null when untyped),
/// and the code target whose pattern set matched it (null for a shared doc).
typedef CodeStampDoc = ({
  String docPath,
  String lf,
  MergedDocType? type,
  String? target,
});

/// One value a doc's field takes: the field id, the value as written, the
/// value with its fingerprint, and the target whose count it adds to.
typedef _Stamp = ({
  String field,
  String value,
  String stamped,
  CodeTarget target,
});

// MARK: - CodeStampStep

/// The `stamp_code_fingerprints` step of a pack upgrade: each code link the
/// check reads, but a `planned` entry's, takes its code's current
/// fingerprint, with no compare.
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
  /// in. A `planned` entry, a waiting target's `covers:` entry, an entry
  /// whose path names nothing, one whose code cannot be read, and one whose
  /// scalar style takes no tail edit stay as written and are not counted; no
  /// other byte of a doc changes.
  factory plan(
    List<CodeStampDoc> docs, {
    required Directory projectRoot,
    required MergedSet set,
    required List<CodeTarget> targets,
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
      final stamps = _stampsOf(read, work, reader, doc);
      final (:lf, :applied) = _withStamps(doc.lf, stamps);
      if (lf != doc.lf) rewrites[doc.docPath] = lf;
      for (final stamp in applied) {
        entries[stamp.target] = entries[stamp.target]! + 1;
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
  CodeStampDoc doc,
) {
  final indexed = read.tree.at(doc.docPath);
  final type = doc.type;
  final target = indexed == null ? null : work.targetOf(indexed);
  if (indexed == null || type == null || target == null) return const [];
  final codeRoot = codeRootFolderOf(reader.projectRoot, target);
  final links = codeLinksOf(
    read.tree,
    work,
    indexed,
    type: type,
    target: target,
    codeRoot: codeRoot,
    linesOf: () => read.linesOf(doc.docPath),
  );
  return [
    for (final link in links)
      if (link.status != RecordStatus.planned)
        if (reader.fingerprintOf(target, link.path, codeRoot) case final fp?)
          if (_stampedValue(link, fp) case final stamped
              when stamped != link.value)
            (
              field: link.field,
              value: link.value,
              stamped: stamped,
              target: target,
            ),
  ];
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
  new(this.projectRoot, this._targets);

  /// The project root the code roots resolve from.
  final Directory projectRoot;

  final List<CodeTarget> _targets;
  final _bytes = <(CodeTarget, String), List<int>?>{};

  /// Each code file a read failed on, as a path from the project root.
  final unreadable = <String>{};

  /// Returns the current fingerprint of [path] of [target], as the check
  /// reads it, null when its code cannot be read.
  String? fingerprintOf(CodeTarget target, String path, Directory codeRoot) =>
      currentCodeFingerprint(
        projectRoot,
        target,
        path,
        codeRoot: codeRoot,
        targets: _targets,
        bytesOf: (file) => _read(target, codeRoot, file),
        onUnlistable: (_) {},
      );

  List<int>? _read(CodeTarget target, Directory codeRoot, String file) =>
      _bytes.putIfAbsent((target, file), () {
        final read = File('${codeRoot.path}/$file');
        try {
          return readPlanInput(read);
        } on FileSystemException {
          unreadable.add(pathFromRoots(read.absolute.path, [projectRoot.path]));
          return null;
        }
      });
}

// MARK: - Writing

/// Returns [lf] with each value of [stamps] rewritten in its field, quotes
/// and every other byte kept, and the stamps that landed.
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
    if (block == null) continue;
    final (:written, :landed) = _withScalars(block.text, field, fieldStamps);
    applied.addAll(landed);
    if (written != block.text) text = withKeyBlock(text, field, written);
  }
  return (lf: text, applied: applied);
}

/// Returns the key block [text] of [field] with the scalar of each of
/// [stamps] rewritten in place, and the stamps whose scalar took the edit.
({String written, List<_Stamp> landed}) _withScalars(
  String text,
  String field,
  List<_Stamp> stamps,
) {
  final node = switch (loadYamlNode(text)) {
    YamlMap(:final nodes) => nodes[field],
    _ => null,
  };
  final scalars = switch (node) {
    final YamlList list => list.nodes.whereType<YamlScalar>(),
    final YamlScalar scalar => [scalar],
    _ => const <YamlScalar>[],
  };
  final byValue = {for (final stamp in stamps) stamp.value: stamp};
  final edits = <({int start, int end, String source, _Stamp stamp})>[];
  for (final scalar in scalars) {
    final stamp = byValue[scalar.value];
    if (stamp == null) continue;
    if (_tailEdit(text, scalar, stamp.value, stamp.stamped) case final edit?) {
      edits.add((
        start: edit.start,
        end: edit.end,
        source: edit.source,
        stamp: stamp,
      ));
    }
  }
  edits.sort((a, b) => b.start.compareTo(a.start));
  var written = text;
  for (final (:start, :end, :source, stamp: _) in edits) {
    written = written.replaceRange(start, end, source);
  }
  return (written: written, landed: [for (final edit in edits) edit.stamp]);
}

/// Returns the edit that makes the source of [scalar], read as [old], read
/// as [value]; null when the scalar's style or source keeps it from one.
///
/// [value] differs from [old] only past the pointer, so the edit replaces
/// the tail alone and the source keeps its quotes and escapes.
({int start, int end, String source})? _tailEdit(
  String text,
  YamlScalar scalar,
  String old,
  String value,
) {
  final quoteLength = switch (scalar.style) {
    ScalarStyle.PLAIN => 0,
    ScalarStyle.SINGLE_QUOTED || ScalarStyle.DOUBLE_QUOTED => 1,
    _ => null,
  };
  if (quoteLength == null) return null;
  var shared = 0;
  while (shared < old.length &&
      shared < value.length &&
      old[shared] == value[shared]) {
    shared++;
  }
  final oldTail = old.substring(shared);
  final end = scalar.span.end.offset - quoteLength;
  final start = end - oldTail.length;
  if (start < scalar.span.start.offset + quoteLength ||
      text.substring(start, end) != oldTail) {
    return null;
  }
  return (start: start, end: end, source: value.substring(shared));
}
