import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/consistency_check/code_link_rules.dart'
    show currentCodeFingerprint;
import 'package:specstone_core/src/consistency_check/code_rules.dart'
    show namesFileOrFolderFrom, ownerTargetOf;
import 'package:specstone_core/src/consistency_check/finding.dart'
    show FindingKind;
import 'package:specstone_core/src/consistency_check/implements_entry.dart';
import 'package:specstone_core/src/consistency_check/implements_rule.dart'
    show unresolvedSymbolOf;
import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_splice.dart'
    show isFingerprint, withKeyBlock;
import 'package:specstone_core/src/doc_model/doc_type_matcher.dart';
import 'package:specstone_core/src/doc_model/list_block_writer.dart';
import 'package:specstone_core/src/document_writing/set_doc.dart'
    show readLocked;
import 'package:specstone_core/src/document_writing/stamp_fault.dart';
import 'package:specstone_core/src/document_writing/write_fault.dart';
import 'package:specstone_core/src/document_writing/write_session.dart';
import 'package:specstone_core/src/index_query/code_root_files.dart'
    show isEmptyCodeEntry, normalCodeEntry;
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';
import 'package:specstone_core/src/index_query/record_entries.dart'
    show recordCodeFieldOf, recordCodeLineOf;
import 'package:specstone_core/src/rendering/models/line_ending.dart';
import 'package:specstone_core/src/templates/code_link_entry.dart';
import 'package:specstone_core/src/templates/code_target.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';

const _pairMark = '=';
const _addressExample = 'architecture:login';
const _stampExample = '--stamp <entry>=<fingerprint>';

// MARK: - Request

/// One `--stamp` argument: an entry and the code fingerprint judged for it.
final class StampPair {
  const new({required this.entry, required this.fingerprint});

  /// The entry's text before its fingerprint, as the doc holds it.
  final String entry;

  /// The 12 lowercase hex characters the Agent judged.
  final String fingerprint;
}

/// The checked arguments of one `set --stamp` call.
final class StampRequest {
  const new({required this.address, required this.stamps, this.codeTarget});

  /// Reads the arguments of `set --stamp`.
  ///
  /// Each of [stampArgs] splits on its last `=`, since an entry may hold `:`
  /// and `=` and a fingerprint never does. [codeTarget] keeps the doc's name
  /// to that code target's docs and the shared docs.
  /// Throws [IndexFault] `argument_missing` for a missing [address] and
  /// `argument_invalid` for an argument with no `=` or a fingerprint that is
  /// not 12 lowercase hex characters, and `argument_missing` for no
  /// [stampArgs].
  static StampRequest parse(
    String? address,
    List<String> stampArgs, {
    String? codeTarget,
  }) {
    if (address == null) {
      throw missingArgument('set', 'a doc address', _addressExample);
    }
    if (stampArgs.isEmpty) {
      throw missingArgument('set', '--stamp', _stampExample);
    }
    return StampRequest(
      address: address,
      stamps: [for (final argument in stampArgs) _pairOf(argument)],
      codeTarget: codeTarget,
    );
  }

  /// The doc as `<type>:<name>`.
  final String address;

  /// The stamps in the order the call gave them.
  final List<StampPair> stamps;

  /// The code target [address] is kept to; null keeps every target.
  final String? codeTarget;
}

StampPair _pairOf(String argument) {
  final at = argument.lastIndexOf(_pairMark);
  final fingerprint = at < 0 ? null : argument.substring(at + 1);
  if (fingerprint == null || !isFingerprint(fingerprint)) {
    throw IndexFault(
      IndexFaultCode.argumentInvalid,
      '--stamp takes <entry>=<fingerprint>, 12 lowercase hex characters '
      'after the last =; got "$argument"',
    );
  }
  return StampPair(entry: argument.substring(0, at), fingerprint: fingerprint);
}

// MARK: - Answer

/// Ends each entry of a doc that [request] names with its judged code
/// fingerprint, in one write, and prints how many were stamped.
///
/// An entry is matched whole against the doc's `covers`-like fields and its
/// record `implements` field, whatever its item's status or wait. Every stamp
/// is judged before any write, so a refused call writes nothing. The draft
/// flag stays as it was, and every other byte of the doc is kept.
/// Throws [StampFault] holding each refused entry, [IndexFault] for the doc,
/// and [WriteFault] `migrate_pending`.
ReadAnswer answerStamp(WriteSession session, StampRequest request) {
  final doc = session.target(request.address, codeTarget: request.codeTarget);
  final docType =
      session.index.typeOf(doc) ??
      (throw StateError('${doc.docPath} is typed but its type is gone'));
  final address = session.index.addressOf(doc);
  final code = _CodeJudge(session, ownerTargetOf(doc, session.project.targets));
  final stamped = {for (final pair in request.stamps) pair.entry}.toList();
  return session.locked(() {
    final locked = readLocked(session, doc, MatchedDocType(docType));
    final fields = _stampFieldsOf(locked.lfText, docType);
    final refusals = <StampRefusal>[];
    for (final pair in request.stamps) {
      if (_holdsEntry(fields, pair)) {
        refusals.addAll(_stamp(pair, fields, code));
      } else {
        refusals.add(_unknown(pair, address));
      }
    }
    if (refusals.isNotEmpty) throw StampFault(refusals);
    session.writeDoc(
      doc.docPath,
      _withStamps(locked.lfText, fields),
      LineEnding.of(locked.parsed.content.text),
    );
    return ReadAnswer(
      text: '$address: ${stamped.length} stamped\n',
      json: {'doc': address, 'stamped': stamped},
    );
  });
}

