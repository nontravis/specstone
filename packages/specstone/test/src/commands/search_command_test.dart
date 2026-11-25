import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../../../specstone_core/test/helpers/nested_fixture.dart';
import '../../../../specstone_core/test/helpers/shipped_pins.dart';
import '../../helpers/read_fixture.dart';
import '../../helpers/temp_tree.dart';

void main() {
  test('unquoted words search as one query', () async {
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
  });
  test(
    'search credentials --out saves the text reply and prints only its header',
    () async {
      final project = await writeReadProject();
      final plain = readRunner(project);
      expect(await plain.runner.run(['search', 'credentials']), 0);

      final (:runner, :out, :err) = readRunner(project);
      expect(
        await runner.run([
          ...['search', 'credentials'],
          '--out',
        ]),
        0,
        reason: err.toString(),
      );

      final file = File(
        '${project.path}/.specstone/reports/search.credentials.txt',
      );
      expect(file.readAsStringSync(), plain.out.toString());
      expect(
        out.toString(),
        matches(RegExp(r'^==> search: \d+ lines, \d+ tokens · .+ <==\n$')),
      );
      expect(out.toString(), contains(file.resolveSymbolicLinksSync()));
      expect(err.toString(), isEmpty);
    },
  );
  test('search credentials --json --out saves the JSON reply and prints '
      'only {out, lines, tokens, warnings}', () async {
    final project = await writeReadProject();
    final plain = readRunner(project);
    expect(
      await plain.runner.run([
        ...['search', 'credentials'],
        '--json',
      ]),
      0,
    );

    final (:runner, :out, :err) = readRunner(project);
    expect(
      await runner.run([
        ...['search', 'credentials'],
        '--json',
        '--out',
      ]),
      0,
      reason: err.toString(),
    );

    final file = File(
      '${project.path}/.specstone/reports/search.credentials.json',
    );
    expect(file.readAsStringSync(), plain.out.toString());
    final printed = jsonDecode(out.toString()) as Map<String, Object?>;
    expect(printed.keys.toList(), ['out', 'lines', 'tokens', 'warnings']);
    expect(printed['out'], file.resolveSymbolicLinksSync());
    expect(err.toString(), isEmpty);
  });
  test('a bare --out after the query is no option error', () async {
    final project = await writeReadProject();
    final (:runner, :out, :err) = readRunner(project);

    expect(await runner.run(['search', 'check the email', '--out']), 0);

    expect(err.toString(), isEmpty);
    expect(
      File('${project.path}/.specstone/reports/search.check the email.txt')
          .existsSync(),
      isTrue,
    );
  });
  test('--json prints hits and warnings', () async {
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
  test('no query is argument_missing, exit 64', () async {
    final (:runner, :out, :err) = readRunner(await writeReadProject());
    expect(await runner.run(['search']), 64);
    expect(
      err.toString(),
      'search needs a query, such as specstone search "lock the account"\n',
    );
  });
  test('a short query fails before any index exists', () async {
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
  test('a missing query prints argument_missing in the --json error', () async {
    final (:runner, :out, :err) = readRunner(await writeReadProject());
    expect(await runner.run(['search', '--json']), 64);
    expect(
      ((jsonDecode(err.toString()) as Map)['error'] as Map)['code'],
      'argument_missing',
    );
    expect(out.toString(), isEmpty);
  });
  test('no project and a template fault name their codes and touch no '
      'index', () async {
    final bare = await writeTree({});
    final outside = readRunner(bare);
    expect(await outside.runner.run(['search', 'login', '--json']), 78);
    expect(
      ((jsonDecode(outside.err.toString()) as Map)['error'] as Map)['code'],
      'project_not_found',
    );
    expect(File('${bare.path}/.specstone/index.sqlite').existsSync(), isFalse);
    final pinned = await writeReadProject(
      extra: {'.specstone/config.yaml': 'packs:\n  prd-core: 9.9.9\n'},
    );
    final faulty = readRunner(pinned);
    expect(await faulty.runner.run(['search', 'login', '--json']), 78);
    expect(
      ((jsonDecode(faulty.err.toString()) as Map)['error'] as Map)['code'],
      'pack_pin_newer',
    );
    expect(
      File('${pinned.path}/.specstone/index.sqlite').existsSync(),
      isFalse,
    );
  });
  test('an unknown --type is doc_type_unknown, exit 64', () async {
    final (:runner, :out, :err) = readRunner(await writeReadProject());
    expect(
      await runner.run(['search', 'login', '--type', 'nosuchtype', '--json']),
      64,
    );
    expect(
      ((jsonDecode(err.toString()) as Map)['error'] as Map)['code'],
      'doc_type_unknown',
    );
  });
  test('an --under name no doc carries is doc_not_found, exit 64', () async {
    final (:runner, :out, :err) = readRunner(await writeReadProject());
    expect(
      await runner.run(['search', 'login', '--under', 'nosuchdoc', '--json']),
      64,
    );
    expect(
      ((jsonDecode(err.toString()) as Map)['error'] as Map)['code'],
      'doc_not_found',
    );
  });
  test('a --limit of -5 or ten is argument_invalid, exit 64', () async {
    for (final limit in ['-5', 'ten']) {
      final (:runner, :out, :err) = readRunner(await writeReadProject());
      expect(
        await runner.run(['search', 'login', '--limit', limit, '--json']),
        64,
        reason: '--limit $limit',
      );
      expect(
        ((jsonDecode(err.toString()) as Map)['error'] as Map)['code'],
        'argument_invalid',
        reason: '--limit $limit',
      );
    }
  });
  test('--limit 0 exits 64', () async {
    final (:runner, :out, :err) = readRunner(await writeReadProject());
    expect(await runner.run(['search', 'login', '--limit', '0']), 64);
    expect(err.toString(), '--limit takes a positive integer, not 0\n');
  });
  test('an invalid --limit wins over a short query', () async {
    final (:runner, :out, :err) = readRunner(await writeReadProject());
    expect(await runner.run(['search', 'ab', '--limit', '0', '--json']), 64);
    expect(
      ((jsonDecode(err.toString()) as Map)['error'] as Map)['code'],
      'argument_invalid',
    );
  });
  test('outside a project, or under a 9.9.9 pin, exits 78', () async {
    expect(
      await readRunner(await writeTree({})).runner.run(['search', 'login']),
      78,
    );
    final pinned = await writeReadProject(
      extra: {'.specstone/config.yaml': 'packs:\n  prd-core: 9.9.9\n'},
    );
    expect(await readRunner(pinned).runner.run(['search', 'login']), 78);
  });

  test('search --under --target keeps one target, '
      'an unknown name is refused', () async {
    final project = await writeTree({
      '.specstone/templates/architecture.yaml':
          'id: architecture\nper_target: true\n',
      '.specstone/templates/implementation.yaml':
          'id: implementation\n'
          'description: One feature record per target.\n'
          'path: specs/f{nn}_{slug}/IMPLEMENTATION.md\n'
          'parent: feature\n'
          'per_target: true\n'
          'fields:\n'
          '  - id: statuses\n'
          '    type: record_status\n'
          '    list: true\n',
      '.specstone/config.yaml':
          '${shippedPinsConfig()}targets:\n'
          '  flutter:\n    code_root: flutter_lib\n'
          '  jaspr:\n    code_root: jaspr_lib\n',
      'flutter_lib/.keep': '',
      'jaspr_lib/.keep': '',
      'docs/prds/features/f01_toast/FEATURE.md':
          '# Toast\n\n## Problem\nWarm toast.\n',
      'docs/specs/flutter/f01_toast/ARCHITECTURE.md':
          '# Toast architecture\n\n## Purpose\nWarm toast on flutter.\n',
      'docs/specs/jaspr/f01_toast/ARCHITECTURE.md':
          '# Toast architecture\n\n## Purpose\nWarm toast on jaspr.\n',
    });
    final scoped = readRunner(project);
    expect(
      await scoped.runner.run([
        'search',
        'Warm toast',
        '--under',
        'toast',
        '--target',
        'jaspr',
      ]),
      0,
    );
    expect(scoped.out.toString(), contains('Warm toast on jaspr.'));
    expect(
      scoped.out.toString(),
      isNot(contains('on flutter')),
      reason:
          'the flutter twin would print its own marker text; the twins '
          'share one name, so only their text tells them apart',
    );
    final unknown = readRunner(project);
    expect(
      await unknown.runner.run(['search', 'toast', '--target', 'web']),
      64,
    );
    expect(
      unknown.err.toString(),
      '--target web: the code targets are flutter, jaspr\n',
    );
  });
  group('search --under named by the end of its name', () {
    test(
      'search --under takes a unique suffix as it takes the full name',
      () async {
        final root = await writeNestedProject();
        final full = readRunner(root);
        expect(
          await full.runner.run(['search', 'shopper', '--under', 'shop/cart']),
          0,
        );
        final short = readRunner(root);
        expect(
          await short.runner.run(['search', 'shopper', '--under', 'cart']),
          0,
        );
        expect(short.out.toString(), full.out.toString());
        expect(short.out.toString(), contains('shop/cart/add_item'));
      },
    );
    test('search --under refuses a suffix of no identity, naming it', () async {
      final (:runner, :out, :err) = readRunner(await writeNestedProject());
      expect(await runner.run(['search', 'shopper', '--under', 'art']), 64);
      expect(err.toString(), 'no doc carries the name art\n');
    });
  });
}
