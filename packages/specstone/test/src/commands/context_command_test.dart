// The test titles and literals are plan values kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:convert';

import 'package:test/test.dart';

import '../../helpers/read_fixture.dart';
import '../../helpers/temp_tree.dart';

void main() {
  test('f01/us05/s1: context for a story prints the bundle and its doc list, exit 0', () async {
    final (:runner, :out, :err) = readRunner(await writeReadProject());
    expect(
      await runner.run(['context', 'login/email_login', '--for', 'implement']),
      0,
    );
    expect(out.toString(), contains('==> bundle: '));
    expect(out.toString(), endsWith('- login (architecture)\n'));
  });
  test('f01/us05/fr01/e10: no target, no --for, or another --for value refuses with exit 64', () async {
    final project = await writeReadProject();
    final noTarget = readRunner(project);
    expect(await noTarget.runner.run(['context', '--for', 'implement']), 64);
    expect(
      noTarget.err.toString(),
      'context needs a target or --code, such as specstone context login --for implement\n',
    );
    final noMode = readRunner(project);
    expect(await noMode.runner.run(['context', 'login']), 64);
    expect(
      noMode.err.toString(),
      'context needs --for, such as specstone context login --for implement\n',
    );
    final badMode = readRunner(project);
    expect(
      await badMode.runner.run(['context', 'login', '--for', 'deploy']),
      64,
    );
    expect(
      badMode.err.toString(),
      '--for takes query, implement, or design, not deploy\n',
    );
  });
  test('f01/us05/fr03/e06: over budget with --json exits 1 with stdout one object and stderr empty', () async {
    final (:runner, :out, :err) = readRunner(await writeReadProject());
    expect(
      await runner.run([
        'context',
        'login/email_login',
        '--for',
        'implement',
        '--budget',
        '1',
        '--json',
      ]),
      1,
    );
    expect((jsonDecode(out.toString()) as Map)['overBudget'], isTrue);
    expect(err.toString(), isEmpty);
  });
  test('f01/us01/s7, f01/us05/s10: an untyped target exits 64 with the untyped_target message', () async {
    final (:runner, :out, :err) = readRunner(await writeReadProject());
    expect(
      await runner.run([
        'context',
        'prds/d01_context.md',
        '--for',
        'implement',
      ]),
      64,
    );
    expect(
      err.toString(),
      'prds/d01_context.md has no doc type, so it never joins a bundle; read it with specstone get\n',
    );
  });
  test('f01/us05/s13, f01/us05/fr01/e12: outside a project, or under a 9.9.9 pin, exits 78', () async {
    expect(
      await readRunner(await writeTree({})).runner
          .run(['context', 'login', '--for', 'query']),
      78,
    );
    final pinned = await writeReadProject(
      extra: {'.specstone/config.yaml': 'packs:\n  prd-core: 9.9.9\n'},
    );
    expect(
      await readRunner(pinned).runner
          .run(['context', 'login', '--for', 'query']),
      78,
    );
  });
}
