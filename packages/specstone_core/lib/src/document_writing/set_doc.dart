import 'dart:convert';

import 'package:specstone_core/src/consistency_check/frontmatter_rules.dart'
    show fieldTakesItem, recordStatusLineShape;
import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_splice.dart';
import 'package:specstone_core/src/doc_model/doc_type_matcher.dart';
import 'package:specstone_core/src/doc_model/reference_grammar.dart';
import 'package:specstone_core/src/document_writing/write_fault.dart';
import 'package:specstone_core/src/document_writing/write_session.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/get_docs.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';
import 'package:specstone_core/src/rendering/line_ending.dart';
import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:yaml/yaml.dart';

const _targetExample =
    'specstone set user_story:login/email_login#use_case '
    '--base 3f9a1c0b7e21';

/// What a `set` call writes: a section, a frontmatter field, the title, or the
/// lead.
sealed class SetTarget {
  const new();
}

/// The section keyed [key].
final class SectionTarget extends SetTarget {
  const new(this.key);

  /// The template section id, else the [sectionKeyOf] key of the header.
  final String key;
}

/// The frontmatter field [fieldId].
final class FieldTarget extends SetTarget {
  const new(this.fieldId);

  /// The template field id.
  final String fieldId;
}

/// The lead: the head text after the title line.
final class LeadTarget extends SetTarget {
  const new();
}

/// The title line.
final class TitleTarget extends SetTarget {
  const new();
}

/// The checked arguments of one `set` call.
final class SetRequest {
  const new({
    required this.address,
    required this.target,
    required this.base,
    this.codeTarget,
  });

  /// Reads the arguments of `set`.
  ///
  /// [target] is `<type>:<name>[#<key>]`; [field] and [title] are the other
  /// two targets, and exactly one of the three must be given.
  /// With an [index], a [target] that names a doc as a path has no section
  /// key, even when it holds `#`. [codeTarget] keeps the doc's name to that
  /// code target's docs and the shared docs.
  /// Throws [IndexFault] `argument_missing` for a missing target, section
  /// key, or [base], and `argument_conflict` for two targets at once.
  static SetRequest parse(
    String? target, {
    String? field,
    bool title = false,
    String? base,
    DocIndex? index,
    String? codeTarget,
  }) {
    final (target: written, base: checkedBase) = requireShape(target, base);
    final (:docPart, sectionKey: key) = index == null
        ? _splitAsWritten(written)
        : index.splitAddress(written);
    final sectionKey = key == null || key.isEmpty ? null : key;
    final targets = [?sectionKey, ?field, if (title) ''];
    if (targets.length > 1) {
      throw IndexFault(
        IndexFaultCode.argumentConflict,
        'set takes one target: a section key, --field, or --title',
      );
    }
    final SetTarget chosen;
    if (sectionKey == leadKey) {
      chosen = const LeadTarget();
    } else if (sectionKey != null) {
      chosen = SectionTarget(sectionKey);
    } else if (field != null) {
      chosen = FieldTarget(field);
    } else if (title) {
      chosen = const TitleTarget();
    } else {
      throw missingArgument(
        'set',
        'a section key, --field, or --title',
        _targetExample,
      );
    }
    return SetRequest(
      address: docPart,
      target: chosen,
      base: checkedBase,
      codeTarget: codeTarget,
    );
  }

  /// Returns [target] and [base] when both are given; throws [IndexFault]
  /// `argument_missing` otherwise.
  ///
  /// Needs no index, so a command calls it before it reads stdin.
  static ({String target, String base}) requireShape(
    String? target,
    String? base,
  ) {
    if (target == null) {
      throw missingArgument('set', 'a target', _targetExample);
    }
    if (base == null) throw missingArgument('set', '--base', _targetExample);
    return (target: target, base: base);
  }

  static ({String docPart, String? sectionKey}) _splitAsWritten(String text) {
    final read = readDocAddress(text);
    return (docPart: read.docPart, sectionKey: read.sectionKey);
  }

  /// The doc as `<type>:<name>`.
  final String address;

  /// What to write.
  final SetTarget target;

  /// The base hash of [target] the caller last read.
  final String base;

  /// The code target [address] is kept to; null keeps every target.
  final String? codeTarget;
}

/// Returns [lfText] as a draft: unchanged when it is one, else with
/// `draft: true` added to its frontmatter.
///
/// The key lands at its slot in [docType]'s field order, as [withKeyBlock]
/// reads it, so `set` and `new` place it alike and no key moves.
String markDraft(String lfText, MergedDocType docType) =>
    Doc.parse(lfText).isDraft
    ? lfText
    : withKeyBlock(
        lfText,
        'draft',
        'draft: true\n',
        fieldOrder: [for (final field in docType.fields) field.id],
      );

