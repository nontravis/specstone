import 'dart:convert';

import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_splice.dart';
import 'package:specstone_core/src/doc_model/list_block_writer.dart';
import 'package:specstone_core/src/doc_model/task_ref.dart';
import 'package:specstone_core/src/document_writing/locked_doc_texts.dart';
import 'package:specstone_core/src/document_writing/set_doc.dart'
    show checkFieldWrite;
import 'package:specstone_core/src/document_writing/write_session.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';

// MARK: - Public

/// Throws [IndexFault] `argument_invalid` for the first of [tasks] that is
/// empty or holds a `:`, naming it.
void requireTaskIds(List<String> tasks) {
  for (final task in tasks) {
    if (TaskRef.isTaskId(task)) continue;
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
    final texts = LockedDocTexts(session);
    final removals = removalsOf(session, texts, named, codeTarget);
    return _answerOf(removals, writeChangedDocs(session, texts));
  });
}

/// Removes every `task_ref` entry of a task in [named] from the text [texts]
/// holds of each doc [codeTarget] keeps (every doc when null), and returns
/// what each doc lost and the tasks no doc held. Reading through [texts]
/// keeps an earlier edit; each changed field takes the checks of a single
/// `set --field`, and the first that fails throws its [IndexFault].
TaskRemovals removalsOf(
  WriteSession session,
  LockedDocTexts texts,
  Set<String> named,
  String? codeTarget,
) {
  if (named.isEmpty) return const TaskRemovals(docs: [], noRefs: []);
  final docs = [
    for (final doc in session.index.docs)
      if (doc.inTarget(codeTarget)) doc,
  ]..sort((a, b) => a.docPath.compareTo(b.docPath));
  final removals = <TaskRemoval>[];
  final held = <String>{};
  for (final doc in docs) {
    final docType = session.index.typeOf(doc);
    if (docType == null) continue;
    final removal = _removalIn(texts, doc, docType, named);
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
    texts.of(doc).text = removal.text;
    held.addAll(removal.tasks);
    removals.add(TaskRemoval(doc: doc, removed: removal.removed));
  }
  return TaskRemovals(
    docs: removals,
    noRefs: [
      for (final task in named)
        if (!held.contains(task)) task,
    ],
  );
}

// MARK: - Planning

/// What one removal of named tasks changes.
final class TaskRemovals {
  const new({required this.docs, required this.noRefs});

  /// Each doc that loses entries, in DocPath order.
  final List<TaskRemoval> docs;

  /// The named tasks no doc in scope holds, each once in the order named.
  final List<String> noRefs;
}

/// One doc that loses `task_ref` entries.
final class TaskRemoval {
  const new({required this.doc, required this.removed});

  final IndexedDoc doc;

  /// The entries removed, as the doc held them, in field then entry order.
  final List<String> removed;
}

/// One doc's text after the removal, before its checks.
final class _Removal {
  const new({
    required this.text,
    required this.removed,
    required this.tasks,
    required this.fieldValues,
  });

  /// The doc's text after the removal, with LF line ends.
  final String text;

  /// The entries removed, as the doc held them, in field then entry order.
  final List<String> removed;

  /// The named tasks the removed entries hold.
  final Set<String> tasks;

  /// The YAML each changed field takes, by field id; null drops the key.
  final Map<String, String?> fieldValues;
}

/// Returns what [doc] loses, or null when it holds no entry of [named].
_Removal? _removalIn(
  LockedDocTexts texts,
  IndexedDoc doc,
  MergedDocType docType,
  Set<String> named,
) {
  final fields = [
    for (final field in docType.fields)
      if (field.type == FieldType.taskRef) field.id,
  ];
  if (fields.isEmpty) return null;
  final held = texts.of(doc).text;
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
    final items = block == null ? null : listEntriesOf(block);
    if (block == null || items == null) continue;
    final _SplitEntries(:kept, :gone) = _split(items, named);
    if (gone.isEmpty) continue;
    removed.addAll(gone);
    tasks.addAll([for (final entry in gone) TaskRef.parse(entry)!.task]);
    fieldValues[fieldId] = kept.isEmpty ? null : jsonEncode(kept);
    text = withKeyBlock(
      text,
      fieldId,
      kept.isEmpty ? null : listBlockOf(fieldId, kept, onDisk: block),
    );
  }
  if (removed.isEmpty) return null;
  return _Removal(
    text: text,
    removed: removed,
    tasks: tasks,
    fieldValues: fieldValues,
  );
}

/// The list items that stay, and the task entries that go.
final class _SplitEntries {
  const new({required this.kept, required this.gone});

  final List<Object?> kept;
  final List<String> gone;
}

/// Splits [items] into those that stay and the entries of a task in [named].
_SplitEntries _split(List<Object?> items, Set<String> named) {
  final kept = <Object?>[];
  final gone = <String>[];
  for (final item in items) {
    if (item case final String entry
        when named.contains(TaskRef.parse(entry)?.task)) {
      gone.add(entry);
    } else {
      kept.add(item);
    }
  }
  return _SplitEntries(kept: kept, gone: gone);
}

// MARK: - Answer

/// Returns the answer of a `--remove-task` that [removals] planned and
/// [written] wrote, each removal's doc among [written].
ReadAnswer _answerOf(TaskRemovals removals, List<WrittenDoc> written) {
  final bases = {for (final doc in written) doc.doc.docPath: doc.base};
  final text = StringBuffer();
  final docs = <Map<String, Object>>[];
  for (final removal in removals.docs) {
    final doc = removal.doc;
    final base =
        bases[doc.docPath] ??
        (throw StateError('${doc.docPath} lost entries but was not written'));
    text.writeln(namingLine(doc, base: base, removed: removal.removed));
    docs.add({
      'path': doc.docPath,
      'name': doc.name,
      'docType': ?doc.docTypeId,
      'removed': removal.removed,
      'base': base,
    });
  }
  for (final task in removals.noRefs) {
    text.writeln('$task · no refs');
  }
  return ReadAnswer(
    text: text.toString(),
    json: {'docs': docs, 'noRefs': removals.noRefs},
  );
}
