import 'dart:convert';

import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_splice.dart';
import 'package:specstone_core/src/doc_model/doc_type_matcher.dart';
import 'package:specstone_core/src/doc_model/task_ref.dart';
import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:specstone_core/src/document_writing/set_doc.dart'
    show checkFieldWrite, readLocked;
import 'package:specstone_core/src/document_writing/write_session.dart';
import 'package:specstone_core/src/index_query/get_docs.dart' show basesOf;
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';
import 'package:specstone_core/src/rendering/formatter.dart' show layOutDoc;
import 'package:specstone_core/src/rendering/line_ending.dart';
import 'package:specstone_core/src/templates/doc_type_layer.dart'
    show FieldType;
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:yaml/yaml.dart';

// MARK: - Public

/// Throws [IndexFault] `argument_invalid` for the first of [tasks] that is
/// empty or holds a `:`, naming it.
void requireTaskIds(List<String> tasks) {
  for (final task in tasks) {
    if (task.isNotEmpty && !task.contains(':')) continue;
    throw IndexFault(
      IndexFaultCode.argumentInvalid,
      '--remove-task takes a task id that is not empty and holds no ":"; '
      'got "$task"',
    );
  }
}

/// Removes every `task_ref` entry whose task is one of [tasks] from every doc
/// in scope, in one write of every doc it changes or of none.
///
/// The docs in scope are those [codeTarget] keeps, else every doc. A field is
/// found by its type alone, and a list left empty loses its key block. Each
/// changed doc takes the checks a single `set --field` makes, then is written
/// through one journal in the line ends and byte-order mark it had, its draft
/// flag and approval as they were. `json` is `docs`, in DocPath order, each
/// with `path`, `name`, `docType`, `removed`, and `base`, and `noRefs`, the
/// tasks no doc held, each once in the order named. Throws [IndexFault]
/// `argument_invalid` for a [codeTarget] the project lacks and the fault of
/// the first doc that fails a check, with 0 docs written.
ReadAnswer answerRemoveTasks(
  WriteSession session,
  List<String> tasks, {
  String? codeTarget,
}) {
  session.index.checkCodeTarget(codeTarget);
  final named = {...tasks};
  return session.locked(() {
    final removals = _removalsOf(session, named, codeTarget);
    final steps = [for (final removal in removals) _stepOf(session, removal)];
    if (steps.isNotEmpty) MoveJournal(steps).run(session.journalTarget);
    return _answerOf(session, named, removals);
  });
}

// MARK: - Planning

/// One doc that loses entries: its text as written after the removal.
final class _Removal {
  const new({
    required this.doc,
    required this.docType,
    required this.bytes,
    required this.laidOut,
    required this.removed,
    required this.tasks,
    required this.fieldValues,
  });

  final IndexedDoc doc;
  final MergedDocType docType;

  /// The file's bytes as read under the lock.
  final List<int> bytes;

  /// The doc's text after the removal, laid out, with LF line ends.
  final String laidOut;

  /// The entries removed, as the doc held them, in field then entry order.
  final List<String> removed;

  /// The named tasks the removed entries hold.
  final Set<String> tasks;

  /// The YAML each changed field takes, by field id; null drops the key.
  final Map<String, String?> fieldValues;
}

/// Reads each doc of the scope fresh and returns the removal of each doc that
/// holds an entry of a task in [named], in DocPath order, each checked as a
/// single `set --field` of its fields checks.
List<_Removal> _removalsOf(
  WriteSession session,
  Set<String> named,
  String? codeTarget,
) {
  final docs = [
    for (final doc in session.index.docs)
      if (doc.inTarget(codeTarget)) doc,
  ]..sort((a, b) => a.docPath.compareTo(b.docPath));
  final removals = <_Removal>[];
  for (final doc in docs) {
    final docType = session.index.typeOf(doc);
    if (docType == null) continue;
    final removal = _removalIn(session, doc, docType, named);
    if (removal == null) continue;
    for (final MapEntry(key: fieldId, :value) in removal.fieldValues.entries) {
      checkFieldWrite(
        doc: doc,
        docType: docType,
        fieldId: fieldId,
        value: value,
        held: true,
      );
    }
    removals.add(removal);
  }
  return removals;
}

/// Returns what [doc] loses, or null when it holds no entry of [named].
_Removal? _removalIn(
  WriteSession session,
  IndexedDoc doc,
  MergedDocType docType,
  Set<String> named,
) {
  final fields = [
    for (final field in docType.fields)
      if (field.type == FieldType.taskRef) field.id,
  ];
  if (fields.isEmpty) return null;
  final read = readLocked(session, doc, MatchedDocType(docType));
  final held = toLf(read.parsed.content.text);
  final blocks = <String, KeyBlock>{};
  for (final block in Doc.parse(held).frontmatter ?? const <KeyBlock>[]) {
    blocks.putIfAbsent(block.name, () => block);
  }

  var text = held;
  final removed = <String>[];
  final tasks = <String>{};
  final fieldValues = <String, String?>{};
  for (final fieldId in fields) {
    final block = blocks[fieldId];
    final items = block == null ? null : _itemsOf(block);
    if (block == null || items == null) continue;
    final (:kept, :gone, :goneAt) = _split(items, named);
    if (gone.isEmpty) continue;
    removed.addAll(gone);
    tasks.addAll([for (final entry in gone) TaskRef.parse(entry)!.task]);
    final after = _blockAfter(block, fieldId, kept, goneAt);
    fieldValues[fieldId] = after == null
        ? null
        : [for (final item in kept) '- ${_yamlOf(item)}'].join('\n');
    text = withKeyBlock(text, fieldId, after);
  }
  if (removed.isEmpty) return null;
  return _Removal(
    doc: doc,
    docType: docType,
    bytes: read.bytes,
    laidOut: layOutDoc(text, session.docTypeAt(doc.docPath)),
    removed: removed,
    tasks: tasks,
    fieldValues: fieldValues,
  );
}

