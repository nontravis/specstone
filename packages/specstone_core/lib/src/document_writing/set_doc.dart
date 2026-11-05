import 'dart:convert';

import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_splice.dart';
import 'package:specstone_core/src/doc_model/doc_type_matcher.dart';
import 'package:specstone_core/src/document_writing/write_fault.dart';
import 'package:specstone_core/src/document_writing/write_session.dart';
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
  const new({required this.address, required this.target, required this.base});

  /// Reads the arguments of `set`.
  ///
  /// [target] is `<type>:<name>[#<key>]`; [field] and [title] are the other
  /// two targets, and exactly one of the three must be given.
  /// Throws [IndexFault] `argument_missing` for a missing target, section
  /// key, or [base], and `argument_conflict` for two targets at once.
  static SetRequest parse(
    String? target, {
    String? field,
    bool title = false,
    String? base,
  }) {
    if (target == null) {
      throw missingArgument('set', 'a target', _targetExample);
    }
    final hash = target.indexOf('#');
    final key = hash < 0 ? null : target.substring(hash + 1);
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
    if (base == null) throw missingArgument('set', '--base', _targetExample);
    return SetRequest(
      address: hash < 0 ? target : target.substring(0, hash),
      target: chosen,
      base: base,
    );
  }

  /// The doc as `<type>:<name>`.
  final String address;

  /// What to write.
  final SetTarget target;

  /// The base hash of [target] the caller last read.
  final String base;
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
ReadAnswer answerSet(WriteSession session, SetRequest request, String text) =>
    switch (request.target) {
      SectionTarget(:final key) => _setSection(session, request, key, text),
      FieldTarget(:final fieldId) => _setField(session, request, fieldId, text),
      TitleTarget() => _setTitle(session, request, text),
      LeadTarget() => _setLead(session, request, text),
    };

/// The one ComputedField (PD17): a feature's status, computed from stories.
const _computedStatusType = 'feature';

