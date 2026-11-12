import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/specstone_core.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import '../helpers/package_root.dart';

void main() {
  group('shared version', () {
    test('the specstone pubspec carries the core version', () {
      final pubspec = File.fromUri(packageRoot().uri.resolve('pubspec.yaml'))
          .readAsStringSync();
      final match = RegExp(
        r'^version:\s*(\S+)\s*$',
        multiLine: true,
      ).firstMatch(pubspec);

      expect(match?.group(1), specstoneVersion);
    });

    test('the plugin manifest carries the core version', () {
      final manifest = File.fromUri(
        packageRoot().uri.resolve('../../plugin/.claude-plugin/plugin.json'),
      ).readAsStringSync();
      final json = jsonDecode(manifest) as Map<String, Object?>;

      expect(json['version'], specstoneVersion);
    });

    test('f09/us04/fr02, INV-1: the specstone_core pubspec carries the core '
        'version', () {
      final pubspec = File.fromUri(
        packageRoot().uri.resolve('../specstone_core/pubspec.yaml'),
      ).readAsStringSync();
      final match = RegExp(
        r'^version:\s*(\S+)\s*$',
        multiLine: true,
      ).firstMatch(pubspec);

      expect(match?.group(1), specstoneVersion);
    });

    test(
      'f09/us04/fr02, INV-1: the specstone pubspec constrains specstone_core '
      'to ^<core version>',
      () {
        final pubspec = File.fromUri(packageRoot().uri.resolve('pubspec.yaml'))
            .readAsStringSync();
        final match = RegExp(
          r'^  specstone_core: \^(\S+)\s*$',
          multiLine: true,
        ).firstMatch(pubspec);

        expect(match?.group(1), specstoneVersion);
      },
    );

    test('install_update/version_match INV-1: the workspace root lists '
        'specstone_core with no version constraint', () {
      final pubspec = File.fromUri(
        packageRoot().uri.resolve('../../pubspec.yaml'),
      ).readAsStringSync();
      final dependencies =
          (loadYaml(pubspec) as YamlMap)['dependencies'] as YamlMap;

      expect(dependencies.containsKey('specstone_core'), isTrue);
      expect(dependencies['specstone_core'], isNull);
    });
  });
}
