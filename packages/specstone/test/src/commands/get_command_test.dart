import 'dart:convert';
import 'dart:io';

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
  test('f01/us04/s8: get prints the section base on the naming line', () async {
    final (:runner, :out, :err) = readRunner(await writeReadProject());
    expect(
      await runner.run([
        'get',
        'user_story:login/email_login#acceptance_criteria',
      ]),
      0,
    );
    expect(out.toString(), contains('USER_STORY.md · base '));
  });

  group('journey options', () {
    const journeyDoc = 'docs/prds/journeys/sign_in/JOURNEY.md';
    const journeyText =
        '# Sign in\n\n## Goal\nReach home.\n\n## Flow\n\n## Steps\n'
        '### 1. Open the page\nstep: login/email_login S1\n';

    const storyDoc =
        'docs/prds/features/f01_login/us01_email_login/USER_STORY.md';
    const storyText =
        '# Agent signs in with email\n\n## Use Case\nSign in.\n\n'
        '## Acceptance Criteria\n\n### Scenario 1 — [happy] Sign in\n'
        '- **Given** an account\n- **Then** the Agent sees home\n';

    Future<Directory> project({String text = journeyText}) =>
        writeReadProject(extra: {journeyDoc: text, storyDoc: storyText});

    test(
      'f10/us02/fr01/e04: --paths with --code is argument_conflict, exit 64',
      () async {
        final (:runner, :out, :err) = readRunner(await project());
        expect(
          await runner.run(['get', 'sign_in', '--paths', '--code', '--json']),
          64,
        );
        expect((jsonDecode(err.toString()) as Map)['error'], {
          'code': 'argument_conflict',
          'message': '--code and --paths cannot be given together',
        });
      },
    );
    test('f10/us02/fr01/e04: --paths with a section key is argument_conflict, exit 64', () async {
      final (:runner, :out, :err) = readRunner(await project());
      expect(
        await runner.run(['get', 'journey:sign_in#steps', '--paths', '--json']),
        64,
      );
      expect((jsonDecode(err.toString()) as Map)['error'], {
        'code': 'argument_conflict',
        'message': '--paths takes no #<section key>',
      });
    });
    test('f10/us02/fr01: get journey:<slug> --paths prints on stdout, warnings on stderr, exit 0', () async {
      final (:runner, :out, :err) = readRunner(await project());
      expect(await runner.run(['get', 'journey:sign_in', '--paths']), 0);
      expect(
        out.toString(),
        startsWith(
          '==> sign_in (journey) · prds/journeys/sign_in/JOURNEY.md <==\n'
          'journey:sign_in path 1\n1. Open the page — login/email_login S1\n'
          '- **Given** an account\n- **Then** the Agent sees home\n',
        ),
      );
      expect(err.toString(), isEmpty);
    });
    test('f10/us02/fr01: a step naming no scenario warns on stderr and still exits 0', () async {
      final (:runner, :out, :err) = readRunner(
        await project(text: journeyText.replaceFirst('S1', 'S9')),
      );
      expect(await runner.run(['get', 'sign_in', '--paths']), 0);
      expect(err.toString(), '⚠️ WARNING: sign_in: step 1 names no scenario\n');
    });
    test('f10/us03/fr01: get journey:<slug> --code --json prints one object, exit 0', () async {
      final (:runner, :out, :err) = readRunner(await project());
      expect(
        await runner.run(['get', 'journey:sign_in', '--code', '--json']),
        0,
      );
      final printed = jsonDecode(out.toString()) as Map;
      expect(printed.keys, ['journeys', 'warnings']);
      expect(
        ((printed['journeys'] as List).single as Map)['steps'],
        hasLength(1),
      );
    });
  });
}
