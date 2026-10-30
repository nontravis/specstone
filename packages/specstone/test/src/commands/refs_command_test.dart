// The test titles and literals are plan values kept as written.

import 'dart:convert';

import 'package:test/test.dart';

import '../../helpers/read_fixture.dart';
import '../../helpers/temp_tree.dart';

void main() {
  test('f01/us07/s1, f01/us07/fr01: refs on the story prints its groups and exits 0', () async {
    final (:runner, :out, :err) = readRunner(await writeReadProject());
    expect(await runner.run(['refs', 'login/email_login']), 0);
    expect(
      out.toString(),
      contains(
        'Inbound\n- link: login/email_login/validate_credentials (fr)\n',
      ),
    );
  });
  test('f01/us07/fr01/e08: no name is argument_missing, exit 64; a typed name no doc carries names the type', () async {
    final (:runner, :out, :err) = readRunner(await writeReadProject());
    expect(await runner.run(['refs']), 64);
    expect(err.toString(), 'refs needs a name, such as specstone refs login\n');
    final typed = readRunner(await writeReadProject());
    expect(
      await typed.runner.run(['refs', 'architecture:signup', '--json']),
      64,
    );
    expect((jsonDecode(typed.err.toString()) as Map)['error'], {
      'code': 'doc_not_found',
      'message': 'no architecture doc carries the name signup',
    });
  });
  test('f01/us07/s6, f01/us07/fr01/e09: outside a project, or under a 9.9.9 pin, exits 78', () async {
    expect(
      await readRunner(await writeTree({})).runner.run(['refs', 'login']),
      78,
    );
    final pinned = await writeReadProject(
      extra: {'.specstone/config.yaml': 'packs:\n  prd-core: 9.9.9\n'},
    );
    expect(await readRunner(pinned).runner.run(['refs', 'login']), 78);
  });
  test('f01/us07/fr02: refs --json gives the step reference kind, name, and docType', () async {
    final (:runner, :out, :err) = readRunner(
      await writeReadProject(
        extra: {
          'docs/prds/journeys/sign_in/JOURNEY.md':
              '# Sign in\n\n## Goal\nGet in.\n\n## Flow\n\n## Steps\n'
              '### 1. Enter\nstep: login/email_login S1\n',
        },
      ),
    );
    expect(await runner.run(['refs', 'journey:sign_in', '--json']), 0);
    final doc =
        ((jsonDecode(out.toString()) as Map)['docs']! as List).single as Map;
    expect(doc['outbound'], [
      {'kind': 'step', 'name': 'login/email_login', 'docType': 'user_story'},
    ]);
  });
}
