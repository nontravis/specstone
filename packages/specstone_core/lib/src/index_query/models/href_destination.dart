import 'package:specstone_core/src/doc_model/models/destination_kind.dart';

/// A link destination as written, by its body range, the href `markdown`
/// gives it, and how `markdown` reads it.
final class HrefDestination {
  const new({
    required this.start,
    required this.end,
    required this.href,
    required this.kind,
  });

  final int start;
  final int end;
  final String href;
  final DestinationKind kind;
}
