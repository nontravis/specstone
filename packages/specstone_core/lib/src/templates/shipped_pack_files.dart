import 'dart:convert';
import 'dart:typed_data';

import 'package:specstone_core/src/templates/shipped_packs.g.dart';

/// Decodes the base64 [base64Files] constants back to file bytes (F3-D50).
Map<String, Uint8List> decodeShippedPacks(Map<String, String> base64Files) => {
  for (final MapEntry(:key, :value) in base64Files.entries)
    key: base64Decode(value),
};

/// Every shipped pack file as raw bytes, keyed `<pack>/<path>` (F3-D18).
final Map<String, Uint8List> shippedPackFiles = decodeShippedPacks(
  shippedPackFilesBase64,
);
