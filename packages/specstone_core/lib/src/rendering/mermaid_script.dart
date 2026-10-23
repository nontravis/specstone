import 'dart:convert';

import 'package:specstone_core/src/rendering/mermaid_script.g.dart';

/// The pinned mermaid 11.17.2 script, inlined into the html build.
final String mermaidScript = utf8.decode(base64Decode(mermaidScriptBase64));

/// The MIT license notice that ships with [mermaidScript].
final String mermaidLicense = utf8.decode(base64Decode(mermaidLicenseBase64));
