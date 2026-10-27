// The expected values are plan literals kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import '../../../../specstone_core/test/helpers/check_fixture.dart';
import '../../helpers/read_fixture.dart';
import '../../helpers/temp_tree.dart';

Map<String, String> frWith(String line) => fr('verify_method: test', line);

void main() {
  test('f04/us01/s1, f04/us01/fr02/e01: a clean project prints 0 findings and exits 0', () async {
    final (:runner, :out, :err) = readRunner(await writeCheckProject());
    expect(await runner.run(['check']), 0);
    expect(out.toString(), '0 findings\n');
    expect(err.toString(), isEmpty);
  });

  test('f04/us01/fr02: each finding prints on its own line before the count, and the check exits 1', () async {
    final (:runner, :out, :err) = readRunner(
      await writeCheckProject(extra: frWith('verify_method: maybe')),
    );
    expect(await runner.run(['check']), 1);
    expect(
      out.toString(),
      '$loginFr:5: field_value_mismatch: verify_method is maybe; it takes test, analysis, inspection, or '
      'demonstration\n1 finding\n',
    );
  });

  test("f04/us01/s8, f04/us01/fr02: --json gives each finding's kind, file, name, line, and message, and the count", () async {
    final (:runner, :out, :err) = readRunner(
      await writeCheckProject(extra: frWith('verify_method: maybe')),
    );
    expect(await runner.run(['check', '--json']), 1);
    final json = jsonDecode(out.toString()) as Map<String, Object?>;
    expect(json.keys, ['findings', 'count']);
    expect(json['count'], 1);
    expect((json['findings']! as List).single, {
      'kind': 'field_value_mismatch',
      'docPath': loginFr,
      'name': 'login/email_login/check_password',
      'line': 5,
      'message': 'verify_method is maybe; it takes test, analysis, inspection, or demonstration',
      'field': 'verify_method',
      'value': 'maybe',
    });
  });

  test('f04/us01/s9, f04/us01/fr01/e05, f04/us01/fr02/e07: a name no doc carries refuses, exit 64, no finding', () async {
    final (:runner, :out, :err) = readRunner(await writeCheckProject());
    expect(await runner.run(['check', 'login/emial_login']), 64);
    expect(err.toString(), 'no doc carries the name login/emial_login\n');
    expect(out.toString(), isEmpty);
  });

  test('f04/us01/fr01/e06, f04/us01/fr01/e07: an unknown doc type exits 64; outside a project exits 78', () async {
    final inside = readRunner(await writeCheckProject());
    expect(await inside.runner.run(['check', 'nope:login']), 64);
    final outside = readRunner(await writeTree({}));
    expect(await outside.runner.run(['check']), 78);
    expect(outside.err.toString(), startsWith('no Specstone project'));
    expect(outside.out.toString(), isEmpty);
  });

  test('f04/us01/fr02/e05: a warning no finding states goes to stderr, and to warnings under --json', () async {
    Future<Directory> damaged() async {
      final project = await writeCheckProject();
      File('${project.path}/.specstone/index.sqlite')
          .writeAsStringSync('not a database');
      return project;
    }

    final text = readRunner(await damaged());
    expect(await text.runner.run(['check']), 0);
    expect(text.err.toString(), startsWith('⚠️ WARNING: '));
    final json = readRunner(await damaged());
    expect(await json.runner.run(['check', '--json']), 0);
    expect((jsonDecode(json.out.toString()) as Map)['warnings'], hasLength(1));
  });

  test('f04/us01/fr01/e08, f04/us01/fr01/e10: a pin fault exits 78 before any rule; an unknown option or two targets '
      'exit 64', () async {
    final pinned = readRunner(
      await writeCheckProject(
        extra: {'.specstone/config.yaml': 'packs:\n  prd-core: 9.9.9\n'},
      ),
    );
    expect(await pinned.runner.run(['check']), 78);
    expect(pinned.out.toString(), isEmpty);
    for (final args in [
      ['check', '--fix'],
      ['check', 'a', 'b'],
    ]) {
      expect(await readRunner(await writeCheckProject()).runner.run(args), 64);
    }
  });

  test('f04/us01/fr01/e09: a write lock held past the busy timeout exits 75 with the JSON envelope', () async {
    final project = await writeCheckProject();
    expect(await readRunner(project).runner.run(['check']), 0);
    final holder = sqlite3.open('${project.path}/.specstone/index.sqlite')
      ..execute('BEGIN IMMEDIATE');
    addTearDown(
      () => holder
        ..execute('ROLLBACK')
        ..close(),
    );
    File('${project.path}/docs/$loginFeature')
        .writeAsStringSync('# Login v2\n');
    final (:runner, :out, :err) = readRunner(
      project,
      busyTimeout: const Duration(milliseconds: 200),
    );
    expect(await runner.run(['check', '--json']), 75);
    expect(
      (jsonDecode(err.toString()) as Map)['error'],
      containsPair('code', 'index_busy'),
    );
    expect(out.toString(), isEmpty);
  });
}
