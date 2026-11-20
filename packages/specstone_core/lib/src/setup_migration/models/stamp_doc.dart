import 'package:specstone_core/src/templates/models/merged_doc_type.dart';

/// A doc of the run: planned DocPath, LF text, and merged doc type, null for
/// an untyped doc.
final class StampDoc {
  const new({required this.docPath, required this.lf, required this.type});

  final String docPath;
  final String lf;
  final MergedDocType? type;
}
