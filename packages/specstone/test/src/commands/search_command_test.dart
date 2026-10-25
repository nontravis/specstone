import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../helpers/read_fixture.dart';
import '../../helpers/temp_tree.dart';

void main() {
  test(
    'f01/us06/s1, f01/us06/fr01: unquoted words search as one query',
    () async {
      final project = await writeReadProject();
      final split = readRunner(project);
      expect(await split.runner.run(['search', 'check', 'the', 'email']), 0);
      final quoted = readRunner(project);
      expect(await quoted.runner.run(['search', 'check the email']), 0);
      expect(split.out.toString(), quoted.out.toString());
      expect(
        split.out.toString(),
        contains('login/email_login/validate_credentials#statement (fr)'),
      );
    },
  );
  test('f01/us06/fr01: --json prints hits and warnings', () async {
    final (:runner, :out, :err) = readRunner(await writeReadProject());
    expect(await runner.run(['search', 'check the email', '--json']), 0);
    final json = jsonDecode(out.toString()) as Map<String, Object?>;
    expect(json.keys.toList(), ['hits', 'warnings']);
    expect(((json['hits']! as List).first as Map).keys.toList(), [
      'name',
      'docType',
      'section',
      'title',
      'snippet',
    ]);
  });
  test('f01/us06/fr01/e08: no query is argument_missing, exit 64', () async {
    final (:runner, :out, :err) = readRunner(await writeReadProject());
    expect(await runner.run(['search']), 64);
    expect(
      err.toString(),
      'search needs a query, such as specstone search "lock the account"\n',
    );
  });
  test('f01/us06/s7, f01/us06/fr01/e01: a short query fails before any index exists', () async {
    final project = await writeReadProject();
    final (:runner, :out, :err) = readRunner(project);
    expect(await runner.run(['search', 'ui', '--json']), 64);
    expect(
      ((jsonDecode(err.toString()) as Map)['error'] as Map)['code'],
      'query_too_short',
    );
    expect(
      File('${project.path}/.specstone/index.sqlite').existsSync(),
      isFalse,
    );
  });
  test('f01/us06/fr02/e06: --limit 0 exits 64', () async {
    final (:runner, :out, :err) = readRunner(await writeReadProject());
    expect(await runner.run(['search', 'login', '--limit', '0']), 64);
    expect(err.toString(), '--limit takes a positive integer, not 0\n');
  });
  test('f01/us06/fr02/e06, plan decision 9: an invalid --limit wins over a short query', () async {
    final (:runner, :out, :err) = readRunner(await writeReadProject());
    expect(await runner.run(['search', 'ab', '--limit', '0', '--json']), 64);
    expect(
      ((jsonDecode(err.toString()) as Map)['error'] as Map)['code'],
      'argument_invalid',
    );
  });
  test('f01/us06/s8, f01/us06/fr01/e09: outside a project, or under a 9.9.9 pin, exits 78', () async {
    expect(
      await readRunner(await writeTree({})).runner.run(['search', 'login']),
      78,
    );
    final pinned = await writeReadProject(
      extra: {'.specstone/config.yaml': 'packs:\n  prd-core: 9.9.9\n'},
    );
    expect(await readRunner(pinned).runner.run(['search', 'login']), 78);
  });
}
