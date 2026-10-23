import 'dart:io';

/// Returns why `chmod` cannot make a path unreadable here, else null.
///
/// Windows has no `chmod`, and a root user reads every file and folder.
String? unreadablePathSkipReason() {
  if (Platform.isWindows) return 'chmod does not apply on Windows';
  final user = Process.runSync('id', ['-u']).stdout.toString().trim();
  return user == '0' ? 'the process ignores file permissions (root)' : null;
}
