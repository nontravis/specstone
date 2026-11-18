import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/code_rules.dart'
    show namesFileOrFolderFrom;
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/doc_model/reference_grammar.dart'
    show isRootedOrDrivePath, isWebLink;
import 'package:specstone_core/src/index_query/code_root_files.dart'
    show normalCodeEntry;
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/templates/doc_type_layer.dart'
    show FieldType;

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
      if (value is! String || isWebLink(value)) continue;
      yield* _entryFindings(context, doc, value, line);
    }
  }
}

/// Yields the finding of the path [entry] at [line], none when it names
/// something under the project root.
Iterable<Finding> _entryFindings(
  CheckContext context,
  IndexedDoc doc,
  String entry,
  int line,
) sync* {
  if (_leavesProject(entry)) {
    yield context.finding(
      doc,
      FindingKind.sourcePathOutsideProject,
      line: line,
      message: '$entry leaves the project root',
      keys: {'entry': entry},
    );
  } else if (!namesFileOrFolderFrom(context.projectRoot, entry)) {
    yield context.finding(
      doc,
      FindingKind.sourcePathMissing,
      line: line,
      message: '$entry names nothing on disk',
      keys: {'entry': entry},
    );
  }
}

/// Whether [entry] is rooted, or reaches above the project root after its
/// `.` and `..` segments apply, `\` read as a separator too.
bool _leavesProject(String entry) {
  if (isRootedOrDrivePath(entry)) return true;
  final normal = normalCodeEntry(entry.replaceAll(r'\', '/'));
  return normal == _parentSegment || normal.startsWith('$_parentSegment/');
}
