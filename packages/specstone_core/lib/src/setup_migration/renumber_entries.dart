import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_splice.dart' show withKeyBlock;
import 'package:specstone_core/src/document_writing/key_block_values.dart';

/// Returns [text] with each value of the frontmatter key [name] set to what
/// [rename] returns for it, or kept when it returns null.
String withBlockValues(
  String text,
  String name,
  String? Function(String value) rename,
) {
  final block = Doc.parse(text).frontmatter
      ?.where((candidate) => candidate.name == name)
      .firstOrNull;
  if (block == null) return text;
  final renamed = renameKeyBlockValues(block.text, block.key, rename);
  return renamed == block.text ? text : withKeyBlock(text, name, renamed);
}
