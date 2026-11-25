import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

const _agentAssetsDir = 'assets/agent';
const _agentMdName = 'AGENT.md';

/// Lists the git-tracked files under `assets/agent/` but AGENT.md, sorted.
///
/// Paths are `/`-separated and relative to `assets/agent/`; a new file must be
/// `git add`ed before the generator runs.
List<String> listAgentAssetPaths(Directory packageRoot) {
  final result = Process.runSync(
    'git',
    ['ls-files', '-z', '--', '$_agentAssetsDir/'],
    workingDirectory: packageRoot.path,
    stdoutEncoding: utf8,
  );
  if (result.exitCode != 0) {
    throw StateError('git ls-files failed: ${result.stderr}');
  }
  const prefix = '$_agentAssetsDir/';
  return [
    for (final path in (result.stdout as String).split('\u0000'))
      if (path.startsWith(prefix) && path != '$prefix$_agentMdName')
        path.substring(prefix.length),
  ]..sort();
}

/// Reads the bytes of each of [paths] under `assets/agent/`, keyed by path.
Map<String, Uint8List> readAgentAssets(
  Directory packageRoot,
  List<String> paths,
) => {
  for (final path in paths)
    path: File.fromUri(packageRoot.uri.resolve('$_agentAssetsDir/$path'))
        .readAsBytesSync(),
};

Uint8List _normalizeLineFeeds(Uint8List bytes) {
  final out = BytesBuilder(copy: false);
  for (var i = 0; i < bytes.length; i++) {
    final isCrLf =
        bytes[i] == 0x0D && i + 1 < bytes.length && bytes[i + 1] == 0x0A;
    if (!isCrLf) out.addByte(bytes[i]);
  }
  return out.takeBytes();
}

/// Renders the Dart source of the base64 constants for the AGENT.md [text] and
/// the [assets], keyed by path and written with LF line endings, sorted by key.
///
/// The constant is `const String agentMdTextBase64 = '<base64>';`. When that
/// does not fit in 80 columns the string moves to the next line behind four
/// spaces, the layout `dart format` leaves unchanged. Throws [StateError] when
/// [text] is empty or does not end in exactly one line feed, since every
/// project receives these bytes byte for byte.
String renderAgentText(Uint8List text, Map<String, Uint8List> assets) {
  if (text.isEmpty || text.last != 0x0A) {
    throw StateError('the AGENT.md text must end in one line feed');
  }
  if (text.length > 1 && text[text.length - 2] == 0x0A) {
    throw StateError('the AGENT.md text must end in exactly one line feed');
  }
  const head = 'const String agentMdTextBase64 =';
  final literal = "'${base64Encode(text)}';";
  final out = StringBuffer()
    ..writeln('// GENERATED CODE - DO NOT MODIFY BY HAND')
    ..writeln()
    ..write(
      head.length + 1 + literal.length <= 80
          ? '$head $literal\n'
          : '$head\n    $literal\n',
    )
    ..writeln()
    ..writeln('const Map<String, String> agentAssetsBase64 = {');
  for (final key in assets.keys.toList()..sort()) {
    final value = base64Encode(_normalizeLineFeeds(assets[key]!));
    out.writeln("  '$key': '$value',");
  }
  out.writeln('};');
  return out.toString();
}

Future<void> main() async {
  final libUri = Isolate.resolvePackageUriSync(
    Uri.parse('package:specstone_core/specstone_core.dart'),
  );
  if (libUri == null) {
    throw StateError('cannot resolve package:specstone_core');
  }
  final packageRoot = Directory.fromUri(libUri.resolve('..'));
  final asset = File.fromUri(packageRoot.uri.resolve('assets/agent/AGENT.md'));
  final out = File.fromUri(
    packageRoot.uri.resolve('lib/src/setup_migration/agent_text.g.dart'),
  );
  await out.writeAsString(
    renderAgentText(
      asset.readAsBytesSync(),
      readAgentAssets(packageRoot, listAgentAssetPaths(packageRoot)),
    ),
  );
}
