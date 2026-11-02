import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../specstone_core/test/helpers/check_fixture.dart';
import '../../specstone_core/test/helpers/relative_link.dart';
import '../../specstone_core/test/helpers/shipped_pins.dart';
import 'helpers/built_cli.dart';
import 'helpers/temp_tree.dart';

const _featureDoc = 'prds/features/f01_login/FEATURE.md';

void main() {
  late String binary;

  setUpAll(() async {
    binary = await buildSpecstone();
  });

  test('a read command run in a linked code folder lists the nested '
      "project's docs and writes nothing", () async {
    final tree = await writeTree({
      'ws/.specstone/config.yaml': shippedPinsConfig(),
      'ws/docs/prds/features/f02_outer/FEATURE.md': '# Outer\n',
      'ws/example/.specstone/config.yaml': shippedPinsConfig(),
      'ws/example/docs/$_featureDoc':
          '---\nvision:\n  - PV-01\nslug:\n  - sign-in\n---\n\n# Login\n\n'
          '## Problem\nUsers sign in with an email and a password.\n\n'
          '## Out-of-scope\n- Social sign-in\n',
      'ws/code/example/keep.txt': '',
    });
    try {
      createRelativeLink(
        '${tree.path}/ws/code/example/docs',
        '../../example/docs',
      );
    } on FileSystemException {
      markTestSkipped('symbolic links need privileges on this machine');
      return;
    }
    final codeExample = '${tree.path}/ws/code/example';

    final result = await Process.run(binary, [
      'list',
      'feature',
      '--json',
    ], workingDirectory: codeExample);

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    final docs = (jsonDecode(result.stdout as String) as Map)['docs']! as List;
    expect([for (final doc in docs) (doc as Map)['name']], ['login']);
    expect(Directory('$codeExample/.specstone').existsSync(), isFalse);
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
