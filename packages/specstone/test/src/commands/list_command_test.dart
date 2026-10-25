import 'dart:convert';

import 'package:test/test.dart';

import '../../helpers/read_fixture.dart';
import '../../helpers/temp_tree.dart';

void main() {
  test('f01/us03/s1, f01/us03/fr01: list feature prints the feature line and exits 0', () async {
    final (:runner, :out, :err) = readRunner(await writeReadProject());
    expect(await runner.run(['list', 'feature']), 0);
    expect(out.toString(), startsWith('login (feature) — Login · planned · '));
    expect(err.toString(), isEmpty);
  });
  test('f01/us03/fr01: --json prints docs and warnings', () async {
    final (:runner, :out, :err) = readRunner(await writeReadProject());
    expect(await runner.run(['list', 'feature', '--json']), 0);
    expect((jsonDecode(out.toString()) as Map).keys.toList(), [
      'docs',
      'warnings',
    ]);
  });
  test('f01/us03/fr01/e04: no doc type is argument_missing, exit 64', () async {
    final (:runner, :out, :err) = readRunner(await writeReadProject());
    expect(await runner.run(['list']), 64);
    expect(
      err.toString(),
      'list needs a doc type, such as specstone list feature\n',
    );
    expect(out.toString(), isEmpty);
  });
  test('f01/us03/fr02/e08: --suspect is an unknown option: usage on stderr, exit 64', () async {
    final (:runner, :out, :err) = readRunner(await writeReadProject());
    expect(await runner.run(['list', 'fr', '--suspect']), 64);
    expect(
      err.toString(),
      startsWith('Could not find an option named "--suspect".'),
    );
    expect(err.toString(), contains('Usage: specstone list'));
  });
  test('f01/us03/s10, f01/us03/fr01/e06: outside a project, or under a 9.9.9 pin, exits 78', () async {
    final outside = readRunner(await writeTree({}));
    expect(await outside.runner.run(['list', 'feature']), 78);
    final pinned = readRunner(
      await writeReadProject(
        extra: {'.specstone/config.yaml': 'packs:\n  prd-core: 9.9.9\n'},
      ),
    );
    expect(await pinned.runner.run(['list', 'feature']), 78);
  });
}
