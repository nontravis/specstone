import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' show sha256;
import 'package:specstone_core/src/canonical_path.dart';

/// Returns the SHA-256 of [bytes] in lowercase hex.
String digestOf(List<int> bytes) => sha256.convert(bytes).toString();

/// Returns the file of the record kept for [key] under [folder] of [home], or
/// null when [home] is no place for a record.
///
/// The file is named by the SHA-256 of [key]. A [home] that is null, is not
/// absolute, or equals or lies inside one of the canonical folders [keepOut]
/// counts as none: a git clone could carry the record. [key] and [keepOut] are
/// asked only once [home] is absolute.
///
/// [folder] is `/`-separated, relative to [home].
File? homeRecordFile(
  Directory? home, {
  required String folder,
  required String Function() key,
  required List<String> Function() keepOut,
}) {
  if (home == null || !home.isAbsolute) return null;
  final canonicalHome = canonicalPath(home.path);
  for (final root in keepOut()) {
    if (canonicalHome == root ||
        canonicalHome.startsWith('$root${Platform.pathSeparator}')) {
      return null;
    }
  }
  return File(
    [
      home.path,
      ...folder.split('/'),
      digestOf(utf8.encode(key())),
    ].join(Platform.pathSeparator),
  );
}
