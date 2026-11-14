// The fixture texts are plan literals kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:convert';
import 'dart:io';

import 'package:specstone/src/command_runner.dart';
import 'package:specstone/src/console.dart';
import 'package:specstone_core/src/doc_model/doc_splice.dart';
import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:test/test.dart';

import '../../../../specstone_core/test/helpers/target_fixture.dart';
import '../../../../specstone_core/test/helpers/write_fixture.dart';
import '../../helpers/write_runner.dart';

void main() {
  test('set refuses while a migration is unfinished', () async {
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
      console: FakeConsole(input: 'x\n'),
    );
    expect(
      await runner.run([
        'set',
        'user_story:login/email_login#use_case',
        '--base',
        '7e11fc4a24d2',
      ]),
      75,
    );
    expect(
      err.toString(),
      '.specstone/trash/journal.json: a migration is unfinished; run '
      'specstone migrate at an interactive terminal, or with --yes after the '
      "Owner's ok in the chat, to finish it, then run the command again\n",
    );
    expect(out.toString(), isEmpty);
  });

  test('f08/us05/fr01/e02, f02/us01/fr03: set --field with empty stdin removes a held undeclared key, exit 0', () async {
    final root = await writeWriteProject(
      extra: {
        'docs/$story1':
            '---\nstatus: planned\ndraft: true\nsize: 1\nvision:\n  - PV-01\npersona:\n  - buyer\n---\n\n'
            '# Sign in with email\n\n## Use Case\nSign in with an email.\n\n'
            '## Acceptance Criteria\n\n### Scenario 1 — [happy] Sign in\n- **Given** a registered email\n',
      },
    );
    const target = 'user_story:login/email_login';
    final base =
        ((getDoc(root, target)['bases']! as Map)['fields']! as Map)['size']!
            as String;
    final (:runner, :out, :err) = writeRunner(
      root,
      console: FakeConsole(input: '\n'),
    );
    expect(
      await runner.run(['set', target, '--field', 'size', '--base', base]),
      0,
    );
    expect(err.toString(), isEmpty);
    expect(
      out.toString(),
      '==> login/email_login (user_story) · $story1 · field size · base e3b0c44298fc <==\n',
    );
    expect(
      readDoc(root, story1),
      startsWith('---\nstatus: planned\ndraft: true\nvision:\n'),
    );
  });

  test('f02/us01/s1: set prints the naming line with the new base, exit 0', () async {
    final passkeyBase = baseHashOf('\nSign in with a passkey.\n');
    final root = await writeWriteProject();
    final (:runner, :out, :err) = writeRunner(
      root,
      console: FakeConsole(input: 'Sign in with a passkey.\n'),
    );
    expect(
      await runner.run([
        'set',
        'user_story:login/email_login#use_case',
        '--base',
        '7e11fc4a24d2',
      ]),
      0,
    );
    expect(err.toString(), isEmpty);
    expect(
      out.toString(),
      '==> login/email_login (user_story) · $story1#use_case · base $passkeyBase <==\n',
    );
    final written = writeRunner(root);
    expect(
      await written.runner.run([
        'get',
        'user_story:login/email_login#use_case',
      ]),
      0,
    );
    expect(written.out.toString(), contains('base $passkeyBase'));
    expect(written.out.toString(), contains('Sign in with a passkey.'));
  });
  test('f02/us01/s8, f02/us01/fr02/e06: a stale base prints the fault on stderr and only the current section on stdout, exit 75', () async {
    final root = await writeWriteProject();
    final (:runner, :out, :err) = writeRunner(
      root,
      console: FakeConsole(input: 'x\n'),
    );
    expect(
      await runner.run([
        'set',
        'user_story:login/email_login#use_case',
        '--base',
        '000000000000',
      ]),
      75,
    );
    expect(
      err.toString(),
      '$story1: use_case: the section changed since base 000000000000\n',
    );
    expect(
      out.toString(),
      '==> login/email_login (user_story) · $story1#use_case · base 7e11fc4a24d2 <==\n'
      '## Use Case\n\nSign in with an email.\n',
    );
  });
  test(
    'f02/us01/fr02: --json keeps stdout empty and puts current in the envelope',
    () async {
      final root = await writeWriteProject();
      final (:runner, :out, :err) = writeRunner(
        root,
        console: FakeConsole(input: 'x\n'),
      );
      expect(
        await runner.run([
          'set',
          'user_story:login/email_login#use_case',
          '--base',
          '000000000000',
          '--json',
        ]),
        75,
      );
      expect(out.toString(), isEmpty);
      expect(((jsonDecode(err.toString()) as Map)['error'] as Map)['current'], {
        'text': '## Use Case\n\nSign in with an email.\n',
        'base': '7e11fc4a24d2',
      });
    },
  );
  test(
    'f02/us01/s9: --field draft --json is field_not_writable with file and key',
    () async {
      final root = await writeWriteProject();
      final (:runner, :out, :err) = writeRunner(
        root,
        console: FakeConsole(input: 'false\n'),
      );
      expect(
        await runner.run([
          'set',
          'user_story:login/email_login',
          '--field',
          'draft',
          '--base',
          '000000000000',
          '--json',
        ]),
        64,
      );
      expect(out.toString(), isEmpty);
      expect(jsonDecode(err.toString()), {
        'error': {
          'code': 'field_not_writable',
          'message': 'draft is written only by specstone approve',
          'file': story1,
          'key': 'draft',
        },
      });
    },
  );
  test('f02/us01/fr01/e12: no --base is argument_missing', () async {
    final (:runner, :out, :err) = writeRunner(
      await writeWriteProject(),
      console: FakeConsole(input: 'x\n'),
    );
    expect(
      await runner.run(['set', 'user_story:login/email_login#use_case']),
      64,
    );
    expect(out.toString(), isEmpty);
    expect(err.toString(), startsWith('set needs --base'));
  });
  test('f02/us01/s12: an untyped doc is untyped_target, exit 64', () async {
    final (:runner, :out, :err) = writeRunner(
      await writeWriteProject(),
      console: FakeConsole(input: 'x\n'),
    );
    expect(
      await runner.run([
        'set',
        'prds/d01_context.md#features',
        '--base',
        '000000000000',
      ]),
      64,
    );
    expect(out.toString(), isEmpty);
    expect(
      err.toString(),
      'prds/d01_context.md has no doc type; migrate it to one before a write\n',
    );
  });
  test(
    'f02/us01/fr01/e12: a missing target or --base fails before stdin is read',
    () async {
      for (final args in [
        ['set', '--base', '000000000000'],
        ['set', 'user_story:login/email_login#use_case'],
      ]) {
        final console = _RecordingConsole();
        final (:runner, :out, :err) = writeRunner(
          await writeWriteProject(),
          console: console,
        );
        expect(await runner.run(args), 64);
        expect(console.reads, 0, reason: args.join(' '));
        expect(err.toString(), startsWith('set needs '));
      }
    },
  );
  test('f02/us01/fr01/e12: no target is argument_missing', () async {
    final (:runner, :out, :err) = writeRunner(await writeWriteProject());
    expect(await runner.run(['set', '--base', '000000000000']), 64);
    expect(err.toString(), startsWith('set needs a target'));
  });
  test('f02/us01/fr01/e12: non-UTF-8 stdin is argument_invalid, exit 64, the doc untouched', () async {
    final root = await writeWriteProject();
    final out = StringBuffer();
    final err = StringBuffer();
    final runner = SpecstoneCommandRunner(
      out: out,
      err: err,
      workingDirectory: root,
      homeDirectory: testHome(),
      console: SystemConsole(input: Stream.value([0xff, 0xfe])),
    );
    expect(
      await runner.run([
        'set',
        'user_story:login/email_login#use_case',
        '--base',
        '7e11fc4a24d2',
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
    final read = writeRunner(root);
    await read.runner.run(['get', 'user_story:login/email_login#use_case']);
    expect(read.out.toString(), contains('base 7e11fc4a24d2'));
  });
  test(
    'f02/us01/fr03: set --help says --field reads stdin as a YAML value',
    () async {
      final (:runner, :out, :err) = writeRunner(await writeWriteProject());
      expect(await runner.run(['set', '--help']), 0);
      expect(
        out.toString(),
        contains(
          'The id of the field to write; stdin holds its YAML value, a list as `- item` lines.',
        ),
      );
      expect(err.toString(), isEmpty);
    },
  );
  test('set --help names every flag --batch conflicts with', () async {
    final (:runner, :out, :err) = writeRunner(await writeWriteProject());
    expect(await runner.run(['set', '--help']), 0);
    expect(
      out.toString().replaceAll(RegExp(r'\s+'), ' '),
      contains(
        'Takes no doc address, --base, --field, --title, or --target; reads no stdin.',
      ),
    );
  });
  test('f02/us01/fr03/e07: set --field with plain lines for a list field says the stdin is a YAML list, exit 64', () async {
    final root = await writeWriteProject();
    const target = 'user_story:login/email_login';
    final base =
        ((getDoc(root, target)['bases']! as Map)['fields']! as Map)['vision']!
            as String;
    final (:runner, :out, :err) = writeRunner(
      root,
      console: FakeConsole(input: 'PV-01\nPV-02\n'),
    );
    expect(
      await runner.run([
        'set',
        target,
        '--field',
        'vision',
        '--base',
        base,
        '--json',
      ]),
      64,
    );
    expect(out.toString(), isEmpty);
    expect(jsonDecode(err.toString()), {
      'error': {
        'code': 'field_value_invalid',
        'message': 'vision takes a YAML list, one `- item` line each',
        'file': story1,
        'key': 'vision',
      },
    });
  });
  test('f02/us01/fr01: two positionals are a usage error, exit 64', () async {
    final (:runner, :out, :err) = writeRunner(await writeWriteProject());
    expect(await runner.run(['set', 'a', 'b']), 64);
    expect(out.toString(), isEmpty);
    expect(
      err.toString(),
      contains(
        'Expected one target, got 2.\n\n'
        'Usage: specstone set <doc address>(#<section key> | '
        '--field <field id> | --title) --base <hash> [--target <name>] '
        '[--json]\n',
      ),
    );
  });

  test('f02/us01/fr06: set #_lead writes the lead end to end and prints the new base', () async {
    final root = await writeWriteProject(
      extra: {
        'docs/$story1': writeProject['docs/$story1']!.replaceFirst(
          '# Sign in with email\n',
          '# Sign in with email\n\nOld lead.\n',
        ),
      },
    );
    const target = 'user_story:login/email_login#_lead';
    final base = getDoc(root, target)['base']! as String;
    expect(base, baseHashOf('\nOld lead.\n'));
    final (:runner, :out, :err) = writeRunner(
      root,
      console: FakeConsole(input: 'New lead.\n'),
    );
    expect(await runner.run(['set', target, '--base', base]), 0);
    expect(err.toString(), isEmpty);
    expect(
      out.toString(),
      '==> login/email_login (user_story) · $story1#_lead · base ${baseHashOf('\nNew lead.\n')} <==\n',
    );
    expect(
      readDoc(root, story1),
      contains('# Sign in with email\n\nNew lead.\n\n## Use Case\n'),
    );
    expect(readDoc(root, story1), contains('draft: true'));
  });

  group('with two code targets', () {
    const story = 'user_story:login/email_login';
    const storyPath = 'prds/features/f01_login/us01_email_login/USER_STORY.md';

    String fieldBaseAt(Directory root, String address, String id) =>
        ((getDoc(root, address)['bases']! as Map)['fields']! as Map)[id]!
            as String;

    test('f02/us01/s3: --target keeps a shared story reachable, and the field is written', () async {
      final root = await writeTwinProject();
      final (:runner, :out, :err) = writeRunner(
        root,
        console: FakeConsole(input: '- PV-01\n'),
      );
      expect(
        await runner.run([
          'set',
          story,
          '--field',
          'vision',
          '--base',
          fieldBaseAt(root, story, 'vision'),
          '--target',
          'jaspr',
        ]),
        0,
        reason: err.toString(),
      );
      expect(readDoc(root, storyPath), contains('vision:\n  - PV-01\n'));
      expect(readDoc(root, storyPath), contains('draft: true'));
    });

    test('f02/us01/s4: set --field covers --target jaspr fixes the jaspr twin only, and it keeps its approval', () async {
      final root = await writeTwinProject();
      final flutterBefore = readDoc(root, flutterArchitecture);
      final (:runner, :out, :err) = writeRunner(
        root,
        console: FakeConsole(input: '- app/lib/login/\n'),
      );
      expect(
        await runner.run([
          'set',
          'architecture:login',
          '--target',
          'jaspr',
          '--field',
          'covers',
          '--base',
          fieldBaseAt(root, jasprArchitecture, 'covers'),
          '--json',
        ]),
        0,
        reason: err.toString(),
      );
      final json = jsonDecode(out.toString()) as Map<String, Object?>;
      expect(json['path'], jasprArchitecture);
      expect(json['draft'], isFalse);
      expect(
        readDoc(root, jasprArchitecture),
        contains('covers:\n  - app/lib/login/\n'),
      );
      expect(readDoc(root, flutterArchitecture), flutterBefore);
    });

    test('f02/us01/s4: a name that two targets share, with no --target, exits 64 listing both docs and writes nothing', () async {
      final root = await writeTwinProject();
      final before = readDoc(root, jasprArchitecture);
      final (:runner, :out, :err) = writeRunner(
        root,
        console: FakeConsole(input: '- app/lib/login/\n'),
      );
      expect(
        await runner.run([
          'set',
          'architecture:login',
          '--field',
          'covers',
          '--base',
          fieldBaseAt(root, jasprArchitecture, 'covers'),
        ]),
        64,
      );
      expect(
        err.toString(),
        'architecture:login names 2 docs: '
        '$flutterArchitecture, $jasprArchitecture\n',
      );
      expect(readDoc(root, jasprArchitecture), before);
    });

    test('f02/us01/fr01: --target with no value, or a name the project lacks, exits 64 naming the targets', () async {
      final root = await writeTwinProject();
      for (final (target, message) in [
        (
          <String>['--target'],
          '--target needs a code target name: the code targets are flutter, jaspr\n',
        ),
        (
          <String>['--target', 'dart'],
          '--target dart: the code targets are flutter, jaspr\n',
        ),
      ]) {
        final (:runner, :out, :err) = writeRunner(
          root,
          console: FakeConsole(input: 'x\n'),
        );
        expect(
          await runner.run([
            'set',
            'architecture:login#components',
            '--base',
            emptyBaseHash,
            ...target,
          ]),
          64,
        );
        expect(err.toString(), message);
      }
    });

    test('f02/us01/fr07: --batch writes a block that names the jaspr twin by its path, and the flutter twin stays', () async {
      final root = await writeTwinProject();
      final flutterBefore = readDoc(root, flutterArchitecture);
      final read = writeRunner(root);
      expect(
        await read.runner.run(['get', '$jasprArchitecture#components']),
        0,
      );
      final file = File('${root.path}/batch.md')
        ..writeAsStringSync(
          read.out.toString().replaceFirst(
            '| Sign-in page |',
            '| Jaspr sign-in page |',
          ),
        );
      final (:runner, :out, :err) = writeRunner(root);
      expect(
        await runner.run(['set', '--batch', file.path]),
        0,
        reason: err.toString(),
      );
      expect(
        readDoc(root, jasprArchitecture),
        contains('| Jaspr sign-in page | Takes the form |\n'),
      );
      expect(readDoc(root, flutterArchitecture), flutterBefore);
    });
    test('f02/us01/fr07: --batch with --target exits 64 as argument_conflict and writes nothing', () async {
      final root = await writeTwinProject();
      final before = readDoc(root, jasprArchitecture);
      final file = File('${root.path}/batch.md')..writeAsStringSync('x\n');
      final (:runner, :out, :err) = writeRunner(root);
      expect(
        await runner.run(['set', '--batch', file.path, '--target', 'jaspr']),
        64,
      );
      expect(
        err.toString(),
        '--batch takes no doc address, --base, --field, --title, or --target\n',
      );
      expect(readDoc(root, jasprArchitecture), before);
    });
  });
}

/// A [Console] that counts how often stdin is read.
final class _RecordingConsole implements Console {
  int reads = 0;

  @override
  bool get stdinIsTerminal => false;

  @override
  bool get stdoutIsTerminal => false;

  @override
  bool get noColor => false;

  @override
  Future<String> readAll() async {
    reads++;
    return '';
  }

  @override
  String? readLine() => null;
}
