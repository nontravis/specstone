// The fixture texts are plan literals kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:convert';
import 'dart:io';

import 'package:specstone/src/command_runner.dart';
import 'package:specstone/src/console.dart';
import 'package:specstone_core/src/consistency_check/code_fingerprint.dart';
import 'package:specstone_core/src/consistency_check/models/file_fingerprint.dart';
import 'package:specstone_core/src/doc_model/doc_splice.dart';
import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:test/test.dart';

import '../../../../specstone_core/test/helpers/check_fixture.dart'
    as check
    show checkProjectFiles, doc, fr, loginRecord, writeCheckProject;
import '../../../../specstone_core/test/helpers/relative_link.dart';
import '../../../../specstone_core/test/helpers/target_fixture.dart';
import '../../../../specstone_core/test/helpers/temp_tree.dart';
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
  test('set --json prints a docs array of one element and warnings', () async {
    for (final (flags, input) in [
      (<String>[], 'Sign in with a passkey.\n'),
      (['--replace'], '==> old <==\nwith an email\n==> new <==\nwith a link\n'),
    ]) {
      final root = await writeWriteProject();
      final (:runner, :out, :err) = writeRunner(
        root,
        console: FakeConsole(input: input),
      );
      expect(
        await runner.run([
          'set',
          'user_story:login/email_login#use_case',
          '--base',
          '7e11fc4a24d2',
          ...flags,
          '--json',
        ]),
        0,
        reason: err.toString(),
      );
      final json = jsonDecode(out.toString()) as Map<String, Object?>;
      expect(json.keys, ['docs', 'warnings'], reason: '$flags');
      final docs = json['docs']! as List;
      expect(docs, hasLength(1), reason: '$flags');
      expect((docs.single as Map).keys, [
        'name',
        'docType',
        'path',
        'base',
        'draft',
      ], reason: '$flags');
    }
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
        'warnings': <Object>[],
      });
    },
  );
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
        'warnings': <Object>[],
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
    final text = out.toString().replaceAll(RegExp(r'\s+'), ' ');
    for (final form in [
      'specstone set <doc address>(#<section key> | #_lead) [--base <hash>] --dry-run [--target <name>] [--json] [--out [<path>]]',
      'Takes no doc address, --base, --field, --title, or --target; reads no stdin.',
      'specstone set --remove-task <task id>',
      'Removes every entry of the task',
      'specstone set <doc address> --stamp <entry>=<fingerprint>',
      'Ends a covers or implements entry',
      'specstone set --sync <file>',
    ]) {
      expect(text, contains(form));
    }
    expect(err.toString(), isEmpty);
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
  });

  group('--stamp', () {
    const address = 'implementation:login';
    const covered = 'app/lib/login.dart';

    final fingerprint = fileCodeFingerprint(
      utf8.encode(check.checkProjectFiles()[covered]!),
      path: covered,
    );

    Future<Directory> project() => check.writeCheckProject(
      extra: check.doc(check.loginRecord, '  - app/lib/\n', '  - $covered\n'),
      unfingerprinted: {check.loginRecord},
    );

    String recordText(Directory root) =>
        File('${root.path}/${check.loginRecord}').readAsStringSync();

    test(
      'set --stamp prints the stamped count and leaves the doc approved',
      () async {
        final root = await project();
        final before = recordText(root);
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
          recordText(root),
          before.replaceFirst('  - $covered\n', '  - $covered $fingerprint\n'),
        );
        expect(recordText(root), isNot(contains('draft: true')));
      },
    );

    test('set --stamp beside --base, --field, --title, --batch, --remove-task, --replace, or a section key is argument_conflict, reads no stdin', () async {
      final root = await project();
      final before = recordText(root);
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
        final target = input == 'a section key' ? '$address#statuses' : address;

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
      expect(recordText(root), before);
    });

    test('set --stamp --json lists each refused entry with its code', () async {
      final root = await project();
      final before = recordText(root);

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
      expect(recordText(root), before);
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

    // D9: a `..` segment is refused, never folded.
    test('set --stamp on an entry holding a .. segment prints its refusal line with stamp_entry_unresolved', () async {
      const outside = 'app/lib/../lib/login.dart';
      final root = await check.writeCheckProject(
        extra: check.doc(check.loginRecord, '  - app/lib/\n', '  - $outside\n'),
        unfingerprinted: {check.loginRecord},
      );
      final before = recordText(root);

      final run = await _set(root, [
        address,
        '--stamp',
        '$outside=0123456789ab',
      ]);

      expect(run.status, 64);
      expect(
        run.err,
        'stamp_entry_unresolved: $outside does not resolve: covers_path_outside\n',
      );
      expect(recordText(root), before);
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

    test('set --stamp --json prints a docs array and warnings', () async {
      final root = await project();
      final (:runner, :out, :err) = writeRunner(root);

      expect(
        await runner.run([
          'set',
          address,
          '--stamp',
          '$covered=$fingerprint',
          '--json',
        ]),
        0,
        reason: err.toString(),
      );

      expect(jsonDecode(out.toString()), {
        'docs': [
          {
            'name': 'login',
            'docType': 'implementation',
            'path': check.loginRecord,
            'stamped': [covered],
          },
        ],
        'warnings': <Object?>[],
      });
      expect(err.toString(), isEmpty);
    });

    test('--target keeps the stamp to one code target', () async {
      const folder = 'app/lib/';
      const jasprFile = 'app/lib/login.dart';
      final root = await writeTwinProject(
        unfingerprinted: {flutterRecord, jasprRecord},
      );
      String recordAt(String path) =>
          File('${root.path}/$path').readAsStringSync();
      final flutterBefore = recordAt(flutterRecord);
      final jasprFingerprint = folderCodeFingerprint([
        FileFingerprint(
          path: jasprFile,
          fingerprint: fileCodeFingerprint(
            File('${root.path}/jaspr_ws/$jasprFile').readAsBytesSync(),
            path: jasprFile,
          ),
        ),
      ]);
      final (:runner, :out, :err) = writeRunner(root);

      expect(
        await runner.run([
          'set',
          address,
          '--stamp',
          '$folder=$jasprFingerprint',
          '--target',
          'jaspr',
        ]),
        0,
        reason: err.toString(),
      );

      expect(out.toString(), '$jasprRecord: 1 stamped\n');
      expect(
        recordAt(jasprRecord),
        contains('  - $folder $jasprFingerprint\n'),
      );
      expect(recordAt(flutterRecord), flutterBefore);
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
  });

  group('--remove-task faults', () {});

  group('--dry-run', () {
    const frTarget = 'fr:login/email_login/check_password#edge_cases';
    const shortEdge = '1. E01 — An empty password → refused.\n';
    final longEdge = '1. E01 — A long case →'.padRight(640, '.');
    final secondEdge = '2. E02 — A long case →'.padRight(640, '.');

    Future<Directory> projectWithLongEdge() =>
        check.writeCheckProject(extra: check.fr(shortEdge, '$longEdge\n'));

    Map<String, List<int>> docBytes(Directory root) => {
      for (final MapEntry(:key, :value) in treeBytes(root).entries)
        if (key.startsWith('docs/')) key: value,
    };

    test(
      'set --dry-run prints the findings and exits 0, the doc unchanged',
      () async {
        final root = await projectWithLongEdge();
        final before = docBytes(root);
        final (:runner, :out, :err) = writeRunner(
          root,
          console: FakeConsole(input: '$longEdge\n'),
        );
        expect(await runner.run(['set', frTarget, '--dry-run']), 0);

        expect(err.toString(), isEmpty);
        expect(out.toString().split('\n').first, startsWith('==> '));
        expect(out.toString(), endsWith('0 findings\n'));
        expect(docBytes(root), before);
      },
    );

    test('set --dry-run beside --field, --title, --batch, --replace, --sync, --stamp, or --remove-task is argument_conflict, exit 64, nothing written', () async {
      final root = await writeWriteProject();
      final before = docBytes(root);
      const beside = {
        '--field': ['--field', 'size'],
        '--title': ['--title'],
        '--batch': ['--batch', 'edited.txt'],
        '--replace': ['--replace'],
        '--sync': ['--sync', 'sync.txt'],
        '--stamp': ['--stamp', 'a=b'],
        '--remove-task': ['--remove-task', 'T1'],
      };
      for (final MapEntry(:key, :value) in beside.entries) {
        final (:runner, :out, :err) = writeRunner(
          root,
          console: FakeConsole(input: 'x\n'),
        );
        expect(
          await runner.run([
            'set',
            'user_story:login/email_login#use_case',
            '--dry-run',
            ...value,
          ]),
          64,
          reason: key,
        );
        expect(out.toString(), isEmpty, reason: key);
        expect(err.toString(), '--dry-run takes no $key\n', reason: key);
      }
      expect(docBytes(root), before);
    });

    test('set --dry-run with no section key is argument_missing naming the dry run target shape, exit 64, before stdin is read', () async {
      for (final target in [
        'user_story:login/email_login',
        'user_story:login/email_login#',
      ]) {
        final console = _RecordingConsole();
        final (:runner, :out, :err) = writeRunner(
          await writeWriteProject(),
          console: console,
        );

        expect(
          await runner.run(['set', target, '--dry-run']),
          64,
          reason: target,
        );

        expect(console.reads, 0, reason: target);
        expect(out.toString(), isEmpty, reason: target);
        expect(
          err.toString(),
          contains('a section key or #_lead'),
          reason: target,
        );
        expect(err.toString(), isNot(contains('--field')), reason: target);
      }
    });

    test('set --dry-run in a project whose roots wait for the trust record prints its findings and no output_not_writable', () async {
      final base = await writeTree({
        for (final MapEntry(:key, :value) in writeProject.entries)
          if (key.startsWith('docs/'))
            'ext/${key.substring(5)}': value
          else
            'src/clone/$key': value,
      });
      createRelativeLink('${base.path}/src/clone/docs', '../../ext');
      final clone = Directory('${base.path}/src/clone');
      const target = 'user_story:login/email_login#use_case';

      final dry = writeRunner(clone, console: FakeConsole(input: 'x\n'));
      expect(await dry.runner.run(['set', target, '--dry-run']), 0);
      expect(dry.err.toString(), isEmpty);
      expect(dry.out.toString(), endsWith(' findings\n'));
      expect(dry.out.toString(), isNot(contains('output_not_writable')));

      final plain = writeRunner(clone, console: FakeConsole(input: 'x\n'));
      expect(
        await plain.runner.run(['set', target, '--base', '7e11fc4a24d2']),
        73,
      );
      expect(plain.err.toString(), contains('run specstone trust'));
    });

    test('set --dry-run --json prints findings and warnings', () async {
      final root = await projectWithLongEdge();
      File('${root.path}/docs/prds/GLOSSARY.md')
        ..createSync(recursive: true)
        ..writeAsStringSync('---\nkey: [unclosed\n---\n\n# Domain glossary\n');
      final (:runner, :out, :err) = writeRunner(
        root,
        console: FakeConsole(input: '$longEdge\n$secondEdge\n'),
      );

      expect(await runner.run(['set', frTarget, '--dry-run', '--json']), 0);

      expect(err.toString(), isEmpty);
      final json = jsonDecode(out.toString()) as Map<String, Object?>;
      expect(json.keys, ['findings', 'warnings']);
      expect(json['findings'], [containsPair('kind', 'item_over_limit')]);
      expect(json['warnings'], [
        'prds/GLOSSARY.md: frontmatter is not valid YAML; its values are not indexed',
      ]);
    });

    for (final json in [false, true]) {
      test(
        'set --dry-run${json ? ' --json' : ''} --out saves the dry run reply '
        'and changes no doc',
        () async {
          final root = await projectWithLongEdge();
          final before = docBytes(root);
          final call = ['set', frTarget, '--dry-run', if (json) '--json'];
          final (runner: plain, out: printed, err: _) = writeRunner(
            root,
            console: FakeConsole(input: '$longEdge\n$secondEdge\n'),
          );
          expect(await plain.run(call), 0);

          final (:runner, :out, :err) = writeRunner(
            root,
            console: FakeConsole(input: '$longEdge\n$secondEdge\n'),
          );
          expect(await runner.run([...call, '--out', 'dry.txt']), 0);

          expect(err.toString(), isEmpty);
          expect(
            File('${root.path}/dry.txt').readAsStringSync(),
            printed.toString(),
          );
          if (json) {
            expect(
              jsonDecode(out.toString()),
              containsPair('lines', isA<int>()),
            );
          } else {
            expect(
              out.toString(),
              matches(RegExp(r'^==> set: \d+ lines, \d+ tokens · ')),
            );
          }
          expect(docBytes(root), before);
        },
      );
    }

    test('set --dry-run --base <stale> --out prints the current section, exits 75, '
        'and writes no file', () async {
      final root = await writeWriteProject();
      final before = docBytes(root);
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
          '--dry-run',
          '--out',
          'dry.txt',
        ]),
        75,
      );

      expect(
        err.toString(),
        '$story1: use_case: the section changed since base 000000000000\n',
      );
      expect(docBytes(root), before);
      expect(
        out.toString(),
        '==> login/email_login (user_story) · $story1#use_case · '
        'base 7e11fc4a24d2 <==\n'
        '## Use Case\n\nSign in with an email.\n',
      );
      expect(File('${root.path}/dry.txt').existsSync(), isFalse);
    });

    test(
      'set --out with no --dry-run is argument_invalid and changes no doc',
      () async {
        final root = await projectWithLongEdge();
        final before = docBytes(root);
        final (:runner, :out, :err) = writeRunner(
          root,
          console: FakeConsole(input: '$longEdge\n'),
        );

        expect(await runner.run(['set', frTarget, '--out', 'gone.txt']), 64);

        expect(out.toString(), isEmpty);
        expect(err.toString(), '--out goes with --dry-run\n');
        expect(File('${root.path}/gone.txt').existsSync(), isFalse);
        expect(docBytes(root), before);
      },
    );
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
