import 'dart:io';

import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';

const _field = 'implements';
const _symbolMark = ':';
const _segmentMark = '.';
const _edge = r'[\p{L}\p{N}_]';

/// Returns the `implements` findings of a typed [doc]; an untyped doc has none.
///
/// Only a doc type that defines `implements` is resolved (INV-2). An entry
/// `path[:Symbol]` is a path finding when the path names no regular file, and a
/// symbol finding when a segment of its Symbol occurs nowhere in that file as a
/// whole word. A code file is read only to resolve a Symbol (INV-11).
Iterable<Finding> checkImplements(CheckContext context, IndexedDoc doc) sync* {
  final type = context.typeOf(doc);
  if (type == null || !type.fields.any((field) => field.id == _field)) return;
  for (final (:value, :line, text: _)
      in context.linesOf(doc).entriesOf(_field)) {
    if (value is! String) continue;
    final split = value.indexOf(_symbolMark);
    final path = split < 0 ? value : value.substring(0, split);
    final symbol = split < 0 ? '' : value.substring(split + 1);
    if (FileSystemEntity.typeSync('${context.projectRoot.path}/$path') !=
        FileSystemEntityType.file) {
      yield context.finding(
        doc,
        FindingKind.implementsPathUnresolved,
        line: line,
        message: '$path is no file',
        keys: {'entry': value},
      );
      continue;
    }
    if (symbol.isEmpty) continue;
    final text = context.codeTextOf(path);
    if (text == null) continue;
    for (final segment in symbol.split(_segmentMark)) {
      if (_wordPattern(segment).hasMatch(text)) continue;
      yield context.finding(
        doc,
        FindingKind.implementsSymbolUnresolved,
        line: line,
        message: '$segment occurs nowhere in $path',
        keys: {'entry': value, 'symbol': segment},
      );
      break;
    }
  }
}

RegExp _wordPattern(String word) =>
    RegExp('(?<!$_edge)${RegExp.escape(word)}(?!$_edge)', unicode: true);
