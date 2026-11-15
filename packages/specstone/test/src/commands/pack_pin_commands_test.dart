import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/templates/shipped_pack_files.dart';
import 'package:test/test.dart';

import '../../../../specstone_core/test/helpers/check_fixture.dart';
import '../../../../specstone_core/test/helpers/shipped_pins.dart';
import '../../helpers/built_cli.dart';

void main() {
  late String binary;
  late Directory project;

  setUpAll(() async {
    binary = await buildSpecstone();
  });

  setUp(() async {
    project = await writeCheckProject(
      extra: {'.specstone/config.yaml': shippedPinsOneMinorBelow('prd-core')},
    );
  });

  Future<ProcessResult> run(List<String> args) =>
      Process.run(binary, args, workingDirectory: project.path);

  const story = 'user_story:login/email_login';
  final forms = {
    'check': ['check', '--json'],
    'check <target>': ['check', story, '--json'],
    'check --repeats': ['check', '--repeats', '--json'],
    'context': ['context', story, '--for', 'implement', '--json'],
  };

  for (final MapEntry(:key, :value) in forms.entries) {
    test('$key refuses a pin one minor below the shipped pack', () async {
      final result = await run(value);
      final shipped = shippedPackVersions()['prd-core']!;

      expect(result.exitCode, 78, reason: '${result.stdout}\n${result.stderr}');
      final envelope =
          jsonDecode(result.stderr as String) as Map<String, Object?>;
      final error = envelope['error']! as Map<String, Object?>;
      expect(error['code'], 'pack_pin_older');
      expect(
        error['message'],
        allOf(
          contains('prd-core'),
          contains(shipped),
          contains(_oneMinorBelow(shipped)),
          contains('specstone migrate --dry-run'),
        ),
      );
    });
  }

  test('--version exits 0 on the same project', () async {
    final result = await run(['--version']);

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  });
}

String _oneMinorBelow(String version) {
  final [major, minor, _] = version.split('.');
  return '$major.${int.parse(minor) - 1}.0';
}
