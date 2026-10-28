import 'dart:io';

import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/rendering/formatter.dart';
import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:yaml/yaml.dart';

const _referenceType = 'reference';
const _architectureType = 'architecture';
const _filesField = 'files';
const _concernsSection = 'concerns';
const _separator = '/';
const _seeMarker = ' see ';
const _notApplicable = 'N/A — ';
const _backtick = '`';
const _templatesFolder = '.specstone/templates';
const _referenceKey = 'reference';
const _addKey = 'add';
const _docKey = 'doc';

/// Returns the `listed_file_missing` and `concerns_target_unresolved`
/// findings of a typed [doc].
///
/// A `reference` doc lists files that sit beside it. An `architecture` doc
/// ends each Concerns line with `see <x>`, where `<x>` is a sibling file or a
/// `##` header of the doc, matched as F-05's `format` matches headers.
Iterable<Finding> checkReferenceEntries(
  CheckContext context,
  IndexedDoc doc,
) sync* {
  switch (doc.docTypeId) {
    case _referenceType:
      yield* _missingListedFiles(context, doc);
    case _architectureType:
      yield* _unresolvedConcerns(context, doc);
  }
}

/// Returns a `reference_doc_unresolved` finding for each `doc` entry of a
/// project template `reference:` list that names no doc.
///
/// Reads the top-level `<id>.yaml` files of `.specstone/templates/`, in the
/// plain `reference:` list or its `add:` list. The finding sits at the entry's
/// line of the template file and carries no name.
Iterable<Finding> unresolvedTemplateReferences(CheckContext context) sync* {
  final folder = Directory('${context.projectRoot.path}/$_templatesFolder');
  if (!folder.existsSync()) return;
  final files = [
    for (final entity in folder.listSync())
      if (entity is File && isDocTypeFileName(_baseName(entity))) entity,
  ]..sort((a, b) => _baseName(a).compareTo(_baseName(b)));
  final names = {for (final doc in context.index.docs) doc.name};
  for (final file in files) {
    final path = '$_templatesFolder/${_baseName(file)}';
    for (final (:value, :line) in _docEntries(file)) {
      if (names.contains(value)) continue;
      yield Finding(
        kind: FindingKind.referenceDocUnresolved,
        path: path,
        line: line,
        message: 'reference doc $value names no doc',
        keys: {'value': value},
      );
    }
  }
}

Iterable<Finding> _missingListedFiles(
  CheckContext context,
  IndexedDoc doc,
) sync* {
  final folder = _folderOf(context, doc);
  for (final (:value, :line, text: _)
      in context.linesOf(doc).entriesOf(_filesField)) {
    if (value is! String || File('$folder/$value').existsSync()) continue;
    yield context.finding(
      doc,
      FindingKind.listedFileMissing,
      line: line,
      message: '$value is not beside the doc',
      keys: {'entry': value},
    );
  }
}

Iterable<Finding> _unresolvedConcerns(
  CheckContext context,
  IndexedDoc doc,
) sync* {
  final held = context.contentOf(doc).sections;
  final type = context.typeOf(doc);
  if (type == null) return;
  final headers = {
    for (final section in held)
      headerKey(section.headerLine.trimLeft().substring(2)),
  };
  final folder = _folderOf(context, doc);
  for (var i = 0; i < held.length; i++) {
    if (context.templateSectionAt(doc, i)?.id != _concernsSection) {
      continue;
    }
    for (final line in context.bodyLinesOf(doc, i)) {
      final target = line.fenced ? null : _seeTarget(line.text);
      if (target == null) continue;
      if (headers.contains(headerKey(target)) ||
          File('$folder/$target').existsSync()) {
        continue;
      }
      yield context.finding(
        doc,
        FindingKind.concernsTargetUnresolved,
        line: line.line,
        message: 'see $target names no section or file',
        keys: {'target': target},
      );
    }
  }
}

/// Returns the text after the last ` see ` of [line], or null for a line that
/// is `N/A — ` or holds no ` see `.
String? _seeTarget(String line) {
  if (line.contains(_notApplicable)) return null;
  final at = line.lastIndexOf(_seeMarker);
  if (at < 0) return null;
  var target = line.substring(at + _seeMarker.length).trim();
  if (target.length > 1 &&
      target.startsWith(_backtick) &&
      target.endsWith(_backtick)) {
    target = target.substring(1, target.length - 1);
  }
  return target.isEmpty ? null : target;
}

/// Returns each string `doc` value of the reference entries of [file], with
/// its 1-based line.
Iterable<({String value, int line})> _docEntries(File file) sync* {
  final YamlNode root;
  try {
    root = loadYamlNode(file.readAsStringSync());
  } on YamlException {
    return;
  } on FileSystemException {
    return;
  }
  if (root is! YamlMap) return;
  var list = root.nodes[_referenceKey];
  if (list is YamlMap) list = list.nodes[_addKey];
  if (list is! YamlList) return;
  for (final item in list.nodes) {
    if (item is! YamlMap) continue;
    final value = item[_docKey];
    if (value is String) {
      yield (value: value, line: item.span.start.line + 1);
    }
  }
}

String _folderOf(CheckContext context, IndexedDoc doc) {
  final at = doc.docPath.lastIndexOf(_separator);
  final folder = at < 0 ? '' : doc.docPath.substring(0, at);
  return folder.isEmpty
      ? context.docsRoot.path
      : '${context.docsRoot.path}/$folder';
}

String _baseName(File file) =>
    file.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
