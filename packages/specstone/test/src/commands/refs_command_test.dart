// The test titles and literals are plan values kept as written.

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../../../specstone_core/test/helpers/shipped_pins.dart';
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
  test('f01/us07/fr01/e22: refs prints a traced_from line on the FR and on the story it traces', () async {
    const base = 'docs/prds/features/f01_login';
    final (:runner, :out, :err) = readRunner(
      await writeReadProject(
        extra: {
          '$base/us02_reset_password/USER_STORY.md':
              '# Reset\n\n## Use Case\nReset.\n',
          '$base/us01_email_login/fr01_validate_credentials.md':
              '---\ntraced_from:\n  - S1\n  - login/reset_password#S2\n---\n\n'
              '# Validate credentials\n\n## Statement\n'
              'The system shall check.\n',
        },
      ),
    );
    expect(await runner.run(['refs', 'login/reset_password']), 0);
    expect(
      out.toString(),
      contains(
        'Inbound\n- traced_from: login/email_login/validate_credentials (fr)\n',
      ),
    );
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
  test('index_query/follow_references/list_doc_references S3: a doc that writes the name in a code span shows among the mentions, in text and in JSON', () async {
    final project = await writeReadProject(
      extra: {
        'docs/prds/personas/buyer/PERSONA.md':
            '# Buyer\n\n## Profile\nUses `feature:login` daily.\n',
        'docs/prds/d01_notes.md':
            '# Notes\n\nPlain feature login. Also `login/email_login`.\n',
      },
    );
    final (:runner, :out, :err) = readRunner(project);
    expect(await runner.run(['refs', 'feature:login']), 0);
    expect(
      out.toString(),
      contains('Mentions\n- prds/personas/buyer/PERSONA.md:4\n'),
    );
    final json = readRunner(project);
    expect(await json.runner.run(['refs', 'login/email_login', '--json']), 0);
    final doc =
        ((jsonDecode(json.out.toString()) as Map)['docs']! as List).single
            as Map;
    expect(doc['untypedMentions'], [
      {'path': 'prds/d01_notes.md', 'line': 3},
    ]);
  });
  group('two targets', () {
    Future<Directory> twoTargets() => writeReadProject(
      extra: {
        '.specstone/templates/implementation.yaml':
            'id: implementation\n'
            'description: One feature record per target.\n'
            'path: specs/f{nn}_{slug}/IMPLEMENTATION.md\n'
            'parent: feature\n'
            'per_target: true\n'
            'fields:\n'
            '  - id: statuses\n'
            '    type: record_status\n'
            '    list: true\n'
            '  - id: implements\n'
            '    type: output_ref\n'
            '    list: true\n'
            '    pointer: item_exact\n',
        '.specstone/config.yaml':
            '${shippedPinsConfig()}targets:\n'
            '  flutter:\n    code_root: flutter_lib\n'
            '  jaspr:\n    code_root: jaspr_lib\n',
        'flutter_lib/.keep': '',
        'jaspr_lib/.keep': '',
        'docs/specs/flutter/f01_login/IMPLEMENTATION.md':
            '---\nimplements:\n  - email_login:lib/sign_in_page.dart\n---\n\n'
            '# Record\n',
        'docs/specs/jaspr/f01_login/IMPLEMENTATION.md':
            '---\nimplements:\n  - email_login:lib/web_page.dart\n---\n\n'
            '# Record\n',
      },
    );

    test('f01/us07/s2, f01/us07/fr01/e03: refs on a record prints its code paths outbound', () async {
      final (:runner, :out, :err) = readRunner(await twoTargets());

      expect(
        await runner.run(['refs', 'specs/flutter/f01_login/IMPLEMENTATION.md']),
        0,
      );

      expect(
        out.toString(),
        contains('Outbound\n- implements: lib/sign_in_page.dart\nInbound\n'),
      );
    });

    test('f01/us07/fr01: refs --target jaspr keeps the jaspr record of a shared name', () async {
      final (:runner, :out, :err) = readRunner(await twoTargets());

      expect(
        await runner.run(['refs', 'implementation:login', '--target', 'jaspr']),
        0,
      );

      expect(out.toString(), contains('- implements: lib/web_page.dart\n'));
      expect(out.toString(), isNot(contains('sign_in_page')));
    });

    test('index_query/read_doc_section/resolve_doc_name E22: refs --target web is argument_invalid, exit 64', () async {
      final (:runner, :out, :err) = readRunner(await twoTargets());

      expect(
        await runner.run(['refs', 'implementation:login', '--target', 'web']),
        64,
      );

      expect(
        err.toString(),
        '--target web: the code targets are flutter, jaspr\n',
      );
    });
  });
  test('f01/us04/fr01/e09: two names are a usage error whose usage line takes a name or a path, exit 64', () async {
    final (:runner, :out, :err) = readRunner(await writeReadProject());
    expect(await runner.run(['refs', 'a', 'b']), 64);
    expect(out.toString(), isEmpty);
    expect(
      err.toString(),
      contains(
        'Expected one name, got 2.\n\n'
        'Usage: specstone refs <name | path> [--target <name>] [--json]\n',
      ),
    );
  });
}
