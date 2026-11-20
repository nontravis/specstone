import 'dart:io';

/// A migrate root and the folder whose `docs` link led to it; `linkFolder` is
/// null when the walk stopped at the root.
final class MigrateRoot {
  const new({required this.root, required this.linkFolder});

  final Directory root;
  final Directory? linkFolder;
}
