import 'dart:io';

import 'package:specstone_core/src/path_tail.dart';
import 'package:specstone_core/src/portable_path.dart';

/// The frontmatter field whose entries point at code.
const implementsField = 'implements';

/// One `implements` entry, `path[:Symbol]`.
///
/// `check` and the migrate count resolve an entry through this one rule.
extension type const ImplementsEntry(String text) {
  /// The path part: the text before the first `:`, or all of it.
  String get path => splitPathTail(text).path;

  /// The Symbol part after the first `:`; empty when there is none.
  String get symbol => splitPathTail(text).tail ?? '';

  /// The test name of an `item_test` entry `path[:name]`: the text after the
  /// first `:`; null when there is none.
  ///
  /// The name keeps its colons and spaces whole.
  String? get testName => splitPathTail(text).tail;

  /// Whether [path] names a regular file from [base].
  bool namesFileFrom(Directory base) =>
      isPortablePath(path) &&
      FileSystemEntity.typeSync('${base.path}/$path') ==
          FileSystemEntityType.file;
}
