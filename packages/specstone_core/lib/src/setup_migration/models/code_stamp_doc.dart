import 'package:specstone_core/src/templates/models/merged_doc_type.dart';

/// A doc of the run: DocPath, LF text, merged doc type (null when untyped),
/// and the code target whose pattern set matched it (null for a shared doc).
final class CodeStampDoc {
  const new({
    required this.docPath,
    required this.lf,
    required this.type,
    required this.target,
  });

  final String docPath;
  final String lf;
  final MergedDocType? type;
  final String? target;
}
