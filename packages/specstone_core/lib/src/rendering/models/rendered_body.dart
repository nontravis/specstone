import 'package:specstone_core/src/doc_model/models/doc_anchors.dart';

/// A doc rendered as html, whether `parseMarkdown` read its body, and the
/// anchor set of that parse.
final class RenderedBody {
  const new({
    required this.html,
    required this.bodyParsed,
    required this.anchors,
  });

  final String html;
  final bool bodyParsed;
  final DocAnchors anchors;
}
