import 'dart:io';

/// A project root a walk found and the folder the walk stood in; they differ
/// only when the root came through the folder's `docs` link.
final class RootMatch {
  const new({required this.folder, required this.root});

  final Directory folder;
  final Directory root;
}
