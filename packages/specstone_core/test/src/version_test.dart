import 'dart:io';

import 'package:specstone_core/specstone_core.dart';
import 'package:test/test.dart';

import '../helpers/package_root.dart';

void main() {
  group('specstoneVersion', () {
    test('equals the version in the package pubspec', () {
      final pubspec = File.fromUri(packageRoot().uri.resolve('pubspec.yaml'))
          .readAsStringSync();
      final match = RegExp(
        r'^version:\s*(\S+)\s*$',
        multiLine: true,
      ).firstMatch(pubspec);

      expect(match?.group(1), specstoneVersion);
    });
  });
}