StampRefusal _unknown(StampPair pair, String address) => StampRefusal(
  entry: pair.entry,
  code: WriteFaultCode.stampEntryUnknown,
  message: 'no entry of $address reads ${pair.entry}',
);

// MARK: - Fields

/// A `covers`-like or record code field of the doc, with its entries as the
/// doc holds them.
final class _StampField {
  new(this.field, this.block, this.entries);

  final MergedField field;
  final KeyBlock block;

  /// The block's entries; a stamped one is replaced in place.
  final List<Object?> entries;

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

  /// The finding `check` gives an entry of this field whose path is gone.
  FindingKind get pathFinding => isRecord
      ? FindingKind.implementsPathUnresolved
      : FindingKind.coversPathMissing;
}

List<_StampField> _stampFieldsOf(String lfText, MergedDocType docType) {
  final blocks = Doc.parse(lfText).frontmatter ?? const <KeyBlock>[];
  return [
    for (final field in [
      ...coversFieldsOf(docType),
      ?recordCodeFieldOf(docType),
    ])
      if (blocks.where((block) => block.name == field.id).firstOrNull
          case final block?)
        if (listEntriesOf(block) case final entries?)
          _StampField(field, block, entries),
  ];
}

bool _holdsEntry(List<_StampField> fields, StampPair pair) => fields.any(
  (field) => field.entries.any(
    (entry) => entry is String && CodeLinkEntry(entry).pointer == pair.entry,
  ),
);

/// Stamps each entry of [fields] that [pair] names whole and returns the
/// refusal of each that cannot take it.
List<StampRefusal> _stamp(
  StampPair pair,
  List<_StampField> fields,
  _CodeJudge code,
) {
  final refusals = <StampRefusal>[];
  for (final field in fields) {
    for (final (at, value) in field.entries.indexed) {
      if (value is! String || CodeLinkEntry(value).pointer != pair.entry) {
        continue;
      }
      final refusal = code.refusalOf(field, pair);
      if (refusal != null) {
        refusals.add(refusal);
        continue;
      }
      field.entries[at] = codeLinkEntryOf(pair.entry, pair.fingerprint);
      field.isStamped = true;
    }
  }
  return refusals;
}

/// Returns [lfText] with each stamped field written back through the list
/// writer over its block on disk, so kept entries stay byte for byte and no
/// draft mark moves.
String _withStamps(String lfText, List<_StampField> fields) {
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

// MARK: - Code

/// Judges an entry against the code it names, by the helpers `check` reads it
/// with, so a stamp refuses what `check` reports and never writes a
/// fingerprint `check` would call stale.
final class _CodeJudge {
  new(this._session, this._target);

  final WriteSession _session;

  /// The target the doc's entries read from; null for a doc of none.
  final CodeTarget? _target;

  /// Returns the refusal of [pair] on an entry of [field], null when the
  /// entry resolves and its code fingerprints as [pair] says.
  StampRefusal? refusalOf(_StampField field, StampPair pair) {
    final root = _rootOf(field.field);
    if (root == null) {
      return _unresolved(pair, FindingKind.sharedDocCodePath.wire);
    }
    final unresolved = _unresolvedKind(field, pair.entry, root);
    if (unresolved != null) return _unresolved(pair, unresolved.wire);
    final current = currentCodeFingerprint(
      field.pathOf(pair.entry),
      codeRoot: root,
      nestedRoots: _nestedRootsOf(field.field),
      bytesOf: (file) => _bytesOf(root, file),
      onUnlistable: (_) {},
    );
    if (current == null) {
      return _unresolved(pair, FindingKind.fileUnreadable.wire);
    }
    if (current == pair.fingerprint) return null;
    return StampRefusal(
      entry: pair.entry,
      code: WriteFaultCode.stampStale,
      message:
          '${pair.entry} changed after ${pair.fingerprint}; '
          'judge it again',
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
    _StampField field,
    String entry,
    Directory root,
  ) {
    if (!field.isRecord) {
      if (isEmptyCodeEntry(entry)) return FindingKind.coversEntryEmpty;
      return namesFileOrFolderFrom(root, entry) ? null : field.pathFinding;
    }
    final code = ImplementsEntry(field.codeOf(entry));
    if (!code.namesFileFrom(root)) return field.pathFinding;
    final bytes = _bytesOf(root, normalCodeEntry(code.path));
    if (bytes == null) return null;
    final text = const Utf8Decoder(allowMalformed: true).convert(bytes);
    return unresolvedSymbolOf(code.text, text) == null
        ? null
        : FindingKind.implementsSymbolUnresolved;
  }
}

StampRefusal _unresolved(StampPair pair, String reason) => StampRefusal(
  entry: pair.entry,
  code: WriteFaultCode.stampEntryUnresolved,
  message: '${pair.entry} does not resolve: $reason',
);

List<int>? _bytesOf(Directory root, String file) {
  try {
    return File('${root.path}/$file').readAsBytesSync();
  } on FileSystemException {
    return null;
  }
}
