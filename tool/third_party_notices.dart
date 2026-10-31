// Writes THIRD_PARTY_NOTICES for a release archive.
//
// Usage: dart run tool/third_party_notices.dart <out path>, run from the repo
// root. Contract: docs/specs/install_update/s02_api_release.md `## release.dart`
// (the `build` job) and US-04 FR-06.
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
  final packages = await _runtimePackages();
  final roots = _packageRoots();
  final out = StringBuffer(_intro);
  for (final MapEntry(:key, :value) in packages.entries) {
    final root = roots[key];
    if (root == null) {
      throw _Failure('$key is not in .dart_tool/package_config.json');
    }
    out.write(_section('$key $value', _licenseText(key, root)));
  }
  final mermaid = File(_mermaidLicense);
  if (!mermaid.existsSync()) {
    throw _Failure('$_mermaidLicense is missing');
  }
  out
    ..write(_section('mermaid', mermaid.readAsStringSync()))
    ..write(_section('SQLite', _sqliteNotice));
  return out.toString();
}

/// Returns name to version for the runtime closure of the CLI package.
///
/// Follows each package's `directDependencies`, which leave out dev ones, and
/// passes through workspace packages (`source: root`) without listing them:
/// `specstone_core` brings in markdown, yaml, and sqlite3.
Future<Map<String, String>> _runtimePackages() async {
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
  final found = <String, String>{};
  final visited = <String>{};
  while (queue.isNotEmpty) {
    final name = queue.removeLast();
    final package = all[name];
    if (package == null || !visited.add(name)) continue;
    if (package['source'] != 'root') {
      found[name] = package['version']! as String;
    }
    queue.addAll((package['directDependencies']! as List).cast<String>());
  }
  return Map.fromEntries(
    found.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
  );
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

String _section(String heading, String text) =>
    '## $heading\n\n${text.trimRight()}\n\n';
