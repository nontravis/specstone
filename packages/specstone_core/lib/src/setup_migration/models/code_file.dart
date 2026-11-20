import 'dart:io';

/// A code file: the code root of the target that lists it, and its path from
/// that root.
final class CodeFile {
  const new({required this.root, required this.path});

  final Directory root;
  final String path;
}
