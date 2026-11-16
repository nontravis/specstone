import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/index_query/link_scan.dart'
    show LinkScan, linkScanOf;

/// One doc body read once: its links, its prose, and where each line starts.
final class BodyScan {
  new(this.lf);

  final String lf;
  late final String body = Doc.parse(lf).afterFrontmatter;

  /// The file line of the first body line.
  late final int firstLine =
      '\n'.allMatches(lf.substring(0, lf.length - body.length)).length + 1;
  late final LinkScan scan = linkScanOf(body, firstLine: firstLine);
  late final List<int> starts = _lineStartsOf(body);

  int _lineIndexOf(int offset) => starts.lastIndexWhere((s) => s <= offset);
  int fileLineOf(int offset) => firstLine + _lineIndexOf(offset);
  int columnOf(int offset) => offset - starts[_lineIndexOf(offset)];
}

List<int> _lineStartsOf(String text) => [
  0,
  for (var at = 0; at < text.length; at++)
    if (text.codeUnitAt(at) == 0x0A) at + 1,
];