/// Writes [text] to the target of [request] and prints the doc's new base.
///
/// The write runs under the session lock against a fresh read of the file,
/// so a target changed since [SetRequest.base] refuses with its current text.
/// A section body is written as [text] gives it, leading blank lines
/// included, so a `get` then `set` of unchanged text changes no byte; its
/// trailing blank lines are spacing and are dropped. An empty [text] removes
/// an optional section or field; a field key the doc holds that its type does
/// not declare is removed too. The lead is written as a section body, and
/// empty [text] empties it. Throws [IndexFault] for a body that holds a
/// `## ` line, a lead that holds a `# ` line, a doc, section, or field that is
/// not there, a title that is not one line, and [WriteFault] `base_mismatch`,
/// `required_target`, or a refused field.
ReadAnswer answerSet(WriteSession session, SetRequest request, String text) {
  final doc = session.target(request.address, codeTarget: request.codeTarget);
  final docType =
      session.index.typeOf(doc) ??
      (throw StateError('${doc.docPath} is typed but its type is gone'));
  final match = MatchedDocType(docType);
  checkPartText(doc: doc, docType: docType, target: request.target, text: text);

  return session.locked(() {
    final read = readLocked(session, doc, match).parsed;
    final part = splicePart(
      doc: doc,
      docType: docType,
      lfText: toLf(read.content.text),
      sections: read.content.sections,
      target: request.target,
      base: request.base,
      text: text,
    );
    final written = session.writeDoc(
      doc.docPath,
      part.marksDraft ? markDraft(part.lfText, docType) : part.lfText,
      LineEnding.of(read.content.text),
    );

    final after = parseIndexedDoc(
      docPath: doc.docPath,
      bytes: utf8.encode(written),
      match: match,
    );
    final base = _baseAfter(after, request.target, docType);
    return ReadAnswer(
      text: '${_namingLineOf(doc, request.target, base)}\n',
      json: {
        'name': doc.name,
        'docType': ?doc.docTypeId,
        'path': doc.docPath,
        'base': base,
        'draft': after.doc.isDraft,
      },
    );
  });
}

/// Checks [text] against the part [target] names in [lfText] and splices it
/// in, as a single `set` does.
///
/// [lfText] is the doc's text with LF line ends as read under the write lock,
/// [sections] its sections, and [base] the hash of the part the caller read.
/// `lfText` of the result is the spliced text and `marksDraft` tells whether
/// the write marks the doc a draft: false only for an `output_ref` field.
/// Touches no disk and takes no lock. Runs [checkPartText] first, then throws
/// what [answerSet] throws for the part, [WriteFault] `base_mismatch` with the
/// part's current text included.
({String lfText, bool marksDraft}) splicePart({
  required IndexedDoc doc,
  required MergedDocType docType,
  required String lfText,
  required List<IndexedSection> sections,
  required SetTarget target,
  required String base,
  required String text,
}) {
  checkPartText(doc: doc, docType: docType, target: target, text: text);
  final stdin = toLf(text);
  return switch (target) {
    SectionTarget(:final key) => _spliceSection(
      doc: doc,
      docType: docType,
      lfText: lfText,
      sections: sections,
      key: key,
      base: base,
      stdin: stdin,
    ),
    FieldTarget(:final fieldId) => _spliceField(
      doc: doc,
      docType: docType,
      lfText: lfText,
      fieldId: fieldId,
      base: base,
      stdin: stdin,
    ),
    TitleTarget() => _spliceTitle(doc, lfText, base, stdin),
    LeadTarget() => _spliceLead(doc, docType, lfText, base, stdin),
  };
}

