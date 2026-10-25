import 'dart:convert';

import 'package:test/test.dart';

import '../../helpers/read_fixture.dart';
import '../../helpers/temp_tree.dart';

void main() {
  test('f01/us04/s1, f01/us04/fr02: get login prints the feature and its spec doc and exits 0', () async {
    final (:runner, :out, :err) = readRunner(await writeReadProject());
    expect(await runner.run(['get', 'login']), 0);
    expect(
      out.toString(),
      startsWith(
        '==> login (feature) · prds/features/f01_login/FEATURE.md <==\n',
      ),
    );
  });
  test('f01/us04/fr02/e06: no name is argument_missing, exit 64', () async {
    final (:runner, :out, :err) = readRunner(await writeReadProject());
    expect(await runner.run(['get']), 64);
    expect(err.toString(), 'get needs a name, such as specstone get login\n');
  });
  test('f01/us04/s6, f01/us04/fr02/e02: --json puts section_not_found on stderr with stdout empty', () async {
    final (:runner, :out, :err) = readRunner(await writeReadProject());
    expect(await runner.run(['get', 'login#acceptance', '--json']), 64);
    expect(
      ((jsonDecode(err.toString()) as Map)['error'] as Map)['code'],
      'section_not_found',
    );
    expect(out.toString(), isEmpty);
  });
  test('f01/us04/fr01/e08: a typed name no doc carries names the type, as the sidecar does', () async {
    final (:runner, :out, :err) = readRunner(await writeReadProject());
    expect(await runner.run(['get', 'architecture:signup', '--json']), 64);
    expect((jsonDecode(err.toString()) as Map)['error'], {
      'code': 'doc_not_found',
      'message': 'no architecture doc carries the name signup',
    });
  });
  test('f01/us04/s7, f01/us04/fr02/e07: outside a project, or under a 9.9.9 pin, exits 78', () async {
    expect(
      await readRunner(await writeTree({})).runner.run(['get', 'login']),
      78,
    );
    final pinned = await writeReadProject(
      extra: {'.specstone/config.yaml': 'packs:\n  prd-core: 9.9.9\n'},
    );
    expect(await readRunner(pinned).runner.run(['get', 'login']), 78);
  });
}
