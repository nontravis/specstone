import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/consistency_check/code_link_rules.dart'
    show currentCodeFingerprint;
import 'package:specstone_core/src/consistency_check/code_rules.dart'
    show CodePathField, codePathFindingOf, readPathOf;
import 'package:specstone_core/src/consistency_check/exact_case_path.dart';
import 'package:specstone_core/src/consistency_check/finding.dart'
    show FindingKind;
import 'package:specstone_core/src/consistency_check/implements_entry.dart';
import 'package:specstone_core/src/consistency_check/implements_rule.dart'
    show unresolvedSymbolOf;
import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_splice.dart' show withKeyBlock;
import 'package:specstone_core/src/doc_model/list_block_writer.dart';
import 'package:specstone_core/src/document_writing/stamp_fault.dart';
import 'package:specstone_core/src/document_writing/write_fault.dart';
import 'package:specstone_core/src/document_writing/write_session.dart';
import 'package:specstone_core/src/index_query/record_entries.dart'
    show recordCodeFieldOf, recordCodeLineOf;
import 'package:specstone_core/src/templates/code_link_entry.dart';
import 'package:specstone_core/src/templates/code_target.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';

// MARK: - Fields

/// A `covers`-like or record field of a doc, with its entries as the doc
/// holds them.
final class StampField {
  new(this.field, this.block, this.entries);

  final MergedField field;
  final KeyBlock block;

  /// The block's entries; a stamped one is replaced in place.
  final List<Object?> entries;

  /// Whether an entry was replaced, so [withStampedFields] writes the block.
  bool isStamped = false;

  /// Whether the field is a record's `implements`, whose entries lead with
  /// their item.
  bool get isRecord => field.pointer == PointerKind.itemExact;

  /// Returns the `path[:Symbol]` of the record [entry], or [entry] itself
  /// when it names no item.
  String codeOf(String entry) => recordCodeLineOf(entry)?.code ?? entry;

  /// Returns the file or folder [entry] names, from its root.
  String pathOf(String entry) =>
      isRecord ? ImplementsEntry(codeOf(entry)).path : entry;

  /// The field `check` reads an entry of this one as.
  CodePathField get pathField =>
      isRecord ? CodePathField.implements : CodePathField.covers;
}

/// Returns the fields of [docType] a stamp reads: its `covers`-like fields,
/// then its record `implements`.
List<MergedField> stampableFieldsOf(MergedDocType docType) => [
  ...coversFieldsOf(docType),
  ?recordCodeFieldOf(docType),
];

/// Returns each of [fields] that [lfText] holds as a list block, in [fields]
/// order.
List<StampField> stampFieldsOf(String lfText, List<MergedField> fields) {
  final blocks = Doc.parse(lfText).frontmatter ?? const <KeyBlock>[];
  return [
    for (final field in fields)
      if (blocks.where((block) => block.name == field.id).firstOrNull
          case final block?)
        if (listEntriesOf(block) case final entries?)
          StampField(field, block, entries),
  ];
}

/// Returns [lfText] with each stamped field written back through the list
/// writer over its block on disk, so kept entries stay byte for byte and no
/// draft mark moves.
String withStampedFields(String lfText, List<StampField> fields) {
  var text = lfText;
  for (final field in fields.where((field) => field.isStamped)) {
    text = withKeyBlock(
      text,
      field.field.id,
      listBlockOf(field.field.id, field.entries, onDisk: field.block),
    );
  }
  return text;
}

// MARK: - Judge

/// Judges an entry against the code it names, by the helpers `check` reads it
/// with, so a stamp refuses what `check` reports and never writes a
/// fingerprint `check` would call stale.
final class CodeJudge {
  new(this._session, this._target, this._paths);

  final WriteSession _session;

  /// The resolver of every entry, one per run so each folder is listed once.
  final ExactCasePaths _paths;

  /// The target the doc's entries read from; null for a doc of none.
  final CodeTarget? _target;

  /// Returns the refusal of [fingerprint] on [entry] of [field], null when the
  /// entry resolves and its code fingerprints as [fingerprint].
  StampRefusal? refusalOf(StampField field, String entry, String fingerprint) {
    final root = _rootOf(field.field);
    if (root == null) {
      return _unresolved(entry, FindingKind.sharedDocCodePath.wire);
    }
    final verdict = _paths.resolve(root, field.pathOf(entry));
    final unresolved = _unresolvedKind(field, entry, root, verdict);
    if (unresolved != null) return _unresolved(entry, unresolved.wire);
    final current = currentCodeFingerprint(
      readPathOf(field.pathOf(entry), verdict.diskPath!),
      codeRoot: root,
      nestedRoots: _nestedRootsOf(field.field),
      bytesOf: (file) => _bytesOf(root, file),
      onUnlistable: (_) {},
    );
    if (current == null) {
      return _unresolved(entry, FindingKind.fileUnreadable.wire);
    }
    if (current == fingerprint) return null;
    return StampRefusal(
      entry: entry,
      code: WriteFaultCode.stampStale,
      message: '$entry changed after $fingerprint; judge it again',
    );
  }

  Directory? _rootOf(MergedField field) {
    if (readsFromProjectRoot(field)) return _session.project.projectRoot;
    final target = _target;
    return target == null ? null : _session.project.codeRootOf(target);
  }

  List<String> _nestedRootsOf(MergedField field) {
    final target = _target;
    return readsFromProjectRoot(field) || target == null
        ? const []
        : _session.project.nestedRootsOf(target);
  }

  FindingKind? _unresolvedKind(
    StampField field,
    String entry,
    Directory root,
    CodePathVerdict verdict,
  ) {
    final kind = codePathFindingOf(field.pathField, verdict);
    if (kind != null || !field.isRecord) return kind;
    final code = field.codeOf(entry);
    if (CodePointer(code).fault == CodePointerFault.emptyTail) {
      return FindingKind.implementsSymbolUnresolved;
    }
    final bytes = _bytesOf(root, verdict.diskPath!);
    if (bytes == null) return null;
    final text = const Utf8Decoder(allowMalformed: true).convert(bytes);
    return unresolvedSymbolOf(code, text) == null
        ? null
        : FindingKind.implementsSymbolUnresolved;
  }
}

StampRefusal _unresolved(String entry, String reason) => StampRefusal(
  entry: entry,
  code: WriteFaultCode.stampEntryUnresolved,
  message: '$entry does not resolve: $reason',
);

List<int>? _bytesOf(Directory root, String file) {
  try {
    return File('${root.path}/$file').readAsBytesSync();
  } on FileSystemException {
    return null;
  }
}
