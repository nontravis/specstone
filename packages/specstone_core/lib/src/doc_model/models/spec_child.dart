import 'package:specstone_core/src/templates/merged_doc_type.dart';

/// A child doc type whose docs sit in a folder outside its parent's own
/// segment, that folder, and the code target it is read in.
final class SpecChild {
  const new({
    required this.docType,
    required this.folder,
    required this.target,
  });

  final MergedDocType docType;
  final String folder;
  final String? target;
}
