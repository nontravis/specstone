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

const _namingOpen = '==> ';
const _namingClose = ' <==';
const _namingSeparator = ' · ';
const _namingFieldPart = 'field ';
const _namingTitlePart = 'title';
const _namingBasePart = 'base ';
const _namingUnchangedPart = 'unchanged';
const _namingSummaryPart = 'summary';

final _baseHash = RegExp(r'^[0-9a-f]{12}$');
final _lineEndBlanks = RegExp(r'[ \t]+$');

/// Returns the line that heads the text of [doc] in `get`, `set`, `refs`, and
/// `context`: `==> <name> (<doc type>) · <DocPath> <==`.
///
/// The path part names the target a [base] belongs to: `<DocPath>#<sectionKey>`
/// for a section (`_lead` for the lead), else `<DocPath>`; a [fieldId] adds
/// ` · field <id>` and a [title] adds ` · title`, at most one of the three.
/// A [base] adds ` · base <base>`, [unchanged] adds ` · unchanged`, and
/// [summary] adds ` · summary`, in that order before the closing ` <==`.
String namingLine(
  IndexedDoc doc, {
  String? sectionKey,
  String? fieldId,
  bool title = false,
  String? base,
  bool unchanged = false,
  bool summary = false,
}) {
  assert(
    [sectionKey != null, fieldId != null, title].where((set) => set).length <=
        1,
    'a naming line names one target: a section, a field, or the title',
  );
  final path = sectionKey == null ? doc.docPath : '${doc.docPath}#$sectionKey';
  return '$_namingOpen${nameWithType(doc)}$_namingSeparator$path'
      '${fieldId == null ? '' : '$_namingSeparator$_namingFieldPart$fieldId'}'
      '${title ? '$_namingSeparator$_namingTitlePart' : ''}'
      '${base == null ? '' : '$_namingSeparator$_namingBasePart$base'}'
      '${unchanged ? '$_namingSeparator$_namingUnchangedPart' : ''}'
      '${summary ? '$_namingSeparator$_namingSummaryPart' : ''}$_namingClose';
}

/// What [readNamingLine] reads from a naming line.
final class NamingLine {
  const new({
    required this.path,
    this.base,
    this.fieldId,
    this.isTitle = false,
  });

  /// The path part as written, with any `#<key>`.
  final String path;

  /// The base hash when the line ends in ` · base <hash>`, else null.
  final String? base;

  /// The id of a ` · field <id>` part, else null.
  final String? fieldId;

  /// Whether the line has a ` · title` part.
  final bool isTitle;
}

/// Returns what [line], its trailing spaces and tabs dropped, names, or null
/// when it is no naming line.
///
/// A naming line opens `==> ` at column 0 and closes ` <==`. Its `path` is the
/// second ` · `-separated part, or the whole text between the arrows when
/// there is none (a guide's `==> <type> <==`). The `base` is set only when the
/// last part is `base ` and 12 lowercase hex characters, so a ` · unchanged`
/// or ` · summary` tail leaves it null.
NamingLine? readNamingLine(String line) {
  final text = line.replaceFirst(_lineEndBlanks, '');
  if (text.length < _namingOpen.length + _namingClose.length ||
      !text.startsWith(_namingOpen) ||
      !text.endsWith(_namingClose)) {
    return null;
  }
  final inner = text.substring(
    _namingOpen.length,
    text.length - _namingClose.length,
  );
  final parts = inner.split(_namingSeparator);
  if (parts.length < 2) return NamingLine(path: inner);

  String? fieldId;
  var isTitle = false;
  for (final part in parts.skip(2)) {
    if (part.startsWith(_namingFieldPart) &&
        part.length > _namingFieldPart.length) {
      fieldId = part.substring(_namingFieldPart.length);
    } else if (part == _namingTitlePart) {
      isTitle = true;
    }
  }
  final last = parts.last;
  final hash = parts.length > 2 && last.startsWith(_namingBasePart)
      ? last.substring(_namingBasePart.length)
      : null;
  return NamingLine(
    path: parts[1],
    base: hash != null && _baseHash.hasMatch(hash) ? hash : null,
    fieldId: fieldId,
    isTitle: isTitle,
  );
}

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
