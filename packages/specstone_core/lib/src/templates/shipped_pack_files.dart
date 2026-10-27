import 'dart:convert';
import 'dart:typed_data';

import 'package:specstone_core/src/templates/code_point_order.dart';
import 'package:specstone_core/src/templates/pack_manifest.dart';
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

/// Maps each shipped pack's name to the version its `pack.yaml` carries.
///
/// Packs are in code point order, versions as `PackVersion.toString()` prints
/// them. The one source of the shipped pins a fixture writes (PD22).
Map<String, String> shippedPackVersions() {
  final names = {
    for (final key in shippedPackFiles.keys) key.split('/').first,
  }.toList()..sort(compareCodePoints);
  return {
    for (final name in names)
      name: PackManifest.parse(
        utf8.decode(shippedPackFiles['$name/pack.yaml']!),
        file: 'packs/$name/pack.yaml',
      ).version.toString(),
  };
}