/// Checks [text] against the part [target] names in [doc], as far as the
/// text and the doc type decide, throwing the fault `set` refuses it with.
///
/// Needs no doc text, so a caller runs it before it takes the write lock;
/// [splicePart] runs it too. What the doc's text decides stays in
/// [splicePart]: a first line that may be the section's own header, a held
/// key, a stale base, and the section lookup. Throws [IndexFault]
/// `argument_invalid` for an open fence, a `## ` line after a section body's
/// first line, a lead that holds a `# ` or `## ` line, a section or lead
/// that holds a naming line (see [refuseNamingLine]), and a title that is not
/// one line, and the faults of [checkFieldWrite] for a field.
void checkPartText({
  required IndexedDoc doc,
  required MergedDocType docType,
  required SetTarget target,
  required String text,
}) {
  final lf = toLf(text);
  switch (target) {
    case SectionTarget():
      _checkSectionText(lf);
    case LeadTarget():
      _checkLeadText(lf);
    case TitleTarget():
      _titleOf(lf);
    case FieldTarget(:final fieldId):
      // The held key decides only an emptied key the type does not declare;
      // `splicePart` checks it against the doc's text.
      checkFieldWrite(
        doc: doc,
        docType: docType,
        fieldId: fieldId,
        value: _fieldValueOf(lf),
        held: true,
      );
  }
}

/// Checks that [doc] may take [value] as the YAML of [fieldId], throwing the
/// fault `set` refuses it with.
///
/// A null [value] removes the key; [held] tells whether the doc holds the key
/// now. Throws [WriteFault] `field_not_writable` for `draft`, `approved`, or a
/// value for a feature's computed status, `field_unknown` for an id the doc
/// type does not declare unless the write removes a held key,
/// `field_value_invalid` for a value its field does not take, and
/// `required_target` for removing a required field.
void checkFieldWrite({
  required IndexedDoc doc,
  required MergedDocType docType,
  required String fieldId,
  required String? value,
  required bool held,
}) {
  if (fieldId == 'draft' || fieldId == 'approved') {
    throw WriteFault(
      WriteFaultCode.fieldNotWritable,
      fieldId == 'draft'
          ? 'draft is written only by specstone approve'
          : approvedNotWritableMessage,
      file: doc.docPath,
      key: fieldId,
    );
  }
  // Empty stdin on a feature's status removes the written key (`document_writing/edit_one_section_or_field/write_one_field` E05, E13).
  if (value != null &&
      fieldId == 'status' &&
      doc.docTypeId == _computedStatusType) {
    throw WriteFault(
      WriteFaultCode.fieldNotWritable,
      'the status of a feature is computed from its stories',
      file: doc.docPath,
      key: fieldId,
    );
  }
  final field = docType.fields.where((f) => f.id == fieldId).firstOrNull;
  if (field == null) {
    // Removing a held key the type does not declare passes; an unheld one
    // still refuses field_unknown.
    if (value != null || !held) throw _fieldUnknown(doc, fieldId);
    return;
  }
  if (value != null) {
    _checkedValue(doc, field, value);
  } else if (field.required) {
    throw WriteFault(
      WriteFaultCode.requiredTarget,
      '${doc.docTypeId} requires the field $fieldId',
      file: doc.docPath,
      key: fieldId,
    );
  }
}

/// The one ComputedField (PD17): a feature's status, computed from stories.
const _computedStatusType = 'feature';

/// Returns the base hash of the part [target] names in [after].
String _baseAfter(ParsedDoc after, SetTarget target, MergedDocType docType) {
  final doc = Doc.parse(toLf(after.content.text));
  return switch (target) {
    SectionTarget(:final key) =>
      after.content.sections
              .where((section) => section.key == key)
              .map((section) => sectionBaseOf(section.body, docType))
              .firstOrNull ??
          emptyBaseHash,
    FieldTarget(:final fieldId) =>
      (doc.frontmatter ?? const <KeyBlock>[])
              .where((b) => b.name == fieldId)
              .map((b) => baseHashOf(b.text))
              .firstOrNull ??
          emptyBaseHash,
    TitleTarget() => titleBaseOf(doc.title),
    LeadTarget() => leadBaseOf(doc, docType),
  };
}

/// Returns the naming line of the part [target] names in [doc], ending at
/// [base].
String _namingLineOf(IndexedDoc doc, SetTarget target, String base) =>
    switch (target) {
      SectionTarget(:final key) => namingLine(doc, sectionKey: key, base: base),
      FieldTarget(:final fieldId) => namingLine(
        doc,
        fieldId: fieldId,
        base: base,
      ),
      TitleTarget() => namingLine(doc, title: true, base: base),
      LeadTarget() => namingLine(doc, sectionKey: leadKey, base: base),
    };

