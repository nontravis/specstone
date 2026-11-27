import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/code_rules.dart'
    show CodePathField, codePathMessageOf;
import 'package:specstone_core/src/consistency_check/exact_case_path.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/consistency_check/models/yaml_entry.dart';
import 'package:specstone_core/src/doc_model/reference_grammar.dart'
    show isRootedOrDrivePath, isWebLink;
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/templates/models/merged_field.dart'
    show FieldType;

/// Returns the `source_path_missing` and `source_path_outside_project`
/// findings of a typed [doc].
///
/// Reads each entry of every `source_ref` field, found by field type alone.
/// A web URL is never checked. Any other entry is a path from the project
/// root: a rooted one, or one holding a `..` segment, is reported unread; one
/// that names no file or folder there, in exact letter case and links
/// followed, is missing.
Iterable<Finding> checkDesignSources(
  CheckContext context,
  IndexedDoc doc,
) sync* {
  final type = context.typeOf(doc);
  if (type == null) return;
  final lines = context.linesOf(doc);
  for (final field in type.fields) {
    if (field.type != FieldType.sourceRef) continue;
    for (final YamlEntry(:value, :line) in lines.entriesOf(field.id)) {
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
  final verdict = context.exactPaths.resolve(context.projectRoot, entry);
  if (isRootedOrDrivePath(entry) ||
      verdict.kind == CodePathKind.parentSegment) {
    yield context.finding(
      doc,
      FindingKind.sourcePathOutsideProject,
      line: line,
      message: verdict.kind == CodePathKind.parentSegment
          ? codePathMessageOf(CodePathField.covers, entry, verdict)
          : '$entry leaves the project root',
      keys: {'entry': entry},
    );
  } else if (!verdict.exists && verdict.kind != CodePathKind.empty) {
    yield context.finding(
      doc,
      FindingKind.sourcePathMissing,
      line: line,
      message: verdict.kind == CodePathKind.wrongCase
          ? '$entry is spelled ${verdict.diskPath} on disk'
          : '$entry names nothing on disk',
      keys: {
        'entry': entry,
        if (verdict.kind == CodePathKind.wrongCase)
          'diskPath': ?verdict.diskPath,
      },
    );
  }
}
