import 'dart:io';

/// Creates a directory symbolic link at [linkPath] whose target is the
/// `/`-separated relative path [target], as a real repository holds it.
///
/// Windows resolves a relative link target only with `\` separators, so
/// the target is rewritten with the platform separator while staying
/// relative. Throws the [FileSystemException] the platform raises when a
/// link cannot be created, so callers can skip the test.
void createRelativeLink(String linkPath, String target) {
  Link(linkPath)
      .createSync(Platform.isWindows ? target.replaceAll('/', r'\') : target);
}