({String lfText, bool marksDraft}) _spliceField({
  required IndexedDoc doc,
  required MergedDocType docType,
  required String lfText,
  required String fieldId,
  required String base,
  required String stdin,
}) {
  final value = _fieldValueOf(stdin);
  final blocks = Doc.parse(lfText).frontmatter ?? const <KeyBlock>[];
  final held = blocks.where((b) => b.name == fieldId).firstOrNull;
  checkFieldWrite(
    doc: doc,
    docType: docType,
    fieldId: fieldId,
    value: value,
    held: held != null,
  );
  final currentBase = held == null ? emptyBaseHash : baseHashOf(held.text);
  if (currentBase != base) {
    throw _staleBase(
      doc,
      target: 'field',
      key: fieldId,
      sinceBase: base,
      currentText: held?.text ?? '',
      currentBase: currentBase,
    );
  }
  final spliced = withKeyBlock(
    lfText,
    fieldId,
    value == null ? null : _blockOf(fieldId, value),
  );
  final field = docType.fields.where((f) => f.id == fieldId).firstOrNull;
  return (lfText: spliced, marksDraft: field?.type != FieldType.outputRef);
}

/// Checks the YAML value of [stdin] against [field], throwing the fault.
void _checkedValue(IndexedDoc doc, MergedField field, String stdin) {
  final Object? value;
  try {
    value = loadYaml(stdin);
  } on YamlException {
    throw WriteFault(
      WriteFaultCode.fieldValueInvalid,
      '${field.id} takes a YAML value',
      file: doc.docPath,
      key: field.id,
    );
  }
  WriteFault takes(String what) => WriteFault(
    WriteFaultCode.fieldValueInvalid,
    '${field.id} takes $what',
    file: doc.docPath,
    key: field.id,
  );
  if (field.list) {
    if (value is! YamlList) throw takes('a YAML list, one `- item` line each');
    for (final item in value) {
      if (!fieldTakesItem(field, item)) throw takes(_typeOf(field));
    }
    return;
  }
  if (value is YamlList) throw takes('one YAML value, not a list');
  if (!fieldTakesItem(field, value)) throw takes(_typeOf(field));
}

/// Returns the `<what>` the field's type and `enum` name in a fault.
String _typeOf(MergedField field) => switch (field.type) {
  FieldType.string || FieldType.docRef || FieldType.outputRef => 'a string',
  FieldType.recordStatus => recordStatusLineShape,
  FieldType.integer => 'a whole number',
  FieldType.boolean => 'true or false',
  FieldType.date => 'a date as YYYY-MM-DD',
  FieldType.enumType =>
    field.enumValues == null
        ? 'a string'
        : 'one of ${field.enumValues!.join(', ')}',
};

/// Returns [stdin] as the key block text of [fieldId], per PD6.
///
/// A blank interior line stays blank; a trailing blank line is dropped.
String _blockOf(String fieldId, String stdin) {
  final lines = stdin.split('\n');
  if (lines.length == 1 && !stdin.startsWith('- ')) {
    return '$fieldId: ${lines[0]}\n';
  }
  final buffer = StringBuffer('$fieldId:\n');
  final last = lines.last == '' ? lines.length - 1 : lines.length;
  for (final line in lines.take(last)) {
    buffer.write(line.isEmpty ? '\n' : '  $line\n');
  }
  return buffer.toString();
}

({String lfText, bool marksDraft}) _spliceTitle(
  IndexedDoc doc,
  String lfText,
  String base,
  String stdin,
) {
  final currentTitle = Doc.parse(lfText).title ?? '';
  final currentBase = titleBaseOf(currentTitle);
  if (currentBase != base) {
    throw _staleBase(
      doc,
      target: 'title',
      key: 'title',
      sinceBase: base,
      currentText: currentTitle.isEmpty ? '' : '# $currentTitle\n',
      currentBase: currentBase,
    );
  }
  return (lfText: withTitle(lfText, _titleOf(stdin)), marksDraft: true);
}

/// Returns the one-line title [lf] holds; throws [IndexFault]
/// `argument_invalid` for any other count of lines.
String _titleOf(String lf) {
  final dropped = lf.endsWith('\n') ? lf.substring(0, lf.length - 1) : lf;
  final count = dropped.trim().isEmpty ? 0 : dropped.split('\n').length;
  if (count != 1) {
    throw IndexFault(
      IndexFaultCode.argumentInvalid,
      'a title is one line; stdin held $count lines',
    );
  }
  return dropped.trim();
}

/// Returns the YAML [lf] gives a field, its trailing blank lines dropped; null
/// when nothing is left, which removes the key.
String? _fieldValueOf(String lf) {
  final stripped = withoutTrailingBlankLines(lf);
  return stripped.trim().isEmpty ? null : stripped;
}

