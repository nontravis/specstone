import 'dart:convert';

import 'package:specstone_core/src/consistency_check/frontmatter_rules.dart'
    show fieldTakesItem, recordStatusLineShape, taskRefEntryShape;
import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_splice.dart';
import 'package:specstone_core/src/doc_model/doc_type_matcher.dart';
import 'package:specstone_core/src/doc_model/list_block_writer.dart';
import 'package:specstone_core/src/doc_model/models/doc_address.dart';
import 'package:specstone_core/src/doc_model/reference_grammar.dart';
import 'package:specstone_core/src/document_writing/approval.dart'
    show isMatrixSection, isOutsideApproval;
import 'package:specstone_core/src/document_writing/models/locked_doc.dart';
import 'package:specstone_core/src/document_writing/models/replace_stdin.dart';
import 'package:specstone_core/src/document_writing/models/spliced_doc.dart';
import 'package:specstone_core/src/document_writing/replace_passage.dart';
import 'package:specstone_core/src/document_writing/write_fault.dart';
import 'package:specstone_core/src/document_writing/write_session.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/get_docs.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';
import 'package:specstone_core/src/rendering/generated_blocks.dart'
    show withTemplateSection;
import 'package:specstone_core/src/rendering/line_ending.dart';
import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:yaml/yaml.dart';

/// The `argument_conflict` message for `--replace` beside another target or
/// mode.
const replaceConflictMessage =
    '--replace takes a section target alone: no --field, --title, --batch, '
    '--remove-task, #_lead, or whole-doc target';

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

