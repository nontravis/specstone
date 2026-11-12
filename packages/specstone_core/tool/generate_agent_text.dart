import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

/// Renders the Dart source of the base64 constant for the AGENT.md [text].
///
/// The constant is `const String agentMdTextBase64 = '<base64>';`. When that
/// does not fit in 80 columns the string moves to the next line behind four
/// spaces, the layout `dart format` leaves unchanged. Throws [StateError] when
/// [text] is empty or does not end in exactly one line feed, since every
/// project receives these bytes byte for byte.
String renderAgentText(Uint8List text) {
  if (text.isEmpty || text.last != 0x0A) {
    throw StateError('the AGENT.md text must end in one line feed');
  }
  if (text.length > 1 && text[text.length - 2] == 0x0A) {
    throw StateError('the AGENT.md text must end in exactly one line feed');
  }
  const head = 'const String agentMdTextBase64 =';
  final literal = "'${base64Encode(text)}';";
  return (StringBuffer()
        ..writeln('// GENERATED CODE - DO NOT MODIFY BY HAND')
        ..writeln()
        ..write(
          head.length + 1 + literal.length <= 80
              ? '$head $literal\n'
              : '$head\n    $literal\n',
        ))
      .toString();
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
  await out.writeAsString(renderAgentText(asset.readAsBytesSync()));
}
