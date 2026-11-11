import 'dart:io';

import 'package:specstone_core/src/portable_path.dart';

/// The frontmatter field whose entries point at code.
const implementsField = 'implements';

const _symbolMark = ':';

/// One `implements` entry, `path[:Symbol]`.
///
/// `check` and the migrate count resolve an entry through this one rule.
extension type const ImplementsEntry(String text) {
  /// The path part: the text before the first `:`, or all of it.
  String get path {
    final split = text.indexOf(_symbolMark);
    return split < 0 ? text : text.substring(0, split);
  }

  /// The Symbol part after the first `:`; empty when there is none.
  String get symbol {
    final split = text.indexOf(_symbolMark);
    return split < 0 ? '' : text.substring(split + 1);
  }

  /// Whether [path] names a regular file from [base].
  bool namesFileFrom(Directory base) =>
      !hasWindowsDroppedEnd(path.split('/')) &&
      FileSystemEntity.typeSync('${base.path}/$path') ==
          FileSystemEntityType.file;
}
