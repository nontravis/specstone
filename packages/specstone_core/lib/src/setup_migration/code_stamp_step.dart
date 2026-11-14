import 'dart:io';

import 'package:specstone_core/src/consistency_check/code_fingerprint.dart';
import 'package:specstone_core/src/consistency_check/code_rules.dart'
    show readsCoversCode, readsEntryCode;
import 'package:specstone_core/src/consistency_check/implements_entry.dart';
import 'package:specstone_core/src/consistency_check/reference_rules.dart'
    show architectureTypeId;
import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_splice.dart' show withKeyBlock;
import 'package:specstone_core/src/index_query/code_root_files.dart'
    show normalCodeEntry;
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/parents.dart'
    show resolveParents;
import 'package:specstone_core/src/index_query/record_entries.dart';
import 'package:specstone_core/src/plan_hash.dart';
import 'package:specstone_core/src/setup_migration/run_plan.dart'
    show UpgradeStepLine;
import 'package:specstone_core/src/templates/code_link_entry.dart';
import 'package:specstone_core/src/templates/code_point_order.dart';
import 'package:specstone_core/src/templates/code_target.dart';
import 'package:specstone_core/src/templates/doc_type_layer.dart'
    show PointerKind, RecordStatus;
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

/// One code link the step reads: its field, its value as written, the value
/// it takes with a fingerprint, the file or folder of its code, and its
/// target.
typedef _Link = ({
  String field,
  String value,
  String Function(String fingerprint) stamped,
  String path,
  CodeTarget target,
});

// MARK: - CodeStampStep

/// The `stamp_code_fingerprints` step of a pack upgrade: each code link the
/// check reads, but a `planned` entry's, takes its code's current
/// fingerprint, with no compare.
///
/// Each code file is read through [readPlanInput], so the plan hash covers
/// the code the step stamps, and hashed by the recipe the check compares by.
final class CodeStampStep {
  new _(this.rewrites, this.unreadable, this._entries);

