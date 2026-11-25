import 'dart:convert';

import 'package:specstone_core/src/rendering/mermaid_script.dart';
import 'package:specstone_core/src/rendering/mermaid_script.g.dart';

/// The script `node -e` runs to parse Mermaid blocks with the bundled parser.
///
/// stdin takes [patchedMermaidBundle], `\n`, then one JSON line of
/// `[{"i": int, "text": block text}]`; stdout gives one JSON line per block,
/// in input order.
final String mermaidParseScript = utf8.decode(
  base64Decode(mermaidParseScriptBase64),
);

/// The `sha256` hex over the bundled parser, the parse script, and patches.
String get mermaidParserHash => mermaidParserSha256;

/// Returns the mermaid script with every node patch applied, so it loads in
/// Node.
String patchedMermaidBundle() => _patchedBundle;

final String _patchedBundle = _applyPatches(
  mermaidScript,
  utf8.decode(base64Decode(mermaidNodePatchesBase64)),
);

/// Applies each `{"find", "replace"}` pair of [patchesJson] to [script] once,
/// in order; the generator has checked each `find` occurs once.
String _applyPatches(String script, String patchesJson) {
  var text = script;
  for (final patch in jsonDecode(patchesJson) as List<Object?>) {
    if (patch case {'find': final String find, 'replace': final String to}) {
      text = text.replaceFirst(find, to);
    }
  }
  return text;
}
