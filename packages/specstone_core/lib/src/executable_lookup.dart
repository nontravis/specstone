import 'dart:io';

/// Returns the path of the program [name] on the `PATH` of [environment], or
/// null.
///
/// Only an absolute `PATH` entry is searched: an empty, `.`, or relative entry
/// would run a program the current folder supplies, and a Windows
/// `CreateProcessW` searches the current folder before any `PATH` entry. On
/// [isWindows] the name gets each of [windowsExtensions] in turn inside one
/// entry, `PATH` is read without case, and an entry may be double-quoted.
/// [isFile] decides whether a candidate is a program; it defaults to a regular
/// file, and on POSIX one with an execute bit.
String? findExecutable(
  String name,
  Map<String, String> environment, {
  required bool isWindows,
  List<String> windowsExtensions = const ['.exe'],
  bool Function(String path)? isFile,
}) {
  final path = [
    for (final MapEntry(:key, :value) in environment.entries)
      if (isWindows ? key.toUpperCase() == 'PATH' : key == 'PATH') value,
  ].firstOrNull;
  if (path == null) return null;
  final isProgram = isFile ?? (isWindows ? _isRegularFile : _isExecutableFile);
  final fileNames = isWindows
      ? [for (final extension in windowsExtensions) '$name$extension']
      : [name];
  for (final entry in isWindows ? _windowsEntries(path) : path.split(':')) {
    if (!_isAbsolute(entry, isWindows: isWindows)) continue;
    final folder = entry.endsWith(Platform.pathSeparator)
        ? entry
        : '$entry${Platform.pathSeparator}';
    for (final fileName in fileNames) {
      final candidate = '$folder$fileName';
      if (isProgram(candidate)) return candidate;
    }
  }
  return null;
}

/// Splits a Windows `PATH` on each `;` outside double quotes and drops the
/// quotes, as `cmd.exe` and Go do.
List<String> _windowsEntries(String path) {
  final entries = <String>[];
  final entry = StringBuffer();
  var isQuoted = false;
  for (final character in path.split('')) {
    if (character == '"') {
      isQuoted = !isQuoted;
    } else if (character == ';' && !isQuoted) {
      entries.add('$entry');
      entry.clear();
    } else {
      entry.write(character);
    }
  }
  return entries..add('$entry');
}

/// A Windows drive root such as `C:\` or `C:/`, or a UNC path.
final _windowsAbsolute = RegExp(r'^(?:[A-Za-z]:[\\/]|\\\\)');

bool _isAbsolute(String entry, {required bool isWindows}) =>
    isWindows ? _windowsAbsolute.hasMatch(entry) : entry.startsWith('/');

bool _isRegularFile(String path) =>
    FileSystemEntity.typeSync(path) == FileSystemEntityType.file;

/// The owner, group, and other execute bits of a POSIX file mode.
const _executeBits = 0x49;

bool _isExecutableFile(String path) =>
    _isRegularFile(path) && FileStat.statSync(path).mode & _executeBits != 0;

final _processLookups = <String, String?>{};

/// Returns the program [name] on the absolute `PATH` entries of this process,
/// or null; the lookup runs once per name for the life of the process.
String? findOnProcessPath(String name) => _processLookups.putIfAbsent(
  name,
  () =>
      findExecutable(name, Platform.environment, isWindows: Platform.isWindows),
);
