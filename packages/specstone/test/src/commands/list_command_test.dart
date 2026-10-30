// The expected values are plan literals kept as written.
// ignore_for_file: lines_longer_than_80_chars, avoid_escaping_inner_quotes

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../../../specstone_core/test/helpers/check_fixture.dart';
import '../../helpers/read_fixture.dart';
import '../../helpers/temp_tree.dart';

final String edited = loginScenario2.replaceFirst(
  'wrong password',
  'wrong pass',
);

Map<String, String> _extraFr(String name, String confirmed) => {
  'docs/prds/features/f01_login/us01_email_login/$name.md':
      '---\nstatus: planned\ntraced_from:\n  - S1\nverify_method: test\n$confirmed---\n\n'
      '# Remember the device\n\n## Statement\nThe system shall remember a device.\n\n'
      '## Edge cases\n1. E01 — A new device → asked again.\n\n## Rationale\nFewer sign-ins.\n\n'
      '## Verification\nTest: a remembered device.\n',
};

Future<Directory> suspectProject() => writeCheckProject(
  extra: {
    ...doc(loginStory, loginScenario2, edited),
    ..._extraFr('fr02_remember_device', ''),
    ..._extraFr(
      'fr03_keep_session',
      'confirmed:\n  - S1 ${fingerprintFor(loginScenario1)}\n',
    ),
  },
);

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
  test('f04/us04/s8, f04/us04/fr04/e01, f04/us04/fr04/e02: list fr --suspect keeps the suspect FR only', () async {
    for (final args in [
      ['list', 'fr', '--suspect'],
      ['list', 'fr', '--suspect', '--under', 'login/email_login'],
    ]) {
      final (:runner, :out, :err) = readRunner(await suspectProject());
      expect(await runner.run(args), 0);
      expect(
        out.toString(),
        startsWith(
          'login/email_login/check_password (fr) — Check the password',
        ),
      );
      expect(
        out.toString().split('\n').where((l) => l.isNotEmpty),
        hasLength(1),
      );
    }
  });

  test('f04/us04/fr04: list journey --suspect keeps a journey with a suspect step', () async {
    final (:runner, :out, :err) = readRunner(
      await writeCheckProject(
        extra: {
          ...doc(
            loginStory,
            loginScenario1,
            loginScenario1.replaceFirst('home page', 'dashboard'),
          ),
          'docs/prds/journeys/sign_in/JOURNEY.md':
              '---\nconfirmed:\n  - login/email_login#S1 ${fingerprintFor(loginScenario1)}\n---\n\n'
              '# Sign in\n\n## Goal\nGet in.\n\n## Flow\n\n## Steps\n### 1. Open\nstep: login/email_login S1\n',
        },
      ),
    );
    expect(await runner.run(['list', 'journey', '--suspect']), 0);
    expect(out.toString(), startsWith('sign_in (journey)'));
    expect(out.toString().split('\n').where((l) => l.isNotEmpty), hasLength(1));
  });

  test('f04/us04/fr04/e03, f04/us04/fr04/e05: list api --suspect keeps an API doc with a suspect row; a type with no '
      'tracked link lists nothing', () async {
    final api = readRunner(
      await writeCheckProject(
        extra: fr(
          checkPasswordStatement,
          'The system shall refuse a wrong password within 2 s.',
        ),
      ),
    );
    expect(await api.runner.run(['list', 'api', '--suspect']), 0);
    expect(api.out.toString(), startsWith('login (api)'));
    final feature = readRunner(await suspectProject());
    expect(await feature.runner.run(['list', 'feature', '--suspect']), 0);
    expect(feature.out.toString(), isEmpty);
  });

  test('f04/us04/fr04/e04, f04/us04/fr02/e06: an unconfirmed link, a draft\'s included, does not count', () async {
    final (:runner, :out, :err) = readRunner(
      await writeCheckProject(
        extra: edit(loginFr, [
          ('status: implemented\n', 'status: implemented\ndraft: true\n'),
          ('  - S2 ${fingerprintFor(loginScenario2)}', '  - S2 000000000000'),
        ]),
      ),
    );
    expect(await runner.run(['list', 'fr', '--suspect']), 0);
    expect(out.toString(), isEmpty);
  });

  test('f04/us04/fr04/e06: --json gives F-01\'s docs object', () async {
    final (:runner, :out, :err) = readRunner(await suspectProject());
    expect(await runner.run(['list', 'fr', '--suspect', '--json']), 0);
    final docs = (jsonDecode(out.toString()) as Map)['docs']! as List;
    expect(
      docs.single,
      containsPair('name', 'login/email_login/check_password'),
    );
  });

  test(
    'f04/us04/fr04/e07: list\'s faults come before any link state',
    () async {
      final unknown = readRunner(await suspectProject());
      expect(await unknown.runner.run(['list', 'nope', '--suspect']), 64);
      final under = readRunner(await suspectProject());
      expect(
        await under.runner.run([
          'list',
          'fr',
          '--suspect',
          '--under',
          'login/emial_login',
        ]),
        64,
      );
      final outside = readRunner(await writeTree({}));
      expect(await outside.runner.run(['list', 'fr', '--suspect']), 78);
    },
  );
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
