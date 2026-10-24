// The expected values are plan literals kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import '../../helpers/read_fixture.dart';
import '../../helpers/temp_tree.dart';

const legacyFr = {
  '.specstone/templates/legacy_fr.yaml':
      'id: legacy_fr\n'
      'description: Old FRs.\npath: prds/features/f{nn}_{slug}/us{nn}_{slug}/{slug}.md\n',
};
const frWarning =
    'prds/features/f01_login/us01_email_login/fr01_validate_credentials.md matches two doc types: fr, legacy_fr';

Map<String, Object?> errorOf(StringBuffer err) =>
    (jsonDecode(err.toString()) as Map)['error'] as Map<String, Object?>;

void main() {
  test('f01/us02/s1, f01/us02/fr01: structure prints the tree on stdout and exits 0', () async {
    final (:runner, :out, :err) = readRunner(await writeReadProject());
    expect(await runner.run(['structure']), 0);
    expect(out.toString(), contains('login (feature) — Login · planned · '));
    expect(err.toString(), isEmpty);
  });
  test('f01/us02/fr01/e06: --json prints one object; a warning goes only to its warnings array', () async {
    final (:runner, :out, :err) = readRunner(
      await writeReadProject(extra: legacyFr),
    );
    expect(await runner.run(['structure', '--json']), 0);
    final json = jsonDecode(out.toString()) as Map<String, Object?>;
    expect(json.keys.toList(), ['docs', 'untyped', 'warnings']);
    expect(json['warnings'], [frWarning]);
    expect(err.toString(), isEmpty);
  });
  test('f01/us02/fr01: in text mode the warning prints on stderr with the warning prefix', () async {
    final (:runner, :out, :err) = readRunner(
      await writeReadProject(extra: legacyFr),
    );
    expect(await runner.run(['structure']), 0);
    expect(err.toString(), '⚠️ WARNING: $frWarning\n');
  });
  test('f01/us02/s5, f01/us02/fr01/e03: a target no doc carries exits 64 and names it', () async {
    final (:runner, :out, :err) = readRunner(await writeReadProject());
    expect(await runner.run(['structure', 'logn']), 64);
    expect(err.toString(), 'no doc carries the name logn\n');
    expect(out.toString(), isEmpty);
  });
  test('f01/us02/s6, f01/us02/fr01/e07, f01/us01/s11, f01/us01/fr01/e01: outside a project exits 78', () async {
    final (:runner, :out, :err) = readRunner(await writeTree({}));
    expect(await runner.run(['structure']), 78);
    expect(
      err.toString(),
      'no Specstone project: no folder from the working directory upward holds .specstone/config.yaml\n',
    );
  });
  test("f01/us02/fr01/e07, f01/us01/fr01/e02: a template fault exits 78 with F-03's code", () async {
    final (:runner, :out, :err) = readRunner(
      await writeReadProject(
        extra: {'.specstone/config.yaml': 'packs:\n  prd-core: 9.9.9\n'},
      ),
    );
    expect(await runner.run(['structure', '--json']), 78);
    expect(errorOf(err)['code'], 'pack_pin_newer');
    expect(out.toString(), isEmpty);
  });
  test(
    'f01/us02/fr01: a surplus positional prints usage and exits 64',
    () async {
      final (:runner, :out, :err) = readRunner(await writeReadProject());
      expect(await runner.run(['structure', 'a', 'b']), 64);
      expect(err.toString(), contains('Usage: specstone structure'));
    },
  );
  test(
    'f01/us01/s12, f01/us01/fr02/e07, s05: a read-only .specstone/ exits 73 with the JSON envelope',
    skip: readOnlySkipReason(),
    () async {
      final project = await writeReadProject();
      final dot = Directory('${project.path}/.specstone');
      Process.runSync('chmod', ['555', dot.path]);
      addTearDown(() => Process.runSync('chmod', ['755', dot.path]));
      final (:runner, :out, :err) = readRunner(project);
      expect(await runner.run(['structure', '--json']), 73);
      expect(errorOf(err), {
        'code': 'index_not_writable',
        'message': 'cannot write the index under .specstone/; make it writable and run the command again',
      });
      expect(out.toString(), isEmpty);
    },
  );
  test('f01/us01/s13, f01/us01/fr05/e05, s05: a write lock held past the timeout exits 75 with the JSON envelope', () async {
    final project = await writeReadProject();
    expect(await readRunner(project).runner.run(['structure']), 0);
    final holder = sqlite3.open('${project.path}/.specstone/index.sqlite')
      ..execute('BEGIN IMMEDIATE');
    addTearDown(
      () => holder
        ..execute('ROLLBACK')
        ..close(),
    );
    File('${project.path}/docs/prds/features/f01_login/FEATURE.md')
        .writeAsStringSync('# Login v2\n');
    final (:runner, :out, :err) = readRunner(
      project,
      busyTimeout: const Duration(milliseconds: 200),
    );
    expect(await runner.run(['structure', '--json']), 75);
    expect(errorOf(err), {
      'code': 'index_busy',
      'message': 'the index is busy; run the command again once the other call finishes',
    });
    expect(out.toString(), isEmpty);
  });
}
