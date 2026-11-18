import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../specstone_core/test/helpers/check_fixture.dart';
import '../../specstone_core/test/helpers/relative_link.dart';
import '../../specstone_core/test/helpers/shipped_pins.dart';
import 'helpers/built_cli.dart';
import 'helpers/temp_tree.dart';

const _record = '.specstone/records/f01_login/IMPLEMENTATION.md';
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

  test('check run in a linked code folder checks the nested project and'
      ' resolves its code paths from its code root', () async {
    final nested = withApprovalHashes(
      withCodeFingerprints(checkProjectFiles()),
    );
    final tree = await writeTree({
      'ws/.specstone/config.yaml': shippedPinsConfig(),
      'ws/docs/prds/features/f02_outer/FEATURE.md': '# Outer\n',
      for (final MapEntry(:key, :value) in nested.entries)
        'ws/example/$key': value,
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

    final inner = await Process.run(binary, [
      'check',
    ], workingDirectory: codeExample);
    final outer = await Process.run(binary, [
      'check',
    ], workingDirectory: '${tree.path}/ws');

    expect(inner.exitCode, 0, reason: '${inner.stdout}\n${inner.stderr}');
    expect(inner.stdout, isNot(contains('f02_outer')));
    expect(outer.exitCode, 1, reason: '${outer.stdout}\n${outer.stderr}');
    expect(outer.stdout, contains('f02_outer'));
  });

  group('with no trust record for a linked code folder', () {
    const trustHint = 'run specstone trust at a terminal to allow it';

    late Directory home;

    setUp(() async {
      home = await writeTree({'keep.txt': ''});
    });

    Future<ProcessResult> run(List<String> args, String folder) => Process.run(
      binary,
      args,
      workingDirectory: folder,
      environment: {'HOME': home.path, 'USERPROFILE': home.path},
    );

    /// Links [path] to [target], or marks the test skipped when the machine
    /// refuses links; returns whether the link exists.
    bool link(String path, String target) {
      try {
        createRelativeLink(path, target);
        return true;
      } on FileSystemException {
        markTestSkipped('symbolic links need privileges on this machine');
        return false;
      }
    }

    Future<({String folder, String project})?> linkedExample() async {
      final tree = await writeTree({
        'ws/example/.specstone/config.yaml': shippedPinsConfig(),
        'ws/example/docs/$_featureDoc':
            '---\nvision:\n  - PV-01\nslug:\n  - sign-in\n---\n\n'
            '# Login\n\n## Problem\nUsers sign in.\n\n'
            '## Out-of-scope\n- Social sign-in\n',
        'ws/code/example/keep.txt': '',
      });
      if (!link('${tree.path}/ws/code/example/docs', '../../example/docs')) {
        return null;
      }
      return (
        folder: '${tree.path}/ws/code/example',
        project: '${tree.path}/ws/example',
      );
    }

    test('format, init, migrate, approve --dry-run, and build of the default'
        ' output are refused', () async {
      final example = await linkedExample();
      if (example == null) return;
      final base = await writeTree({
        'victim/docs/prds/keep.md': '# Keep\n',
        'clone/keep.txt': '',
      });
      if (!link('${base.path}/clone/docs', '../victim/docs')) return;
      final folder = example.folder;

      final runs = {
        'format': await run(['format'], folder),
        'migrate': await run(['migrate'], folder),
        'approve --dry-run': await run(['approve', '--dry-run'], folder),
        'build': await run(['build', 'docs'], folder),
        'init': await run(['init'], '${base.path}/clone'),
      };

      for (final MapEntry(key: command, value: result) in runs.entries) {
        expect(result.exitCode, 73, reason: '$command: ${result.stderr}');
        expect(result.stderr, contains(trustHint), reason: command);
      }
      expect(
        File('${base.path}/victim/.specstone/config.yaml').existsSync(),
        isFalse,
      );
    });

    test('the missing record gates the write commands only, never the'
        ' index', () async {
      final example = await linkedExample();
      if (example == null) return;
      final (:folder, :project) = example;

      final list = await run(['list', 'feature'], folder);
      final format = await run(['format'], folder);

      expect(list.exitCode, 0, reason: '${list.stdout}\n${list.stderr}');
      expect(list.stdout, contains('login'));
      expect(File('$project/.specstone/index.sqlite').existsSync(), isTrue);
      expect(File('$project/.specstone/.gitignore').existsSync(), isTrue);
      expect(format.exitCode, 73, reason: '${format.stderr}');
    });
  });

  test('a code_root naming a missing folder still lists, and check names '
      'each pointer it cannot resolve from there', () async {
    final project = await writeCheckProject(
      extra: {
        '.specstone/config.yaml': '${shippedPinsConfig()}code_root: code\n',
        _record:
            "---\nstatuses:\n  - 'email_login/check_password:implemented'\n"
            "implements:\n  - 'email_login/check_password:lib/a.dart'\n"
            '---\n\n# Record\n',
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
        '$_record:6: implements_path_unresolved: lib/a.dart is no file\n',
      ),
    );
  });
}
