import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/rendering/line_ending.dart';

/// A doc as it stands on disk under the write lock.
final class LockedDoc {
  new({required this.bytes, required this.parsed})
    : lfText = toLf(parsed.content.text);

  final List<int> bytes;
  final ParsedDoc parsed;

  /// The doc's text with LF line ends and no BOM.
  final String lfText;

  List<IndexedSection> get sections => parsed.content.sections;
}
