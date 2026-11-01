import 'dart:io';

import 'package:test/test.dart';

import '../../specstone_core/test/helpers/check_fixture.dart';
import '../../specstone_core/test/helpers/shipped_pins.dart';
import 'helpers/built_cli.dart';

void main() {
  late String binary;

  setUpAll(() async {
    binary = await buildSpecstone();
  });

  test('a code_root naming a missing folder still lists, and check names '
      'each pointer it cannot resolve from there', () async {
    final project = await writeCheckProject(
      extra: {
        '.specstone/config.yaml': '${shippedPinsConfig()}code_root: code\n',
        ...fr('app/lib/login.dart:checkPassword', 'lib/a.dart'),
        // Resolved from the project root, the pointer would hold.
        'lib/a.dart': 'class A {}\n',
      },
    );

    final list = await Process.run(binary, [
      'list',
      'fr',
    ], workingDirectory: project.path);
    final check = await Process.run(binary, [
      'check',
    ], workingDirectory: project.path);

    expect(list.exitCode, 0, reason: '${list.stdout}\n${list.stderr}');
    expect(check.exitCode, 1, reason: '${check.stdout}\n${check.stderr}');
    expect(
      check.stdout,
      contains(
        '$loginFr:7: implements_path_unresolved: lib/a.dart is no file\n',
      ),
    );
  });
}
