// Writes THIRD_PARTY_NOTICES for a release archive.
//
// Usage: dart run tool/third_party_notices.dart <out path>, run from the repo
// root. Contract: docs/specs/install_update/s02_api_release.md `## release.dart`
// (the `build` job) and `install_update/release_new_version/package_archive`.
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

const String _cliPackage = 'specstone';
const String _mermaidLicense = 'packages/specstone_core/assets/mermaid/LICENSE';
const String _sqliteNotice =
    'SQLite is in the public domain: https://www.sqlite.org/copyright.html';
const String _intro =
    'Specstone bundles the third-party software below, each under its own '
    'license.\n\n';
const List<String> _licenseNames = ['LICENSE', 'LICENSE.md', 'COPYING'];
const String _besideSuffix = '.LICENSE';
const List<String> _shippedFolders = ['lib', 'bin'];
// A `//` or `///` comment (not inside a string or URL) or a `/* */` comment
// on one line, saying the code is adapted from other code.
final RegExp _adaptedLine = RegExp(
  r'''(?:(?<![/'":])//|/\*).*\badapted from\b''',
  caseSensitive: false,
);

/// The runtime closure of the CLI package: third-party versions and the
/// workspace packages whose source ships in the binary.
final class _Closure {
  new(this.versions, this.workspace);

  final SplayTreeMap<String, String> versions;
  final List<String> workspace;
}

/// A failed run: printed as `third_party_notices: <message>` on stderr, exit 1.
final class _Failure implements Exception {
  new(this.message);

  final String message;
}

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln(
      'third_party_notices: usage: '
      'dart run tool/third_party_notices.dart <out path>',
    );
    exit(1);
  }
  try {
    final notices = await _build();
    File(args.single).writeAsStringSync(notices);
  } on _Failure catch (failure) {
    stderr.writeln('third_party_notices: ${failure.message}');
    exit(1);
  }
}

Future<String> _build() async {
  final closure = await _runtimePackages();
  final roots = _packageRoots();
  final out = StringBuffer(_intro);
  for (final MapEntry(:key, :value) in closure.versions.entries) {
    final root = roots[key];
    if (root == null) {
      throw _Failure('$key is not in .dart_tool/package_config.json');
    }
    out.write(_section('$key $value', _licenseText(key, root)));
  }
  out.write(_besideLicenses(closure, roots));
  final mermaid = File(_mermaidLicense);
  if (!mermaid.existsSync()) {
    throw _Failure('$_mermaidLicense is missing');
  }
  out
    ..write(_section('mermaid', mermaid.readAsStringSync()))
    ..write(_section('SQLite', _sqliteNotice))
    ..write(_section('Dart SDK', _dartSdkLicense()));
  return out.toString();
}

/// Returns the runtime closure of the CLI package.
///
/// Follows each package's `directDependencies`, which leave out dev ones, and
/// passes through workspace packages (`source: root`) without listing them in
/// `versions`: `specstone_core` brings in markdown, yaml, and sqlite3. Those
/// workspace packages and the CLI itself fill `workspace`.
Future<_Closure> _runtimePackages() async {
  final result = await Process.run(Platform.resolvedExecutable, [
    'pub',
    'deps',
    '--json',
  ], workingDirectory: 'packages/$_cliPackage');
  if (result.exitCode != 0) {
    throw _Failure('dart pub deps failed: ${result.stderr}');
  }
  final all = <String, Map<String, Object?>>{
    for (final p in (jsonDecode('${result.stdout}') as Map)['packages'] as List)
      (p as Map<String, Object?>)['name']! as String: p,
  };
  final queue = [
    ...(all[_cliPackage]!['directDependencies']! as List).cast<String>(),
  ];
  final found = SplayTreeMap<String, String>();
  final workspace = <String>{_cliPackage};
  final visited = <String>{};
  while (queue.isNotEmpty) {
    final name = queue.removeLast();
    final package = all[name];
    if (package == null || !visited.add(name)) continue;
    if (package['source'] == 'root') {
      workspace.add(name);
    } else {
      found[name] = package['version']! as String;
    }
    queue.addAll((package['directDependencies']! as List).cast<String>());
  }
  return _Closure(found, workspace.toList()..sort());
}