ReadAnswer _setField(
  WriteSession session,
  SetRequest request,
  String fieldId,
  String stdin,
) {
  final doc = session.target(request.address);
  final docType = session.index.typeOf(doc);
  if (docType == null) {
    throw StateError('${doc.docPath} is typed but its type is gone');
  }
  final match = MatchedDocType(docType);
  if (fieldId == 'draft' || fieldId == 'approved') {
    throw WriteFault(
      WriteFaultCode.fieldNotWritable,
      '$fieldId is written only by specstone approve',
      file: doc.docPath,
      key: fieldId,
    );
  }

  final lf = toLf(stdin);
  final stripped = withoutTrailingBlankLines(lf);
  final empty = stripped.trim().isEmpty;
  final field = docType.fields.where((f) => f.id == fieldId).firstOrNull;
  // Empty stdin on a feature's status removes the written key (f08/us05).
  if (!empty && fieldId == 'status' && doc.docTypeId == _computedStatusType) {
    throw WriteFault(
      WriteFaultCode.fieldNotWritable,
      'the status of a feature is computed from its stories',
      file: doc.docPath,
      key: fieldId,
    );
  }
  if (field == null && !empty) {
    throw _fieldUnknown(doc, fieldId);
  }
  if (field != null && !empty) {
    _checkedValue(doc, field, stripped);
  }

  return session.locked(() {
    final read = _readLocked(session, doc, match);
    final lfText = toLf(read.content.text);
    final blocks = Doc.parse(lfText).frontmatter ?? const <KeyBlock>[];
    final held = blocks.where((b) => b.name == fieldId).firstOrNull;
    // Empty stdin removes a held key the type does not declare; an unheld
    // one still refuses field_unknown.
    if (field == null && held == null) {
      throw _fieldUnknown(doc, fieldId);
    }
    final currentText = held?.text ?? '';
    final currentBase = held == null ? emptyBaseHash : baseHashOf(held.text);
    if (currentBase != request.base) {
      throw _staleBase(
        doc,
        target: 'field',
        key: fieldId,
        sinceBase: request.base,
        currentText: currentText,
        currentBase: currentBase,
      );
    }
    if (empty && (field?.required ?? false)) {
      throw WriteFault(
        WriteFaultCode.requiredTarget,
        '${doc.docTypeId} requires the field $fieldId',
        file: doc.docPath,
        key: fieldId,
      );
    }

    var spliced = empty
        ? withKeyBlock(lfText, fieldId, null)
        : withKeyBlock(lfText, fieldId, _blockOf(fieldId, stripped));
    if (field?.type != FieldType.outputRef) {
      spliced = markDraft(spliced, docType);
    }
    final written = session.writeDoc(
      doc.docPath,
      spliced,
      LineEnding.of(read.content.text),
    );

    final after = parseIndexedDoc(
      docPath: doc.docPath,
      bytes: utf8.encode(written),
      match: match,
    );
    final afterBlock =
        (Doc.parse(toLf(after.content.text)).frontmatter ?? const <KeyBlock>[])
            .where((b) => b.name == fieldId)
            .firstOrNull;
    final base = afterBlock == null
        ? emptyBaseHash
        : baseHashOf(afterBlock.text);
    return ReadAnswer(
      text: '${namingLine(doc, base: base)}\n',
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
      if (!_itemIs(item, field)) throw takes(_typeOf(field));
    }
    return;
  }
  if (value is YamlList) throw takes('one YAML value, not a list');
  if (!_itemIs(value, field)) throw takes(_typeOf(field));
}

/// Returns the `<what>` the field's type and `enum` name in a fault.
String _typeOf(MergedField field) => switch (field.type) {
  FieldType.string || FieldType.docRef || FieldType.outputRef => 'a string',
  FieldType.integer => 'a whole number',
  FieldType.boolean => 'true or false',
  FieldType.date => 'a date as YYYY-MM-DD',
  FieldType.enumType =>
    field.enumValues == null
        ? 'a string'
        : 'one of ${field.enumValues!.join(', ')}',
};

/// Whether [value] is one item the field's type accepts.
bool _itemIs(Object? value, MergedField field) => switch (field.type) {
  FieldType.string ||
  FieldType.docRef ||
  FieldType.outputRef => value is String,
  FieldType.integer => value is int,
  FieldType.boolean => value is bool,
  FieldType.date =>
    value is String &&
        RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value) &&
        DateTime.tryParse(value) != null,
  FieldType.enumType =>
    value is String && (field.enumValues?.contains(value) ?? false),
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

ReadAnswer _setTitle(WriteSession session, SetRequest request, String stdin) {
  final lf = toLf(stdin);
  final dropped = lf.endsWith('\n') ? lf.substring(0, lf.length - 1) : lf;
  final count = dropped.trim().isEmpty ? 0 : dropped.split('\n').length;
  if (count != 1) {
    throw IndexFault(
      IndexFaultCode.argumentInvalid,
      'a title is one line; stdin held $count lines',
    );
  }
  final title = dropped.trim();

  final doc = session.target(request.address);
  final docType =
      session.index.typeOf(doc) ??
      (throw StateError('${doc.docPath} is typed but its type is gone'));
  final match = MatchedDocType(docType);

  return session.locked(() {
    final read = _readLocked(session, doc, match);
    final lfText = toLf(read.content.text);
    final currentTitle = Doc.parse(lfText).title ?? '';
    final currentText = currentTitle.isEmpty ? '' : '# $currentTitle\n';
    final currentBase = titleBaseOf(currentTitle);
    if (currentBase != request.base) {
      throw _staleBase(
        doc,
        target: 'title',
        key: 'title',
        sinceBase: request.base,
        currentText: currentText,
        currentBase: currentBase,
      );
    }

    final written = session.writeDoc(
      doc.docPath,
      markDraft(withTitle(lfText, title), docType),
      LineEnding.of(read.content.text),
    );

    final after = parseIndexedDoc(
      docPath: doc.docPath,
      bytes: utf8.encode(written),
      match: match,
    );
    final base = titleBaseOf(Doc.parse(written).title);
    return ReadAnswer(
      text: '${namingLine(doc, base: base)}\n',
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

/// Reads [lf] as [Doc.parse] would, from outside any fence.
///
/// `refused` is the first line outside fenced code that [isRefused] accepts.
/// `openFence` is the delimiter of a fence the text leaves open.
({String? refused, String? openFence}) _scanStdin(
  String lf,
  bool Function(String line) isRefused,
) {
  final lines = lf.split('\n');
  final scan = fenceScan(lines);
  String? refused;
  for (var i = 0; i < lines.length; i++) {
    if (!scan.fenced[i] && isRefused(lines[i])) {
      refused = lines[i];
      break;
    }
  }
  return (refused: refused, openFence: scan.openFence);
}

ReadAnswer _setLead(WriteSession session, SetRequest request, String stdin) {
  final lf = toLf(stdin);
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
  final body = _pipedBodyOf(lf);

  final doc = session.target(request.address);
  final docType =
      session.index.typeOf(doc) ??
      (throw StateError('${doc.docPath} is typed but its type is gone'));
  final match = MatchedDocType(docType);

  return session.locked(() {
    final read = _readLocked(session, doc, match);
    final lfText = toLf(read.content.text);
    final currentDoc = Doc.parse(lfText);
    final currentLead = currentDoc.lead;
    final currentBase = leadBaseOf(currentDoc, docType);
    if (currentBase != request.base) {
      throw _staleBase(
        doc,
        target: 'lead',
        key: leadKey,
        sinceBase: request.base,
        currentText: currentLead,
        currentBase: currentBase,
      );
    }

    final written = session.writeDoc(
      doc.docPath,
      markDraft(withLead(lfText, body), docType),
      LineEnding.of(read.content.text),
    );

    final after = parseIndexedDoc(
      docPath: doc.docPath,
      bytes: utf8.encode(written),
      match: match,
    );
    final base = leadBaseOf(Doc.parse(written), docType);
    return ReadAnswer(
      text: '${namingLine(doc, base: base)}\n',
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

ReadAnswer _setSection(
  WriteSession session,
  SetRequest request,
  String key,
  String stdin,
) {
  final lf = toLf(stdin);
  final scan = _scanStdin(lf, isSectionHeaderLine);
  if (scan.refused case final header?) {
    throw IndexFault(
      IndexFaultCode.argumentInvalid,
      'the body holds the header line "$header"; send the body only',
    );
  }
  if (scan.openFence case final fence?) {
    throw IndexFault(
      IndexFaultCode.argumentInvalid,
      'the body leaves the fence "$fence" open; close it',
    );
  }
  final body = _pipedBodyOf(lf);

  final doc = session.target(request.address);
  final docType =
      session.index.typeOf(doc) ??
      (throw StateError('${doc.docPath} is typed but its type is gone'));
  final match = MatchedDocType(docType);

  return session.locked(() {
    final read = _readLocked(session, doc, match);
    final sections = read.content.sections;
    final held = sections.indexWhere((section) => section.key == key);
    final template = docType.sections.where((s) => s.id == key).firstOrNull;
    if (held < 0 && template == null) {
      throw IndexFault(
        IndexFaultCode.sectionNotFound,
        '${request.address} holds no section with the key $key, '
        'and its template defines none',
      );
    }
    final currentText = held < 0 ? '' : '${sections[held].text}\n';
    final currentBase = held < 0
        ? emptyBaseHash
        : sectionBaseOf(sections[held].body, docType);
    if (currentBase != request.base) {
      throw _staleBase(
        doc,
        target: 'section',
        key: key,
        sinceBase: request.base,
        currentText: currentText,
        currentBase: currentBase,
      );
    }
    if (body.isEmpty && (template?.required ?? false)) {
      throw WriteFault(
        WriteFaultCode.requiredTarget,
        '${doc.docTypeId} requires the section $key',
        file: doc.docPath,
        key: key,
      );
    }

    final lfText = toLf(read.content.text);
    final String spliced;
    if (body.isEmpty) {
      spliced = held < 0 ? lfText : withoutSection(lfText, held);
    } else if (held >= 0) {
      spliced = withSectionBody(lfText, held, body);
    } else {
      spliced = _withTemplateSection(lfText, docType, key, sections, body);
    }
    final written = session.writeDoc(
      doc.docPath,
      markDraft(spliced, docType),
      LineEnding.of(read.content.text),
    );

    final after = parseIndexedDoc(
      docPath: doc.docPath,
      bytes: utf8.encode(written),
      match: match,
    );
    final newBase = after.content.sections
        .where((section) => section.key == key)
        .map((section) => sectionBaseOf(section.body, docType))
        .firstOrNull;
    final base = newBase ?? emptyBaseHash;
    return ReadAnswer(
      text: '${namingLine(doc, base: base)}\n',
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

/// Returns piped [lf] as a section body, its leading blank lines kept; empty
/// when [lf] is blank.
String _pipedBodyOf(String lf) => lf.trim().isEmpty ? '' : sectionBodyOf(lf);

/// Reads [doc] from disk as it is now, not as the session's index saw it.
ParsedDoc _readLocked(
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
  return parseIndexedDoc(docPath: doc.docPath, bytes: bytes, match: match);
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
    heading: namingLine(doc, base: currentBase),
    text: currentText,
    base: currentBase,
  ),
);
