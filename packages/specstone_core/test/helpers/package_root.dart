import 'dart:io';
import 'dart:isolate';

/// Returns the specstone_core package folder, independent of the working
/// directory.
Directory packageRoot() {
  final libUri = Isolate.resolvePackageUriSync(
    Uri.parse('package:specstone_core/specstone_core.dart'),
  );
  if (libUri == null) {
    throw StateError('cannot resolve package:specstone_core');
  }
  return Directory.fromUri(libUri.resolve('..'));
}