/// Returns a section per `.LICENSE` file kept beside shipped workspace source.
///
/// Throws when a `.dart` file says it is adapted from other code and has no
/// `<base name>.LICENSE` beside it.
String _besideLicenses(_Closure closure, Map<String, Directory> roots) {
  final out = StringBuffer();
  for (final name in closure.workspace) {
    final root = roots[name];
    if (root == null) {
      throw _Failure('$name is not in .dart_tool/package_config.json');
    }
    out.write(_packageBesideLicenses(name, root));
  }
  return out.toString();
}

String _packageBesideLicenses(String name, Directory root) {
  final out = StringBuffer();
  final rootDepth = root.uri.pathSegments.where((s) => s.isNotEmpty).length;
  for (final folder in _shippedFolders) {
    final dir = Directory.fromUri(root.uri.resolve('$folder/'));
    if (!dir.existsSync()) continue;
    final shownFiles = {
      for (final file in dir.listSync(recursive: true).whereType<File>())
        '$name/${file.uri.pathSegments.skip(rootDepth).join('/')}': file,
    };
    for (final shown in shownFiles.keys.toList()..sort()) {
      out.write(_besideSection(shown, shownFiles[shown]!));
    }
  }
  return out.toString();
}

/// Returns the section for a `.LICENSE` file, or nothing for other files.
///
/// Throws when a `.dart` file says it is adapted from other code and has no
/// license beside it.
String _besideSection(String shown, File file) {
  if (shown.endsWith(_besideSuffix)) {
    return _section(shown, file.readAsStringSync());
  }
  if (!shown.endsWith('.dart') ||
      !_adaptedLine.hasMatch(file.readAsStringSync())) {
    return '';
  }
  final licenseName = _licenseNameFor(file);
  if (!File.fromUri(file.uri.resolve(licenseName)).existsSync()) {
    throw _Failure(
      '$shown says it is adapted from other code and has no '
      '$licenseName beside it',
    );
  }
  return '';
}

/// Returns the name of the `.LICENSE` file that sits beside [source].
String _licenseNameFor(File source) {
  final fileName = source.uri.pathSegments.last;
  final baseName = fileName.substring(0, fileName.length - '.dart'.length);
  return '$baseName$_besideSuffix';
}

/// Returns each package's folder from `.dart_tool/package_config.json`.
Map<String, Directory> _packageRoots() {
  final config = File('.dart_tool/package_config.json');
  if (!config.existsSync()) {
    throw _Failure(
      '.dart_tool/package_config.json is missing; '
      'run dart pub get',
    );
  }
  final base = config.absolute.uri;
  final json = jsonDecode(config.readAsStringSync()) as Map<String, Object?>;
  return {
    for (final p in (json['packages']! as List).cast<Map<String, Object?>>())
      p['name']! as String: Directory.fromUri(base.resolve('${p['rootUri']}/')),
  };
}

String _licenseText(String name, Directory root) {
  for (final fileName in _licenseNames) {
    final file = File.fromUri(root.uri.resolve(fileName));
    if (file.existsSync()) return file.readAsStringSync();
  }
  throw _Failure('$name has no ${_licenseNames.join(', ')} file');
}

/// Returns the LICENSE of the running Dart SDK, whose runtime every archive
/// ships inside the AOT-compiled binary.
String _dartSdkLicense() {
  final sdk = File(Platform.resolvedExecutable).parent.parent;
  final license = File('${sdk.path}${Platform.pathSeparator}LICENSE');
  if (!license.existsSync()) {
    throw _Failure('the Dart SDK has no LICENSE file at ${license.path}');
  }
  return license.readAsStringSync();
}

String _section(String heading, String text) =>
    '## $heading\n\n${text.trimRight()}\n\n';
