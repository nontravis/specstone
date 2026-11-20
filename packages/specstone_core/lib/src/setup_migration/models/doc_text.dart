import 'package:specstone_core/src/rendering/models/line_ending.dart';

/// A doc file as LF text with the line style and byte order mark it came with,
/// and the `textHashOf` its text had.
final class DocText {
  const new({
    required this.lf,
    required this.ending,
    required this.bom,
    required this.hash,
  });

  final String lf;
  final LineEnding ending;
  final bool bom;
  final String hash;
}
