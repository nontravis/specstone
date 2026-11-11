import 'dart:io';

import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/index_query/code_root_files.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';

const _coversField = 'covers';
const _codeField = 'code';
const _separator = '/';

/// Returns the `covers_path_missing` and `code_root_missing` findings of a
/// typed [doc].
///
/// Only a doc type that defines `covers` or `code` is read. An entry names
/// something when its path in [normalCodeEntry]'s form is a file or a folder.
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
      final paths = filesUnderCodeRoot(
        context.codeRoot,
        value,
        onUnlistable: (folder) => context.warn(
          '$folder: cannot list the folder; files under it are not checked '
          'for covers',
        ),
      );
      for (final path in paths) {
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

/// Returns every `covers` entry of every typed doc in [normalCodeEntry]'s
/// form, the form the lister gives its paths in.
List<String> _coversOf(CheckContext context) => [
  for (final doc in context.index.docs)
    if (context.typeHoldsField(context.typeOf(doc), _coversField))
      for (final (:value, line: _, text: _)
          in context.linesOf(doc).entriesOf(_coversField))
        if (value is String) normalCodeEntry(value),
];

/// Whether an entry equals [path], names a folder that holds it, or names
/// the code root itself.
///
/// Matching is by path segment: `lib/src` does not reach `lib/srcx/a.dart`.
bool _isCovered(List<String> covers, String path) => covers.any(
  (entry) =>
      entry.isEmpty || path == entry || path.startsWith('$entry$_separator'),
);

bool _namesSomething(CheckContext context, String entry) =>
    namesFileOrFolderFrom(context.codeRoot, entry);

/// Whether [entry], in [normalCodeEntry]'s form, is a file or a folder from
/// [base].
///
/// The one rule `check` and the migrate's `code_root` count resolve a
/// `covers` or `code` entry by.
bool namesFileOrFolderFrom(Directory base, String entry) =>
    FileSystemEntity.typeSync(
      '${base.path}$_separator${normalCodeEntry(entry)}',
    ) !=
    FileSystemEntityType.notFound;
