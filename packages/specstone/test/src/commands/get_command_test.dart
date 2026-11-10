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
        '==> login (feature) · prds/features/f01_login/FEATURE.md · base ',
      ),
    );
  });
  group('index_query/read_doc_section/print_doc_or_section, several names', () {
    const storyPath = 'prds/features/f01_login/us01_email_login/USER_STORY.md';
    const featurePath = 'prds/features/f01_login/FEATURE.md';

    test('S10: three names print each doc or section once, in the order named, '
        'each with its base, exit 0', () async {
      final (:runner, :out, :err) = readRunner(await writeReadProject());
      expect(
        await runner.run([
          'get',
          'user_story:login/email_login',
          'prds/d01_context.md#project_name',
          'feature:login',
          'user_story:login/email_login#use_case',
        ]),
        0,
      );
      final names = [
        for (final line in out.toString().split('\n'))
          if (line.startsWith('==> ')) line.split(' · ')[1],
      ];
      expect(names, [
        storyPath,
        'prds/d01_context.md#project_name',
        featurePath,
      ]);
      expect(
        RegExp(
          r' · base [0-9a-f]{12} <==$',
          multiLine: true,
        ).allMatches(out.toString()),
        hasLength(3),
      );
      expect(err.toString(), isEmpty);
    });

    test('S10: --json holds the docs in argument order', () async {
      final (:runner, :out, :err) = readRunner(await writeReadProject());
      expect(
        await runner.run([
          'get',
          'prds/d01_context.md#project_name',
          'login',
          '--json',
        ]),
        0,
      );
      final docs = (jsonDecode(out.toString()) as Map)['docs']! as List;
      expect(
        [for (final doc in docs) (doc as Map)['path']],
        ['prds/d01_context.md', featurePath, 'specs/f01_login/ARCHITECTURE.md'],
      );
    });

    test(
      'S11: one name that finds nothing refuses the whole call, stdout empty, '
      'exit 64',
      () async {
        final (:runner, :out, :err) = readRunner(await writeReadProject());
        expect(await runner.run(['get', 'login', 'logn', 'nope']), 64);
        expect(out.toString(), isEmpty);
        expect(
          err.toString(),
          'no doc carries the name logn; no doc carries the name nope\n',
        );
        expect(await runner.run(['get', 'login', 'login#acceptance']), 64);
        expect(out.toString(), isEmpty);
        expect(
          err.toString(),
          endsWith(
            'no doc named login holds a section with the key acceptance\n',
          ),
        );
      },
    );

    test('E17: faults of two codes print one stderr line each, exit status '
        "the first fault's", () async {
      final (:runner, :out, :err) = readRunner(await writeReadProject());
      expect(await runner.run(['get', 'logn', 'login#acceptance', 'nope']), 64);
      expect(out.toString(), isEmpty);
      expect(
        err.toString(),
        'no doc carries the name logn; no doc carries the name nope\n'
        'no doc named login holds a section with the key acceptance\n',
      );
    });

    test('E17: an unknown doc type is one more fault, one stderr line per '
        "code, the first name's fault first", () async {
      final (:runner, :out, :err) = readRunner(await writeReadProject());
      expect(
        await runner.run(['get', 'nosuch1', 'login#zzz', 'nosuchtype:x']),
        64,
      );
      expect(out.toString(), isEmpty);
      expect(
        err.toString(),
        'no doc carries the name nosuch1\n'
        'no doc named login holds a section with the key zzz\n'
        'Could not find a doc type named "nosuchtype".\n',
      );
    });

    test("E17: --json with an unknown doc type prints the first name's "
        'fault', () async {
      for (final (names, code) in [
        (['nosuch1', 'login#zzz', 'nosuchtype:x'], 'doc_not_found'),
        (['nosuchtype:x', 'nosuch2'], 'doc_type_unknown'),
      ]) {
        final (:runner, :out, :err) = readRunner(await writeReadProject());
        expect(await runner.run(['get', ...names, '--json']), 64);
        expect(out.toString(), isEmpty);
        expect(
          ((jsonDecode(err.toString()) as Map)['error'] as Map)['code'],
          code,
          reason: '$names',
        );
      }
    });

    test('E15, E02: a name given twice is named once on stderr', () async {
      final (:runner, :out, :err) = readRunner(await writeReadProject());
      expect(await runner.run(['get', 'logn', 'logn']), 64);
      expect(err.toString(), 'no doc carries the name logn\n');
    });

    test("E17: --json prints the first fault's code and message", () async {
      final (:runner, :out, :err) = readRunner(await writeReadProject());
      expect(
        await runner.run(['get', 'login#acceptance', 'logn', '--json']),
        64,
      );
      expect(out.toString(), isEmpty);
      expect((jsonDecode(err.toString()) as Map)['error'], {
        'code': 'section_not_found',
        'message': 'no doc named login holds a section with the key acceptance',
      });
    });
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
  test('index_query/read_doc_section/resolve_doc_name E18: a target whose text before its first colon is no slug is doc_not_found, exit 64', () async {
    for (final target in ['Grid:login', 'check architecture:login']) {
      final (:runner, :out, :err) = readRunner(await writeReadProject());
      expect(await runner.run(['get', target, '--json']), 64, reason: target);
      expect((jsonDecode(err.toString()) as Map)['error'], {
        'code': 'doc_not_found',
        'message': 'no doc carries the name $target',
      }, reason: target);
    }
  });
  test('index_query/read_doc_section/resolve_doc_name E07: a misspelled slug prefix is doc_type_unknown, exit 64', () async {
    final (:runner, :out, :err) = readRunner(await writeReadProject());
    expect(await runner.run(['get', 'architectur:login', '--json']), 64);
    expect(
      ((jsonDecode(err.toString()) as Map)['error'] as Map)['code'],
      'doc_type_unknown',
    );
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
    expect(
      out.toString(),
      startsWith(
        '==> login/email_login (user_story) · prds/features/f01_login/us01_email_login/USER_STORY.md#acceptance_criteria · base 6d6a67fa9a00 <==\n',
      ),
    );
  });
  test('index_query/read_doc_section/print_doc_or_section E08: '
      'get --json prints the laid-out section bases', () async {
    final (:runner, :out, :err) = readRunner(await writeReadProject());
    expect(
      await runner.run(['get', 'user_story:login/email_login', '--json']),
      0,
    );
    final docs = (jsonDecode(out.toString()) as Map)['docs']! as List;
    final bases = (docs.single as Map)['bases']! as Map;
    expect((bases['sections']! as Map)['acceptance_criteria'], '6d6a67fa9a00');
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
    test('index_query/read_doc_section/resolve_doc_name E13 (W8): --paths reads a path holding # whole, so it is no section key and no argument_conflict', () async {
      final (:runner, :out, :err) = readRunner(
        await writeReadProject(
          extra: {'docs/prds/notes#draft.md': '# Draft\n'},
        ),
      );
      await runner.run(['get', 'prds/notes#draft.md', '--paths', '--json']);
      expect(err.toString(), isNot(contains('argument_conflict')));
      expect(err.toString(), isNot(contains('takes no #<section key>')));
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
    for (final option in ['--paths', '--code']) {
      test(
        'journeys/${option == '--paths' ? 'get_journey_test_paths/print_journey_paths' : 'read_code_per_step/list_code_per_step'} E09: '
        '$option with two names is argument_invalid, exit 64, nothing printed',
        () async {
          final (:runner, :out, :err) = readRunner(await project());
          expect(
            await runner.run([
              'get',
              'journey:sign_in',
              'login',
              option,
              '--json',
            ]),
            64,
          );
          expect(out.toString(), isEmpty);
          expect((jsonDecode(err.toString()) as Map)['error'], {
            'code': 'argument_invalid',
            'message': '$option takes one name, got 2',
          });
          err.clear();
          expect(
            await runner.run(['get', 'journey:sign_in', 'login', option]),
            64,
          );
          expect(out.toString(), isEmpty);
          expect(err.toString(), '$option takes one name, got 2\n');
        },
      );
    }
    test('journeys/read_code_per_step/list_code_per_step E10, '
        'journeys/get_journey_test_paths/print_journey_paths: '
        'the journey line holds no base', () async {
      for (final option in ['--paths', '--code']) {
        final (:runner, :out, :err) = readRunner(await project());
        expect(await runner.run(['get', 'journey:sign_in', option]), 0);
        expect(
          out.toString(),
          startsWith(
            '==> sign_in (journey) · prds/journeys/sign_in/JOURNEY.md <==\n',
          ),
          reason: option,
        );
      }
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
