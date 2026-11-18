// The test titles and literals are plan values kept as written.

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../../../specstone_core/test/helpers/shipped_pins.dart';
import '../../helpers/read_fixture.dart';
import '../../helpers/temp_tree.dart';

void main() {
  test('no name is argument_missing, exit 64; a typed name no doc carries '
      'names the type', () async {
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

    test(
      'refs --target jaspr keeps the jaspr record of a shared name',
      () async {
        final (:runner, :out, :err) = readRunner(await twoTargets());

        expect(
          await runner.run([
            'refs',
            'implementation:login',
            '--target',
            'jaspr',
          ]),
          0,
        );

        expect(out.toString(), contains('- implements: lib/web_page.dart\n'));
        expect(out.toString(), isNot(contains('sign_in_page')));
      },
    );

    test('E22: refs --target web is argument_invalid, exit 64', () async {
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

  group('matrix rows', () {
    const item = 'email_login/validate_credentials';
    const row = '$item E02: `refuses a wrong password`';

    Future<Directory> projectWithRow() => writeReadProject(
      extra: {
        '.specstone/records/f01_login/IMPLEMENTATION.md':
            "---\nstatuses:\n  - '$item:implemented'\n---\n\n"
            '# Login implementation\n\n## Verification matrix\n\n'
            '- $row 5d1e0c4b7a92\n',
      },
    );

    test(
      'refs prints a row as a verifies line without its fingerprint',
      () async {
        final (:runner, :out, :err) = readRunner(await projectWithRow());

        expect(await runner.run(['refs', 'implementation:login']), 0);

        expect(
          out.toString(),
          contains('Outbound\n- verifies: $row\nInbound\n'),
        );
        expect(out.toString(), isNot(contains('5d1e0c4b7a92')));
      },
    );
  });

  for (final folder in ['measurements', 'plans']) {
    test('a mention in an untyped .md under $folder/ lists under untyped '
        'mentions, never under mentions', () async {
      final project = await writeReadProject(
        extra: {
          'docs/$folder/notes.md':
              '# Notes\n\nPlain login. Also `login/email_login`.\n',
        },
      );
      final (:runner, :out, :err) = readRunner(project);
      expect(await runner.run(['refs', 'login/email_login', '--json']), 0);
      final doc =
          ((jsonDecode(out.toString()) as Map)['docs']! as List).single as Map;
      expect(doc['mentions'], isEmpty);
      expect(doc['untypedMentions'], [
        {'path': '$folder/notes.md', 'line': 3},
      ]);
    });
  }
}