/// Returns the entries of [block]: the items of its list, or its one scalar
/// string; null when it holds neither.
List<Object?>? _itemsOf(KeyBlock block) {
  try {
    return switch (loadYaml(block.indentedValueText)) {
      final YamlList list => list.toList(),
      final String entry => [entry],
      _ => null,
    };
  } on YamlException {
    return null;
  }
}

/// Splits [items] into those that stay and the entries of a task in [named],
/// with the position of each entry that goes.
({List<Object?> kept, List<String> gone, Set<int> goneAt}) _split(
  List<Object?> items,
  Set<String> named,
) {
  final kept = <Object?>[];
  final gone = <String>[];
  final goneAt = <int>{};
  for (final (position, item) in items.indexed) {
    if (item case final String entry
        when named.contains(TaskRef.parse(entry)?.task)) {
      gone.add(entry);
      goneAt.add(position);
    } else {
      kept.add(item);
    }
  }
  return (kept: kept, gone: gone, goneAt: goneAt);
}

/// Returns the key block of [fieldId] after the entries at [goneAt] go, or
/// null when no entry [kept] stays.
///
/// A plain block list keeps every other byte; any other form is written anew
/// as a block list.
String? _blockAfter(
  KeyBlock block,
  String fieldId,
  List<Object?> kept,
  Set<int> goneAt,
) {
  if (kept.isEmpty) return null;
  final spliced = _withoutItemLines(block, kept.length + goneAt.length, goneAt);
  if (spliced != null) return spliced;
  final lines = [for (final item in kept) '  - ${_yamlOf(item)}\n'];
  return '$fieldId:\n${lines.join()}';
}

final _itemLine = RegExp(r'^\s*-(\s|$)');

/// Returns [block]'s text without the item lines at [goneAt], or null when
/// the block is not a plain block list of [count] one-line items.
String? _withoutItemLines(KeyBlock block, int count, Set<int> goneAt) {
  final lines = const LineSplitter().convert(block.text);
  final keyAt = lines.indexWhere((line) => !_isTrivia(line));
  if (keyAt < 0) return null;
  final afterKey = lines[keyAt].substring(block.key.length).trim();
  if (!afterKey.startsWith(':') || !_isTrivia(afterKey.substring(1))) {
    return null;
  }
  final itemAt = [
    for (var i = keyAt + 1; i < lines.length; i++)
      if (!_isTrivia(lines[i])) i,
  ];
  if (itemAt.length != count) return null;
  if (itemAt.any((i) => !_itemLine.hasMatch(lines[i]))) return null;
  final dropped = {for (final position in goneAt) itemAt[position]};
  return [
    for (final (i, line) in lines.indexed)
      if (!dropped.contains(i)) '$line\n',
  ].join();
}

/// Whether [line] is blank or a comment.
bool _isTrivia(String line) {
  final text = line.trim();
  return text.isEmpty || text.startsWith('#');
}

/// Returns [item] as a YAML list item, quoted when a bare one would read
/// back as another value.
String _yamlOf(Object? item) {
  if (item is String && _isPlain(item)) return item;
  return jsonEncode(item);
}

bool _isPlain(String text) {
  try {
    return loadYaml(text) == text;
  } on YamlException {
    return false;
  }
}

// MARK: - Writing

/// Returns the step that writes [removal]'s doc, laid out.
///
/// Trust is checked before the path, so a project whose roots wait refuses
/// with the trust text first.
WriteStep _stepOf(WriteSession session, _Removal removal) {
  session.journalTarget.requireTrusted();
  session.requireWritable(removal.doc.docPath);
  return session.docWriteStep(
    removal.doc.docPath,
    removal.laidOut,
    removal.bytes,
  );
}

// MARK: - Answer

ReadAnswer _answerOf(
  WriteSession session,
  Set<String> named,
  List<_Removal> removals,
) {
  final text = StringBuffer();
  final docs = <Map<String, Object>>[];
  for (final removal in removals) {
    final doc = removal.doc;
    final base = _baseAfter(session, removal);
    text.writeln(namingLine(doc, base: base, removed: removal.removed));
    docs.add({
      'path': doc.docPath,
      'name': doc.name,
      'docType': ?doc.docTypeId,
      'removed': removal.removed,
      'base': base,
    });
  }
  final held = {for (final removal in removals) ...removal.tasks};
  final noRefs = [
    for (final task in named)
      if (!held.contains(task)) task,
  ];
  for (final task in noRefs) {
    text.writeln('$task · no refs');
  }
  return ReadAnswer(
    text: text.toString(),
    json: {'docs': docs, 'noRefs': noRefs},
  );
}

/// Returns the `bases.doc` `get` prints for the doc [removal] wrote.
String _baseAfter(WriteSession session, _Removal removal) {
  final after = parseIndexedDoc(
    docPath: removal.doc.docPath,
    bytes: utf8.encode(removal.laidOut),
    match: MatchedDocType(removal.docType),
    statusesOutside: session.project.statusesOutsideApproval,
  );
  return basesOf(after.content, removal.docType)['doc']! as String;
}
