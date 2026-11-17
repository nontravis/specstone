import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../../../specstone_core/test/helpers/check_fixture.dart'
    show fingerprintFor, writeCheckProject;
import '../../../../specstone_core/test/helpers/nested_fixture.dart'
    show writeNestedProject;
import '../../../../specstone_core/test/helpers/override_link_fixture.dart';
import '../../../../specstone_core/test/helpers/record_fixture.dart';
import '../../../../specstone_core/test/helpers/write_fixture.dart';
import '../../helpers/built_cli.dart';
import '../../helpers/write_runner.dart';

void main() {
  test('f01/us04/fr01/e14: rename takes a bare name one doc carries', () async {
    final (:runner, :out, :err) = writeRunner(await writeWriteProject());
    expect(
      await runner.run([
        'rename',
        'login/reset_password',
        '--to',
        'recover_account',
      ]),
      0,
    );
    expect(err.toString(), isEmpty);
    expect(
      out.toString(),
      startsWith(
        'moved prds/features/f01_login/us03_reset_password/ to prds/features/f01_login/us03_recover_account/\n',
      ),
    );
  });

  test('a taken slug --json is doc_exists with file', () async {
    final (:runner, :out, :err) = writeRunner(await writeWriteProject());
    expect(
      await runner.run([
        'rename',
        'user_story:login/reset_password',
        '--to',
        'sign_out',
        '--json',
      ]),
      64,
    );
    expect(out.toString(), isEmpty);
    final error = (jsonDecode(err.toString()) as Map)['error'] as Map;
    expect(error['code'], 'doc_exists');
    expect(error['file'], story2);
  });
  test('rename takes no --base', () async {
    final (:runner, :out, :err) = writeRunner(await writeWriteProject());
    expect(
      await runner.run([
        'rename',
        'user_story:login/reset_password',
        '--to',
        'x',
        '--base',
        'x',
      ]),
      64,
    );
  });
  test('no target is argument_missing', () async {
    final (:runner, :out, :err) = writeRunner(await writeWriteProject());
    expect(await runner.run(['rename', '--to', 'x']), 64);
    expect(err.toString(), startsWith('rename needs a target'));
  });
  test('two positionals are a usage error, exit 64', () async {
    final (:runner, :out, :err) = writeRunner(await writeWriteProject());
    expect(await runner.run(['rename', 'a', 'b']), 64);
    expect(out.toString(), isEmpty);
    expect(
      err.toString(),
      contains(
        'Expected one target, got 2.\n\n'
        'Usage: specstone rename <doc address> --to <slug> '
        '[--dry-run] [--target <name>] [--json]\n',
      ),
    );
  });
  test('rename with no --to is argument_missing, exit 64', () async {
    final (:runner, :out, :err) = writeRunner(await writeWriteProject());
    expect(await runner.run(['rename', 'user_story:login/reset_password']), 64);
    expect(out.toString(), isEmpty);
    expect(
      err.toString(),
      'rename needs a slug, such as specstone rename user_story:login/reset_password --to recover_account\n',
    );
  });
  test('after a feature rename the overriding doc stays approved and check '
      'reports nothing for it', () async {
    const shopRule = '- **INV-3** A cart holds stock.';
    final root = await writeCheckProject(
      extra: overrideFiles(
        extra: {
          'docs/prds/features/f02_shop/FEATURE.md': '# Shop\n',
          'docs/prds/features/f02_shop/f01_cart/FEATURE.md': '# Cart\n',
          'docs/specs/f02_shop/DOMAIN.md': domainDoc([shopRule]),
          'docs/specs/f02_shop/f01_cart/DOMAIN.md': domainDoc(
            [
              '- **INV-9** A cart is small.',
              '- Overrides: [INV-3](../DOMAIN.md#invariants) — stock, because stock',
            ],
            entries: ['domain:shop#INV-3 ${fingerprintFor(shopRule)}'],
          ),
        },
      ),
    );
    final (:runner, :out, :err) = writeRunner(root);
    expect(
      readDoc(root, 'specs/f02_shop/f01_cart/DOMAIN.md'),
      contains(RegExp('^approved: ', multiLine: true)),
    );
    // The fixture's own template findings stay; the rename adds no other.
    await runner.run(['check', 'domain:shop/cart']);
    final before = out.toString();
    out.clear();
    expect(await runner.run(['rename', 'feature:shop', '--to', 'store']), 0);
    out.clear();
    await runner.run(['check', 'domain:store/cart']);
    expect(out.toString(), before.replaceAll('f02_shop', 'f02_store'));
    expect(out.toString(), isNot(contains('suspect')));
    expect(out.toString(), isNot(contains('stale')));
    expect(err.toString(), isEmpty);
    expect(
      readDoc(root, 'specs/f02_store/f01_cart/DOMAIN.md'),
      allOf(
        contains('domain:store#INV-3'),
        contains(RegExp('^approved: ', multiLine: true)),
        isNot(contains('draft: true')),
      ),
    );
  });

  test('E07: rename writes a rewritten typed doc laid out', () async {
    final root = await writeWriteProject(
      extra: {
        'docs/$fr12': '---\ndraft: true\ntraced_from: US-01\nverify_method: test\n---\n\n# Lock after failures\n\n## Statement\n\n\n\nThe system shall lock the account. See [reset](../us03_reset_password/USER_STORY.md#use-case).\n\n\n',
      },
    );
    final (:runner, :out, :err) = writeRunner(root);
    expect(
      await runner.run([
        'rename',
        'user_story:login/reset_password',
        '--to',
        'recover_account',
      ]),
      0,
    );
    final text = readDoc(root, fr12);
    expect(text, contains('us03_recover_account/USER_STORY.md#use-case'));
    expect(text, isNot(contains('\n\n\n')));
    expect(text, contains('draft: true\n'));
  });

  test('rename sets each link text equal to the old Name '
      'to the new Name and keeps every other link text', () async {
    final root = await writeWriteProject(
      extra: {
        'docs/notes/links.md':
            '# Links\n\n'
            '[user_story:login/reset_password](../prds/features/f01_login/us03_reset_password/USER_STORY.md#use-case)\n'
            '[login/reset_password](../prds/features/f01_login/us03_reset_password/USER_STORY.md)\n'
            '[the reset rules](../prds/features/f01_login/us03_reset_password/USER_STORY.md)\n'
            '[INV-6](../prds/features/f01_login/us03_reset_password/USER_STORY.md#use-case)\n'
            '[login/reset_password](https://example.com/x)\n',
      },
    );
    final (:runner, :out, :err) = writeRunner(root);
    expect(
      await runner.run([
        'rename',
        'user_story:login/reset_password',
        '--to',
        'recover_account',
      ]),
      0,
    );
    const folder = '../prds/features/f01_login/us03_recover_account';
    expect(
      readDoc(root, 'notes/links.md'),
      '# Links\n\n'
      '[user_story:login/recover_account]($folder/USER_STORY.md#use-case)\n'
      '[login/recover_account]($folder/USER_STORY.md)\n'
      '[the reset rules]($folder/USER_STORY.md)\n'
      '[INV-6]($folder/USER_STORY.md#use-case)\n'
      '[login/reset_password](https://example.com/x)\n',
    );
    expect(out.toString(), contains('rewrote notes/links.md\n'));
  });

  group('with two code targets', () {
    const flutterRecord = 'specs/flutter/f01_login/IMPLEMENTATION.md';
    const jasprRecord = 'specs/jaspr/f01_login/IMPLEMENTATION.md';

    Future<Directory> twins() => writeWriteProject(
      extra: {
        '.specstone/config.yaml': twinConfig(),
        '.specstone/templates/implementation.yaml': recordLayer,
        '.specstone/templates/architecture.yaml':
            'id: architecture\nper_target: true\n',
        'docs/$flutterRecord': recordText(
          statuses: ['reset_password:implemented'],
        ),
        'docs/$jasprRecord': recordText(statuses: ['reset_password:planned']),
        'docs/specs/flutter/f01_login/ARCHITECTURE.md':
            '# Login architecture\n',
        'docs/specs/jaspr/f01_login/ARCHITECTURE.md': '# Login architecture\n',
      },
      without: {'docs/specs/f01_login/ARCHITECTURE.md'},
    );

    test(
      'E11: rename prints each record it rewrites, one per target',
      () async {
        final root = await twins();
        final (:runner, :out, :err) = writeRunner(root);
        expect(
          await runner.run([
            'rename',
            'user_story:login/reset_password',
            '--to',
            'recover',
          ]),
          0,
          reason: err.toString(),
        );
        expect(out.toString(), contains('rewrote $flutterRecord\n'));
        expect(out.toString(), contains('rewrote $jasprRecord\n'));
        expect(readDoc(root, flutterRecord), contains("'recover:implemented'"));
        expect(readDoc(root, jasprRecord), contains("'recover:planned'"));
      },
    );

    group('matrix rows', () {
      const story = 'reset_password';
      const frName = '$story/send_reset_link';
      const renamedFr = 'recover/send_reset_link';
      const tail = 'E02: `refuses a wrong password` 5d1e0c4b7a92';
      const skipTail = 'E03 skipped: needs root on CI  9a1c03be55d2';
      const note = 'A paragraph naming $frName E02.';

      String record(String status, {String lineEnd = '\n'}) =>
          '${recordText(statuses: ['$story:$status'])}\n'
                  '## Verification matrix\n\n'
                  '- $frName $tail\n'
                  '- $frName $skipTail\n'
                  '- $frName E04 `no colon`\n'
                  '$note\n'
              .replaceAll('\n', lineEnd);

      Future<Directory> matrixTwins({String lineEnd = '\n'}) =>
          writeWriteProject(
            extra: {
              '.specstone/config.yaml': twinConfig(),
              '.specstone/templates/implementation.yaml': recordLayer,
              '.specstone/templates/architecture.yaml':
                  'id: architecture\nper_target: true\n',
              'docs/$flutterRecord': record('implemented', lineEnd: lineEnd),
              'docs/$jasprRecord': record('planned'),
              'docs/specs/flutter/f01_login/ARCHITECTURE.md':
                  '# Login architecture\n',
              'docs/specs/jaspr/f01_login/ARCHITECTURE.md':
                  '# Login architecture\n',
            },
            without: {'docs/specs/f01_login/ARCHITECTURE.md'},
          );

      test('rename sets the item of each matrix row in each target '
          'record and keeps the rest of the row', () async {
        final root = await matrixTwins();
        final (:runner, :out, :err) = writeRunner(root);
        expect(
          await runner.run([
            'rename',
            'user_story:login/reset_password',
            '--to',
            'recover',
          ]),
          0,
          reason: err.toString(),
        );

        for (final path in [flutterRecord, jasprRecord]) {
          final text = readDoc(root, path);
          expect(text, contains('\n- $renamedFr $tail\n'), reason: path);
          expect(text, contains('\n- $renamedFr $skipTail\n'), reason: path);
          expect(text, contains('\n- $frName E04 `no colon`\n'), reason: path);
          expect(text, contains('\n$note\n'), reason: path);
        }
      });

      test(
        'a CRLF record keeps its line ends through the row rewrite',
        () async {
          final root = await matrixTwins(lineEnd: '\r\n');
          final (:runner, :out, :err) = writeRunner(root);
          expect(
            await runner.run([
              'rename',
              'user_story:login/reset_password',
              '--to',
              'recover',
            ]),
            0,
            reason: err.toString(),
          );

          final text = readDoc(root, flutterRecord);
          expect(text, contains('\r\n- $renamedFr $tail\r\n'));
          expect(text, contains('\r\n- $renamedFr $skipTail\r\n'));
          expect(text.replaceAll('\r\n', ''), isNot(contains('\n')));
        },
      );
    });

    test(
      'E06: rename --target reads a per-target doc and names its feature',
      () async {
        final (:runner, :out, :err) = writeRunner(await twins());
        expect(
          await runner.run([
            'rename',
            'architecture:login',
            '--to',
            'signin',
            '--target',
            'flutter',
          ]),
          64,
        );
        expect(out.toString(), isEmpty);
        expect(
          err.toString(),
          'architecture:login takes its name from its feature; '
          'rename feature:login instead\n',
        );
      },
    );

    test('E12: rename --target a project lacks exits 64', () async {
      final (:runner, :out, :err) = writeRunner(await twins());
      expect(
        await runner.run([
          'rename',
          'feature:login',
          '--to',
          'signin',
          '--target',
          'dart',
        ]),
        64,
      );
      expect(
        err.toString(),
        '--target dart: the code targets are flutter, jaspr\n',
      );
    });
  });

  group('--dry-run', () {
    test('lists a Name mention in a code file and keeps the file', () async {
      const code = '// Adds `user_story:login/reset_password#use_case`.\n';
      final root = await writeWriteProject(
        extra: {
          'docs/specs/TECH_STACK.md':
              '---\ncode:\n  - app/lib/\n---\n\n# Tech stack\n\n'
              '## Stack\n\n| Slot | Choice |\n|---|---|\n'
              '| Language | Dart |\n\n## Naming\n\n- snake_case file names\n',
          'app/lib/reset.dart': code,
        },
      );
      final (:runner, :out, :err) = writeRunner(root);
      expect(
        await runner.run([
          'rename',
          'user_story:login/reset_password',
          '--to',
          'recover_account',
          '--dry-run',
        ]),
        0,
      );
      expect(err.toString(), isEmpty);
      expect(
        out.toString(),
        endsWith(
          'mentions app/lib/reset.dart:1 '
          'user_story:login/reset_password#use_case\n'
          'dry run: nothing moved\n',
        ),
      );
      expect(File('${root.path}/app/lib/reset.dart').readAsStringSync(), code);
    });

    test(
      "a dry run of a rename prints the longer span's mentions line",
      () async {
        const note = 'docs/notes/ideas.md';
        const span = 'shop/cart/add_item E05';
        const text = '# Ideas\n\nA span `$span`.\n';
        final root = await writeNestedProject(extra: {note: text});
        final result = await Process.run(await buildSpecstone(), [
          'rename',
          'user_story:shop/cart/add_item',
          '--to',
          'add_one',
          '--dry-run',
        ], workingDirectory: root.path);
        expect(result.exitCode, 0, reason: '${result.stderr}');
        expect(
          result.stdout,
          endsWith('mentions $note:3 $span\ndry run: nothing moved\n'),
        );
        expect(File('${root.path}/$note').readAsStringSync(), text);
      },
    );

    test('--json prints moved, rewritten, mentions, and dryRun true', () async {
      final (:runner, :out, :err) = writeRunner(await writeWriteProject());
      expect(
        await runner.run([
          'rename',
          'user_story:login/reset_password',
          '--to',
          'recover_account',
          '--dry-run',
          '--json',
        ]),
        0,
      );
      final answer = jsonDecode(out.toString()) as Map;
      expect(answer.keys, containsAll(['moved', 'rewritten', 'mentions']));
      expect(answer['dryRun'], isTrue);
    });

    test('refuses a slug a sibling carries with the status and message the '
        'rename gives', () async {
      final (:runner, :out, :err) = writeRunner(await writeWriteProject());
      final apply = await runner.run([
        'rename',
        'user_story:login/reset_password',
        '--to',
        'sign_out',
      ]);
      final applyErr = err.toString();
      final (runner: dryRunner, out: dryOut, err: dryErr) = writeRunner(
        await writeWriteProject(),
      );
      expect(
        await dryRunner.run([
          'rename',
          'user_story:login/reset_password',
          '--to',
          'sign_out',
          '--dry-run',
        ]),
        apply,
      );
      expect(apply, 64);
      expect(dryOut.toString(), isEmpty);
      expect(dryErr.toString(), applyErr);
    });
  });
}
