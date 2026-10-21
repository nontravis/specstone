import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/specstone_core.dart';
import 'package:test/test.dart';

void main() {
  group('shared version', () {
    test('the specstone pubspec carries the core version', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final match = RegExp(
        r'^version:\s*(\S+)\s*$',
        multiLine: true,
      ).firstMatch(pubspec);

      expect(match?.group(1), specstoneVersion);
    });

    test('the plugin manifest carries the core version', () {
      final manifest = File('../../plugin/.claude-plugin/plugin.json')
          .readAsStringSync();
      final json = jsonDecode(manifest) as Map<String, Object?>;

      expect(json['version'], specstoneVersion);
    });
  });
}
