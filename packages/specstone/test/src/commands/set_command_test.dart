// The fixture texts are plan literals kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:convert';
import 'dart:io';

import 'package:specstone/src/command_runner.dart';
import 'package:specstone/src/console.dart';
import 'package:specstone_core/src/consistency_check/code_fingerprint.dart';
import 'package:specstone_core/src/doc_model/doc_splice.dart';
import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:test/test.dart';

import '../../../../specstone_core/test/helpers/check_fixture.dart'
    as check
    show checkProjectFiles, doc, loginArchitecture, writeCheckProject;
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

  test('set --field with empty stdin removes a held undeclared key, exit 0', () async {
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

  test('set prints the naming line with the new base, exit 0', () async {
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
  test('a stale base prints the fault on stderr and only the current section on stdout, exit 75', () async {
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
  test('--json keeps stdout empty and puts current in the envelope', () async {
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
  });
  test(
    '--field draft --json is field_not_writable with file and key',
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
  test('no --base is argument_missing', () async {
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
  test('an untyped doc is untyped_target, exit 64', () async {
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
  test('a missing target or --base fails before stdin is read', () async {
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
  });
  test('no target is argument_missing', () async {
    final (:runner, :out, :err) = writeRunner(await writeWriteProject());
    expect(await runner.run(['set', '--base', '000000000000']), 64);
    expect(err.toString(), startsWith('set needs a target'));
  });
  test(
    'non-UTF-8 stdin is argument_invalid, exit 64, the doc untouched',
    () async {
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
    },
  );
  test('set --help says --field reads stdin as a YAML value', () async {
    final (:runner, :out, :err) = writeRunner(await writeWriteProject());
    expect(await runner.run(['set', '--help']), 0);
    expect(
      out.toString(),
      contains(
        'The id of the field to write; stdin holds its YAML value, a list as `- item` lines.',
      ),
    );
    expect(err.toString(), isEmpty);
  });
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
  test('set --field with plain lines for a list field says the stdin is a YAML list, exit 64', () async {
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
  test('two positionals are a usage error, exit 64', () async {
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

  group('with two code targets', () {
    const story = 'user_story:login/email_login';
    const storyPath = 'prds/features/f01_login/us01_email_login/USER_STORY.md';

    String fieldBaseAt(Directory root, String address, String id) =>
        ((getDoc(root, address)['bases']! as Map)['fields']! as Map)[id]!
            as String;

    test(
      '--target keeps a shared story reachable, and the field is written',
      () async {
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
      },
    );

    test('set --field covers --target jaspr fixes the jaspr twin only, and it keeps its approval', () async {
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

    test('--target with no value, or a name the project lacks, exits 64 naming the targets', () async {
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

    test('--batch writes a block that names the jaspr twin by its path, and the flutter twin stays', () async {
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
    test('--batch with --target exits 64 as argument_conflict and writes nothing', () async {
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

  group('--remove-task', () {
    const conflict =
        '--remove-task takes no doc address, --base, --field, --title, or --batch\n';

    Future<Directory> project() => writeWriteProject(
      extra: {
        'docs/$loginArch': withKeyBlock(
          writeProject['docs/$loginArch']!,
          'tasks',
          'tasks:\n  - INV-4:ENG-42\n  - ENG-42\n  - INV-7:ENG-50\n',
        ),
      },
    );

    test('removes the refs of the task, prints one line per doc and one per task with no ref, exit 0, stdin ignored', () async {
      final root = await project();
      final console = _RecordingConsole();
      final (:runner, :out, :err) = writeRunner(root, console: console);

      expect(
        await runner.run([
          'set',
          '--remove-task',
          'ENG-42',
          '--remove-task',
          'ENG-43',
        ]),
        0,
        reason: err.toString(),
      );

      expect(readDoc(root, loginArch), contains('tasks:\n  - INV-7:ENG-50\n'));
      expect(readDoc(root, loginArch), isNot(contains('ENG-42')));
      expect(
        out.toString(),
        matches(
          RegExp(
            r'^==> login \(architecture\) · specs/f01_login/ARCHITECTURE\.md · base [0-9a-f]{12} · removed INV-4:ENG-42, ENG-42 <==\nENG-43 · no refs\n$',
          ),
        ),
      );
      expect(err.toString(), isEmpty);
      expect(console.reads, 0);
    });

    test('--json prints docs, noRefs, and warnings', () async {
      final root = await project();
      final (:runner, :out, :err) = writeRunner(root);

      expect(
        await runner.run([
          'set',
          '--remove-task',
          'ENG-42',
          '--remove-task',
          'ENG-43',
          '--json',
        ]),
        0,
        reason: err.toString(),
      );

      final json = jsonDecode(out.toString()) as Map<String, Object?>;
      expect(json.keys, ['docs', 'noRefs', 'warnings']);
      expect(json['noRefs'], ['ENG-43']);
      expect(json['docs'], [
        containsPair('removed', ['INV-4:ENG-42', 'ENG-42']),
      ]);
    });

    test('a doc address, --base, --field, --title, or --batch beside it exits 64 as argument_conflict before its value is read, writes nothing, and reads no stdin', () async {
      final root = await project();
      final before = readDoc(root, loginArch);
      for (final beside in [
        ['architecture:login'],
        ['--base', 'e3b0c44298fc'],
        ['--field', 'tasks'],
        ['--title'],
        ['--batch', '${root.path}/batch.md'],
      ]) {
        final console = _RecordingConsole();
        final (:runner, :out, :err) = writeRunner(root, console: console);

        // The value is bad too: the conflict is refused first.
        expect(
          await runner.run(['set', '--remove-task', 'a:b', ...beside]),
          64,
          reason: '$beside',
        );

        expect(err.toString(), conflict, reason: '$beside');
        expect(out.toString(), isEmpty, reason: '$beside');
        expect(console.reads, 0, reason: '$beside');
      }
      expect(readDoc(root, loginArch), before);
    });

    test('--target keeps the removal to one code target', () async {
      final root = await writeTwinProject();
      for (final docPath in [flutterArchitecture, jasprArchitecture]) {
        docFile(root, docPath).writeAsStringSync(
          withKeyBlock(readDoc(root, docPath), 'tasks', 'tasks:\n  - ENG-42\n'),
        );
      }
      final (:runner, :out, :err) = writeRunner(root);

      expect(
        await runner.run([
          'set',
          '--remove-task',
          'ENG-42',
          '--target',
          'jaspr',
        ]),
        0,
        reason: err.toString(),
      );

      expect(readDoc(root, jasprArchitecture), isNot(contains('ENG-42')));
      expect(readDoc(root, flutterArchitecture), contains('ENG-42'));
    });

    test('the help and the invocation show the form', () async {
      final (:runner, :out, :err) = writeRunner(await writeWriteProject());

      expect(await runner.run(['set', '--help']), 0);

      final text = out.toString().replaceAll(RegExp(r'\s+'), ' ');
      expect(text, contains('specstone set --remove-task <task id>'));
      expect(text, contains('--remove-task'));
      expect(text, contains('Removes every entry of the task'));
    });
  });

  group('--stamp', () {
    const address = 'architecture:login';
    const covered = 'app/lib/login.dart';

    final fingerprint = fileCodeFingerprint(
      utf8.encode(check.checkProjectFiles()[covered]!),
      path: covered,
    );

    Future<Directory> project() => check.writeCheckProject(
      extra: check.doc(
        check.loginArchitecture,
        '  - app/lib/\n',
        '  - $covered\n',
      ),
      unfingerprinted: {'docs/${check.loginArchitecture}'},
    );

    String archText(Directory root) =>
        File('${root.path}/docs/${check.loginArchitecture}').readAsStringSync();

    test(
      'set --stamp prints the stamped count and leaves the doc approved',
      () async {
        final root = await project();
        final before = archText(root);
        final (:runner, :out, :err) = writeRunner(root);

        expect(
          await runner.run([
            'set',
            address,
            '--stamp',
            '$covered=$fingerprint',
          ]),
          0,
          reason: err.toString(),
        );

        expect(out.toString(), '$address: 1 stamped\n');
        expect(err.toString(), isEmpty);
        expect(
          archText(root),
          before.replaceFirst('  - $covered\n', '  - $covered $fingerprint\n'),
        );
        expect(archText(root), isNot(contains('draft: true')));
      },
    );

    test('set --stamp beside --base, --field, --title, --batch, --remove-task, --replace, or a section key is argument_conflict, reads no stdin', () async {
      final root = await project();
      final before = archText(root);
      for (final (:input, :beside) in [
        (input: '--base', beside: ['--base', 'e3b0c44298fc']),
        (input: '--field', beside: ['--field', 'covers']),
        (input: '--title', beside: ['--title']),
        (input: '--batch', beside: ['--batch', '${root.path}/batch.md']),
        (input: '--remove-task', beside: ['--remove-task', 'ENG-42']),
        (input: '--replace', beside: ['--replace']),
        (input: 'a section key', beside: <String>[]),
      ]) {
        final console = _RecordingConsole();
        final (:runner, :out, :err) = writeRunner(root, console: console);
        final target = input == 'a section key' ? '$address#concerns' : address;

        expect(
          await runner.run([
            'set',
            target,
            '--stamp',
            '$covered=$fingerprint',
            ...beside,
          ]),
          64,
          reason: input,
        );

        expect(err.toString(), '--stamp takes no $input\n', reason: input);
        expect(out.toString(), isEmpty, reason: input);
        expect(console.reads, 0, reason: input);
      }
      expect(archText(root), before);
    });

    test('set --stamp --json lists each refused entry with its code', () async {
      final root = await project();
      final before = archText(root);

      final run = await _set(root, [
        address,
        '--stamp',
        '$covered=0123456789ab',
        '--json',
      ]);

      expect(run.status, 75);
      expect(run.out, isEmpty);
      expect(_error(run), {
        'code': 'stamp_stale',
        'message': '$covered changed after 0123456789ab; judge it again',
        'refusals': [
          {'entry': covered, 'code': 'stamp_stale'},
        ],
      });
      expect(archText(root), before);
    });

    test('set --stamp prints one stderr line per refused entry', () async {
      final root = await project();

      final run = await _set(root, [
        address,
        '--stamp',
        'app/lib/none.dart=0123456789ab',
        '--stamp',
        '$covered=0123456789ab',
      ]);

      expect(run.status, 64);
      expect(
        run.err,
        'stamp_entry_unknown: no entry of $address reads app/lib/none.dart\n'
        'stamp_stale: $covered changed after 0123456789ab; judge it again\n',
      );
    });

    test('a comma in a --stamp path stays one entry', () async {
      final root = await project();

      final run = await _set(root, [
        address,
        '--stamp',
        'app/lib/a,b.dart=0123456789ab',
      ]);

      expect(
        run.err,
        'stamp_entry_unknown: no entry of $address reads app/lib/a,b.dart\n',
      );
    });
  });

  group('--replace', () {
    const target = 'user_story:login/email_login#use_case';
    const stdin = '==> old <==\nwith an email\n==> new <==\nwith a link\n';

    test('replaces one passage of a section and prints its new base', () async {
      final root = await writeWriteProject();
      final before = readDoc(root, story1);
      final base = getDoc(root, target)['base']! as String;
      final (:runner, :out, :err) = writeRunner(
        root,
        console: FakeConsole(input: stdin),
      );
      expect(
        await runner.run(['set', target, '--base', base, '--replace']),
        0,
        reason: err.toString(),
      );
      expect(
        readDoc(root, story1),
        before.replaceFirst('with an email', 'with a link'),
      );
      expect(
        out.toString(),
        '==> login/email_login (user_story) · $story1#use_case · base ${baseHashOf('\nSign in with a link.\n')} <==\n',
      );
      expect(err.toString(), isEmpty);
    });

    test('exits 75 as replace_unmatched and prints the current section', () async {
      final root = await writeWriteProject();
      final before = readDoc(root, story1);
      final base = getDoc(root, target)['base']! as String;
      final (:runner, :out, :err) = writeRunner(
        root,
        console: FakeConsole(
          input: '==> old <==\nBlue fish.\n==> new <==\nx\n',
        ),
      );
      expect(
        await runner.run(['set', target, '--base', base, '--replace']),
        75,
      );
      expect(
        out.toString(),
        '==> login/email_login (user_story) · $story1#use_case · base $base <==\n'
        '## Use Case\n\nSign in with an email.\n',
      );
      expect(err.toString(), contains('the old passage is not in the section'));
      expect(readDoc(root, story1), before);
    });

    test('exits 64 as argument_conflict beside --field, --title, --batch, a lead target, or a whole-doc target, and writes nothing', () async {
      final root = await writeWriteProject();
      final before = readDoc(root, story1);
      final batch = File.fromUri(root.uri.resolve('batch.md'))
        ..writeAsStringSync('x\n');
      const doc = 'user_story:login/email_login';
      for (final args in [
        [target, '--field', 'vision'],
        [doc, '--field', 'vision'],
        [doc, '--title'],
        [target, '--title'],
        [target, '--batch', batch.path],
        ['$doc#_lead'],
        [doc],
      ]) {
        final (:runner, :out, :err) = writeRunner(
          root,
          console: FakeConsole(input: stdin),
        );
        expect(
          await runner.run([
            'set',
            ...args,
            '--base',
            'e3b0c44298fc',
            '--replace',
            '--json',
          ]),
          64,
          reason: '$args',
        );
        expect(out.toString(), isEmpty, reason: '$args');
        expect(
          ((jsonDecode(err.toString()) as Map)['error']! as Map)['code'],
          'argument_conflict',
          reason: '$args',
        );
      }
      expect(readDoc(root, story1), before);
    });

    test(
      'exits 64 as argument_conflict beside --remove-task and reads no stdin',
      () async {
        final root = await writeWriteProject();
        final console = _RecordingConsole();
        final (:runner, :out, :err) = writeRunner(root, console: console);
        expect(
          await runner.run([
            'set',
            '--remove-task',
            'a:b',
            '--replace',
            '--json',
          ]),
          64,
        );
        expect(
          ((jsonDecode(err.toString()) as Map)['error']! as Map)['code'],
          'argument_conflict',
        );
        expect(console.reads, 0);
      },
    );
  });

  group('field and title writes', () {
    const story = 'user_story:login/email_login';
    const frAddress = 'fr:login/email_login/validate_credentials';

    String fieldBase(Directory root, String address, String id) =>
        ((getDoc(root, address)['bases']! as Map)['fields']! as Map)[id]!
            as String;

    test('set --field draft or approved with a value is field_not_writable naming the field, exit 64', () async {
      final root = await writeWriteProject();
      final before = readDoc(root, story1);
      for (final field in ['draft', 'approved']) {
        final run = await _set(root, [
          story,
          '--field',
          field,
          '--base',
          '000000000000',
          '--json',
        ], stdin: 'false\n');
        expect(run.status, 64, reason: field);
        expect(run.out, isEmpty, reason: field);
        final error = _error(run);
        expect(error['code'], 'field_not_writable', reason: field);
        expect(error['key'], field, reason: field);
        expect(error['message'], startsWith(field), reason: field);
      }
      expect(readDoc(root, story1), before);
    });

    test('set --field draft or approved with empty stdin is field_not_writable naming the field, exit 64', () async {
      final root = await writeWriteProject();
      final before = readDoc(root, story1);
      for (final field in ['draft', 'approved']) {
        final run = await _set(root, [
          story,
          '--field',
          field,
          '--base',
          '000000000000',
          '--json',
        ], stdin: '');
        expect(run.status, 64, reason: field);
        expect(run.out, isEmpty, reason: field);
        final error = _error(run);
        expect(error['code'], 'field_not_writable', reason: field);
        expect(error['key'], field, reason: field);
      }
      expect(readDoc(root, story1), before);
    });

    test('set --field status with a value on a feature is field_not_writable, exit 64', () async {
      final root = await writeWriteProject();
      final before = readDoc(root, loginFeature);
      final run = await _set(root, [
        'feature:login',
        '--field',
        'status',
        '--base',
        emptyBaseHash,
        '--json',
      ], stdin: 'implemented\n');
      expect(run.status, 64, reason: run.err);
      expect(run.out, isEmpty);
      final error = _error(run);
      expect(error['code'], 'field_not_writable');
      expect(error['key'], 'status');
      expect(readDoc(root, loginFeature), before);
    });

    test('set --field verify_method with a value outside its enum is field_value_invalid naming the values, exit 64', () async {
      final root = await writeWriteProject();
      final before = readDoc(root, fr11);
      final run = await _set(root, [
        frAddress,
        '--field',
        'verify_method',
        '--base',
        fieldBase(root, frAddress, 'verify_method'),
        '--json',
      ], stdin: 'maybe\n');
      expect(run.status, 64, reason: run.err);
      expect(run.out, isEmpty);
      final error = _error(run);
      expect(error['code'], 'field_value_invalid');
      expect(error['key'], 'verify_method');
      expect(
        error['message'],
        allOf(
          contains('verify_method'),
          contains('test'),
          contains('analysis'),
          contains('inspection'),
          contains('demonstration'),
        ),
      );
      expect(readDoc(root, fr11), before);
    });

    test('set --field with a list on a scalar field, or with invalid YAML, is field_value_invalid, exit 64', () async {
      final root = await writeWriteProject();
      final before = readDoc(root, story1);
      for (final (stdin, message) in [
        ('- a\n- b\n', 'status takes one YAML value, not a list'),
        ('[unclosed\n', 'status takes a YAML value'),
      ]) {
        final run = await _set(root, [
          story,
          '--field',
          'status',
          '--base',
          fieldBase(root, story, 'status'),
          '--json',
        ], stdin: stdin);
        expect(run.status, 64, reason: stdin);
        expect(run.out, isEmpty, reason: stdin);
        final error = _error(run);
        expect(error['code'], 'field_value_invalid', reason: stdin);
        expect(error['key'], 'status', reason: stdin);
        expect(error['message'], message, reason: stdin);
      }
      expect(readDoc(root, story1), before);
    });

    test('set --field with empty stdin on a required field is required_target naming it, exit 64', () async {
      final root = await writeWriteProject();
      final before = readDoc(root, fr11);
      final run = await _set(root, [
        frAddress,
        '--field',
        'verify_method',
        '--base',
        fieldBase(root, frAddress, 'verify_method'),
        '--json',
      ], stdin: '');
      expect(run.status, 64, reason: run.err);
      expect(run.out, isEmpty);
      final error = _error(run);
      expect(error['code'], 'required_target');
      expect(error['message'], contains('verify_method'));
      expect(readDoc(root, fr11), before);
    });

    test('set --field naming an undeclared id is field_unknown naming the doc type and the id, exit 64', () async {
      final root = await writeWriteProject();
      final before = readDoc(root, story1);
      for (final stdin in ['x\n', '']) {
        final run = await _set(root, [
          story,
          '--field',
          'nonesuch',
          '--base',
          emptyBaseHash,
          '--json',
        ], stdin: stdin);
        expect(run.status, 64, reason: 'stdin "$stdin"');
        expect(run.out, isEmpty, reason: 'stdin "$stdin"');
        final error = _error(run);
        expect(error['code'], 'field_unknown', reason: 'stdin "$stdin"');
        expect(
          error['message'],
          allOf(contains('user_story'), contains('nonesuch')),
          reason: 'stdin "$stdin"',
        );
      }
      expect(readDoc(root, story1), before);
    });

    test('a stale field base prints the current block under its field naming line, one fault line, exit 75', () async {
      final root = await writeWriteProject();
      final before = readDoc(root, story1);
      final current = fieldBase(root, story, 'vision');
      final run = await _set(root, [
        story,
        '--field',
        'vision',
        '--base',
        '000000000000',
      ], stdin: '- PV-02\n');
      expect(run.status, 75, reason: run.err);
      expect(
        run.out,
        '==> login/email_login (user_story) · $story1 · field vision · base $current <==\n'
        'vision:\n  - PV-01\n',
      );
      expect(
        run.err,
        '$story1: vision: the field changed since base 000000000000\n',
      );
      expect(readDoc(root, story1), before);
    });

    test('a stale title base prints the current title line under its title naming line, one fault line, exit 75', () async {
      final root = await writeWriteProject();
      final before = readDoc(root, story1);
      final current = baseHashOf('Sign in with email');
      final run = await _set(root, [
        story,
        '--title',
        '--base',
        '000000000000',
      ], stdin: 'Sign in\n');
      expect(run.status, 75, reason: run.err);
      expect(
        run.out,
        '==> login/email_login (user_story) · $story1 · title · base $current <==\n'
        '# Sign in with email\n',
      );
      expect(
        run.err,
        '$story1: title: the title changed since base 000000000000\n',
      );
      expect(readDoc(root, story1), before);
    });

    test('set --title with empty stdin or two lines is argument_invalid, exit 64, the title untouched', () async {
      final root = await writeWriteProject();
      final before = readDoc(root, story1);
      for (final stdin in ['', '\n', 'One\nTwo\n']) {
        final run = await _set(root, [
          story,
          '--title',
          '--base',
          baseHashOf('Sign in with email'),
          '--json',
        ], stdin: stdin);
        expect(run.status, 64, reason: 'stdin "$stdin"');
        expect(run.out, isEmpty, reason: 'stdin "$stdin"');
        expect(
          _error(run)['code'],
          'argument_invalid',
          reason: 'stdin "$stdin"',
        );
      }
      expect(readDoc(root, story1), before);
    });

    test('set --title beside a section key or --field is argument_conflict, and no key, field, or title is argument_missing, exit 64', () async {
      final root = await writeWriteProject();
      final before = readDoc(root, story1);
      for (final (args, code) in [
        (<String>['$story#use_case', '--title'], 'argument_conflict'),
        (<String>[story, '--title', '--field', 'vision'], 'argument_conflict'),
        (<String>[story], 'argument_missing'),
      ]) {
        final run = await _set(root, [
          ...args,
          '--base',
          '000000000000',
          '--json',
        ]);
        expect(run.status, 64, reason: '$args');
        expect(run.out, isEmpty, reason: '$args');
        expect(_error(run)['code'], code, reason: '$args');
      }
      expect(readDoc(root, story1), before);
    });

    test('set --field and --title meet an untyped doc, a missing doc, and a missing --base with exit 64', () async {
      final root = await writeWriteProject();
      for (final write in [
        ['--field', 'vision'],
        ['--title'],
      ]) {
        for (final (args, code) in [
          (
            <String>['prds/d01_context.md', ...write, '--base', emptyBaseHash],
            'untyped_target',
          ),
          (
            <String>[
              'user_story:login/ghost',
              ...write,
              '--base',
              emptyBaseHash,
            ],
            'doc_not_found',
          ),
          (<String>[story, ...write], 'argument_missing'),
        ]) {
          final run = await _set(root, [...args, '--json'], stdin: 'x\n');
          expect(run.status, 64, reason: '$args');
          expect(run.out, isEmpty, reason: '$args');
          expect(_error(run)['code'], code, reason: '$args');
        }
      }
    });

    test('set --field and --title on a file the disk refuses are output_not_writable, exit 73, the doc as it was', () async {
      final root = await writeWriteProject();
      final before = readDoc(root, story1);
      final folder = docFile(root, story1).parent.path;
      expect(Process.runSync('chmod', ['555', folder]).exitCode, 0);
      addTearDown(() => Process.runSync('chmod', ['755', folder]));
      for (final (write, base, stdin) in [
        (
          <String>['--field', 'vision'],
          fieldBase(root, story, 'vision'),
          '- PV-02\n',
        ),
        (<String>['--title'], baseHashOf('Sign in with email'), 'Sign in\n'),
      ]) {
        final run = await _set(root, [
          story,
          ...write,
          '--base',
          base,
          '--json',
        ], stdin: stdin);
        expect(run.status, 73, reason: '$write: ${run.err}');
        expect(run.out, isEmpty, reason: '$write');
        expect(_error(run)['code'], 'output_not_writable', reason: '$write');
      }
      expect(readDoc(root, story1), before);
    }, skip: Platform.isWindows ? 'no chmod' : null);
  });

  group('--remove-task faults', () {
    test('a task no doc holds prints its no refs line, writes no doc and no journal, exit 0', () async {
      final root = await writeWriteProject();
      final before = readDoc(root, loginArch);
      final run = await _set(root, ['--remove-task', 'ENG-99']);
      expect(run.status, 0, reason: run.err);
      expect(run.out, 'ENG-99 · no refs\n');
      expect(run.err, isEmpty);
      expect(readDoc(root, loginArch), before);
      expect(
        File('${root.path}/${MoveJournal.journalPath}').existsSync(),
        isFalse,
      );
    });

    test('an empty or colon task value is argument_invalid with its message, exit 64, no doc written', () async {
      final root = await writeWriteProject();
      final before = readDoc(root, loginArch);
      for (final value in ['', 'INV-4:ENG-42']) {
        final run = await _set(root, ['--remove-task', value]);
        expect(run.status, 64, reason: 'value "$value"');
        expect(run.out, isEmpty, reason: 'value "$value"');
        expect(
          run.err,
          '--remove-task takes a task id that is not empty and holds no ":"; got "$value"\n',
          reason: 'value "$value"',
        );
      }
      expect(readDoc(root, loginArch), before);
    });
  });
}

/// What one `set` run exited with and printed.
final class _SetRun {
  const new(this.status, this.out, this.err);

  final int status;
  final String out;
  final String err;
}

Future<_SetRun> _set(
  Directory root,
  List<String> args, {
  String stdin = 'x\n',
}) async {
  final (:runner, :out, :err) = writeRunner(
    root,
    console: FakeConsole(input: stdin),
  );
  final status = await runner.run(['set', ...args]);
  return _SetRun(status, out.toString(), err.toString());
}

Map<String, Object?> _error(_SetRun run) =>
    (jsonDecode(run.err) as Map<String, Object?>)['error']!
        as Map<String, Object?>;

/// A [Console] that counts how often stdin is read.
final class _RecordingConsole implements Console {
  int reads = 0;

  @override
  bool get stdinIsTerminal => false;

  @override
  bool get stdoutIsTerminal => false;

  @override
  bool get stderrIsTerminal => false;

  @override
  bool get noColor => false;

  @override
  String? get approveModeVariable => null;

  @override
  Future<String> readAll() async {
    reads++;
    return '';
  }

  @override
  String? readLine() => null;
}
