import 'dart:convert';

import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/consistency_check/implements_entry.dart';
import 'package:specstone_core/src/consistency_check/record_doc.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/record_entries.dart';
import 'package:specstone_core/src/templates/code_target.dart';
import 'package:specstone_core/src/templates/doc_type_layer.dart';

/// Returns the test pointer findings of a record [doc]; any other doc has
/// none.
///
/// A line `path[:name]` is resolved from the code root of the record's own
/// target when its item is neither `planned` nor `skipped`. A line naming no
/// item is reported by the record entry rule, never here. A test file is read
/// only to find a name, and at most once per run.
Iterable<Finding> checkTestPointers(
  CheckContext context,
  IndexedDoc doc,
) sync* {
  final read = recordDocOf(context, doc);
  if (read == null) return;
  final (:type, :feature, :lines) = read;
  final fieldId = recordTestFieldOf(type)?.id;
  final target = context.targets
      .where((target) => target.name == doc.target)
      .firstOrNull;
  if (fieldId == null || target == null) return;
  final items = recordItemsOf(feature, context.index.childrenOf);
  for (final (:value, :line, text: _) in lines.entriesOf(fieldId)) {
    if (value is! String) continue;
    final parsed = recordCodeLineOf(value);
    final item = items[parsed?.item];
    if (parsed == null || item == null) continue;
    if (!_isResolved(context, item, doc.target)) continue;
    yield* _resolve(context, doc, target, parsed.code, line);
  }
}

Iterable<Finding> _resolve(
  CheckContext context,
  IndexedDoc doc,
  CodeTarget target,
  String code,
  int line,
) sync* {
  final entry = ImplementsEntry(code);
  final path = entry.path;
  if (!entry.namesFileFrom(context.codeRootOf(target))) {
    yield context.finding(
      doc,
      FindingKind.testsUnresolved,
      line: line,
      message: path.isEmpty ? 'the test path is empty' : '$path is no file',
      keys: {'entry': code},
    );
    return;
  }
  final name = entry.testName;
  if (name == null || name.isEmpty) return;
  final texts = _textsByContext[context] ??= _TestTexts();
  final text = texts.textOf(context, target, path);
  if (text == null || text.contains(name)) return;
  yield context.finding(
    doc,
    FindingKind.testsUnresolved,
    line: line,
    message: '$name occurs nowhere in $path',
    keys: {'entry': code, 'name': name},
  );
}

/// Whether [item]'s lines are resolved: its status in [codeTarget] is
/// `implemented` or `deprecated`.
bool _isResolved(CheckContext context, IndexedDoc item, String? codeTarget) =>
    switch (context.index.itemStatus(item, codeTarget: codeTarget)) {
      RecordStatus.implemented || RecordStatus.deprecated => true,
      RecordStatus.planned || RecordStatus.skipped => false,
    };

/// The test files each run has read, held for the run's lifetime.
final Expando<_TestTexts> _textsByContext = Expando('test files read');

/// The text of each test file one run has read, each read once.
final class _TestTexts {
  final Map<(CodeTarget, String), String?> _texts = {};

  /// Returns the text of the file at [path] under [target]'s code root, or
  /// null when it cannot be read; the unreadable file adds one warning.
  String? textOf(CheckContext context, CodeTarget target, String path) {
    final key = (target, path);
    if (_texts.containsKey(key)) return _texts[key];
    final bytes = context.readCodeBytes(target, path);
    String? text;
    if (bytes == null) {
      context.warn(
        '$path: cannot read the file; tests names in it are not checked',
      );
    } else {
      text = const Utf8Decoder(allowMalformed: true).convert(bytes);
    }
    return _texts[key] = text;
  }
}
