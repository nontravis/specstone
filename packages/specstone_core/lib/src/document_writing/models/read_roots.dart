import 'dart:io';

/// The project root and docs root a read-only command runs from.
final class ReadRoots {
  const new({required this.projectRoot, required this.docsRoot});

  final Directory projectRoot;
  final Directory docsRoot;
}
