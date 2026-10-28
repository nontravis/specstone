import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';

final _asciiDigits = RegExp(r'^[0-9]+$');

/// What one read command prints: its text form and its JSON form.
final class ReadAnswer {
  const new({
    required this.text,
    required this.json,
    this.warnings = const [],
    this.exitStatus = 0,
  });

  /// The text printed on `out` without `--json`.
  final String text;

  /// The object printed on `out` under `--json`, before `warnings` joins it.
  final Map<String, Object> json;

  /// Warnings the answer adds to the session's.
  final List<String> warnings;

  /// The process exit status of the command.
  final int exitStatus;
}

/// Returns `<name> (<doc type>)` for [doc], or its name alone when untyped.
String nameWithType(IndexedDoc doc) {
  final typeId = doc.docTypeId;
  return typeId == null ? doc.name : '${doc.name} ($typeId)';
}

/// Returns the line that heads the text of [doc] in `get`, `refs`, and
/// `context`: `==> <name> (<doc type>) · <DocPath> <==`.
///
/// A [base] adds ` · base <base>` before the closing ` <==`.
String namingLine(IndexedDoc doc, {String? base}) =>
    '==> ${nameWithType(doc)} · ${doc.docPath}'
    '${base == null ? '' : ' · base $base'} <==';

/// Returns the one-line description of [doc].
///
/// It is the name with its doc type, ` — <title>` when there is one, then
/// ` · ` and its status, `draft`, and size in tokens, each when it applies.
String docLine(DocIndex index, IndexedDoc doc) {
  final title = doc.title;
  final status = index.statusOf(doc);
  final parts = [?status, if (doc.isDraft) 'draft', '${doc.tokens} tokens'];
  return '${nameWithType(doc)}${title == null ? '' : ' — $title'}'
      ' · ${parts.join(' · ')}';
}

/// Returns the JSON object describing [doc], leaving out each absent key.
Map<String, Object> docJson(DocIndex index, IndexedDoc doc) {
  final typeId = doc.docTypeId;
  final title = doc.title;
  final status = index.statusOf(doc);
  return {
    'name': doc.name,
    'docType': ?typeId,
    'path': doc.docPath,
    'title': ?title,
    'status': ?status,
    'draft': doc.isDraft,
    'tokens': doc.tokens,
  };
}

/// Returns the fault for a command given no [what].
///
/// The message reads `<command> needs <what>, such as <example>`.
IndexFault missingArgument(String command, String what, String example) =>
    IndexFault(
      IndexFaultCode.argumentMissing,
      '$command needs $what, such as $example',
    );

/// Returns [value] as the positive integer [option] takes, or null for null.
///
/// Throws an [IndexFault] unless [value] is ASCII digits worth at least 1.
int? parsePositiveOption(String option, String? value) {
  if (value == null) return null;
  final parsed = _asciiDigits.hasMatch(value) ? int.tryParse(value) : null;
  if (parsed == null || parsed < 1) {
    throw IndexFault(
      IndexFaultCode.argumentInvalid,
      '$option takes a positive integer, not $value',
    );
  }
  return parsed;
}
