import 'dart:convert';

import 'package:specstone_core/src/templates/pack_manifest.dart';
import 'package:specstone_core/src/templates/shipped_pack_files.dart';
import 'package:test/test.dart';

void main() {
  test('f03/us03/fr03/e08: decodes base64 constants back to bytes', () {
    final files = decodeShippedPacks({
      'a/x.pdf': base64Encode([0xff, 0, 1]),
    });

    expect(files['a/x.pdf'], [0xff, 0, 1]);
  });

  test('f03/us03/fr03/e08: the shipped pack files are decoded', () {
    expect(shippedPackFiles.keys, contains('prd-core/pack.yaml'));
  });

  test(
    'f03/us06/fr01, f03/us07/fr01: shippedPackVersions reads the version each '
    'shipped pack.yaml carries',
    () {
      final versions = shippedPackVersions();
      expect(versions.keys, ['prd-core', 'software-tech']);
      for (final MapEntry(:key, :value) in versions.entries) {
        final manifest = PackManifest.parse(
          utf8.decode(shippedPackFiles['$key/pack.yaml']!),
          file: 'packs/$key/pack.yaml',
        );
        expect(value, manifest.version.toString());
      }
    },
  );

  test('template_packs/write_spec_docs_from_software_tech/ship_software_tech_pack: '
      'the shipped software-tech pack is 1.4.0', () {
    expect(shippedPackVersions()['software-tech'], '1.4.0');
  });

  test('template_packs/write_prd_docs_from_prd_core/ship_prd_core_pack: '
      'the shipped prd-core pack is 1.7.0, so the guide text rides it', () {
    expect(shippedPackVersions()['prd-core'], '1.7.0');
  });

  test('template_packs/write_prd_docs_from_prd_core/'
      'write_shipped_writing_guides E05: the shipped feature type names the '
      'three size findings', () {
    final feature = utf8.decode(shippedPackFiles['prd-core/feature.yaml']!);
    for (final finding in [
      'chars_over_limit',
      'lines_over_limit',
      'item_over_limit',
    ]) {
      expect(feature, contains('`$finding`'));
    }
  });
}
