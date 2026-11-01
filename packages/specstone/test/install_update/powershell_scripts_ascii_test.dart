@Tags(['ps1'])
library;

import 'dart:io';

import 'package:test/test.dart';

import '../helpers/script_sandbox.dart';

void main() {
  for (final (name, story) in [
    ('install.ps1', 'us01'),
    ('uninstall.ps1', 'us03'),
  ]) {
    test('f09/$story/fr03: $name holds only bytes below 0x80', () {
      // Windows PowerShell 5.1 reads a BOM-less file in the ANSI code page,
      // so one non-ASCII byte changes what `-File` runs.
      final bytes = File('${repoRoot().path}/$name').readAsBytesSync();

      expect(bytes.where((byte) => byte >= 0x80), isEmpty);
    });
  }
}
