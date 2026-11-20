import 'package:specstone_core/src/templates/models/merged_doc_type.dart';

/// A typed doc of the run as the placement reads it: its DocPath after the
/// moves, its doc type, the code target whose pattern set matched it (null for
/// a shared doc), and its LF text after the steps so far.
final class PlacementDoc {
  const new({
    required this.plannedPath,
    required this.type,
    required this.target,
    required this.lf,
  });

  final String plannedPath;
  final MergedDocType? type;
  final String? target;
  final String lf;
}
