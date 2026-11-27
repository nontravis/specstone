import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/code_rules.dart'
    show CodePathField, codePathFindingOf, codePathMessageOf;
import 'package:specstone_core/src/consistency_check/exact_case_path.dart'
    show CodePathKind;
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/consistency_check/implements_entry.dart';
import 'package:specstone_core/src/consistency_check/models/record_doc.dart';
import 'package:specstone_core/src/consistency_check/models/yaml_entry.dart';
import 'package:specstone_core/src/consistency_check/record_doc.dart';
import 'package:specstone_core/src/index_query/code_root_files.dart'
    show normalCodeEntry;
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/record_entries.dart';
import 'package:specstone_core/src/templates/code_link_entry.dart';
import 'package:specstone_core/src/templates/code_target.dart';

const _segmentMark = '.';
const _edge = r'[\p{L}\p{N}_]';

/// Returns the code path findings of a record [doc]; any other doc has none.
///
/// A path `path[:Symbol]` is resolved from the code root of the record's own
/// target when its item is neither `planned` nor `skipped`. A line naming no
/// item is `check_record_entries`'s, never reported here. A code file is read
/// only to resolve a Symbol.
Iterable<Finding> checkImplements(CheckContext context, IndexedDoc doc) sync* {
  final read = recordDocOf(context, doc);
  if (read == null) return;
  final RecordDoc(:type, :feature, :lines) = read;
  final fieldId = recordCodeFieldOf(type)?.id;
  final target = context.targets
      .where((target) => target.name == doc.target)
      .firstOrNull;
  if (fieldId == null || target == null) return;
  final items = recordItemsOf(feature, context.index.childrenOf);
  for (final YamlEntry(:value, :line) in lines.entriesOf(fieldId)) {
    if (value is! String) continue;
    final parsed = recordCodeLineOf(value);
    final item = items[parsed?.item];
    if (parsed == null || item == null) continue;
    if (!context.index.itemStatus(item, codeTarget: doc.target).isBuilt) {
      continue;
    }
    yield* _resolve(
      context,
      doc,
      target,
      CodeLinkEntry(parsed.code).pointer,
      line,
    );
  }
}

Iterable<Finding> _resolve(
  CheckContext context,
  IndexedDoc doc,
  CodeTarget target,
  String code,
  int line,
) sync* {
  final pointer = CodePointer(code);
  final path = pointer.path;
  final verdict = context.exactPaths.resolve(context.codeRootOf(target), path);
  if (codePathFindingOf(CodePathField.implements, verdict) case final kind?) {
    yield context.finding(
      doc,
      kind,
      line: line,
      message: codePathMessageOf(CodePathField.implements, path, verdict),
      keys: {
        'entry': code,
        if (verdict.kind == CodePathKind.wrongCase)
          'diskPath': ?verdict.diskPath,
      },
    );
    return;
  }
  final symbol = pointer.tail;
  if (symbol == null) return;
  if (pointer.fault == CodePointerFault.emptyTail) {
    yield context.finding(
      doc,
      FindingKind.implementsSymbolUnresolved,
      line: line,
      message: 'the Symbol after : is empty',
      keys: {'entry': code, 'symbol': ''},
    );
    return;
  }
  final root = context.codeRootOf(target);
  final diskPath = verdict.diskPath!;
  final file = normalCodeEntry(diskPath);
  if (context.codeFiles.isResolved(root, file, code)) return;
  final text = context.codeTextOf(target, diskPath);
  if (text == null) return;
  final unresolved = unresolvedSymbolOf(code, text);
  if (unresolved == null) context.codeFiles.putResolved(root, file, code);
  if (unresolved case final segment?) {
    yield context.finding(
      doc,
      FindingKind.implementsSymbolUnresolved,
      line: line,
      message: '$segment occurs nowhere in $path',
      keys: {'entry': code, 'symbol': segment},
    );
  }
}

/// Returns the first `Symbol` segment of the `implements` entry [code] that
/// occurs nowhere in [text], the code file it names; null when every segment
/// occurs or [code] holds no Symbol.
///
/// The one Symbol rule `check` and `set --stamp` resolve an entry by.
String? unresolvedSymbolOf(String code, String text) {
  final symbol = ImplementsEntry(code).symbol;
  if (symbol.isEmpty) return null;
  return symbol
      .split(_segmentMark)
      .where((segment) => !_wordPattern(segment).hasMatch(text))
      .firstOrNull;
}

RegExp _wordPattern(String word) =>
    RegExp('(?<!$_edge)${RegExp.escape(word)}(?!$_edge)', unicode: true);
