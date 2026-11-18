import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/code_rules.dart'
    show namesFileOrFolderFrom;
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/index_query/code_root_files.dart'
    show normalCodeEntry;
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/templates/doc_type_layer.dart'
    show FieldType;

final _webUrl = RegExp('^https?://', caseSensitive: false);
final _rootedPath = RegExp(r'^(?:[/\\]|[A-Za-z]:)');
const _parentSegment = '..';

/// Returns the `source_path_missing` and `source_path_outside_project`
/// findings of a typed [doc].
///
/// Reads each entry of every `source_ref` field, found by field type alone.
/// A web URL is never checked. Any other entry is a path from the project
/// root: one that leaves it, once normalized, is reported unread; one that
/// names no file or folder there, links followed, is missing.
Iterable<Finding> checkDesignSources(
  CheckContext context,
  IndexedDoc doc,
) sync* {
  final type = context.typeOf(doc);
  if (type == null) return;
  final lines = context.linesOf(doc);
  for (final field in type.fields) {
    if (field.type != FieldType.sourceRef) continue;
    for (final (:value, :line, text: _) in lines.entriesOf(field.id)) {
      if (value is! String || _webUrl.hasMatch(value)) continue;
      final kind = _leavesProject(value)
          ? FindingKind.sourcePathOutsideProject
          : namesFileOrFolderFrom(context.projectRoot, value)
          ? null
          : FindingKind.sourcePathMissing;
      if (kind == null) continue;
      yield context.finding(
        doc,
        kind,
        line: line,
        message: kind == FindingKind.sourcePathMissing
            ? '$value names nothing on disk'
            : '$value leaves the project root',
        keys: {'entry': value},
      );
    }
  }
}

/// Whether [entry] is rooted, or reaches above the project root after its
/// `.` and `..` segments apply.
bool _leavesProject(String entry) {
  if (_rootedPath.hasMatch(entry)) return true;
  final normal = normalCodeEntry(entry);
  return normal == _parentSegment || normal.startsWith('$_parentSegment/');
}