/// Reads [lf] as [Doc.parse] would, from outside any fence.
///
/// `refused` is the first line outside fenced code that [isRefused] accepts.
/// `openFence` is the delimiter of a fence the text leaves open.
({String? refused, String? openFence}) _scanStdin(
  String lf,
  bool Function(String line) isRefused,
) {
  final lines = lf.split('\n');
  final scan = blockScan(lines);
  String? refused;
  for (var i = 0; i < lines.length; i++) {
    if (!scan.fenced[i] && isRefused(lines[i])) {
      refused = lines[i];
      break;
    }
  }
  return (refused: refused, openFence: scan.openFence);
}

({String lfText, bool marksDraft}) _spliceLead(
  IndexedDoc doc,
  MergedDocType docType,
  String lfText,
  String base,
  String stdin,
) {
  final currentDoc = Doc.parse(lfText);
  final currentBase = leadBaseOf(currentDoc, docType);
  if (currentBase != base) {
    throw _staleBase(
      doc,
      target: 'lead',
      key: leadKey,
      sinceBase: base,
      currentText: currentDoc.lead,
      currentBase: currentBase,
    );
  }
  return (lfText: withLead(lfText, _pipedBodyOf(stdin)), marksDraft: true);
}

void _checkLeadText(String lf) {
  final scan = _scanStdin(
    lf,
    (line) => isTitleLine(line) || isSectionHeaderLine(line),
  );
  if (scan.refused case final refused?) {
    throw IndexFault(
      IndexFaultCode.argumentInvalid,
      'the lead holds the line "$refused"; send the lead only',
    );
  }
  if (scan.openFence case final fence?) {
    throw IndexFault(
      IndexFaultCode.argumentInvalid,
      'the lead leaves the fence "$fence" open; close it',
    );
  }
  refuseNamingLine(lf, 'the lead');
}

/// Returns [lf] less its first line after leading blank lines when that line
/// is [headerLine], the section's own header.
///
/// `dropped` tells whether that line was there, so a header-only stdin is told
/// from empty stdin.
({String text, bool dropped}) _withoutOwnHeader(String lf, String headerLine) {
  final lines = lf.split('\n');
  final first = lines.indexWhere((line) => line.trim().isNotEmpty);
  if (first < 0 || lines[first] != headerLine) {
    return (text: lf, dropped: false);
  }
  return (text: (lines..removeAt(first)).join('\n'), dropped: true);
}

({String lfText, bool marksDraft}) _spliceSection({
  required IndexedDoc doc,
  required MergedDocType docType,
  required String lfText,
  required List<IndexedSection> sections,
  required String key,
  required String base,
  required String stdin,
}) {
  final held = sections.indexWhere((section) => section.key == key);
  final template = docType.sections.where((s) => s.id == key).firstOrNull;
  if (held < 0 && template == null) {
    throw IndexFault(
      IndexFaultCode.sectionNotFound,
      '${doc.docTypeId}:${doc.name} holds no section with the key $key, '
      'and its template defines none',
    );
  }
  final unwrapped = _withoutOwnHeader(
    stdin,
    held < 0 ? '## ${template!.header}' : sections[held].headerLine,
  );
  final body = _pipedBodyOf(unwrapped.text);
  final removesSection = body.isEmpty && !unwrapped.dropped;
  // The first line may be the section's own header, which only the doc's
  // text tells; `checkPartText` judged the lines after it.
  _refuseHeaderLine(body);
  final currentBase = held < 0
      ? emptyBaseHash
      : sectionBaseOf(sections[held].body, docType);
  if (currentBase != base) {
    throw _staleBase(
      doc,
      target: 'section',
      key: key,
      sinceBase: base,
      currentText: held < 0 ? '' : '${sections[held].text}\n',
      currentBase: currentBase,
    );
  }
  if (removesSection && (template?.required ?? false)) {
    throw WriteFault(
      WriteFaultCode.requiredTarget,
      '${doc.docTypeId} requires the section $key',
      file: doc.docPath,
      key: key,
    );
  }

  final String spliced;
  if (removesSection) {
    spliced = held < 0 ? lfText : withoutSection(lfText, held);
  } else if (held >= 0) {
    spliced = withSectionBody(lfText, held, body);
  } else {
    spliced = _withTemplateSection(lfText, docType, key, sections, body);
  }
  return (lfText: spliced, marksDraft: true);
}

