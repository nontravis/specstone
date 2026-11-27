import 'package:specstone_core/src/consistency_check/code_rules.dart'
    show ownerTargetOf;
import 'package:specstone_core/src/consistency_check/exact_case_path.dart'
    show ExactCasePaths;
import 'package:specstone_core/src/doc_model/doc_splice.dart'
    show isFingerprint;
import 'package:specstone_core/src/doc_model/doc_type_matcher.dart';
import 'package:specstone_core/src/document_writing/code_judge.dart';
import 'package:specstone_core/src/document_writing/set_doc.dart'
    show readLocked;
import 'package:specstone_core/src/document_writing/stamp_fault.dart';
import 'package:specstone_core/src/document_writing/write_fault.dart';
import 'package:specstone_core/src/document_writing/write_session.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';
import 'package:specstone_core/src/rendering/models/line_ending.dart';
import 'package:specstone_core/src/templates/code_link_entry.dart';

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
/// flag stays as it was, and every other byte of the doc is kept. The json
/// holds one `docs` element: name, docType, path, and the stamped entries.
/// Throws [StampFault] holding each refused entry, [IndexFault] for the doc,
/// and [WriteFault] `migrate_pending`.
ReadAnswer answerStamp(WriteSession session, StampRequest request) {
  final doc = session.target(request.address, codeTarget: request.codeTarget);
  final docType =
      session.index.typeOf(doc) ??
      (throw StateError('${doc.docPath} is typed but its type is gone'));
  final address = session.index.addressOf(doc);
  final code = CodeJudge(
    session,
    ownerTargetOf(doc, session.project.targets),
    ExactCasePaths(),
  );
  final stamped = {for (final pair in request.stamps) pair.entry}.toList();
  return session.locked(() {
    final locked = readLocked(session, doc, MatchedDocType(docType));
    final fields = stampFieldsOf(locked.lfText, stampableFieldsOf(docType));
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
      withStampedFields(locked.lfText, fields),
      LineEnding.of(locked.parsed.content.text),
    );
    return ReadAnswer(
      text: '$address: ${stamped.length} stamped\n',
      json: {
        'docs': [
          {
            'name': doc.name,
            'docType': docType.id,
            'path': doc.docPath,
            'stamped': stamped,
          },
        ],
      },
    );
  });
}

StampRefusal _unknown(StampPair pair, String address) => StampRefusal(
  entry: pair.entry,
  code: WriteFaultCode.stampEntryUnknown,
  message: 'no entry of $address reads ${pair.entry}',
);

// MARK: - Fields

bool _holdsEntry(List<StampField> fields, StampPair pair) => fields.any(
  (field) => field.entries.any(
    (entry) => entry is String && CodeLinkEntry(entry).pointer == pair.entry,
  ),
);

/// Stamps each entry of [fields] that [pair] names whole and returns the
/// refusal of each that cannot take it.
List<StampRefusal> _stamp(
  StampPair pair,
  List<StampField> fields,
  CodeJudge code,
) {
  final refusals = <StampRefusal>[];
  for (final field in fields) {
    for (final (at, value) in field.entries.indexed) {
      if (value is! String || CodeLinkEntry(value).pointer != pair.entry) {
        continue;
      }
      final refusal = code.refusalOf(field, pair.entry, pair.fingerprint);
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