/// One passage of the section keyed [key], replaced as `set --replace` reads
/// its stdin.
final class ReplaceTarget extends SetTarget {
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
  /// With [replace], the target is [ReplaceTarget] of the section key.
  /// Throws [IndexFault] `argument_missing` for a missing target, section
  /// key, or [base], and `argument_conflict` for two targets at once, and for
  /// [replace] beside [field], [title], the lead, or no section key.
  static SetRequest parse(
    String? target, {
    String? field,
    bool title = false,
    String? base,
    DocIndex? index,
    String? codeTarget,
    bool replace = false,
  }) {
    requireShape(target, base);
    final written = target!;
    final DocAddress(:docPart, sectionKey: key) = index == null
        ? readDocAddress(written)
        : index.splitAddress(written);
    final sectionKey = key == null || key.isEmpty ? null : key;
    if (replace &&
        (field != null ||
            title ||
            sectionKey == null ||
            sectionKey == leadKey)) {
      throw IndexFault(IndexFaultCode.argumentConflict, replaceConflictMessage);
    }
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
      chosen = replace ? ReplaceTarget(sectionKey) : SectionTarget(sectionKey);
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
      base: base!,
      codeTarget: codeTarget,
    );
  }

  /// Throws [IndexFault] `argument_missing` unless [target] and [base] are both
  /// given.
  ///
  /// Needs no index, so a command calls it before it reads stdin.
  static void requireShape(String? target, String? base) {
    if (target == null) {
      throw missingArgument('set', 'a target', _targetExample);
    }
    if (base == null) throw missingArgument('set', '--base', _targetExample);
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
/// `required_target`, `replace_unmatched`, `replace_ambiguous`, or a refused
/// field.
ReadAnswer answerSet(WriteSession session, SetRequest request, String text) {
  final doc = session.target(request.address, codeTarget: request.codeTarget);
  final docType =
      session.index.typeOf(doc) ??
      (throw StateError('${doc.docPath} is typed but its type is gone'));
  final match = MatchedDocType(docType);
  checkPartText(doc: doc, docType: docType, target: request.target, text: text);

  final statusesOutside = session.project.statusesOutsideApproval;
  return session.locked(() {
    final locked = readLocked(session, doc, match);
    final part = splicePart(
      doc: doc,
      docType: docType,
      lfText: locked.lfText,
      sections: locked.sections,
      target: request.target,
      base: request.base,
      text: text,
      statusesOutside: statusesOutside,
    );
    final written = session.writeDoc(
      doc.docPath,
      part.marksDraft ? markDraft(part.lfText, docType) : part.lfText,
      LineEnding.of(locked.parsed.content.text),
    );

    final after = parseIndexedDoc(
      docPath: doc.docPath,
      bytes: utf8.encode(written),
      match: match,
      statusesOutside: statusesOutside,
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
/// The result's `marksDraft` is false only for a field outside the approval
/// hash by the rule [statusesOutside] names ([isOutsideApproval]), or for the
/// record's matrix section ([isMatrixSection]).
/// Touches no disk and takes no lock. Runs [checkPartText] first, except for
/// a [ReplaceTarget], which reads its stdin itself, then throws
/// what [answerSet] throws for the part, [WriteFault] `base_mismatch` with the
/// part's current text included.
SplicedDoc splicePart({
  required IndexedDoc doc,
  required MergedDocType docType,
  required String lfText,
  required List<IndexedSection> sections,
  required SetTarget target,
  required String base,
  required String text,
  required bool statusesOutside,
}) {
  // A replace parses its stdin once, in `_spliceReplace`, so it skips the
  // check that would parse it again; `answerSet` already ran that check.
  if (target case ReplaceTarget(:final key)) {
    return _spliceReplace(
      doc: doc,
      docType: docType,
      lfText: lfText,
      sections: sections,
      key: key,
      base: base,
      stdin: text,
    );
  }
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
    ReplaceTarget() => throw StateError('handled before the check'),
    FieldTarget(:final fieldId) => _spliceField(
      doc: doc,
      docType: docType,
      lfText: lfText,
      fieldId: fieldId,
      base: base,
      stdin: stdin,
      statusesOutside: statusesOutside,
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
    case ReplaceTarget():
      parseReplaceStdin(text);
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
  // Empty stdin on a feature's status removes the written key.
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

/// The one ComputedField: a feature's status, computed from stories.
const _computedStatusType = 'feature';

/// Returns the base hash of the part [target] names in [after].
String _baseAfter(ParsedDoc after, SetTarget target, MergedDocType docType) {
  final doc = Doc.parse(toLf(after.content.text));
  return switch (target) {
    SectionTarget(:final key) || ReplaceTarget(:final key) =>
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
      SectionTarget(:final key) ||
      ReplaceTarget(:final key) => namingLine(doc, sectionKey: key, base: base),
      FieldTarget(:final fieldId) => namingLine(
        doc,
        fieldId: fieldId,
        base: base,
      ),
      TitleTarget() => namingLine(doc, title: true, base: base),
      LeadTarget() => namingLine(doc, sectionKey: leadKey, base: base),
    };

SplicedDoc _spliceField({
  required IndexedDoc doc,
  required MergedDocType docType,
  required String lfText,
  required String fieldId,
  required String base,
  required String stdin,
  required bool statusesOutside,
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
  final field = docType.fields.where((f) => f.id == fieldId).firstOrNull;
  final spliced = withKeyBlock(
    lfText,
    fieldId,
    value == null ? null : _fieldBlockOf(fieldId, field, value, held),
  );
  return SplicedDoc(
    lfText: spliced,
    marksDraft:
        field == null ||
        !isOutsideApproval(field, statusesOutside: statusesOutside),
  );
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
  FieldType.string ||
  FieldType.docRef ||
  FieldType.outputRef ||
  FieldType.sourceRef => 'a string',
  FieldType.recordStatus => recordStatusLineShape,
  FieldType.taskRef => taskRefEntryShape,
  FieldType.integer => 'a whole number',
  FieldType.boolean => 'true or false',
  FieldType.date => 'a date as YYYY-MM-DD',
  FieldType.enumType =>
    field.enumValues == null
        ? 'a string'
        : 'one of ${field.enumValues!.join(', ')}',
};

/// Returns the key block of [fieldId] holding the checked YAML [value]: a
/// `list: true` field's entries written over [held], else [value] as given.
String _fieldBlockOf(
  String fieldId,
  MergedField? field,
  String value,
  KeyBlock? held,
) {
  if (field == null || !field.list) return _blockOf(fieldId, value);
  return switch (loadYaml(value)) {
    final YamlList entries => listBlockOf(fieldId, [...entries], onDisk: held),
    _ => throw StateError('$fieldId was checked as a YAML list'),
  };
}

/// Returns [stdin] as the key block text of the scalar field [fieldId].
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

SplicedDoc _spliceTitle(
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
  return SplicedDoc(
    lfText: withTitle(lfText, _titleOf(stdin)),
    marksDraft: true,
  );
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

/// What `_scanStdin` reads of a text outside any fence.
final class _StdinScan {
  const new({required this.refused, required this.openFence});

  /// The first line outside fenced code the check refuses; null when none.
  final String? refused;

  /// The delimiter of a fence the text leaves open.
  final String? openFence;
}

/// Reads [lf] as [Doc.parse] would, from outside any fence.
_StdinScan _scanStdin(String lf, bool Function(String line) isRefused) {
  final lines = lf.split('\n');
  final scan = blockScan(lines);
  String? refused;
  for (var i = 0; i < lines.length; i++) {
    if (!scan.fenced[i] && isRefused(lines[i])) {
      refused = lines[i];
      break;
    }
  }
  return _StdinScan(refused: refused, openFence: scan.openFence);
}

SplicedDoc _spliceLead(
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
  return SplicedDoc(
    lfText: withLead(lfText, _pipedBodyOf(stdin)),
    marksDraft: true,
  );
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

/// A stdin less the section's own header.
final class _Unwrapped {
  const new({required this.text, required this.dropped});

  final String text;

  /// Whether that header was there, so a header-only stdin is told from empty
  /// stdin.
  final bool dropped;
}

/// Returns [lf] less its first line after leading blank lines when that line
/// is [headerLine], the section's own header.
_Unwrapped _withoutOwnHeader(String lf, String headerLine) {
  final lines = lf.split('\n');
  final first = lines.indexWhere((line) => line.trim().isNotEmpty);
  if (first < 0 || lines[first] != headerLine) {
    return _Unwrapped(text: lf, dropped: false);
  }
  return _Unwrapped(text: (lines..removeAt(first)).join('\n'), dropped: true);
}

SplicedDoc _spliceSection({
  required IndexedDoc doc,
  required MergedDocType docType,
  required String lfText,
  required List<IndexedSection> sections,
  required String key,
  required String base,
  required String stdin,
}) {
  final held = _heldSectionIndex(doc, docType, sections, key);
  final template = docType.sections.where((s) => s.id == key).firstOrNull;
  final unwrapped = _withoutOwnHeader(
    stdin,
    held < 0 ? '## ${template!.header}' : sections[held].headerLine,
  );
  final body = _pipedBodyOf(unwrapped.text);
  final removesSection = body.isEmpty && !unwrapped.dropped;
  // The first line may be the section's own header, which only the doc's
  // text tells; `checkPartText` judged the lines after it.
  _refuseHeaderLine(body);
  _requireSectionBase(doc, docType, sections, held, key, base);
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
    spliced = withTemplateSection(lfText, docType, key, body);
  }
  return SplicedDoc(
    lfText: spliced,
    marksDraft: !isMatrixSection(docType, key),
  );
}

/// Returns the index in [sections] of the section keyed [key], or -1 for a
/// template section the doc lacks.
///
/// Throws [IndexFault] `section_not_found` for a key the doc neither holds nor
/// defines in [docType].
int _heldSectionIndex(
  IndexedDoc doc,
  MergedDocType docType,
  List<IndexedSection> sections,
  String key,
) {
  final held = sections.indexWhere((section) => section.key == key);
  if (held < 0 && !docType.sections.any((s) => s.id == key)) {
    throw IndexFault(
      IndexFaultCode.sectionNotFound,
      '${doc.docTypeId}:${doc.name} holds no section with the key $key, '
      'and its template defines none',
    );
  }
  return held;
}

String _sectionBaseOnDisk(
  MergedDocType docType,
  List<IndexedSection> sections,
  int held,
) => held < 0 ? emptyBaseHash : sectionBaseOf(sections[held].body, docType);

String _sectionTextOnDisk(List<IndexedSection> sections, int held) =>
    held < 0 ? '' : '${sections[held].text}\n';

/// Throws [WriteFault] `base_mismatch` with the current section when the
/// section at [held] has a base other than [base].
void _requireSectionBase(
  IndexedDoc doc,
  MergedDocType docType,
  List<IndexedSection> sections,
  int held,
  String key,
  String base,
) {
  final currentBase = _sectionBaseOnDisk(docType, sections, held);
  if (currentBase == base) return;
  throw _staleBase(
    doc,
    target: 'section',
    key: key,
    sinceBase: base,
    currentText: _sectionTextOnDisk(sections, held),
    currentBase: currentBase,
  );
}

/// Replaces one passage of the section keyed [key] with the passages [stdin]
/// holds, then writes the result as a section body.
///
/// The old passage is matched against the section body as `get` prints it.
/// The stdin is read first, then the base is checked before the match, so a
/// stale base wins over a missing passage. [_spliceSection] checks the base
/// again on the new body; it is the same hash and cannot differ.
SplicedDoc _spliceReplace({
  required IndexedDoc doc,
  required MergedDocType docType,
  required String lfText,
  required List<IndexedSection> sections,
  required String key,
  required String base,
  required String stdin,
}) {
  final ReplaceStdin(:oldPassage, :newPassage) = parseReplaceStdin(stdin);
  final held = _heldSectionIndex(doc, docType, sections, key);
  _requireSectionBase(doc, docType, sections, held, key, base);
  final currentBase = _sectionBaseOnDisk(docType, sections, held);
  final body = replacedBody(
    held < 0 ? '' : toLf(sections[held].body),
    oldPassage,
    newPassage,
    docPath: doc.docPath,
    key: key,
    current: CurrentTarget(
      heading: namingLine(doc, sectionKey: key, base: currentBase),
      text: _sectionTextOnDisk(sections, held),
      base: currentBase,
    ),
  );
  _refuseOpenFence(body);
  _refuseHeaderLine(body);
  refuseNamingLine(body, 'the body');
  return _spliceSection(
    doc: doc,
    docType: docType,
    lfText: lfText,
    sections: sections,
    key: key,
    base: base,
    stdin: body,
  );
}

/// Throws [IndexFault] `argument_invalid` when [lf] leaves a fence open.
void _refuseOpenFence(String lf) {
  if (blockScan(lf.split('\n')).openFence case final fence?) {
    throw IndexFault(
      IndexFaultCode.argumentInvalid,
      'the body leaves the fence "$fence" open; close it',
    );
  }
}

/// Checks the lines of [lf] that no doc text changes: the fence is closed, and
/// no `## ` line follows the first line, which may be the section's own header.
void _checkSectionText(String lf) {
  _refuseOpenFence(lf);
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

/// Reads [doc] from disk into a [LockedDoc], as it is now, not as the session's
/// index saw it.
///
/// Call it under the write lock. Throws [IndexFault] `doc_not_found` when the
/// file is gone, and `RenderFault` `output_not_writable` for one that cannot be
/// read or is not UTF-8.
LockedDoc readLocked(WriteSession session, IndexedDoc doc, DocTypeMatch match) {
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
    statusesOutside: session.project.statusesOutsideApproval,
  );
  return LockedDoc(bytes: bytes, parsed: parsed);
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
