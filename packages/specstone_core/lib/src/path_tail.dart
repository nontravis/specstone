import 'package:specstone_core/src/models/path_tail.dart';

const _tailMark = ':';

/// Splits [text] of the form `path[:tail]` at its first `:`.
///
/// The tail is null when [text] holds no `:`; it keeps its own colons and
/// spaces whole.
PathTail splitPathTail(String text) {
  final split = text.indexOf(_tailMark);
  return split < 0
      ? PathTail(path: text, tail: null)
      : PathTail(
          path: text.substring(0, split),
          tail: text.substring(split + 1),
        );
}