/// Checks the lines of [lf] that no doc text changes: the fence is closed, and
/// no `## ` line follows the first line, which may be the section's own header.
void _checkSectionText(String lf) {
  if (blockScan(lf.split('\n')).openFence case final fence?) {
    throw IndexFault(
      IndexFaultCode.argumentInvalid,
      'the body leaves the fence "$fence" open; close it',
    );
  }
  final lines = lf.split('\n');
  final first = lines.indexWhere((line) => line.trim().isNotEmpty);
  final mayBeOwnHeader = first >= 0 && isSectionHeaderLine(lines[first]);
  _refuseHeaderLine(mayBeOwnHeader ? (lines..removeAt(first)).join('\n') : lf);
  refuseNamingLine(lf, 'the body');
}

/// Throws [IndexFault] `argument_invalid` when [lf] holds a line at column 0
/// outside fenced code that has a naming line's shape; [subject] opens the
/// message.
///
/// Such a line would split the doc's `get` output into a false block when it
/// is fed back to `set --batch`, so a doc's text never holds one; an indented
/// or fenced line is text.
void refuseNamingLine(String lf, String subject) {
  if (_scanStdin(lf, hasNamingLineShape).refused case final line?) {
    throw IndexFault(
      IndexFaultCode.argumentInvalid,
      '$subject holds the naming line "${line.trimRight()}"; '
      'indent it or put it in a fenced code block',
    );
  }
}

/// Throws [IndexFault] `argument_invalid` when [body] holds a `## ` line
/// outside fenced code.
void _refuseHeaderLine(String body) {
  if (_scanStdin(body, isSectionHeaderLine).refused case final header?) {
    throw IndexFault(
      IndexFaultCode.argumentInvalid,
      'the body holds the header line "$header"; send the body only',
    );
  }
}

/// Returns piped [lf] as a section body, its leading blank lines kept; empty
/// when [lf] is blank.
String _pipedBodyOf(String lf) => lf.trim().isEmpty ? '' : sectionBodyOf(lf);

/// Reads [doc] from disk as it is now, not as the session's index saw it, and
/// returns its bytes and what they parse to.
///
/// Call it under the write lock. Throws [IndexFault] `doc_not_found` when the
/// file is gone, and `RenderFault` `output_not_writable` for one that cannot be
/// read or is not UTF-8.
({List<int> bytes, ParsedDoc parsed}) readLocked(
  WriteSession session,
  IndexedDoc doc,
  DocTypeMatch match,
) {
  final bytes = session.readDocBytes(doc.docPath);
  if (bytes == null) {
    throw IndexFault(
      IndexFaultCode.docNotFound,
      'no ${doc.docTypeId} doc carries the name ${doc.name}',
    );
  }
  final parsed = parseIndexedDoc(
    docPath: doc.docPath,
    bytes: bytes,
    match: match,
  );
  return (bytes: bytes, parsed: parsed);
}

/// Returns [lfText] with the template section [key] added before the first
/// held section that follows it in the template, else at the end.
String _withTemplateSection(
  String lfText,
  MergedDocType docType,
  String key,
  List<IndexedSection> held,
  String body,
) {
  final template = docType.sections.firstWhere((s) => s.id == key);
  int? before;
  for (final later in docType.sections.skipWhile((s) => s.id != key).skip(1)) {
    final at = held.indexWhere((section) => section.key == later.id);
    if (at >= 0) {
      before = at;
      break;
    }
  }
  return withSectionAdded(
    lfText,
    headerLine: '## ${template.header}',
    body: body,
    before: before,
  );
}

/// Returns the `field_unknown` fault for [fieldId] against [doc]'s doc type.
WriteFault _fieldUnknown(IndexedDoc doc, String fieldId) => WriteFault(
  WriteFaultCode.fieldUnknown,
  '${doc.docTypeId} declares no field $fieldId',
  file: doc.docPath,
  key: fieldId,
);

/// Returns the `base_mismatch` fault for a [target] that changed since
/// [sinceBase], carrying its current text so the caller can retry.
WriteFault _staleBase(
  IndexedDoc doc, {
  required String target,
  required String key,
  required String sinceBase,
  required String currentText,
  required String currentBase,
}) => WriteFault(
  WriteFaultCode.baseMismatch,
  'the $target changed since base $sinceBase',
  file: doc.docPath,
  key: key,
  current: CurrentTarget(
    heading: switch (target) {
      'field' => namingLine(doc, fieldId: key, base: currentBase),
      'title' => namingLine(doc, title: true, base: currentBase),
      _ => namingLine(doc, sectionKey: key, base: currentBase),
    },
    text: currentText,
    base: currentBase,
  ),
);
