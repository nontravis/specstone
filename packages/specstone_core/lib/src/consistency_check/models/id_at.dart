import 'package:specstone_core/src/doc_model/models/id_read.dart';

/// One item of a doc, or one story scenario heading, in document order.
///
/// `line` and `endLine` are the 1-based first and last non-blank file lines
/// of the item, nested lines and fenced code included.
final class IdAt {
  const new({
    required this.sectionKey,
    required this.prefix,
    required this.line,
    required this.endLine,
    required this.id,
  });

  final String sectionKey;
  final String prefix;
  final int line;
  final int endLine;
  final IdRead? id;
}