  /// Plans the step over the [docs] of the run, as the steps before it left
  /// them, in each of [targets], their code roots read from [projectRoot].
  ///
  /// A link takes its fingerprint after one space, in place of any it ends
  /// in. A `planned` entry, a waiting target's `covers:` entry, an entry
  /// whose path names nothing, and one whose code cannot be read stay as
  /// written; no other byte of a doc changes.
  factory plan(
    List<CodeStampDoc> docs, {
    required Directory projectRoot,
    required MergedSet set,
    required List<CodeTarget> targets,
  }) {
    final tree = _Tree(docs, set, targets, projectRoot);
    final reader = _CodeReader(projectRoot, targets);
    final rewrites = <String, String>{};
    final entries = {for (final target in targets) target: 0};
    for (final doc in docs) {
      final stamped = <String, Map<String, String>>{};
      for (final link in tree.linksOf(doc)) {
        final fingerprint = reader.fingerprintOf(link.target, link.path);
        if (fingerprint == null) continue;
        final value = link.stamped(fingerprint);
        if (value == link.value) continue;
        (stamped[link.field] ??= {})[link.value] = value;
        entries[link.target] = entries[link.target]! + 1;
      }
      final lf = _withValues(doc.lf, stamped);
      if (lf != doc.lf) rewrites[doc.docPath] = lf;
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

// MARK: - Reading code

/// Reads the code of each link once, as the check reads it, and keeps each
/// file it could not read.
final class _CodeReader {
  new(this._projectRoot, this._targets);

  final Directory _projectRoot;
  final List<CodeTarget> _targets;
  final _bytes = <(CodeTarget, String), List<int>?>{};

  /// Each code file a read failed on, as a path from the project root.
  final unreadable = <String>{};

  /// Returns the current fingerprint of the file or folder at [path] of
  /// [target], null when a file it holds cannot be read or a folder cannot
  /// be listed.
  String? fingerprintOf(CodeTarget target, String path) {
    final normal = normalCodeEntry(path);
    final isFile =
        FileSystemEntity.typeSync('${_rootOf(target).path}/$normal') ==
        FileSystemEntityType.file;
    if (!isFile) return _folderFingerprintOf(target, path);
    final bytes = _read(target, normal);
    return bytes == null ? null : fileCodeFingerprint(bytes);
  }

  String? _folderFingerprintOf(CodeTarget target, String path) {
    var isReadable = true;
    final listed = codeLinkFiles(
      _projectRoot,
      target,
      path,
      targets: _targets,
      onUnlistable: (_) => isReadable = false,
    );
    final files = <({String path, String fingerprint})>[];
    for (final file in listed) {
      final bytes = _read(target, file);
      if (bytes == null) {
        isReadable = false;
      } else {
        files.add((path: file, fingerprint: fileCodeFingerprint(bytes)));
      }
    }
    return isReadable ? folderCodeFingerprint(files) : null;
  }

  List<int>? _read(CodeTarget target, String normal) => _bytes.putIfAbsent(
    (target, normal),
    () {
      final file = File('${_rootOf(target).path}/$normal');
      try {
        return readPlanInput(file);
      } on FileSystemException {
        unreadable.add(pathFromRoots(file.absolute.path, [_projectRoot.path]));
        return null;
      }
    },
  );

  Directory _rootOf(CodeTarget target) =>
      codeRootFolderOf(_projectRoot, target);
}

// MARK: - The tree

/// The typed docs of the run as the index reads them: each doc's target, the
/// status of each story and FR in each target, and the code links the check
/// reads.
final class _Tree {
  new(List<CodeStampDoc> docs, this._set, this._targets, this._projectRoot) {
    for (final doc in docs) {
      final type = doc.type;
      if (type == null) continue;
      _byPath[doc.docPath] = IndexedDoc(
        docPath: doc.docPath,
        docTypeId: type.id,
        name: docNameOf(doc.docPath, type, target: doc.target),
        frontmatter: _valuesOf(doc.lf),
        tokens: 0,
        target: doc.target,
      );
    }
    _parents = resolveParents(_byPath.values, _set).parents;
    for (final doc in _byPath.values) {
      if (_parentOf(doc) case final parent?) {
        (_children[parent.docPath] ??= []).add(doc);
      }
      if (_set.recordDocType case final type? when doc.docTypeId == type.id) {
        (_records[(doc.name, doc.target)] ??= []).add(doc);
      }
    }
  }

  final MergedSet _set;
  final List<CodeTarget> _targets;
  final Directory _projectRoot;
  final _byPath = <String, IndexedDoc>{};
  final _children = <String, List<IndexedDoc>>{};
  final _records = <(String, String?), List<IndexedDoc>>{};
  late final Map<String, String> _parents;
  final _work = <CodeTarget, ({bool any, Set<String> features})>{};

  /// Returns the code links of [doc] whose code the step reads.
  List<_Link> linksOf(CodeStampDoc doc) {
    final indexed = _byPath[doc.docPath];
    final type = doc.type;
    if (indexed == null || type == null) return const [];
    final target = _targetOf(indexed);
    if (target == null) return const [];
    final codeRoot = codeRootFolderOf(_projectRoot, target);
    return [
      ..._entryLinks(indexed, target, codeRoot),
      ..._coversLinks(indexed, type, target, codeRoot),
    ];
  }

  /// Returns the target [doc] belongs to: the one it names, else the
  /// project's one target; none for a shared doc of several targets.
  CodeTarget? _targetOf(IndexedDoc doc) => switch (doc.target) {
    final name? => _targets.where((target) => target.name == name).firstOrNull,
    null => _targets.length == 1 ? _targets.single : null,
  };

  /// Returns the `implements` entries of a [record] that are not `planned`
  /// and whose file the check reads.
  List<_Link> _entryLinks(
    IndexedDoc record,
    CodeTarget target,
    Directory codeRoot,
  ) {
    final recordType = _set.recordDocType;
    final feature = _parentOf(record);
    final field = recordType == null ? null : recordCodeFieldOf(recordType);
    if (recordType == null ||
        field == null ||
        record.docTypeId != recordType.id ||
        feature?.docTypeId != featureType) {
      return const [];
    }
    final items = recordItemsOf(feature!, _childrenOf);
    final links = <_Link>[];
    for (final value in record.valuesOf(field.id)) {
      final parsed = recordCodeLineOf(value);
      final doc = items[parsed?.item];
      if (parsed == null || doc == null) continue;
      final pointer = CodeLinkEntry(parsed.code).pointer;
      final status = _statusOf(doc, record.target);
      if (status == RecordStatus.planned ||
          !readsEntryCode(codeRoot, status, pointer)) {
        continue;
      }
      links.add((
        field: field.id,
        value: value,
        stamped: (fingerprint) =>
            '${parsed.item}:${codeLinkEntryOf(pointer, fingerprint)}',
        path: ImplementsEntry(pointer).path,
        target: target,
      ));
    }
    return links;
  }

  /// Returns the `covers:` entries of [doc], a prefix field of [type], that
  /// the check reads.
  List<_Link> _coversLinks(
    IndexedDoc doc,
    MergedDocType type,
    CodeTarget target,
    Directory codeRoot,
  ) {
    final endsWait = _endsWaitOf(doc, target);
    return [
      for (final field in type.fields)
        if (isCodeLinkField(field) && field.pointer == PointerKind.prefix)
          for (final value in doc.valuesOf(field.id))
            if (CodeLinkEntry(value).pointer case final pointer
                when readsCoversCode(codeRoot, pointer, endsWait: endsWait))
              (
                field: field.id,
                value: value,
                stamped: (fingerprint) => codeLinkEntryOf(pointer, fingerprint),
                path: pointer,
                target: target,
              ),
    ];
  }

  /// Whether [target] holds the work that ends the wait of [doc]'s covers:
  /// an implemented item of its feature for an architecture doc, else of
  /// the target.
  bool _endsWaitOf(IndexedDoc doc, CodeTarget target) {
    final work = _work[target] ??= _workOf(target);
    final feature = doc.docTypeId == architectureTypeId ? _parentOf(doc) : null;
    return feature?.docTypeId == featureType
        ? work.features.contains(feature!.name)
        : work.any;
  }

  ({bool any, Set<String> features}) _workOf(CodeTarget target) {
    final features = <String>{};
    var any = false;
    for (final doc in _byPath.values) {
      if (doc.docTypeId != storyType && doc.docTypeId != frType) continue;
      final status = _set.recordDocType == null
          ? doc.writtenStatus
          : _statusOf(doc, target.name).wire;
      if (status != RecordStatus.implemented.wire) continue;
      any = true;
      for (var up = _parentOf(doc); up != null; up = _parentOf(up)) {
        if (up.docTypeId == featureType) features.add(up.name);
      }
    }
    return (any: any, features: features);
  }

  /// Returns the status of the story or FR [item] in [codeTarget], as the
  /// index reads it: `skipped` under a skip that covers it, else its own
  /// feature record's entry status, `planned` without one.
  RecordStatus _statusOf(IndexedDoc item, String? codeTarget) {
    final records = _recordsOf(item, _namedOrGiven(codeTarget));
    for (final (:feature, :entries) in records) {
      final relative = _relativeTo(item, feature);
      final isSkipped = entries.any(
        (entry) =>
            entry.status == RecordStatus.skipped &&
            (entry.item.isEmpty ||
                entry.item == relative ||
                relative.startsWith('${entry.item}/')),
      );
      if (isSkipped) return RecordStatus.skipped;
    }
    final own = _featureOf(item)?.name;
    for (final (:feature, :entries) in records) {
      if (feature != own) continue;
      final relative = _relativeTo(item, feature);
      for (final entry in entries) {
        if (entry.item == relative) return entry.status ?? RecordStatus.planned;
      }
    }
    return RecordStatus.planned;
  }

  String? _namedOrGiven(String? codeTarget) =>
      codeTarget ?? (_targets.length == 1 ? _targets.single.name : null);

  /// The records of [doc]'s feature and of each feature above it in
  /// [codeTarget], nearest feature first.
  List<({String feature, List<RecordEntry> entries})> _recordsOf(
    IndexedDoc doc,
    String? codeTarget,
  ) {
    final recordType = _set.recordDocType;
    if (recordType == null) return const [];
    return [
      for (IndexedDoc? member = doc; member != null; member = _parentOf(member))
        if (member.docTypeId == featureType)
          for (final record
              in _records[(member.name, codeTarget)] ?? const <IndexedDoc>[])
            (
              feature: member.name,
              entries: recordEntriesOf(record, recordType),
            ),
    ];
  }

  IndexedDoc? _featureOf(IndexedDoc doc) {
    for (IndexedDoc? member = doc; member != null; member = _parentOf(member)) {
      if (member.docTypeId == featureType) return member;
    }
    return null;
  }

  static String _relativeTo(IndexedDoc item, String feature) =>
      item.name.startsWith('$feature/')
      ? item.name.substring(feature.length + 1)
      : item.name;

  IndexedDoc? _parentOf(IndexedDoc doc) => _byPath[_parents[doc.docPath]];

  List<IndexedDoc> _childrenOf(IndexedDoc doc) =>
      _children[doc.docPath] ?? const [];
}

/// Returns the frontmatter values of [lf], none when it is not valid YAML.
Map<String, Object?> _valuesOf(String lf) {
  try {
    return frontmatterValuesOf(Doc.parse(lf));
  } on YamlException {
    return const {};
  }
}

// MARK: - Writing

/// Returns [lf] with each value of each field of [stamped] replaced by the
/// value it maps to, its quotes and every other byte kept.
String _withValues(String lf, Map<String, Map<String, String>> stamped) {
  var text = lf;
  for (final MapEntry(key: field, value: values) in stamped.entries) {
    final block = Doc.parse(text).frontmatter
        ?.where((candidate) => candidate.name == field)
        .firstOrNull;
    if (block == null) continue;
    final written = _withScalars(block.text, field, values);
    if (written != block.text) text = withKeyBlock(text, field, written);
  }
  return text;
}

/// Returns the key block [text] of [field] with each scalar whose value
/// [values] maps rewritten in place.
String _withScalars(String text, String field, Map<String, String> values) {
  final node = switch (loadYamlNode(text)) {
    YamlMap(:final nodes) => nodes[field],
    _ => null,
  };
  final scalars = switch (node) {
    final YamlList list => list.nodes.whereType<YamlScalar>(),
    final YamlScalar scalar => [scalar],
    _ => const <YamlScalar>[],
  };
  final edits = [
    for (final scalar in scalars)
      if (scalar.value case final String old)
        if (values[old] case final value?) ?_tailEdit(text, scalar, old, value),
  ]..sort((a, b) => b.start.compareTo(a.start));
  var result = text;
  for (final (:start, :end, :source) in edits) {
    result = result.replaceRange(start, end, source);
  }
  return result;
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
