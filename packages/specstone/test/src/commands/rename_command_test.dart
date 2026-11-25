import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../../../specstone_core/test/helpers/nested_fixture.dart'
    show cartRecord;
import '../../../../specstone_core/test/helpers/per_fr_row_fixture.dart';
import '../../../../specstone_core/test/helpers/record_fixture.dart';
import '../../../../specstone_core/test/helpers/write_fixture.dart';
import '../../helpers/write_runner.dart';

/// Returns every file and folder under the docs of [root] by its bytes.
Map<String, List<int>> _docsOf(Directory root) =>
    treeBytes(root)..removeWhere((path, _) => !path.startsWith('docs/'));

void main() {
  test('rename takes a bare name one doc carries', () async {
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

  test('a new title is no rename option and the title line stays', () async {
    final root = await writeWriteProject();
    final before = _docsOf(root);
    final (:runner, :out, :err) = writeRunner(root);
    expect(
      await runner.run([
        'rename',
        'user_story:login/reset_password',
        '--to',
        'recover_account',
        '--title',
        'Recover an account',
      ]),
      64,
    );
    expect(out.toString(), isEmpty);
    expect(_docsOf(root), before);

    final second = writeRunner(root);
    expect(
      await second.runner.run([
        'rename',
        'user_story:login/reset_password',
        '--to',
        'recover_account',
      ]),
      0,
    );
    expect(
      File(
        '${root.path}/docs/prds/features/f01_login/us03_recover_account/USER_STORY.md',
      ).readAsStringSync(),
      contains('\n# Reset password\n'),
    );
  });

  test('an unknown name, an ambiguous name, and an untyped path are each '
      'exit 64 and nothing moves', () async {
    final root = await writeWriteProject();
    final before = _docsOf(root);
    for (final (target, code) in [
      ('user_story:login/no_such_story', 'doc_not_found'),
      ('buyer', 'argument_invalid'),
      ('prds/d01_context.md', 'untyped_target'),
    ]) {
      final (:runner, :out, :err) = writeRunner(root);
      expect(
        await runner.run(['rename', target, '--to', 'other', '--json']),
        64,
        reason: target,
      );
      expect(out.toString(), isEmpty, reason: target);
      final error = (jsonDecode(err.toString()) as Map)['error'] as Map;
      expect(error['code'], code, reason: target);
    }
    expect(_docsOf(root), before);
  });

  test('rename with no target is argument_missing', () async {
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
        '[--dry-run [--out [<path>]]] [--target <name>] [--json]\n',
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
  test('rename lays out the docs it rewrites and adds no missing section to '
      'them', () async {
    final root = await writeWriteProject();
    List<String> headersOf(String docPath) => RegExp(
      r'^## .*$',
      multiLine: true,
    ).allMatches(readDoc(root, docPath)).map((match) => match[0]!).toList();
    final frBefore = headersOf(fr12);
    expect(frBefore, ['## Statement']);
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
    expect(out.toString(), contains('rewrote $fr12\n'));
    expect(headersOf(fr12), frBefore);
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
      'rename --target reads a per-target doc and names its feature',
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

    test('rename --target a project lacks exits 64', () async {
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

    test('prints a record the re-stamp alone changes under dry run', () async {
      // The record keeps no status the rename rewrites, so the re-stamp alone
      // changes it.
      final root = await writePerFrProject(keepsDropStatus: false);
      final before = readDoc(root, cartRecord);
      final (:runner, :out, :err) = writeRunner(root);
      expect(
        await runner.run([
          'rename',
          'user_story:shop/cart/drop_item',
          '--to',
          'remove_item',
          '--dry-run',
        ]),
        0,
      );
      expect(err.toString(), isEmpty);
      expect(out.toString(), contains('rewrites $cartRecord\n'));
      expect(readDoc(root, cartRecord), before);
    });

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

  group('--out', () {
    for (final json in [false, true]) {
      test('rename --dry-run${json ? ' --json' : ''} --out saves the dry run '
          'reply and changes no doc', () async {
        final root = await writeWriteProject();
        final before = _docsOf(root);
        final call = [
          'rename',
          'user_story:login/reset_password',
          '--to',
          'recover_account',
          '--dry-run',
          if (json) '--json',
        ];
        final (runner: plain, out: printed, err: _) = writeRunner(root);
        expect(await plain.run(call), 0);

        final (:runner, :out, :err) = writeRunner(root);
        expect(await runner.run([...call, '--out', 'dry.txt']), 0);

        expect(err.toString(), isEmpty);
        expect(
          File('${root.path}/dry.txt').readAsStringSync(),
          printed.toString(),
        );
        if (json) {
          expect(jsonDecode(out.toString()), containsPair('lines', isA<int>()));
        } else {
          expect(
            out.toString(),
            matches(RegExp(r'^==> rename: \d+ lines, \d+ tokens · ')),
          );
        }
        expect(_docsOf(root), before);
      });
    }

    test(
      'rename --dry-run --out with no path saves under the reports folder',
      () async {
        final root = await writeWriteProject();
        final (:runner, :out, :err) = writeRunner(root);

        expect(
          await runner.run([
            'rename',
            'user_story:login/reset_password',
            '--to',
            'recover_account',
            '--dry-run',
            '--out',
          ]),
          0,
        );

        expect(err.toString(), isEmpty);
        final reports = Directory('${root.path}/.specstone/reports');
        expect(reports.existsSync(), isTrue, reason: out.toString());
        expect(
          [for (final f in reports.listSync()) f.uri.pathSegments.last],
          ['rename-dry-run-to.user_story-login-reset_password.txt'],
        );
      },
    );

    test(
      'rename --out with no --dry-run is argument_invalid and changes no doc',
      () async {
        final root = await writeWriteProject();
        final before = _docsOf(root);
        final (:runner, :out, :err) = writeRunner(root);

        expect(
          await runner.run([
            'rename',
            'user_story:login/reset_password',
            '--to',
            'recover_account',
            '--out',
            'gone.txt',
          ]),
          64,
        );

        expect(out.toString(), isEmpty);
        expect(err.toString(), '--out goes with --dry-run\n');
        expect(File('${root.path}/gone.txt').existsSync(), isFalse);
        expect(_docsOf(root), before);
      },
    );
  });
}
