import 'package:specstone_core/src/templates/code_link_entry.dart'
    show CodePointer;

/// The frontmatter field whose entries point at code.
const implementsField = 'implements';

/// One `implements` entry, `path[:Symbol]`, split as [CodePointer] splits
/// it.
extension type const ImplementsEntry(String text) {
  /// The path part: the text before the first `:`, or all of it.
  String get path => CodePointer(text).path;

  /// The Symbol part after the first `:`; empty when there is none.
  String get symbol => CodePointer(text).tail ?? '';
}
