import 'dart:io';

import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';

const _coversField = 'covers';
const _codeField = 'code';
const _separator = '/';
const _dotName = '.';

/// Returns the `covers_path_missing` and `code_root_missing` findings of a
/// typed [doc].
///
/// Only a doc type that defines `covers` or `code` is read. An entry names
/// something when its path, a final `/` dropped, is a file or a folder.
Iterable<Finding> checkCoversAndCodeRoots(
  CheckContext context,
  IndexedDoc doc,
) sync* {
  final type = context.typeOf(doc);
  if (type == null) return;
  for (final (field, kind) in [
    (_coversField, FindingKind.coversPathMissing),
    (_codeField, FindingKind.codeRootMissing),
  ]) {
    if (!context.typeHoldsField(type, field)) continue;
    for (final (:value, :line, text: _)
        in context.linesOf(doc).entriesOf(field)) {
      if (value is! String || _namesSomething(context, value)) continue;
      yield context.finding(
        doc,
        kind,
        line: line,
        message: '$value names nothing on disk',
        keys: {'entry': value},
      );
    }
  }
}

/// Returns a `code_uncovered` finding for each code file no `covers` entry
/// reaches.
///
/// Each code root of a doc that defines `code` is listed without following
/// links and without reading a file. A file under two roots is reported once,
/// under the first root that lists it. A folder that cannot be listed is a
/// warning, not a finding.
Iterable<Finding> uncoveredCode(CheckContext context) sync* {
  final covers = _coversOf(context);
  final reported = <String>{};
  for (final doc in context.index.docs) {
    if (!context.typeHoldsField(context.typeOf(doc), _codeField)) continue;
    for (final (:value, :line, text: _)
        in context.linesOf(doc).entriesOf(_codeField)) {
      if (value is! String) continue;
      final root = _withoutFinalSlash(value);
      for (final path in _filesUnder(context, root)) {
        if (_isCovered(covers, path) || !reported.add(path)) continue;
        yield context.finding(
          doc,
          FindingKind.codeUncovered,
          line: line,
          message:
              '$path is under the code root $value and no covers entry '
              'reaches it',
          keys: {'path': path},
        );
      }
    }
  }
}

/// Returns every `covers` entry of every typed doc, a final `/` dropped.
List<String> _coversOf(CheckContext context) => [
  for (final doc in context.index.docs)
    if (context.typeHoldsField(context.typeOf(doc), _coversField))
      for (final (:value, line: _, text: _)
          in context.linesOf(doc).entriesOf(_coversField))
        if (value is String) _withoutFinalSlash(value),
];

/// Whether an entry equals [path] or names a folder that holds it.
///
/// Matching is by path segment: `lib/src` does not reach `lib/srcx/a.dart`.
bool _isCovered(List<String> covers, String path) => covers.any(
  (entry) => path == entry || path.startsWith('$entry$_separator'),
);

bool _namesSomething(CheckContext context, String entry) =>
    FileSystemEntity.typeSync(
      '${context.projectRoot.path}$_separator${_withoutFinalSlash(entry)}',
    ) !=
    FileSystemEntityType.notFound;

String _withoutFinalSlash(String entry) =>
    entry.endsWith(_separator) ? entry.substring(0, entry.length - 1) : entry;

/// Yields the regular files under [root], as paths from the project root.
///
/// Skips names starting with a dot and links. A missing root yields nothing.
Iterable<String> _filesUnder(CheckContext context, String root) sync* {
  final folder = Directory('${context.projectRoot.path}$_separator$root');
  final List<FileSystemEntity> entities;
  try {
    entities = folder.listSync(followLinks: false);
  } on FileSystemException {
    if (folder.existsSync()) {
      context.warn(
        '$root: cannot list the folder; files under it are not checked for '
        'covers',
      );
    }
    return;
  }
  for (final entity in entities) {
    final name = entity.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
    if (name.startsWith(_dotName)) continue;
    final path = '$root$_separator$name';
    switch (entity) {
      case File():
        yield path;
      case Directory():
        yield* _filesUnder(context, path);
      case _:
    }
  }
}
