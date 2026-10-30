import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../../../specstone_core/test/helpers/write_fixture.dart';
import '../../helpers/write_runner.dart';

void main() {
  test('f02/us04/s1: delete prints one removed path per line', () async {
    final root = await writeWriteProject();
    final (:runner, :out, :err) = writeRunner(root);
    expect(
      await runner.run(['delete', 'fr:login/reset_password/expire_reset_link']),
      0,
    );
    expect(err.toString(), isEmpty);
    expect(out.toString(), '$fr32\n');
    expect(File('${root.path}/docs/$fr32').existsSync(), isFalse);
  });
  test('f02/us04/s6: an approved unit without a terminal exits 77 with the sidecar message', () async {
    final root = await writeWriteProject();
    final (:runner, :out, :err) = writeRunner(root);
    expect(
      await runner.run([
        'delete',
        'fr:login/email_login/validate_credentials',
        '--json',
      ]),
      77,
    );
    expect(out.toString(), isEmpty);
    final error = (jsonDecode(err.toString()) as Map)['error'] as Map;
    expect(error['code'], 'owner_terminal_required');
    expect(
      error['message'],
      'fr:login/email_login/validate_credentials holds approved docs; '
      'only the Owner deletes them, at an interactive terminal',
    );
    expect(File('${root.path}/docs/$fr11').existsSync(), isTrue);
  });
  test('f02/us04/s3, f02/us04/fr02/e03: the Owner prompt goes to stdout, the removed paths after it', () async {
    final root = await writeWriteProject();
    final (:runner, :out, :err) = writeRunner(
      root,
      console: FakeConsole(
        stdinIsTerminal: true,
        stdoutIsTerminal: true,
        answers: ['y'],
      ),
    );
    expect(
      await runner.run(['delete', 'fr:login/email_login/validate_credentials']),
      0,
    );
    expect(out.toString(), '$fr11\ndelete 1 files? [y/N] $fr11\n');
    expect(err.toString(), isEmpty);
  });
  test('f02/us04/s3, PD9: under --json the Owner prompt goes to stderr and stdout holds one JSON object', () async {
    final root = await writeWriteProject();
    final (:runner, :out, :err) = writeRunner(
      root,
      console: FakeConsole(
        stdinIsTerminal: true,
        stdoutIsTerminal: true,
        answers: ['y'],
      ),
    );
    expect(
      await runner.run([
        'delete',
        'fr:login/email_login/validate_credentials',
        '--json',
      ]),
      0,
    );
    expect(err.toString(), '$fr11\ndelete 1 files? [y/N] ');
    expect(jsonDecode(out.toString()), {
      'removed': [fr11],
      'warnings': <String>[],
    });
  });
  test('f02/us04/fr01/e09: delete takes no --base', () async {
    final (:runner, :out, :err) = writeRunner(await writeWriteProject());
    expect(
      await runner.run([
        'delete',
        'fr:login/reset_password/expire_reset_link',
        '--base',
        'x',
      ]),
      64,
    );
  });
  test('f02/us04/fr01/e09: no target is argument_missing', () async {
    final (:runner, :out, :err) = writeRunner(await writeWriteProject());
    expect(await runner.run(['delete']), 64);
    expect(err.toString(), startsWith('delete needs a target'));
  });
  const notes = 'specs/f01_login/api_notes.md';
  const errors = 'specs/f01_login/api_errors.md';
  const index = 'specs/INDEX.md';
  final untyped = <String, String>{
    'docs/$notes': '# Notes\n\nSee [errors](api_errors.md).\n',
    'docs/$errors': '# Errors\n\nSee [index](../INDEX.md).\n',
    'docs/$index': '# Index\n\nNothing links here but api_errors.md.\n',
  };
  test('f02/us04/fr01/e10, f02/us04/fr04: two targets delete both, one removed path per line', () async {
    const one = 'specs/f01_login/one.md';
    const two = 'specs/f01_login/two.md';
    final root = await writeWriteProject(
      extra: {
        'docs/$one': '---\ndraft: true\n---\n\n# One\n',
        'docs/$two': '---\ndraft: true\n---\n\n# Two\n',
      },
    );
    final (:runner, :out, :err) = writeRunner(root);
    expect(await runner.run(['delete', one, two]), 0);
    expect(err.toString(), isEmpty);
    expect(out.toString(), '$one\n$two\n');
    expect(File('${root.path}/docs/$one').existsSync(), isFalse);
    expect(File('${root.path}/docs/$two').existsSync(), isFalse);
  });
  test("f02/us04/fr04/e02: an Agent's delete of an untyped doc with no draft exits 77", () async {
    final root = await writeWriteProject(extra: untyped);
    final (:runner, :out, :err) = writeRunner(root);
    expect(await runner.run(['delete', notes]), 77);
    expect(err.toString(), contains('only the Owner deletes them'));
    expect(File('${root.path}/docs/$notes').existsSync(), isTrue);
  });
  test('f02/us04/s8, f02/us04/fr04/e03: at a terminal the Owner sees the list and the prompt, then the removed paths', () async {
    final root = await writeWriteProject(extra: untyped);
    final (:runner, :out, :err) = writeRunner(
      root,
      console: FakeConsole(
        stdinIsTerminal: true,
        stdoutIsTerminal: true,
        answers: ['y'],
      ),
    );
    expect(await runner.run(['delete', notes, errors, index]), 0);
    expect(err.toString(), isEmpty);
    // The core lists a delete set sorted by code point, not in call order.
    const paths = '$index\n$errors\n$notes\n';
    expect(out.toString(), '${paths}delete 3 files? [y/N] $paths');
  });
  test('f02/us04/s9, f02/us04/fr04/e04: a referrer outside the set exits 64 and is named after ; also', () async {
    final root = await writeWriteProject(
      extra: {
        ...untyped,
        'docs/$story1':
            '${writeProject['docs/$story1']}\n'
            'See [errors](../../../../specs/f01_login/api_errors.md).\n',
      },
    );
    final (:runner, :out, :err) = writeRunner(
      root,
      console: FakeConsole(
        stdinIsTerminal: true,
        stdoutIsTerminal: true,
        answers: ['y'],
      ),
    );
    expect(await runner.run(['delete', notes, errors]), 64);
    expect(
      err.toString(),
      '$errors: docs outside the delete set link into it; also $story1\n',
    );
    expect(File('${root.path}/docs/$notes').existsSync(), isTrue);
    expect(File('${root.path}/docs/$errors').existsSync(), isTrue);
  });
  test('f02/us04/fr04: delete --help shows several targets', () async {
    final (:runner, :out, :err) = writeRunner(await writeWriteProject());
    expect(await runner.run(['delete', '--help']), 0);
    expect(
      out.toString(),
      contains('Usage: specstone delete <target> [<target> …] [--json]'),
    );
  });
  test('f02/us04/fr04/e01: an untyped DocPath that holds a space deletes that file', () async {
    const spaced = 'specs/f01_login/api notes.md';
    final root = await writeWriteProject(
      extra: {'docs/$spaced': '---\ndraft: true\n---\n\n# Notes\n'},
    );
    final (:runner, :out, :err) = writeRunner(root);
    expect(await runner.run(['delete', spaced]), 0);
    expect(out.toString(), '$spaced\n');
    expect(File('${root.path}/docs/$spaced').existsSync(), isFalse);
  });
}
