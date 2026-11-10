import 'dart:io';

import 'package:specstone_core/src/doc_model/doc_splice.dart';
import 'package:test/test.dart';

import '../../../../specstone_core/test/helpers/write_fixture.dart';
import '../../helpers/write_runner.dart';

/// What one command run printed and returned.
typedef _Run = ({int status, String out, String err});

/// Runs [args] from [workingDirectory] and returns what the run printed.
Future<_Run> _run(
  Directory workingDirectory,
  List<String> args, {
  FakeConsole? console,
}) async {
  final (:runner, :out, :err) = writeRunner(workingDirectory, console: console);
  final status = await runner.run(args);
  return (status: status, out: out.toString(), err: err.toString());
}

/// Returns the folder [path] names under [root]; [path] ends in `/`.
Directory _folder(Directory root, String path) =>
    Directory.fromUri(root.uri.resolve(path));

void main() {
  group('a read command takes the path check prints as its target', () {
    late Directory root;
    setUp(() async => root = await writeWriteProject());

    for (final (label, byName, byPath) in [
      (
        'get',
        ['get', 'feature:login', '--json'],
        ['get', loginFeature, '--json'],
      ),
      (
        'get #<key>',
        ['get', 'feature:login#problem'],
        ['get', 'docs/$loginFeature#problem'],
      ),
      ('check', ['check', 'feature:login'], ['check', loginFeature]),
      ('refs', ['refs', 'user_story:login/email_login'], ['refs', story1]),
      (
        'structure',
        ['structure', 'feature:login'],
        ['structure', loginFeature],
      ),
      (
        'list --under',
        ['list', 'user_story', '--under', 'feature:login'],
        ['list', 'user_story', '--under', 'docs/$loginFeature'],
      ),
      (
        'context',
        ['context', 'user_story:login/email_login', '--for', 'implement'],
        ['context', story1, '--for', 'implement'],
      ),
    ]) {
      test(
        'f01/us04/fr01/e09, f01/us04/fr01/e10: $label by DocPath prints what the name prints',
        () async {
          final named = await _run(root, byName);
          expect(await _run(root, byPath), named);
          expect(named.status, isNot(64));
        },
      );
    }

    test('f01/us04/fr01/e11: get takes a file path from a folder inside the docs root', () async {
      final named = await _run(root, ['get', 'feature:login']);
      final nested = _folder(root, 'docs/prds/features/f01_login/');
      expect(await _run(nested, ['get', 'FEATURE.md']), named);
      expect(
        await _run(_folder(root, 'docs/prds/'), [
          'get',
          'features/f01_login/FEATURE.md',
        ]),
        named,
      );
    });

    test('f01/us04/fr01/e11: a path outside the docs root is doc_not_found, exit 64', () async {
      expect(await _run(root, ['get', '.specstone/config.yaml']), (
        status: 64,
        out: '',
        err: 'no doc carries the name .specstone/config.yaml\n',
      ));
    });
  });

  group('a write command takes the path check prints as its target', () {
    test('f02/us01/s1, f01/us04/fr01/e09: set on a DocPath with #<key> writes as the name does', () async {
      final root = await writeWriteProject();
      expect(
        await _run(root, [
          'set',
          '$story1#use_case',
          '--base',
          '7e11fc4a24d2',
        ], console: FakeConsole(input: 'Sign in with a passkey.\n')),
        (
          status: 0,
          out:
              '==> login/email_login (user_story) · $story1#use_case · base ${baseHashOf('\nSign in with a passkey.\n')} <==\n',
          err: '',
        ),
      );
      expect(readDoc(root, story1), contains('Sign in with a passkey.'));
    });

    test('f02/us01/s1, f01/us04/fr01/e11: set on a file path from a folder inside the docs root writes as the name does', () async {
      final root = await writeWriteProject();
      expect(
        await _run(_folder(root, 'docs/prds/features/f01_login/'), [
          'set',
          'us01_email_login/USER_STORY.md#use_case',
          '--base',
          '7e11fc4a24d2',
        ], console: FakeConsole(input: 'Sign in with a passkey.\n')),
        (
          status: 0,
          out:
              '==> login/email_login (user_story) · $story1#use_case · base ${baseHashOf('\nSign in with a passkey.\n')} <==\n',
          err: '',
        ),
      );
    });

    test(
      'ms-r10, f01/us04/fr01/e09: approve --yes takes <DocPath>@<hash>',
      () async {
        final root = await writeWriteProject();
        final hash = (getDoc(root, 'feature:signup')['bases']! as Map)['doc'];
        expect(await _run(root, ['approve', '$signupFeature@$hash', '--yes']), (
          status: 0,
          out: 'approved feature:signup\n',
          err: '',
        ));
        expect(
          readDoc(root, signupFeature),
          matches(RegExp(r'\napproved: "[0-9a-f]{12}"\n')),
        );
      },
    );

    test(
      'f02/us04/s1, f01/us04/fr01/e10: delete takes docs/ and a DocPath',
      () async {
        final root = await writeWriteProject();
        expect(await _run(root, ['delete', 'docs/$fr32']), (
          status: 0,
          out: '$fr32\n',
          err: '',
        ));
        expect(hasDoc(root, fr32), isFalse);
      },
    );

    test('f02/us02/s1, f01/us04/fr01/e12: new --parent takes the parent doc by DocPath', () async {
      final root = await writeWriteProject();
      const newStory =
          'prds/features/f01_login/us04_recover_account/USER_STORY.md';
      expect(
        await _run(root, [
          'new',
          'user_story',
          '--parent',
          loginFeature,
          '--slug',
          'recover_account',
        ], console: FakeConsole(stdinIsTerminal: true)),
        (
          status: 0,
          out: '==> login/recover_account (user_story) · $newStory <==\n',
          err: '',
        ),
      );
    });

    test('f01/us04/fr01/e12: new --parent on the DocPath of a doc of another type is doc_not_found, exit 64', () async {
      final root = await writeWriteProject();
      expect(
        await _run(root, [
          'new',
          'user_story',
          '--parent',
          persona,
          '--slug',
          'recover_account',
        ], console: FakeConsole(stdinIsTerminal: true)),
        (
          status: 64,
          out: '',
          err: 'no feature doc carries the name $persona\n',
        ),
      );
    });

    test('f01/us04/fr01/e14, dw-s03/inv2: set takes a bare name one typed doc carries', () async {
      final root = await writeWriteProject();
      final run = await _run(root, [
        'set',
        'login/email_login#use_case',
        '--base',
        '7e11fc4a24d2',
      ], console: FakeConsole(input: 'Sign in with a passkey.\n'));
      expect(run.status, 0);
      expect(readDoc(root, story1), contains('Sign in with a passkey.'));
    });

    test('f01/us04/fr01/e06: set refuses a bare name no doc carries with doc_not_found', () async {
      final root = await writeWriteProject();
      final before = _docsText(root);
      final run = await _run(root, [
        'set',
        'nobody_here#use_case',
        '--base',
        '7e11fc4a24d2',
      ], console: FakeConsole(input: 'x\n'));
      expect(run.status, 64);
      expect(run.err, 'no doc carries the name nobody_here\n');
      expect(_docsText(root), before);
    });

    group('f01/us04/fr01: a #<section key> on a whole-doc target refuses, exit 64, nothing written', () {
      for (final (command, args) in [
        ('delete', ['delete', 'feature:login#problem']),
        ('rename', ['rename', 'feature:login#problem', '--to', 'signin']),
        ('reorder', ['reorder', 'feature:login#problem', '--to', '1']),
        (
          'move',
          [
            'move',
            'user_story:login/email_login#use_case',
            '--under',
            'feature:signup',
          ],
        ),
      ]) {
        test(command, () async {
          final root = await writeWriteProject();
          final before = _docsText(root);
          final run = await _run(
            root,
            args,
            console: FakeConsole(input: 'x\n'),
          );
          expect(run.status, 64);
          expect(run.out, isEmpty);
          expect(run.err, contains('takes no #<section key>'));
          expect(_docsText(root), before);
        });
      }
    });

    group('f01/us04/fr01/e15: a bare name 2 docs carry refuses, exit 64, nothing written', () {
      const listed = 'login names 2 docs: feature:login, architecture:login\n';
      for (final (command, args) in [
        ('set', ['set', 'login#problem', '--base', '7e11fc4a24d2']),
        ('delete', ['delete', 'login']),
        ('reorder', ['reorder', 'login', '--to', '1']),
        ('rename', ['rename', 'login', '--to', 'signin']),
        ('move', ['move', 'login', '--under', 'feature:signup']),
        ('approve --yes', ['approve', 'login@7e11fc4a24d2', '--yes']),
      ]) {
        test(command, () async {
          final root = await writeWriteProject();
          final before = _docsText(root);
          final run = await _run(
            root,
            args,
            console: FakeConsole(input: 'x\n'),
          );
          expect(run.status, 64);
          expect(run.out, isEmpty);
          expect(run.err, contains(listed));
          expect(_docsText(root), before);
        });
      }
    });
  });
}

/// Returns every `.md` file under the docs root, keyed by its path.
Map<String, String> _docsText(Directory root) => {
  for (final file in Directory(
    '${root.path}/docs',
  ).listSync(recursive: true).whereType<File>())
    file.path: file.readAsStringSync(),
};
