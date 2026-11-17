import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// The longest parse script `node -e` takes within the Windows command line.
const int maxParseScriptChars = 30000;

/// Renders the Dart source of the mermaid constants and the parser hash.
///
/// Embeds [script], [license], [parseScript], and [patches] as base64, and
/// `mermaidParserSha256` over [script], [parseScript], and [patches]. Throws
/// [StateError] when [script] holds a script tag the html inlining breaks
/// on, when a patch's `find` is not in [script] exactly once, or when
/// [parseScript] passes [maxParseScriptChars].
///
/// - [patches]: a JSON list of `{"find", "replace"}` pairs, applied in order.
String renderMermaidScript(
  Uint8List script,
  Uint8List license, {
  required Uint8List parseScript,
  required Uint8List patches,
}) {
  _checkInlineSafe(script);
  _checkPatches(utf8.decode(script), utf8.decode(patches));
  _checkParseScriptSize(utf8.decode(parseScript));
  final hashed = BytesBuilder(copy: false)
    ..add(script)
    ..add(parseScript)
    ..add(patches);
  final hash = sha256.convert(hashed.takeBytes());
  return (StringBuffer()
        ..writeln('// GENERATED CODE - DO NOT MODIFY BY HAND')
        ..writeln()
        ..write(_constant('mermaidScriptBase64', script))
        ..write(_constant('mermaidLicenseBase64', license))
        ..write(_constant('mermaidParseScriptBase64', parseScript))
        ..write(_constant('mermaidNodePatchesBase64', patches))
        ..write(_declaration('mermaidParserSha256', '$hash')))
      .toString();
}

/// Refuses a patch whose `find` the patched-so-far [script] holds other than
/// once, so a mermaid upgrade that moves an anchor fails the build.
void _checkPatches(String script, String patchesJson) {
  var text = script;
  final patches = jsonDecode(patchesJson);
  if (patches is! List<Object?>) {
    throw StateError('the node patches are not a JSON list');
  }
  for (final patch in patches) {
    if (patch case {'find': final String find, 'replace': final String to}) {
      final count = find.allMatches(text).length;
      if (count != 1) {
        throw StateError(
          'the mermaid script holds the patch anchor "$find" $count times, '
          'not once',
        );
      }
      text = text.replaceFirst(find, to);
    } else {
      throw StateError('a node patch is not a {"find", "replace"} pair');
    }
  }
}

/// Refuses a [parseScript] too long for the Windows command line.
void _checkParseScriptSize(String parseScript) {
  if (parseScript.length > maxParseScriptChars) {
    throw StateError(
      'the parse script holds ${parseScript.length} characters, over the '
      '$maxParseScriptChars the Windows command line takes',
    );
  }
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
String _constant(String name, Uint8List bytes) =>
    _declaration(name, base64Encode(bytes));

/// The declaration of [name] holding [value], which needs no escaping.
///
/// When it does not fit in 80 columns the string moves to the next line
/// behind four spaces, the layout `dart format` leaves unchanged.
String _declaration(String name, String value) {
  final head = 'const String $name =';
  final literal = "'$value';";
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
  final parseScript = File.fromUri(
    packageRoot.uri.resolve('assets/mermaid/parse_diagrams.js'),
  );
  final patches = File.fromUri(
    packageRoot.uri.resolve('assets/mermaid/node_patches.json'),
  );
  final out = File.fromUri(
    packageRoot.uri.resolve('lib/src/rendering/mermaid_script.g.dart'),
  );
  await out.writeAsString(
    renderMermaidScript(
      script.readAsBytesSync(),
      license.readAsBytesSync(),
      parseScript: parseScript.readAsBytesSync(),
      patches: patches.readAsBytesSync(),
    ),
  );
}
