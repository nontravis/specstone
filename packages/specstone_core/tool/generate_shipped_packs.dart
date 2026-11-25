import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:specstone_core/src/templates/code_point_order.dart';

/// Reads every file under each sub-folder of [packs], any file type, as raw
/// bytes (F3-D50).
///
/// Files are keyed `<pack>/<path>` with `/` separators and sorted by
/// `compareCodePoints`. Top-level files such as `.gitkeep` are skipped, and
/// every file or folder whose name starts with `.` is skipped, so a local
/// `.DS_Store` (gitignored, absent in CI) never makes the constants differ
/// between a checkout and CI.
Map<String, Uint8List> readPackSources(Directory packs) {
  final files = <String, Uint8List>{};
  for (final pack in packs.listSync(followLinks: true)) {
    if (pack is! Directory) continue;
    final packName = _lastSegment(pack.uri);
    if (_isDotName(packName)) continue;
    for (final entity in pack.listSync(recursive: true, followLinks: true)) {
      if (entity is! File) continue;
      final segments = _relativeSegments(pack, entity);
      if (segments.any(_isDotName)) continue;
      files['$packName/${segments.join('/')}'] = entity.readAsBytesSync();
    }
  }
  return {
    for (final key in files.keys.toList()..sort(compareCodePoints))
      key: files[key]!,
  };
}

/// The last non-empty path segment of [uri].
String _lastSegment(Uri uri) => uri.pathSegments.lastWhere(
  (segment) => segment.isNotEmpty,
  orElse: () => '',
);

/// True when [name] is a dot-name the generator must skip.
bool _isDotName(String name) => name.startsWith('.');

/// The path segments of [entity] relative to [pack].
///
/// A directory URI ends with `/`, so its path segments hold one trailing
/// empty segment; skipping `length - 1` lands after the pack name.
List<String> _relativeSegments(Directory pack, File entity) =>
    entity.uri.pathSegments.skip(pack.uri.pathSegments.length - 1).toList();

/// Renders the Dart source of the base64 constants for [files].
///
/// The output is `dart format`-stable by construction, so the generator never
/// runs the formatter: a header comment, then
/// `const Map<String, String> shippedPackFilesBase64 = {...};` with each value
/// the file's bytes as a `base64Encode` string, which needs no escaping. An
/// entry whose one-line form `  '<key>': '<base64>',` fits in 80 columns is
/// that one line; any other entry is the line `  '<key>':` followed by the
/// base64 cut into 64-character adjacent string literals, one per line, each
/// indented six spaces, the last followed by `,`. No files gives
/// `const Map<String, String> shippedPackFilesBase64 = {};`.
String renderShippedPacks(Map<String, Uint8List> files) {
  final buffer = StringBuffer()
    ..writeln('// GENERATED CODE - DO NOT MODIFY BY HAND')
    ..writeln();
  final keys = files.keys.toList()..sort(compareCodePoints);
  if (keys.isEmpty) {
    buffer.writeln('const Map<String, String> shippedPackFilesBase64 = {};');
    return buffer.toString();
  }
  buffer.writeln('const Map<String, String> shippedPackFilesBase64 = {');
  for (final key in keys) {
    _checkKey(key);
    final base64 = base64Encode(files[key]!);
    if ("  '$key': '$base64',".length <= 80) {
      buffer.writeln("  '$key': '$base64',");
      continue;
    }
    buffer.writeln("  '$key':");
    for (var start = 0; start < base64.length; start += 64) {
      final chunk = base64.substring(
        start,
        base64.length - start < 64 ? base64.length : start + 64,
      );
      final comma = start + 64 >= base64.length ? ',' : '';
      buffer.writeln("      '$chunk'$comma");
    }
  }
  buffer.writeln('};');
  return buffer.toString();
}

/// Refuses a [key] the one-line or wrapped form cannot quote safely.
void _checkKey(String key) {
  final bad = key.runes.where(
    (r) => r == 0x27 || r == 0x5C || r == 0x24 || (r < 0x20 || r == 0x7F),
  );
  if (bad.isEmpty) return;
  final hex = bad.first.toRadixString(16).toUpperCase().padLeft(4, '0');
  throw StateError(
    'the pack file key "$key" holds a character the generated string '
    'cannot quote: U+$hex',
  );
}

Future<void> main() async {
  final libUri = Isolate.resolvePackageUriSync(
    Uri.parse('package:specstone_core/specstone_core.dart'),
  );
  if (libUri == null) {
    throw StateError('cannot resolve package:specstone_core');
  }
  final packageRoot = Directory.fromUri(libUri.resolve('..'));
  final text = renderShippedPacks(
    readPackSources(Directory.fromUri(packageRoot.uri.resolve('packs/'))),
  );
  final out = File.fromUri(
    packageRoot.uri.resolve('lib/src/templates/shipped_packs.g.dart'),
  );
  await out.writeAsString(text);
  stdout.writeln('wrote ${out.path}');
}
