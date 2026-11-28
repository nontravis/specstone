@Tags(['ps1', 'integration'])
library;

import 'dart:io';

import 'package:test/test.dart';

import '../helpers/script_sandbox.dart';

void main() {
  for (final name in ['install.ps1', 'uninstall.ps1']) {
    test('$name holds only bytes below 0x80', () {
      // Windows PowerShell 5.1 reads a BOM-less file in the ANSI code page,
      // so one non-ASCII byte changes what `-File` runs.
      final bytes = File('${repoRoot().path}/$name').readAsBytesSync();

      expect(bytes.where((byte) => byte >= 0x80), isEmpty);
    });
  }
}
