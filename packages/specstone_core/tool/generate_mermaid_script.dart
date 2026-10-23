import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

/// Renders the Dart source of the base64 constants for the mermaid [script]
/// and its [license].
///
/// Each constant is `const String <name> = '<base64>';`. When that does not
/// fit in 80 columns the string moves to the next line behind four spaces,
/// the layout `dart format` leaves unchanged. Throws [StateError] when the
/// [script] holds `<script` or `</script` in any letter case, since the html
/// inlines it in a `<script>` element.
String renderMermaidScript(Uint8List script, Uint8List license) {
  _checkInlineSafe(script);
  return (StringBuffer()
        ..writeln('// GENERATED CODE - DO NOT MODIFY BY HAND')
        ..writeln()
        ..write(_constant('mermaidScriptBase64', script))
        ..write(_constant('mermaidLicenseBase64', license)))
      .toString();
}

/// Refuses a [script] that would close or open a `<script>` element early.
void _checkInlineSafe(Uint8List script) {
  final text = latin1.decode(script).toLowerCase();
  for (final tag in const ['<script', '</script']) {
    if (text.contains(tag)) {
      throw StateError(
        'the mermaid script holds "$tag", which would break the inline '
        '<script> element',
      );
    }
  }
}

/// The declaration of [name] holding [bytes] as one base64 string.
String _constant(String name, Uint8List bytes) {
  final head = 'const String $name =';
  final literal = "'${base64Encode(bytes)}';";
  if (head.length + 1 + literal.length <= 80) return '$head $literal\n';
  return '$head\n    $literal\n';
}

Future<void> main() async {
  final libUri = Isolate.resolvePackageUriSync(
    Uri.parse('package:specstone_core/specstone_core.dart'),
  );
  if (libUri == null) {
    throw StateError('cannot resolve package:specstone_core');
  }
  final packageRoot = Directory.fromUri(libUri.resolve('..'));
  final script = File.fromUri(
    packageRoot.uri.resolve('assets/mermaid/mermaid.min.js'),
  );
  final license = File.fromUri(
    packageRoot.uri.resolve('assets/mermaid/LICENSE'),
  );
  final out = File.fromUri(
    packageRoot.uri.resolve('lib/src/rendering/mermaid_script.g.dart'),
  );
  await out.writeAsString(
    renderMermaidScript(script.readAsBytesSync(), license.readAsBytesSync()),
  );
}
