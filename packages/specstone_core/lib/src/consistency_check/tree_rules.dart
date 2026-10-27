import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/check_scope.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/doc_model/path_pattern.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/templates/merged_set.dart';

const _pathSeparator = '/';
const _idSeparator = ', ';
const _candidatesMarker = ' candidate parent docs: ';
const _candidatesEnd = '; it has no parent doc';
final _unreadableFile = RegExp(r'^(.*[^/]): cannot be read; skipped$');

/// Returns the first path segment of every doc type `path` in [set] (INV-8).
Set<String> checkedFoldersOf(MergedSet set) => {
  for (final type in set.docTypes)
    if (type.path case final path?) path.split(_pathSeparator).first,
};

/// Returns the findings of an untyped [doc] in a checked folder (FR-06).
///
/// A doc that two or more doc types match is `doc_type_ambiguous`; any other
/// is `untyped_doc`. Each states the F-01 warning it reports.
Iterable<Finding> checkDocType(CheckContext context, IndexedDoc doc) sync* {
  final prefix = '${doc.docPath} matches ';
  for (final warning in doc.warnings) {
    if (!warning.startsWith(prefix)) continue;
    final ids = warning
        .substring(warning.indexOf(': ', prefix.length) + 2)
        .split(_idSeparator);
    if (ids.length < 2) continue;
    context.state(warning);
    yield context.finding(
      doc,
      FindingKind.docTypeAmbiguous,
      line: 1,
      message: 'doc types ${ids.join(_idSeparator)} all match this path',
      keys: {'docTypes': ids},
    );
    return;
  }
  yield context.finding(
    doc,
    FindingKind.untypedDoc,
    line: 1,
    message: 'no doc type matches this path',
  );
}

/// Returns the tree findings of [doc] in a checked folder (FR-07).
///
/// Invalid UTF-8 applies to any doc. A typed doc also reports a repeated order
/// number, candidate parents, and a missing parent. Each states the F-01
/// warning it reports.
Iterable<Finding> checkTree(CheckContext context, IndexedDoc doc) sync* {
  final notUtf8 = '${doc.docPath}: not UTF-8 text; ';
  final utf8Warnings = doc.warnings.where((w) => w.startsWith(notUtf8));
  if (utf8Warnings.isNotEmpty) {
    utf8Warnings.forEach(context.state);
    yield context.finding(
      doc,
      FindingKind.fileNotUtf8,
      line: 1,
      message: 'file is not valid UTF-8',
    );
  }
  if (!doc.isTyped) return;
  yield* _orderNumberDuplicate(context, doc);
  if (context.hasNoParent(doc)) yield _parentProblem(context, doc);
}

/// Returns a `file_unreadable` finding for each file F-01 could not read.
///
/// Only a file in a checked folder and in [scope] is reported; a folder that
/// cannot be read stays a warning (PD9).
Iterable<Finding> unreadableFindings(
  CheckContext context,
  CheckScope scope,
) sync* {
  for (final warning in context.sessionWarnings) {
    final docPath = _unreadableFile.firstMatch(warning)?.group(1);
    if (docPath == null || !context.isCheckedPath(docPath)) continue;
    if (!scope.contains(docPath)) continue;
    context.state(warning);
    yield Finding(
      kind: FindingKind.fileUnreadable,
      path: docPath,
      line: 1,
      message: 'file cannot be read',
    );
  }
}

Finding _parentProblem(CheckContext context, IndexedDoc doc) {
  final candidates = _candidatesOf(context, doc);
  if (candidates != null) {
    return context.finding(
      doc,
      FindingKind.parentAmbiguous,
      line: 1,
      message: 'parent doc is one of ${candidates.join(_idSeparator)}',
      keys: {'candidates': candidates},
    );
  }
  return context.finding(
    doc,
    FindingKind.parentMissing,
    line: 1,
    message:
        'no ${context.typeOf(doc)?.parent} doc is the parent of ${doc.name}',
  );
}

/// Returns the candidate parent paths [doc]'s warning names, and states it.
List<String>? _candidatesOf(CheckContext context, IndexedDoc doc) {
  final prefix = '${doc.docPath} has ';
  for (final warning in doc.warnings) {
    final start = warning.indexOf(_candidatesMarker);
    if (!warning.startsWith(prefix) || start < 0) continue;
    context.state(warning);
    return warning
        .substring(
          start + _candidatesMarker.length,
          warning.lastIndexOf(_candidatesEnd),
        )
        .split(_idSeparator);
  }
  return null;
}

typedef _SiblingKey = (String typeId, String? parentPath, int number);

final _siblingGroups = Expando<Map<_SiblingKey, List<IndexedDoc>>>();

Iterable<Finding> _orderNumberDuplicate(
  CheckContext context,
  IndexedDoc doc,
) sync* {
  final key = _keyOf(context, doc);
  if (key == null) return;
  final groups = _siblingGroups[context] ??= _groupSiblings(context);
  final siblings = groups[key] ?? const <IndexedDoc>[];
  if (siblings.length < 2) return;
  yield context.finding(
    doc,
    FindingKind.orderNumberDuplicate,
    line: 1,
    message: 'order number ${key.$3} repeats among its siblings',
    keys: {
      'siblings': [
        for (final sibling in siblings)
          if (sibling.docPath != doc.docPath) sibling.docPath,
      ],
    },
  );
}

Map<_SiblingKey, List<IndexedDoc>> _groupSiblings(CheckContext context) {
  final groups = <_SiblingKey, List<IndexedDoc>>{};
  for (final doc in context.index.docs) {
    final key = _keyOf(context, doc);
    if (key != null) (groups[key] ??= []).add(doc);
  }
  return groups;
}

/// Returns the sibling group of [doc]; null when it joins none (PD10).
_SiblingKey? _keyOf(CheckContext context, IndexedDoc doc) {
  final type = context.typeOf(doc);
  final path = type?.path;
  if (type == null || path == null || context.hasNoParent(doc)) return null;
  final segments = doc.docPath.split(_pathSeparator);
  final pattern = PathPattern(path);
  for (var depth = segments.length; depth > 0; depth--) {
    final number = pattern.numberAt(segments.sublist(0, depth));
    if (number != null) return (type.id, doc.parentPath, number);
  }
  return null;
}
