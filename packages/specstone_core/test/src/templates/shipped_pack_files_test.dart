import 'dart:convert';

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
    expect(shippedPackFiles, isA<Map<String, List<int>>>());
  });
}
