import 'package:specstone_core/src/templates/models/merged_doc_type.dart';

/// A doc of the run: planned DocPath, LF text, and merged doc type, null for
/// an untyped doc.
final class StampDoc {
  const new({
    required this.docPath,
    required this.lf,
    required this.type,
    this.target,
  });

  final String docPath;
  final String lf;
  final MergedDocType? type;

  /// The code target whose pattern set matched [docPath]; null for a doc of a
  /// shared doc type or of no doc type.
  final String? target;
}
