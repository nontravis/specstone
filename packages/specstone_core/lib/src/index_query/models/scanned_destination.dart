import 'package:specstone_core/src/doc_model/models/destination_kind.dart';

/// A link destination as written: its body range, angle brackets left out,
/// the index in the scan's sources of the link written with it, null for a
/// definition's and for one in an image description, which drops its link,
/// and how `markdown` reads it.
final class ScannedDestination {
  const new({
    required this.start,
    required this.end,
    required this.link,
    required this.kind,
  });

  final int start;
  final int end;
  final int? link;
  final DestinationKind kind;
}
