import 'dart:io';

import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/consistency_check/reference_rules.dart'
    show architectureTypeId;
import 'package:specstone_core/src/index_query/code_root_files.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/portable_path.dart';
import 'package:specstone_core/src/templates/code_target.dart';
import 'package:specstone_core/src/templates/doc_type_layer.dart'
    show RecordStatus;
import 'package:specstone_core/src/templates/merged_doc_type.dart';

const _coversField = 'covers';
const _codeField = 'code';
const _separator = '/';

/// The code targets of one check run and the implemented work each holds.
///
/// A target's `covers` entries and `code` roots resolve once the target holds
/// an `implemented` story or FR (INV-19); this reads that once per target, so
/// each rule stays one pass over the docs.
final class ImplementedWork {
  new(this._context, this.targets)
    : _work = {for (final target in targets) target: _workOf(_context, target)};

  final CheckContext _context;

  /// The targets the run's code rules cover.
  final List<CodeTarget> targets;

  final Map<CodeTarget, ({bool any, Set<String> features})> _work;

  /// Returns the target [doc] belongs to, null when it belongs to none of
  /// [targets].
  ///
  /// A per-target doc belongs to the target it names; any other doc to the
  /// project's one target, and to none when the project has several.
  CodeTarget? targetOf(IndexedDoc doc) {
    final all = _context.targets;
    final owner = switch (doc.target) {
      final name? => all.where((target) => target.name == name).firstOrNull,
      null => all.length == 1 ? all.single : null,
    };
    return targets.contains(owner) ? owner : null;
  }

  /// Whether [target] holds the work that ends the wait of [doc]'s paths.
  ///
  /// An `architecture` doc waits for an entry of its feature, nested features
  /// included; any other doc waits for an entry of the target.
  bool endsWaitOf(IndexedDoc doc, CodeTarget target) {
    final work = _work[target]!;
    final feature = doc.docTypeId == architectureTypeId
        ? _context.index.parentOf(doc)
        : null;
    return switch (feature) {
      IndexedDoc(docTypeId: featureType) => work.features.contains(
        feature.name,
      ),
      _ => work.any,
    };
  }
}

/// Returns whether [target] holds an implemented story or FR, and the name
/// of each feature that holds one in its subtree.
({bool any, Set<String> features}) _workOf(
  CheckContext context,
  CodeTarget target,
) {
  final index = context.index;
  final features = <String>{};
  var any = false;
  for (final doc in index.docs) {
    if (doc.docTypeId != storyType && doc.docTypeId != frType) continue;
    if (index.statusOf(doc, codeTarget: target.name) !=
        RecordStatus.implemented.wire) {
      continue;
    }
    any = true;
    for (var up = index.parentOf(doc); up != null; up = index.parentOf(up)) {
      if (up.docTypeId == featureType) features.add(up.name);
    }
  }
  return (any: any, features: features);
}

/// Returns the `covers_path_missing` and `code_root_missing` findings of a
/// typed [doc].
///
/// Only a doc type that defines `covers` or `code` is read, and only once
/// [work] says the doc's target holds the work that ends its wait. An entry
/// names something when its path in [normalCodeEntry]'s form is a file or a
/// folder of that target's code root.
Iterable<Finding> checkCoversAndCodeRoots(
  CheckContext context,
  ImplementedWork work,
  IndexedDoc doc,
) sync* {
  final type = context.typeOf(doc);
  if (type == null) return;
  if (doc.target == null && context.targets.length > 1) {
    yield* _sharedDocPaths(context, doc, type);
    return;
  }
  final target = work.targetOf(doc);
  if (target == null || !work.endsWaitOf(doc, target)) return;
  final codeRoot = context.codeRootOf(target);
  for (final (field, kind) in [
    (_coversField, FindingKind.coversPathMissing),
    (_codeField, FindingKind.codeRootMissing),
  ]) {
    if (!context.typeHoldsField(type, field)) continue;
    for (final (:value, :line, text: _)
        in context.linesOf(doc).entriesOf(field)) {
      if (value is! String || namesFileOrFolderFrom(codeRoot, value)) continue;
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

/// Yields the `shared_doc_code_path` finding of a doc that belongs to no
/// target but carries `covers` or `code` in a project of several targets.
///
/// One finding per doc, at the line of the first such key; its paths count for
/// no target.
Iterable<Finding> _sharedDocPaths(
  CheckContext context,
  IndexedDoc doc,
  MergedDocType type,
) sync* {
  final lines = context.linesOf(doc);
  final line = [
    for (final field in [_coversField, _codeField])
      if (context.typeHoldsField(type, field) &&
          lines.entriesOf(field).isNotEmpty)
        lines.keyLine(field),
  ].nonNulls.firstOrNull;
  if (line == null) return;
  yield context.finding(
    doc,
    FindingKind.sharedDocCodePath,
    line: line,
    message:
        'the doc carries code paths but belongs to no target; move them into '
        'a doc of the target they belong to',
  );
}

/// Returns a `code_uncovered` finding for each code file no `covers` entry
/// of the same target reaches.
///
/// Each code root of a target's doc that defines `code` is listed without
/// following links and without reading a file. A file under two roots is
/// reported once, under the first root that lists it. A file under the code
/// root of another target nested in this one belongs to that target. A folder
/// that cannot be listed is a warning, not a finding.
Iterable<Finding> uncoveredCode(
  CheckContext context,
  ImplementedWork work,
) sync* {
  for (final target in work.targets) {
    final docs = [
      for (final doc in context.index.docs)
        if (work.targetOf(doc) == target) doc,
    ];
    final covers = _coversOf(context, docs);
    final nested = _nestedRootsOf(context, target);
    final reported = <String>{};
    for (final doc in docs) {
      if (!context.typeHoldsField(context.typeOf(doc), _codeField)) continue;
      for (final (:value, :line, text: _)
          in context.linesOf(doc).entriesOf(_codeField)) {
        if (value is! String) continue;
        final paths = filesUnderCodeRoot(
          context.codeRootOf(target),
          value,
          skipFolders: nested,
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
}

/// Returns the code root of each other target that lies inside [target]'s, as
/// a path from [target]'s code root.
List<String> _nestedRootsOf(CheckContext context, CodeTarget target) {
  final own = context.codeRootOf(target).path;
  final prefix = own.endsWith(Platform.pathSeparator)
      ? own
      : '$own${Platform.pathSeparator}';
  final nested = <String>[];
  for (final other in context.targets) {
    final path = context.codeRootOf(other).path;
    if (other == target || path.length <= prefix.length) continue;
    if (!path.startsWith(prefix)) continue;
    nested.add(
      path
          .substring(prefix.length)
          .split(Platform.pathSeparator)
          .join(_separator),
    );
  }
  return nested;
}

/// Returns every `covers` entry of the typed [docs] in [normalCodeEntry]'s
/// form, the form the lister gives its paths in.
List<String> _coversOf(CheckContext context, List<IndexedDoc> docs) => [
  for (final doc in docs)
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

/// Whether [entry], in [normalCodeEntry]'s form, is a file or a folder from
/// [base].
///
/// An [entry] that is no [isPortablePath] as written names nothing, as the code
/// file lister reads it: `\` is a separator on Windows alone, and the disk
/// finds a trimmed name there alone.
///
/// The one rule `check` and the migrate's `code_root` count resolve a
/// `covers` or `code` entry by.
bool namesFileOrFolderFrom(Directory base, String entry) {
  final normal = normalCodeEntry(entry);
  return isPortablePath(entry) &&
      FileSystemEntity.typeSync('${base.path}$_separator$normal') !=
          FileSystemEntityType.notFound;
}
