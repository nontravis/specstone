import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../../../specstone_core/test/helpers/check_fixture.dart'
    show writeCheckProject;
import '../../../../specstone_core/test/helpers/record_fixture.dart';
import '../../../../specstone_core/test/helpers/write_fixture.dart';
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

  test('f02/us06/s1: rename prints moved and rewrote lines', () async {
    final (:runner, :out, :err) = writeRunner(await writeWriteProject());
    expect(
      await runner.run([
        'rename',
        'user_story:login/reset_password',
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
    expect(
      out.toString(),
      contains(
        'rewrote prds/features/f01_login/us01_email_login/fr02_lock_after_failures.md\n',
      ),
    );
  });
  test('f02/us06/s5: a taken slug --json is doc_exists with file', () async {
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
  test('f02/us06/fr01/e10: rename takes no --base', () async {
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
  test('f02/us06/fr01/e10: no target is argument_missing', () async {
    final (:runner, :out, :err) = writeRunner(await writeWriteProject());
    expect(await runner.run(['rename', '--to', 'x']), 64);
    expect(err.toString(), startsWith('rename needs a target'));
  });
  test(
    'f02/us06/fr01/e10: two positionals are a usage error, exit 64',
    () async {
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
    },
  );
  test(
    'f02/us06/fr01/e07: rename with no --to is argument_missing, exit 64',
    () async {
      final (:runner, :out, :err) = writeRunner(await writeWriteProject());
      expect(
        await runner.run(['rename', 'user_story:login/reset_password']),
        64,
      );
      expect(out.toString(), isEmpty);
      expect(
        err.toString(),
        'rename needs a slug, such as specstone rename user_story:login/reset_password --to recover_account\n',
      );
    },
  );
  test('f02/us06/fr03: rename --json lists the rewritten journey', () async {
    const journey = 'prds/journeys/sign_in/JOURNEY.md';
    final root = await writeCheckProject(
      extra: {
        'docs/$journey':
            '# Sign in\n\n## Goal\nGet in.\n\n## Flow\n\n## Steps\n'
            '### 1. Sign in\nstep: login/email_login S1\n',
      },
    );
    final (:runner, :out, :err) = writeRunner(root);
    expect(
      await runner.run([
        'rename',
        'user_story:login/email_login',
        '--to',
        'password_login',
        '--json',
      ]),
      0,
    );
    expect(err.toString(), isEmpty);
    final rewritten = (jsonDecode(out.toString()) as Map)['rewritten'] as List;
    expect(rewritten, contains(journey));
  });

  test('document_writing/rename_doc/rewrite_name_references E07: rename writes a rewritten typed doc laid out', () async {
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

  test('document_writing/rename_doc/rewrite_link_labels E15: rename rewrites an fr traced_from entry and confirmed label', () async {
    final root = await writeWriteProject(
      extra: {
        'docs/$fr11': '---\ntraced_from: [S1, login/reset_password#S3]\nverify_method: test\nconfirmed:\n  - login/reset_password#S3 0123456789ab\n---\n\n# Validate credentials\n\n## Statement\nThe system shall validate.\n',
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
    final text = readDoc(root, fr11);
    expect(text, contains('traced_from: [S1, login/recover_account#S3]\n'));
    expect(text, contains('  - login/recover_account#S3 0123456789ab\n'));
    expect(out.toString(), contains('rewrote $fr11\n'));
  });

  test('rename keeps a code file as it is and prints its mention after the '
      'rewrote lines', () async {
    const code =
        '/// Lays out `login/email_login`.\nfinal a = "login/email_login";\n';
    final root = await writeCheckProject(extra: {'app/lib/doc.dart': code});
    final (:runner, :out, :err) = writeRunner(root);
    expect(await runner.run(['rename', 'feature:login', '--to', 'signin']), 0);
    expect(err.toString(), isEmpty);
    expect(out.toString(), isNot(contains('rewrote app/lib/doc.dart')));
    expect(
      out.toString(),
      endsWith('mentions app/lib/doc.dart:1 login/email_login\n'),
    );
    expect(File('${root.path}/app/lib/doc.dart').readAsStringSync(), code);
  });

  test('rename --json lists the code file mention and not the file among '
      'rewritten', () async {
    final root = await writeCheckProject(
      extra: {'app/lib/doc.dart': '// `login/email_login`\n'},
    );
    final (:runner, :out, :err) = writeRunner(root);
    expect(
      await runner.run(['rename', 'feature:login', '--to', 'signin', '--json']),
      0,
    );
    final json = jsonDecode(out.toString()) as Map;
    expect(json['rewritten'], isNot(contains('app/lib/doc.dart')));
    expect(json['mentions'], [
      {'path': 'app/lib/doc.dart', 'line': 1, 'mention': 'login/email_login'},
    ]);
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

    test('document_writing/rename_doc/rewrite_name_references E11: rename prints each record it rewrites, one per target', () async {
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
    });

    test('document_writing/rename_doc/rename_doc_segment E06: rename --target reads a per-target doc and names its feature', () async {
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
    });

    test('document_writing/rename_doc/rename_doc_segment E12: rename --target a project lacks exits 64', () async {
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
    const f = 'prds/features/f01_login';

    test('prints the moves and rewrites, then says nothing moved, and moves '
        'nothing', () async {
      final root = await writeWriteProject();
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
        startsWith(
          'moves $f/us03_reset_password/ to $f/us03_recover_account/\n',
        ),
      );
      expect(out.toString(), endsWith('dry run: nothing moved\n'));
      expect(out.toString(), isNot(contains('rewrote')));
      expect(out.toString(), isNot(contains('plan ')));
      expect(docFile(root, story3).existsSync(), isTrue);
      expect(Directory('${root.path}/.specstone/trash').existsSync(), isFalse);
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
}
