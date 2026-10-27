import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_splice.dart';
import 'package:specstone_core/src/doc_model/doc_type_matcher.dart';
import 'package:specstone_core/src/document_writing/write_fault.dart';
import 'package:specstone_core/src/document_writing/write_session.dart';
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

final _headerLine = RegExp(r'^## .*$', multiLine: true);
final _trailingBlankLines = RegExp(r'(\n[ \t]*)+$');

/// What a `set` call writes: a section, a frontmatter field, or the title.
sealed class SetTarget {
  const new();
}

/// The section keyed [key].
final class SectionTarget extends SetTarget {
  const new(this.key);

  /// The template section id, else the heading slug.
  final String key;
}

/// The frontmatter field [fieldId].
final class FieldTarget extends SetTarget {
  const new(this.fieldId);

  /// The template field id.
  final String fieldId;
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
    if (sectionKey != null) {
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
String markDraft(String lfText) => Doc.parse(lfText).isDraft
    ? lfText
    : withKeyBlock(lfText, 'draft', 'draft: true\n');

/// Writes [text] to the target of [request] and prints the doc's new base.
///
/// The write runs under the session lock against a fresh read of the file,
/// so a target changed since [SetRequest.base] refuses with its current text.
/// An empty [text] removes an optional section or field. Throws [IndexFault]
/// for a body that holds a `## ` line, a doc, section, or field that is not
/// there, a title that is not one line, and [WriteFault] `base_mismatch`,
/// `required_target`, or a refused field.
ReadAnswer answerSet(WriteSession session, SetRequest request, String text) =>
    switch (request.target) {
      SectionTarget(:final key) => _setSection(session, request, key, text),
      FieldTarget(:final fieldId) => _setField(session, request, fieldId, text),
      TitleTarget() => _setTitle(session, request, text),
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
  if (fieldId == 'status' && doc.docTypeId == _computedStatusType) {
    throw WriteFault(
      WriteFaultCode.fieldNotWritable,
      'the status of a feature is computed from its stories',
      file: doc.docPath,
      key: fieldId,
    );
  }
  final field = docType.fields.where((f) => f.id == fieldId).firstOrNull;
  if (field == null) {
    throw WriteFault(
      WriteFaultCode.fieldUnknown,
      '${doc.docTypeId} declares no field $fieldId',
      file: doc.docPath,
      key: fieldId,
    );
  }

  final lf = toLf(stdin);
  final stripped = lf.replaceFirst(_trailingBlankLines, '');
  final empty = stripped.trim().isEmpty;
  if (!empty) {
    _checkedValue(doc, field, stripped);
  }

  return session.locked(() {
    final read = _readLocked(session, doc, match);
    final lfText = toLf(read.content.text);
    final blocks = Doc.parse(lfText).frontmatter ?? const <KeyBlock>[];
    final held = blocks.where((b) => b.key == fieldId).firstOrNull;
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
    if (empty && field.required) {
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
    if (field.type != FieldType.outputRef) {
      spliced = markDraft(spliced);
    }
    session.writeDoc(doc.docPath, spliced, LineEnding.of(read.content.text));

    final after = parseIndexedDoc(
      docPath: doc.docPath,
      bytes: utf8.encode(spliced),
      match: match,
    );
    final afterBlock =
        (Doc.parse(toLf(after.content.text)).frontmatter ?? const <KeyBlock>[])
            .where((b) => b.key == fieldId)
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
    if (value is! YamlList) throw takes('a list');
    for (final item in value) {
      if (!_itemIs(item, field)) throw takes(_typeOf(field));
    }
    return;
  }
  if (value is YamlList) throw takes('one value');
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
String _blockOf(String fieldId, String stdin) {
  final lines = stdin.split('\n');
  if (lines.length == 1 && !stdin.startsWith('- ')) {
    return '$fieldId: ${lines[0]}\n';
  }
  final buffer = StringBuffer('$fieldId:\n');
  for (final line in lines.where((l) => l.isNotEmpty)) {
    buffer.write('  $line\n');
  }
  return buffer.toString();
}

ReadAnswer _setTitle(WriteSession session, SetRequest request, String stdin) {
  final lf = toLf(stdin);
  final stripped = lf.replaceFirst(_trailingBlankLines, '');
  final lines = stripped.split('\n').where((l) => l.isNotEmpty).toList();
  if (lines.length != 1 || lines.single.trim().isEmpty) {
    throw IndexFault(
      IndexFaultCode.argumentInvalid,
      'a title is one non-empty line',
    );
  }
  final title = lines.single.trim();

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
    final currentBase = baseHashOf(currentTitle);
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

    final written = markDraft(withTitle(lfText, title));
    session.writeDoc(doc.docPath, written, LineEnding.of(read.content.text));

    final after = parseIndexedDoc(
      docPath: doc.docPath,
      bytes: utf8.encode(written),
      match: match,
    );
    final base = baseHashOf(title);
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
  if (_headerLine.firstMatch(lf) case final header?) {
    throw IndexFault(
      IndexFaultCode.argumentInvalid,
      'the body holds the header line "${header[0]}"; send the body only',
    );
  }
  final stripped = lf.replaceFirst(_trailingBlankLines, '');
  final body = stripped.trim().isEmpty ? '' : '$stripped\n';

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
        : baseHashOf(sections[held].body);
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
    final written = markDraft(spliced);
    session.writeDoc(doc.docPath, written, LineEnding.of(read.content.text));

    final after = parseIndexedDoc(
      docPath: doc.docPath,
      bytes: utf8.encode(written),
      match: match,
    );
    final newBase = after.content.sections
        .where((section) => section.key == key)
        .map((section) => baseHashOf(section.body))
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

/// Reads [doc] from disk as it is now, not as the session's index saw it.
ParsedDoc _readLocked(
  WriteSession session,
  IndexedDoc doc,
  DocTypeMatch match,
) {
  try {
    return parseIndexedDoc(
      docPath: doc.docPath,
      bytes: session.fileOf(doc.docPath).readAsBytesSync(),
      match: match,
    );
  } on PathNotFoundException {
    throw IndexFault(
      IndexFaultCode.docNotFound,
      'no ${doc.docTypeId} doc carries the name ${doc.name}',
    );
  }
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
