// The test titles and literals are plan values kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:io';

import 'package:test/test.dart';

import '../../../../specstone_core/test/helpers/write_fixture.dart';
import '../../helpers/write_runner.dart';

void main() {
  test('f02/us03/s7, f02/us03/fr01/e04: approve without a terminal exits 77 and shows nothing', () async {
    final (:runner, :out, :err) = writeRunner(await writeWriteProject());
    expect(await runner.run(['approve']), 77);
    expect(out.toString(), isEmpty);
    expect(
      err.toString(),
      'approve runs only at an interactive terminal; ask the Owner to run specstone approve\n',
    );
  });
  test('f02/us03/s7: a terminal on stdin alone is still refused', () async {
    final (:runner, :out, :err) = writeRunner(
      await writeWriteProject(),
      console: FakeConsole(stdinIsTerminal: true),
    );
    expect(await runner.run(['approve']), 77);
    expect(out.toString(), isEmpty);
  });
  test('f02/us03/s1: at a terminal, y approves the draft', () async {
    final root = await writeWriteProject();
    final console = FakeConsole(
      stdinIsTerminal: true,
      stdoutIsTerminal: true,
      answers: ['y', 'y'],
    );
    final (:runner, :out, :err) = writeRunner(root, console: console);
    expect(await runner.run(['approve', 'signup']), 0);
    expect(err.toString(), isEmpty);
    expect(out.toString(), contains('approve? [y/n/q] '));
    final text = File('${root.path}/docs/$signupFeature').readAsStringSync();
    expect(text, contains('approved: true'));
    expect(text, isNot(contains('draft: true')));
  });
  test('f02/us03/fr01: approve takes no --json', () async {
    final (:runner, :out, :err) = writeRunner(await writeWriteProject());
    expect(await runner.run(['approve', '--json']), 64);
  });
}
