import 'dart:convert';
import 'dart:io';

import 'package:specstone/src/command_runner.dart';
import 'package:specstone/src/console.dart';
import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_splice.dart' show baseHashOf;
import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:test/test.dart';

import '../../../../specstone_core/test/helpers/write_fixture.dart';
import '../../helpers/write_runner.dart';

void main() {
  const newStory = 'prds/features/f01_login/us04_recover_account/USER_STORY.md';
  test('f02/us02/s1: new prints the naming line, exit 0', () async {
    final root = await writeWriteProject();
    final (:runner, :out, :err) = writeRunner(
      root,
      console: FakeConsole(stdinIsTerminal: true),
    );
    expect(
      await runner.run([
        'new',
        'user_story',
        '--parent',
        'login',
        '--slug',
        'recover_account',
      ]),
      0,
    );
    expect(err.toString(), isEmpty);
    expect(
      out.toString(),
      '==> login/recover_account (user_story) · $newStory <==\n',
    );
    final text = File('${root.path}/docs/$newStory').readAsStringSync();
    expect(text, startsWith('---\ndraft: true\n---\n\n# recover_account\n'));
    expect(text, contains('## Use Case'));
  });
  test('f06/us01/s15: new refuses while a migration is unfinished', () async {
    final root = await writeWriteProject();
    writeJournal(root, [
      const MoveStep('docs/prds/personas/buyer', 'docs/prds/personas/shopper'),
      const CommitStep(
        message: 'move',
        paths: ['docs/prds/personas'],
        base: '0000000',
      ),
    ]);
    final (:runner, :out, :err) = writeRunner(
      root,
      console: FakeConsole(stdinIsTerminal: true),
    );

    expect(
      await runner.run([
        'new',
        'user_story',
        '--parent',
        'login',
        '--slug',
        'recover_account',
      ]),
      75,
    );
    expect(err.toString(), contains('run specstone migrate'));
    expect(out.toString(), isEmpty);
  });
  test('f02/us02/s2: piped stdin is the doc text', () async {
    final root = await writeWriteProject();
    final (:runner, :out, :err) = writeRunner(
      root,
      console: FakeConsole(
        input: '# Recover account\n\n## Use Case\nRecover an account.\n',
      ),
    );
    expect(
      await runner.run([
        'new',
        'user_story',
        '--parent',
        'login',
        '--slug',
        'recover_account',
      ]),
      0,
    );
    expect(err.toString(), isEmpty);
    expect(
      out.toString(),
      '==> login/recover_account (user_story) · $newStory <==\n',
    );
    final text = File('${root.path}/docs/$newStory').readAsStringSync();
    expect(text, contains('Recover an account.'));
    expect(text, contains('draft: true'));
    expect(text, isNot(contains('<Role>')));
  });
  test('f02/us02/s7: a parent no doc carries exits 64', () async {
    final root = await writeWriteProject();
    final (:runner, :out, :err) = writeRunner(
      root,
      console: FakeConsole(stdinIsTerminal: true),
    );
    expect(
      await runner.run([
        'new',
        'user_story',
        '--parent',
        'nobody',
        '--slug',
        'recover_account',
      ]),
      64,
    );
    expect(out.toString(), isEmpty);
    expect(err.toString(), 'no feature doc carries the name nobody\n');
  });
  test(
    'f02/us02/fr01/e10: no --parent --json carries the sidecar message',
    () async {
      final root = await writeWriteProject();
      final (:runner, :out, :err) = writeRunner(
        root,
        console: FakeConsole(stdinIsTerminal: true),
      );
      expect(
        await runner.run([
          'new',
          'user_story',
          '--slug',
          'reset_password',
          '--json',
        ]),
        64,
      );
      expect(out.toString(), isEmpty);
      expect(jsonDecode(err.toString()), {
        'error': {
          'code': 'argument_missing',
          'message': 'user_story needs --parent, the name of a feature',
        },
      });
    },
  );
  test('f02/us02/fr01/e10: no doc type is argument_missing', () async {
    final (:runner, :out, :err) = writeRunner(
      await writeWriteProject(),
      console: FakeConsole(stdinIsTerminal: true),
    );
    expect(await runner.run(['new']), 64);
    expect(err.toString(), startsWith('new needs a doc type'));
  });
  test('f02/us02/fr01: two positionals are a usage error, exit 64', () async {
    final (:runner, :out, :err) = writeRunner(await writeWriteProject());
    expect(await runner.run(['new', 'a', 'b']), 64);
    expect(out.toString(), isEmpty);
    expect(
      err.toString(),
      contains(
        'Expected one doc type, got 2.\n\n'
        'Usage: specstone new <doc type> [--parent <name>] '
        '[--slug <slug>] [--json]\n',
      ),
    );
  });
  test('f02/us02/fr02: non-UTF-8 stdin is argument_invalid, stdin is not UTF-8 text, exit 64', () async {
    final out = StringBuffer();
    final err = StringBuffer();
    final runner = SpecstoneCommandRunner(
      out: out,
      err: err,
      workingDirectory: await writeWriteProject(),
      homeDirectory: null,
      console: SystemConsole(input: Stream.value([0xff, 0xfe])),
    );
    expect(
      await runner.run([
        'new',
        'user_story',
        '--parent',
        'login',
        '--slug',
        'recover_account',
        '--json',
      ]),
      64,
    );
    expect(out.toString(), isEmpty);
    expect(jsonDecode(err.toString()), {
      'error': {
        'code': 'argument_invalid',
        'message': 'stdin is not UTF-8 text',
      },
    });
  });

  group('new journey', () {
    const journeyDoc = 'prds/journeys/sign_in/JOURNEY.md';

    test('f10/us01/fr05/e05: new journey with no --slug is argument_missing and creates nothing', () async {
      final root = await writeWriteProject();
      final (:runner, :out, :err) = writeRunner(
        root,
        console: FakeConsole(stdinIsTerminal: true),
      );

      expect(await runner.run(['new', 'journey', '--json']), 64);

      expect(out.toString(), isEmpty);
      expect(
        (jsonDecode(err.toString()) as Map)['error'],
        containsPair('code', 'argument_missing'),
      );
      expect(
        Directory('${root.path}/docs/prds/journeys').existsSync(),
        isFalse,
      );
    });

    test('f10/us01/fr05: new journey --parent x is argument_invalid: journey takes no --parent', () async {
      final root = await writeWriteProject();
      final (:runner, :out, :err) = writeRunner(
        root,
        console: FakeConsole(stdinIsTerminal: true),
      );

      expect(
        await runner.run([
          'new',
          'journey',
          '--slug',
          'sign_in',
          '--parent',
          'x',
          '--json',
        ]),
        64,
      );

      expect(
        (jsonDecode(err.toString()) as Map)['error'],
        containsPair('code', 'argument_invalid'),
      );
      expect(hasDoc(root, journeyDoc), isFalse);
    });

    test('f10/us01/fr05: new journey --json gives bases taken after the generators ran', () async {
      final root = await writeWriteProject();
      final (:runner, :out, :err) = writeRunner(
        root,
        console: FakeConsole(
          input:
              '# Sign in\n\n## Goal\nReach home.\n\n## Flow\n\n'
              '## Steps\n### 1. Open\nstep: login/email_login S1\n',
        ),
      );

      expect(
        await runner.run(['new', 'journey', '--slug', 'sign_in', '--json']),
        0,
      );

      final text = readDoc(root, journeyDoc);
      final flow = Doc.parse(text).sections
          .singleWhere((section) => section.headerText == 'Flow')
          .body;
      expect(flow, contains('flowchart TD'));
      final answer = jsonDecode(out.toString()) as Map<String, Object?>;
      final bases = answer['bases']! as Map<String, Object?>;
      expect((bases['sections']! as Map)['flow'], baseHashOf(flow));
    });
  });
}
