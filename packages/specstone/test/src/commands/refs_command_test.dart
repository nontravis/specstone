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
  test(
    'refs login --out saves the text reply and prints only its header',
    () async {
      final project = await writeReadProject();
      final plain = readRunner(project);
      expect(await plain.runner.run(['refs', 'login']), 0);

      final (:runner, :out, :err) = readRunner(project);
      expect(
        await runner.run([
          ...['refs', 'login'],
          '--out',
        ]),
        0,
        reason: err.toString(),
      );

      final file = File('${project.path}/.specstone/reports/refs.login.txt');
      expect(file.readAsStringSync(), plain.out.toString());
      expect(
        out.toString(),
        matches(RegExp(r'^==> refs: \d+ lines, \d+ tokens · .+ <==\n$')),
      );
      expect(out.toString(), contains(file.resolveSymbolicLinksSync()));
      expect(err.toString(), isEmpty);
    },
  );
  test('refs login --json --out saves the JSON reply and prints '
      'only {out, lines, tokens, warnings}', () async {
    final project = await writeReadProject();
    final plain = readRunner(project);
    expect(
      await plain.runner.run([
        ...['refs', 'login'],
        '--json',
      ]),
      0,
    );

    final (:runner, :out, :err) = readRunner(project);
    expect(
      await runner.run([
        ...['refs', 'login'],
        '--json',
        '--out',
      ]),
      0,
      reason: err.toString(),
    );

    final file = File('${project.path}/.specstone/reports/refs.login.json');
    expect(file.readAsStringSync(), plain.out.toString());
    final printed = jsonDecode(out.toString()) as Map<String, Object?>;
    expect(printed.keys.toList(), ['out', 'lines', 'tokens', 'warnings']);
    expect(printed['out'], file.resolveSymbolicLinksSync());
    expect(err.toString(), isEmpty);
  });
  test('no name under --json is the argument_missing error, exit 64', () async {
    final (:runner, :out, :err) = readRunner(await writeReadProject());

    expect(await runner.run(['refs', '--json']), 64);

    expect(out.toString(), isEmpty);
    expect(jsonDecode(err.toString()), {
      'error': {
        'code': 'argument_missing',
        'message': 'refs needs a name, such as specstone refs login',
      },
      'warnings': <Object>[],
    });
  });
  test('no project is project_not_found and a template fault keeps its '
      'code, exit 78, with no index read or written', () async {
    final bare = await writeTree({});
    final none = readRunner(bare);
    expect(await none.runner.run(['refs', 'login', '--json']), 78);
    expect((jsonDecode(none.err.toString()) as Map)['error'], {
      'code': 'project_not_found',
      'message': 'no Specstone project: no folder from the working directory upward holds .specstone/config.yaml',
    });
    expect(bare.listSync(), isEmpty);

    final pinned = await writeReadProject(
      extra: {'.specstone/config.yaml': 'packs:\n  prd-core: 9.9.9\n'},
    );
    final fault = readRunner(pinned);
    expect(await fault.runner.run(['refs', 'login', '--json']), 78);
    expect(
      (jsonDecode(fault.err.toString()) as Map)['error'],
      containsPair('code', 'pack_pin_newer'),
    );
    expect(fault.out.toString(), isEmpty);
    expect(
      Directory('${pinned.path}/.specstone')
          .listSync()
          .whereType<File>()
          .map((entity) => entity.uri.pathSegments.last),
      ['config.yaml'],
    );
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

    test('refs --target web is argument_invalid, exit 64', () async {
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
  test('two names are a usage error whose usage line takes a name or a path, '
      'exit 64', () async {
    final (:runner, :out, :err) = readRunner(await writeReadProject());
    expect(await runner.run(['refs', 'a', 'b']), 64);
    expect(out.toString(), isEmpty);
    expect(
      err.toString(),
      contains(
        'Expected one name, got 2.\n\n'
        'Usage: specstone refs <name | path> [--target <name>] [--json] '
        '[--out [<path>]]\n',
      ),
    );
  });
}
