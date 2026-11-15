import 'dart:io';

import 'package:specstone_core/src/canonical_path.dart';

/// How far before a run a bundle file's last change may lie before the run
/// deletes it.
const _bundleAgeBound = Duration(hours: 24);

/// Deletes each file under [bundles], subfolders included, last modified more
/// than 24 hours before [now].
///
/// Keeps every canonical path in [keep], every folder, and every link, and
/// never follows a link. A missing [bundles] and a file that cannot be
/// deleted are skipped without a message.
void pruneBundles(
  Directory bundles, {
  required Set<String> keep,
  required DateTime now,
}) {
  if (!bundles.existsSync()) return;
  final oldest = now.subtract(_bundleAgeBound);
  for (final entity in bundles.listSync(recursive: true, followLinks: false)) {
    if (entity is! File || keep.contains(canonicalPath(entity.path))) continue;
    _deleteIfOlder(entity, oldest);
  }
}

void _deleteIfOlder(File file, DateTime oldest) {
  try {
    if (file.lastModifiedSync().isBefore(oldest)) file.deleteSync();
  } on FileSystemException {
    // Held or not permitted: the file stays; one already gone needs nothing.
  }
}
