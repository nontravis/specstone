import 'dart:io';
import 'dart:isolate';

/// Returns the specstone package folder, independent of the working directory.
///
/// The package has no public library, so resolve a source file and climb two
/// levels out of lib/src.
Directory packageRoot() {
  final sourceUri = Isolate.resolvePackageUriSync(
    Uri.parse('package:specstone/src/command_runner.dart'),
  );
  if (sourceUri == null) {
    throw StateError('cannot resolve package:specstone');
  }
  return Directory.fromUri(sourceUri.resolve('../..'));
}
