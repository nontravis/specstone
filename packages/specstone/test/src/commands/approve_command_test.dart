// The test titles and literals are plan values kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/specstone_core.dart';
import 'package:test/test.dart';

import '../../../../specstone_core/test/helpers/check_fixture.dart' as check;
import '../../../../specstone_core/test/helpers/git_repo.dart';
import '../../../../specstone_core/test/helpers/nested_fixture.dart';
import '../../../../specstone_core/test/helpers/relative_link.dart';
import '../../../../specstone_core/test/helpers/target_fixture.dart';
import '../../../../specstone_core/test/helpers/temp_tree.dart';
import '../../../../specstone_core/test/helpers/write_fixture.dart';
import '../../helpers/built_cli.dart';
import '../../helpers/write_runner.dart';

/// Returns `<address>@<hash>`, the hash `get --json` prints as base.
String _seen(Directory root, String address) =>
    '$address@${getDoc(root, address)['base']}';

const _story = 'user_story:login/email_login';
const _fr = 'fr:login/email_login/check_password';

/// The check project with the story and the FR as drafts, both clean, the FR
/// with a missing section when [frHasFinding].
Future<Directory> _draftsProject({bool frHasFinding = false}) =>
    check.writeCheckProject(
      extra: {
        ...check.edit(check.loginStory, [
          ('goals:\n', 'draft: true\ngoals:\n'),
        ]),
        ...check.edit(check.loginFr, [
          ('traced_from:\n', 'draft: true\ntraced_from:\n'),
          if (frHasFinding)
            ('## Rationale\n\nA wrong password must not sign in.\n\n', ''),
        ]),
      },
    );

/// Writes the audit report [name] under [folder], default [root], naming each
/// of [addresses] at its current hash.
String _writeAudit(
  Directory root,
  List<String> addresses, {
  String name = 'audit.md',
  Directory? folder,
}) {
  final file = File('${(folder ?? root).path}/$name')
    ..createSync(recursive: true)
    ..writeAsStringSync(
      [
        for (final address in addresses)
          'Audited: $address@${getDoc(root, address)['base']}',
        'Findings: none',
      ].join('\n'),
    );
  return file.path;
}

/// The bytes of every file of the docs folder.
Map<String, List<int>> _docBytes(Directory root) => {
  for (final MapEntry(:key, :value) in treeBytes(root).entries)
    if (key.startsWith('docs/')) key: value,
};

bool _isApproved(Directory root, String docPath) {
  final text = readDoc(root, docPath);
  return text.contains('\napproved: ') && !text.contains('draft: true');
}

void main() {
  test('approve without a terminal exits 77 and shows nothing', () async {
    final (:runner, :out, :err) = writeRunner(await writeWriteProject());
    expect(await runner.run(['approve']), 77);
    expect(out.toString(), isEmpty);
    expect(
      err.toString(),
      "approve runs only at an interactive terminal, or with --yes after the Owner's ok in the chat\n",
    );
  });
  test('a terminal on stdin alone is still refused', () async {
    final (:runner, :out, :err) = writeRunner(
      await writeWriteProject(),
      console: FakeConsole(stdinIsTerminal: true),
    );
    expect(await runner.run(['approve']), 77);
    expect(out.toString(), isEmpty);
  });
  test('at a terminal, y approves the draft', () async {
    final root = await writeWriteProject();
    final console = FakeConsole(
      stdinIsTerminal: true,
      stdoutIsTerminal: true,
      answers: ['y', 'y'],
    );
    final (:runner, :out, :err) = writeRunner(root, console: console);
    expect(await runner.run(['approve', 'signup']), 0);
    expect(err.toString(), isEmpty);
    expect(out.toString(), contains('approve? [y/n/q] '));
    final text = File('${root.path}/docs/$signupFeature').readAsStringSync();
    expect(text, matches(RegExp(r'\napproved: "[0-9a-f]{12}"\n')));
    expect(text, isNot(contains('draft: true')));
  });
  test('at a terminal, two names walk the drafts under either', () async {
    final root = await writeWriteProject();
    final console = FakeConsole(
      stdinIsTerminal: true,
      stdoutIsTerminal: true,
      answers: List.filled(12, 'n'),
    );
    final (:runner, :out, :err) = writeRunner(root, console: console);
    expect(
      await runner.run([
        'approve',
        'feature:signup',
        'user_story:login/email_login',
      ]),
      0,
    );
    expect(err.toString(), isEmpty);
    expect('approve? [y/n/q] '.allMatches(out.toString()), hasLength(4));
  });
  test('--yes approves each <type>:<name>@<hash> draft with no terminal and no prompt, one line each', () async {
    final root = await writeWriteProject();
    final (:runner, :out, :err) = writeRunner(root);
    expect(
      await runner.run([
        'approve',
        _seen(root, 'feature:signup'),
        _seen(root, 'fr:login/email_login/lock_after_failures'),
        '--yes',
      ]),
      0,
    );
    expect(err.toString(), isEmpty);
    expect(
      out.toString(),
      'approved fr:login/email_login/lock_after_failures\n'
      'approved feature:signup\n',
    );
    final text = File('${root.path}/docs/$signupFeature').readAsStringSync();
    expect(text, matches(RegExp(r'\napproved: "[0-9a-f]{12}"\n')));
    expect(text, isNot(contains('draft: true')));
  });
  test(
    '--yes deletes the saved copy no doc carries and keeps the copy it saves',
    () async {
      final root = await writeWriteProject();
      final orphan = File('${root.path}/.specstone/approved/ba9876543210.md')
        ..createSync(recursive: true)
        ..writeAsStringSync('an approval no doc carries');
      final (:runner, :out, :err) = writeRunner(root);

      expect(
        await runner.run(['approve', _seen(root, 'feature:signup'), '--yes']),
        0,
      );

      final mark = RegExp(r'\napproved: "([0-9a-f]{12})"\n').firstMatch(
        File('${root.path}/docs/$signupFeature').readAsStringSync(),
      )!;
      expect(orphan.existsSync(), isFalse);
      expect(
        File('${root.path}/.specstone/approved/${mark.group(1)}.md')
            .existsSync(),
        isTrue,
      );
    },
  );
  test('--yes approves a draft that lacks required and optional sections and adds none of them', () async {
    final root = await writeWriteProject();
    List<String> headersOf(String docPath) => RegExp(
      r'^## .*$',
      multiLine: true,
    ).allMatches(readDoc(root, docPath)).map((match) => match[0]!).toList();
    final before = headersOf(fr12);
    expect(before, ['## Statement']);
    final (:runner, :out, :err) = writeRunner(root);
    expect(
      await runner.run([
        'approve',
        _seen(root, 'fr:login/email_login/lock_after_failures'),
        '--yes',
      ]),
      0,
    );
    expect(
      readDoc(root, fr12),
      matches(RegExp(r'\napproved: "[0-9a-f]{12}"\n')),
    );
    expect(headersOf(fr12), before);
  });
  test('--yes with no name is a usage error, exit 64', () async {
    final (:runner, :out, :err) = writeRunner(
      await writeWriteProject(),
      console: FakeConsole(stdinIsTerminal: true, stdoutIsTerminal: true),
    );
    expect(await runner.run(['approve', '--yes']), 64);
    expect(out.toString(), isEmpty);
    expect(
      err.toString(),
      startsWith('--yes needs the names of the drafts it approves.\n'),
    );
  });
  test('--yes on a name without @<hash> is a usage error, exit 64, and approves nothing', () async {
    final root = await writeWriteProject();
    final before = File('${root.path}/docs/$signupFeature').readAsStringSync();
    final (:runner, :out, :err) = writeRunner(root);
    expect(
      await runner.run([
        'approve',
        _seen(root, 'feature:signup'),
        'architecture:signup',
        '--yes',
      ]),
      64,
    );
    expect(out.toString(), isEmpty);
    expect(
      err.toString(),
      startsWith(
        '--yes needs each draft as <name>@<hash>, the hash from '
        'docs[0].base of specstone get <name> --json; got '
        'architecture:signup.\n',
      ),
    );
    expect(File('${root.path}/docs/$signupFeature').readAsStringSync(), before);
  });
  test('a @<hash> without --yes is a usage error, exit 64', () async {
    final root = await writeWriteProject();
    final (:runner, :out, :err) = writeRunner(
      root,
      console: FakeConsole(stdinIsTerminal: true, stdoutIsTerminal: true),
    );
    final named = _seen(root, 'feature:signup');
    expect(await runner.run(['approve', named]), 64);
    expect(out.toString(), isEmpty);
    expect(
      err.toString(),
      startsWith('$named: a @<hash> goes only with --yes.\n'),
    );
  });
  test('--yes on a draft changed since its hash was taken exits 75 naming it, and approves nothing', () async {
    final root = await writeWriteProject();
    final named = _seen(root, 'feature:signup');
    final arch = _seen(root, 'architecture:signup');
    final file = File('${root.path}/docs/$signupFeature');
    file.writeAsStringSync('${file.readAsStringSync()}More.\n');
    final changed = file.readAsStringSync();
    final archBefore = File('${root.path}/docs/$signupArch').readAsStringSync();
    final (:runner, :out, :err) = writeRunner(root);
    expect(await runner.run(['approve', arch, named, '--yes']), 75);
    expect(out.toString(), isEmpty);
    expect(
      err.toString(),
      '$signupFeature: doc: changed since their hash was taken: '
      'feature:signup; read each again and approve it with its new hash\n',
    );
    expect(file.readAsStringSync(), changed);
    expect(
      File('${root.path}/docs/$signupArch').readAsStringSync(),
      archBefore,
    );
  });
  test(
    '--yes on a doc that is no draft exits 65 naming it, and approves nothing',
    () async {
      final root = await writeWriteProject();
      final before = File('${root.path}/docs/$signupFeature')
          .readAsStringSync();
      final (:runner, :out, :err) = writeRunner(root);
      expect(
        await runner.run([
          'approve',
          _seen(root, 'feature:signup'),
          _seen(root, 'feature:login'),
          '--yes',
        ]),
        65,
      );
      expect(out.toString(), isEmpty);
      expect(
        err.toString(),
        'feature:login is no draft waiting for approval\n',
      );
      expect(
        File('${root.path}/docs/$signupFeature').readAsStringSync(),
        before,
      );
    },
  );
  test('--yes on a name no doc carries is doc_not_found, exit 64, and approves nothing', () async {
    final root = await writeWriteProject();
    final before = File('${root.path}/docs/$signupFeature').readAsStringSync();
    final (:runner, :out, :err) = writeRunner(root);
    expect(
      await runner.run([
        'approve',
        _seen(root, 'feature:signup'),
        'feature:nosuch@000000000000',
        '--yes',
      ]),
      64,
    );
    expect(out.toString(), isEmpty);
    expect(err.toString(), isNotEmpty);
    expect(File('${root.path}/docs/$signupFeature').readAsStringSync(), before);
  });
  test('the help names --yes and what it does', () async {
    final (:runner, :out, :err) = writeRunner(await writeWriteProject());
    expect(await runner.run(['approve', '--help']), 0);
    expect(
      out.toString().replaceAll(RegExp(r'\s+'), ' '),
      contains(
        "--yes Approve the named drafts without the terminal prompt; the agent runs it after the Owner's ok.",
      ),
    );
    expect(
      out.toString(),
      contains(
        'Usage: specstone approve [<name> …] [--target <name>] [--dry-run] [--context <n> | --json [--audit <path> …]] [--out [<path>]] | <name>@<hash> … --yes [--target <name>]',
      ),
    );
    expect(
      out.toString().replaceAll(RegExp(r'\s+'), ' '),
      contains(
        '--json With --dry-run, print the drafts as one JSON object in place of the views.',
      ),
    );
  });

  test('dry run needs no terminal and prints no colour', () async {
    final (:runner, :out, :err) = writeRunner(await writeWriteProject());
    expect(await runner.run(['approve', '--dry-run']), 0);
    expect(out.toString(), contains('### Draft 1/'));
    expect(out.toString(), contains('```diff'));
    expect(out.toString(), isNot(contains('\x1b[')));
    expect(err.toString(), isEmpty);
  });
  test(
    'dry run shows the no-copy cell for a never-approved doc, with the '
    'hint when it carries approved: on disk and without it otherwise',
    () async {
      String draft(String mark) =>
          '---\n$mark---\n\n# Signup\n\n## Problem\nUsers sign up.\n';
      final root = await writeWriteProject(
        extra: {'docs/$signupFeature': draft('approved: "0123456789ab"\n')},
      );
      expect(git(root, ['init', '-q']).exitCode, 0);
      expect(git(root, ['config', 'core.autocrlf', 'false']).exitCode, 0);
      commitAll(root, 'approved on disk, never committed as approved');
      var (:runner, :out, :err) = writeRunner(root);
      expect(await runner.run(['approve', '--dry-run']), 0);
      expect(
        out.toString(),
        contains('| old     | none: no commit holds an approved copy |\n'),
      );
      expect(
        out.toString(),
        contains(
          'no copy of this approval is saved here or in a commit; '
          'commit approvals before editing again\n',
        ),
      );

      final bare = await writeWriteProject(
        extra: {'docs/$signupFeature': draft('draft: true\n')},
      );
      expect(git(bare, ['init', '-q']).exitCode, 0);
      expect(git(bare, ['config', 'core.autocrlf', 'false']).exitCode, 0);
      commitAll(bare, 'only ever a draft');
      (:runner, :out, :err) = writeRunner(bare);
      expect(await runner.run(['approve', '--dry-run']), 0);
      expect(
        out.toString(),
        contains('| old     | none: no commit holds an approved copy |\n'),
      );
      expect(
        out.toString(),
        isNot(contains('commit approvals before editing')),
      );
    },
  );
  test('dry run with --yes is a usage error', () async {
    final root = await writeWriteProject();
    final (:runner, :out, :err) = writeRunner(root);
    expect(
      await runner.run([
        'approve',
        '--dry-run',
        '--yes',
        _seen(root, 'feature:signup'),
      ]),
      64,
    );
    expect(err.toString(), contains('--dry-run goes without --yes.'));
  });
  test('a hash with --dry-run is a usage error', () async {
    final root = await writeWriteProject();
    final (:runner, :out, :err) = writeRunner(root);
    expect(
      await runner.run(['approve', '--dry-run', _seen(root, 'feature:signup')]),
      64,
    );
  });
  group('a usage error', () {
    for (final (args, message) in [
      (['--json'], '--json goes only with --dry-run or --auto.'),
      (
        ['--yes', '--json', 'a@0123456789ab'],
        '--json goes only with --dry-run or --auto.',
      ),
      (
        ['--dry-run', '--json', '--context', '0'],
        '--json goes without --context.',
      ),
      (
        ['--dry-run', '--json', '--yes', 'a@0123456789ab'],
        '--dry-run goes without --yes.',
      ),
      (
        ['--dry-run', '--audit', 'audit.md'],
        '--audit goes only with --auto or --dry-run --json.',
      ),
      (
        ['--audit', 'audit.md'],
        '--audit goes only with --auto or --dry-run --json.',
      ),
      (['--author', 'author.md'], '--author and --no-audit need --auto.'),
      (['--no-audit'], '--author and --no-audit need --auto.'),
    ]) {
      test(
        'approve ${args.join(' ')} is a usage error, exit 64, and prints nothing',
        () async {
          final (:runner, :out, :err) = writeRunner(await writeWriteProject());

          expect(await runner.run(['approve', ...args]), 64);

          expect(out.toString(), isEmpty);
          expect(err.toString(), startsWith('$message\n'));
        },
      );
    }
    test('--json beside --auto is no usage error', () async {
      final root = await _draftsProject();
      final (:runner, :out, :err) = writeRunner(root);

      expect(
        await runner.run(['approve', _story, '--auto', '--no-audit', '--json']),
        0,
      );

      expect(err.toString(), isEmpty);
      expect((jsonDecode(out.toString()) as Map).keys, contains('approved'));
    });
  });
  group('--dry-run --json', () {
    test('--dry-run --json prints one object holding each draft and the count, the drafts and hashes its view prints', () async {
      final root = await writeWriteProject();
      var (:runner, :out, :err) = writeRunner(root);
      expect(await runner.run(['approve', 'login', '--dry-run']), 0);
      final view = out.toString();

      (:runner, :out, :err) = writeRunner(root);
      expect(await runner.run(['approve', 'login', '--dry-run', '--json']), 0);

      expect(err.toString(), isEmpty);
      final json = jsonDecode(out.toString()) as Map<String, Object?>;
      final drafts = (json['drafts']! as List).cast<Map<String, Object?>>();
      expect(json['count'], drafts.length);
      expect(drafts, isNotEmpty);
      expect('### Draft '.allMatches(view), hasLength(drafts.length));
      for (final draft in drafts) {
        expect(draft, contains('doc'));
        expect(draft, contains('dropped'));
        expect(draft, contains('new'));
        expect(view, contains('`${draft['base']}`'));
        expect(view, contains('`docs/${draft['path']}`'));
      }
    });
    test('approve --dry-run --json saves an audited copy and changes no doc', () async {
      final root = await writeWriteProject();
      final before = treeBytes(root);
      final (:runner, :out, :err) = writeRunner(root);
      expect(await runner.run(['approve', 'login', '--dry-run', '--json']), 0);

      final drafts = ((jsonDecode(out.toString()) as Map)['drafts']! as List)
          .cast<Map<String, Object?>>();
      expect(drafts, isNotEmpty);
      for (final draft in drafts) {
        final saved = File(
          '${root.path}/.specstone/audited/${draft['path']}/${draft['base']}.md',
        );
        expect(
          saved.readAsStringSync(),
          readDoc(root, draft['path']! as String),
        );
      }
      for (final MapEntry(:key, :value) in before.entries) {
        if (key.startsWith('docs/')) expect(treeBytes(root)[key], value);
      }
    });
    test('a dry-run JSON draft names its address as doc', () async {
      final root = await writeWriteProject();
      final (:runner, :out, :err) = writeRunner(root);
      expect(await runner.run(['approve', 'login', '--dry-run', '--json']), 0);

      final drafts = ((jsonDecode(out.toString()) as Map)['drafts']! as List)
          .cast<Map<String, Object?>>();
      expect(drafts[0]['doc'], isA<String>());
      expect(drafts[0].containsKey('name'), isFalse);
    });
    test('approve --yes takes the base the json dry run printed', () async {
      final root = await writeWriteProject();
      var (:runner, :out, :err) = writeRunner(root);
      expect(await runner.run(['approve', 'login', '--dry-run', '--json']), 0);
      final draft =
          ((jsonDecode(out.toString()) as Map)['drafts']! as List).first
              as Map<String, Object?>;

      (:runner, :out, :err) = writeRunner(root);
      expect(
        await runner.run([
          'approve',
          '${draft['doc']}@${draft['base']}',
          '--yes',
        ]),
        0,
        reason: err.toString(),
      );
    });
    test(
      'no draft in scope prints an empty list and a count of 0, exit 0',
      () async {
        final (:runner, :out, :err) = writeRunner(await writeWriteProject());

        expect(
          await runner.run([
            'approve',
            'architecture:login',
            '--dry-run',
            '--json',
          ]),
          0,
        );

        expect(jsonDecode(out.toString()), {
          'drafts': <Object>[],
          'count': 0,
          'warnings': <Object>[],
          'approveMode': 'ask',
        });
      },
    );
    test('--dry-run --json names the mode the console gives', () async {
      final (:runner, :out, :err) = writeRunner(
        await writeWriteProject(),
        console: FakeConsole(approveModeVariable: 'auto'),
      );

      expect(await runner.run(['approve', 'login', '--dry-run', '--json']), 0);

      final json = jsonDecode(out.toString()) as Map<String, Object?>;
      expect(json['approveMode'], 'auto');
      expect(json['warnings'], isEmpty);
    });
    test(
      '--dry-run --json with a near-miss value prints ask and its warning',
      () async {
        final (:runner, :out, :err) = writeRunner(
          await writeWriteProject(),
          console: FakeConsole(approveModeVariable: 'AUTO'),
        );

        expect(
          await runner.run(['approve', 'login', '--dry-run', '--json']),
          0,
        );

        final json = jsonDecode(out.toString()) as Map<String, Object?>;
        expect(json['approveMode'], 'ask');
        expect(json['warnings'], [
          'SPECSTONE_APPROVE_MODE=AUTO is neither ask nor auto; ask is used',
        ]);
      },
    );
    test('the plain --dry-run view neither warns nor names the mode', () async {
      final (:runner, :out, :err) = writeRunner(
        await writeWriteProject(),
        console: FakeConsole(approveModeVariable: 'yes'),
      );

      expect(await runner.run(['approve', 'login', '--dry-run']), 0);

      expect(err.toString(), isEmpty);
      expect(out.toString(), isNot(contains('approveMode')));
      expect(out.toString(), isNot(contains('SPECSTONE_APPROVE_MODE')));
    });
    test("roots awaiting the Owner's record refuse with exit 73 and the JSON error on stderr, and print no JSON", () async {
      final base = await writeTree({
        for (final MapEntry(:key, :value) in writeProject.entries)
          if (key.startsWith('docs/'))
            'ext/${key.substring(5)}': value
          else
            'src/clone/$key': value,
      });
      createRelativeLink('${base.path}/src/clone/docs', '../../ext');
      final (:runner, :out, :err) = writeRunner(
        Directory('${base.path}/src/clone'),
      );

      expect(await runner.run(['approve', '--dry-run', '--json']), 73);

      expect(out.toString(), isEmpty);
      expect(
        (jsonDecode(err.toString()) as Map)['error'],
        containsPair('code', 'output_not_writable'),
      );
    }, skip: Platform.isWindows ? 'a link needs a privilege on Windows' : null);
  });
  test(
    'a @<hash> without --yes on a non-terminal is a usage error, exit 64',
    () async {
      final root = await writeWriteProject();
      final (:runner, :out, :err) = writeRunner(root);
      final named = _seen(root, 'feature:signup');
      expect(await runner.run(['approve', named]), 64);
      expect(out.toString(), isEmpty);
      expect(
        err.toString(),
        startsWith('$named: a @<hash> goes only with --yes.\n'),
      );
    },
  );
  test('a doc path holding @ names the doc, so --dry-run reads it', () async {
    final root = await writeWriteProject(
      extra: {'docs/prds/a@b.md': '---\ndraft: true\n---\n\n# A\n'},
    );
    final (:runner, :out, :err) = writeRunner(root);
    expect(await runner.run(['approve', 'prds/a@b.md', '--dry-run']), 0);
    expect(err.toString(), isEmpty);
    expect(out.toString(), 'no draft waits for approval\n');
  });
  test(
    '--yes on a doc path holding @ names the doc and asks for the hash',
    () async {
      const name = 'prds/a@0123456789ab.md';
      final root = await writeWriteProject(
        extra: {'docs/$name': '---\ndraft: true\n---\n\n# A\n'},
      );
      final (:runner, :out, :err) = writeRunner(root);
      expect(await runner.run(['approve', name, '--yes']), 64);
      expect(
        err.toString(),
        startsWith(
          '--yes needs each draft as <name>@<hash>, the hash from '
          'docs[0].base of specstone get <name> --json; got $name.\n',
        ),
      );
    },
  );
  test('--context rules', () async {
    final root = await writeWriteProject();
    final seen = _seen(root, 'feature:signup');
    var (:runner, :out, :err) = writeRunner(root);
    expect(await runner.run(['approve', '--yes', '--context', '3', seen]), 64);
    expect(err.toString(), contains('--context goes without --yes.'));
    for (final bad in ['-1', 'x']) {
      (:runner, :out, :err) = writeRunner(root);
      expect(await runner.run(['approve', '--dry-run', '--context', bad]), 64);
      expect(
        err.toString(),
        contains('--context takes a whole number from 0.'),
      );
    }
    (:runner, :out, :err) = writeRunner(root);
    expect(await runner.run(['approve', '--dry-run', '--context', '0']), 0);
  });
  test('the walk colours at a terminal unless NO_COLOR', () async {
    final root = await writeWriteProject();
    var (:runner, :out, :err) = writeRunner(
      root,
      console: FakeConsole(
        stdinIsTerminal: true,
        stdoutIsTerminal: true,
        answers: ['n'],
      ),
    );
    expect(await runner.run(['approve', 'signup']), 0);
    expect(out.toString(), contains('\x1b[32m+'));
    (:runner, :out, :err) = writeRunner(
      root,
      console: FakeConsole(
        stdinIsTerminal: true,
        stdoutIsTerminal: true,
        noColor: true,
        answers: ['n'],
      ),
    );
    expect(await runner.run(['approve', 'signup']), 0);
    expect(out.toString(), isNot(contains('\x1b[')));
  });
  test('--yes with a bad --context reports --yes first', () async {
    final root = await writeWriteProject();
    final (:runner, :out, :err) = writeRunner(root);
    expect(
      await runner.run([
        'approve',
        '--yes',
        '--context',
        'x',
        _seen(root, 'feature:signup'),
      ]),
      64,
    );
    expect(err.toString(), contains('--context goes without --yes.'));
  });
  test('dry run colours at a terminal unless NO_COLOR', () async {
    final root = await writeWriteProject();
    var (:runner, :out, :err) = writeRunner(
      root,
      console: FakeConsole(stdoutIsTerminal: true),
    );
    expect(await runner.run(['approve', '--dry-run']), 0);
    expect(out.toString(), contains('\x1b['));
    (:runner, :out, :err) = writeRunner(
      root,
      console: FakeConsole(stdoutIsTerminal: true, noColor: true),
    );
    expect(await runner.run(['approve', '--dry-run']), 0);
    expect(out.toString(), isNot(contains('\x1b[')));
  });
  test('--dry-run on a layout-only draft shows no change', () async {
    const compact =
        '| Component | Responsibility |\n|---|---|\n| Signup form | Collects the email |\n';
    const padded =
        '| Component   | Responsibility |\n|-------------|----------------|\n| Signup form | Collects the email |\n';
    String arch(String mark, String table) =>
        '---\n$mark---\n\n# Signup architecture\n\n## Components\n\n$table';
    final root = await writeWriteProject(
      extra: {'docs/$signupArch': arch('approved: true\n', compact)},
    );
    expect(git(root, ['init', '-q']).exitCode, 0);
    expect(git(root, ['config', 'core.autocrlf', 'false']).exitCode, 0);
    commitAll(root, 'approved');
    File('${root.path}/docs/$signupArch')
        .writeAsStringSync(arch('draft: true\n', padded));
    commitAll(root, 'padded as a draft');
    final (:runner, :out, :err) = writeRunner(root);
    expect(
      await runner.run(['approve', '--dry-run', 'architecture:signup']),
      0,
    );
    expect(out.toString(), contains('| changes | none |'));
    expect(out.toString(), contains('no change since the approved copy'));
  });
  test('--dry-run lists the sentence dropped and the one new, and not the one moved', () async {
    String story(String mark, String useCase) =>
        '---\nstatus: planned\n$mark---\n\n# Sign out\n\n## Use Case\n\n'
        '$useCase\n\n## Acceptance Criteria\n\n- **Given** a signed-in user\n';
    final root = await writeWriteProject(
      extra: {
        'docs/$story2': story(
          'approved: true\n',
          'Sign out. Clears the cookie. Ends the session.',
        ),
      },
    );
    expect(git(root, ['init', '-q']).exitCode, 0);
    expect(git(root, ['config', 'core.autocrlf', 'false']).exitCode, 0);
    commitAll(root, 'approved');
    File('${root.path}/docs/$story2')
        .writeAsStringSync(story('draft: true\n', 'Sign out. Warns the user.'));
    File('${root.path}/docs/prds/d01_context.md').writeAsStringSync(
      '# Context\n\n## Features\n'
      'See [signup](features/f02_signup/FEATURE.md). Ends the session.\n',
    );
    commitAll(root, 'edited as a draft');
    final (:runner, :out, :err) = writeRunner(root);

    expect(
      await runner.run(['approve', '--dry-run', 'user_story:login/sign_out']),
      0,
    );

    expect(out.toString(), contains('| dropped | 1 sentence dropped |\n'));
    expect(out.toString(), contains('| new     | 1 sentence new |\n'));
    expect(
      out.toString(),
      endsWith(
        '\n```\n\nDropped sentences:\n- Clears the cookie.\n\n'
        'New sentences:\n- Warns the user.\n',
      ),
    );
    expect(out.toString(), isNot(contains('- Ends the session.')));
  });
  test('--dry-run compares an approval left uncommitted, not the last committed one', () async {
    String story(String mark, String useCase) =>
        '---\nstatus: planned\n$mark---\n\n# Sign out\n\n## Use Case\n\n'
        '$useCase\n\n## Acceptance Criteria\n\n- **Given** a signed-in user\n';
    final root = await writeWriteProject(
      extra: {
        'docs/$story2': story(
          'approved: true\n',
          'Sign out. Ends the session.',
        ),
      },
    );
    expect(git(root, ['init', '-q']).exitCode, 0);
    expect(git(root, ['config', 'core.autocrlf', 'false']).exitCode, 0);
    commitAll(root, 'approved');
    final file = File('${root.path}/docs/$story2')
      ..writeAsStringSync(
        story('draft: true\n', 'Sign out. Ends the session. Keeps the cart.'),
      );
    final approve = writeRunner(root);
    expect(
      await approve.runner.run([
        'approve',
        '--yes',
        _seen(root, 'user_story:login/sign_out'),
      ]),
      0,
      reason: approve.err.toString(),
    );
    file.writeAsStringSync(
      file
          .readAsStringSync()
          .replaceFirst(
            '\n---\n\n# Sign out',
            '\ndraft: true\n---\n\n# Sign out',
          )
          .replaceFirst('Keeps the cart.', 'Keeps the cart. Warns the user.'),
    );
    final (:runner, :out, :err) = writeRunner(root);

    expect(
      await runner.run(['approve', '--dry-run', 'user_story:login/sign_out']),
      0,
    );

    expect(
      out.toString(),
      contains('| old     | approved copy not yet committed |\n'),
    );
    expect(out.toString(), contains('| dropped | 0 sentences dropped |\n'));
    expect(out.toString(), contains('| new     | 1 sentence new |\n'));
    expect(out.toString(), endsWith('\nNew sentences:\n- Warns the user.\n'));
  });
  test('--dry-run lists removed items held only in frontmatter or inside a longer sentence', () async {
    String story(String mark, String useCase) =>
        '---\nstatus: planned\n$mark---\n\n# Sign out\n\n## Use Case\n\n'
        '$useCase\n\n## Acceptance Criteria\n\n- **Given** a signed-in user\n';
    final root = await writeWriteProject(
      extra: {
        'docs/$story2': story(
          'approved: true\n',
          '- lib/core.dart\n- ci.yaml\n- Signs the user out.',
        ),
      },
    );
    expect(git(root, ['init', '-q']).exitCode, 0);
    expect(git(root, ['config', 'core.autocrlf', 'false']).exitCode, 0);
    commitAll(root, 'approved');
    File('${root.path}/docs/$story2')
        .writeAsStringSync(story('draft: true\n', '- Signs the user out.'));
    File('${root.path}/docs/notes.md').writeAsStringSync(
      '---\ncovers:\n  - lib/core.dart\n---\n\n# Notes\n\n'
      'Run `ci.yaml` on each push.\n',
    );
    commitAll(root, 'edited as a draft');
    final (:runner, :out, :err) = writeRunner(root);

    expect(
      await runner.run(['approve', '--dry-run', 'user_story:login/sign_out']),
      0,
    );

    expect(out.toString(), contains('| dropped | 2 sentences dropped |\n'));
    expect(out.toString(), contains('| new     | 0 sentences new |\n'));
    expect(
      out.toString(),
      endsWith('\n```\n\nDropped sentences:\n- lib/core.dart\n- ci.yaml\n'),
    );
  });
  group('--context reaches the view', () {
    Future<Directory> editedDraft() async {
      final root = await writeWriteProject(
        extra: {
          'docs/$signupFeature': '---\napproved: true\n---\n\n# Signup\n\n## Problem\nUsers create an account.\nThey stay signed in.\n',
        },
      );
      expect(git(root, ['init', '-q']).exitCode, 0);
      expect(git(root, ['config', 'core.autocrlf', 'false']).exitCode, 0);
      commitAll(root, 'approved');
      File('${root.path}/docs/$signupFeature').writeAsStringSync(
        '---\ndraft: true\n---\n\n# Signup\n\n## Problem\nUsers sign up.\nThey stay signed in.\n',
      );
      commitAll(root, 'edited as a draft');
      return root;
    }

    const kept = ' They stay signed in.';
    test(
      '--dry-run shows the unchanged line by default, not at --context 0',
      () async {
        final root = await editedDraft();
        var (:runner, :out, :err) = writeRunner(root);
        expect(await runner.run(['approve', '--dry-run', 'feature:signup']), 0);
        expect(out.toString(), contains(kept));
        (:runner, :out, :err) = writeRunner(root);
        expect(
          await runner.run([
            'approve',
            '--dry-run',
            '--context',
            '0',
            'feature:signup',
          ]),
          0,
        );
        expect(out.toString(), contains('+Users sign up.'));
        expect(out.toString(), isNot(contains(kept)));
      },
    );
    test(
      'the walk shows the unchanged line by default, not at --context 0',
      () async {
        final root = await editedDraft();
        for (final (args, shown) in [
          (<String>[], true),
          (['--context', '0'], false),
        ]) {
          final (:runner, :out, :err) = writeRunner(
            root,
            console: FakeConsole(
              stdinIsTerminal: true,
              stdoutIsTerminal: true,
              noColor: true,
              answers: ['n'],
            ),
          );
          expect(await runner.run(['approve', ...args, 'feature:signup']), 0);
          expect(out.toString(), contains('+Users sign up.'));
          expect(out.toString().contains(kept), shown);
        }
      },
    );
  });

  group('what awaits approval, through the built CLI', () {
    late String binary;
    setUpAll(() async {
      binary = await buildSpecstone();
    });

    Future<ProcessResult> run(Directory root, List<String> args) =>
        runSpecstone(binary, args, workingDirectory: root.path);

    String editedStory(String text) =>
        text.replaceFirst('Sign out.\n', 'Sign out of every device.\n');

    test('the process environment sets the mode', () async {
      final root = await writeWriteProject();
      final shown = await runSpecstone(
        binary,
        ['approve', 'login', '--dry-run', '--json'],
        workingDirectory: root.path,
        environment: {'SPECSTONE_APPROVE_MODE': 'auto'},
      );
      expect(shown.exitCode, 0, reason: '${shown.stderr}');
      final json = jsonDecode(shown.stdout as String) as Map<String, Object?>;
      expect(json['approveMode'], 'auto');
    });

    test('an approved story edited in an editor is walked, its view showing the edit', () async {
      final root = await writeWriteProject();
      File('${root.path}/docs/$story2').writeAsStringSync(
        editedStory(File('${root.path}/docs/$story2').readAsStringSync()),
      );
      final shown = await run(root, ['approve', '--dry-run']);
      expect(shown.exitCode, 0, reason: '${shown.stderr}');
      expect(shown.stdout, contains('`docs/$story2`'));
      expect(shown.stdout, contains('+Sign out of every device.'));
    });

    test(
      'a layout change keeps the approval, so the story is not walked',
      () async {
        final root = await writeWriteProject();
        final arch = File('${root.path}/docs/$loginArch');
        arch.writeAsStringSync(
          arch.readAsStringSync().replaceFirst(
            '| Component | Responsibility |\n|---|---|\n| Login form | Collects the email and the password |\n',
            '| Component  | Responsibility                       |\n|------------|--------------------------------------|\n| Login form | Collects the email and the password  |\n',
          ),
        );
        final shown = await run(root, ['approve', '--dry-run']);
        expect(shown.exitCode, 0, reason: '${shown.stderr}');
        expect(shown.stdout, isNot(contains('`docs/$loginArch`')));
      },
    );

    test('a story made in an editor with neither mark is walked, and its approval writes the hash', () async {
      const made = '# Reset password\n\n## Use Case\n\nReset a password.\n';
      final root = await writeWriteProject(extra: {'docs/$story3': made});
      final shown = await run(root, ['approve', '--dry-run']);
      expect(shown.stdout, contains('`docs/$story3`'));
      final hash = RegExp(r'\| hash +\| `([0-9a-f]{12})`').firstMatch(
        (await run(root, [
              'approve',
              '--dry-run',
              'user_story:login/reset_password',
            ])).stdout
            as String,
      );
      expect(hash, isNotNull);
      final approved = await run(root, [
        'approve',
        'user_story:login/reset_password@${hash!.group(1)}',
        '--yes',
      ]);
      expect(approved.exitCode, 0, reason: '${approved.stderr}');
      final text = File('${root.path}/docs/$story3').readAsStringSync();
      expect(text, matches(RegExp(r'^---\napproved: "[0-9a-f]{12}"\n---\n')));
      expect(text, isNot(contains('draft:')));
      final after = await run(root, [
        'approve',
        '--dry-run',
        'user_story:login/reset_password',
      ]);
      expect(after.stdout, isNot(contains('`docs/$story3`')));
    });

    test("--dry-run shows the changes against the project's own committed copy under an exported GIT_INDEX_FILE and GIT_DIR", () async {
      final root = await writeWriteProject(
        extra: {
          'docs/$signupFeature': '---\napproved: true\n---\n\n# Signup\n\n## Problem\nUsers create an account.\nThey stay signed in.\n',
        },
      );
      expect(git(root, ['init', '-q']).exitCode, 0);
      expect(git(root, ['config', 'core.autocrlf', 'false']).exitCode, 0);
      commitAll(root, 'approved');
      File('${root.path}/docs/$signupFeature').writeAsStringSync(
        '---\ndraft: true\n---\n\n# Signup\n\n## Problem\nUsers sign up.\nThey stay signed in.\n',
      );
      commitAll(root, 'edited as a draft');
      final other = await writeTree({'elsewhere.txt': 'another repository\n'});
      expect(git(other, ['init', '-q']).exitCode, 0);
      final junkIndex = File('${other.path}/junk-index')
        ..writeAsStringSync('not an index\n');
      const args = ['approve', '--dry-run', 'feature:signup'];

      final plain = await run(root, args);
      final exported = await runSpecstone(
        binary,
        args,
        workingDirectory: root.path,
        environment: {
          'GIT_INDEX_FILE': junkIndex.path,
          'GIT_DIR': '${other.path}/.git',
        },
      );

      expect(plain.exitCode, 0, reason: '${plain.stderr}');
      expect(plain.stdout, contains('+Users sign up.'));
      expect(exported.exitCode, 0, reason: '${exported.stderr}');
      expect(exported.stdout, plain.stdout);
    }, skip: hasGit ? null : 'git is not available');
  });

  group('with two code targets', () {
    const draft = '---\ndraft: true\n---\n\n# Login architecture\n';

    Future<Directory> twinDrafts() => writeTwinProject(
      extra: {
        'docs/$flutterArchitecture': draft,
        'docs/$jasprArchitecture': draft,
      },
    );

    test(
      'approve --dry-run --target jaspr --json lists the jaspr draft only',
      () async {
        final (:runner, :out, :err) = writeRunner(await twinDrafts());
        expect(
          await runner.run([
            'approve',
            '--dry-run',
            '--target',
            'jaspr',
            '--json',
          ]),
          0,
          reason: err.toString(),
        );
        final drafts = (jsonDecode(out.toString()) as Map)['drafts']! as List;
        expect(
          [for (final d in drafts) (d as Map)['path']],
          [jasprArchitecture],
        );
      },
    );

    test('--yes --target flutter approves the flutter twin and leaves the jaspr twin a draft', () async {
      final root = await twinDrafts();
      final hash = getDoc(root, flutterArchitecture)['base'];
      final (:runner, :out, :err) = writeRunner(root);
      expect(
        await runner.run([
          'approve',
          'architecture:login@$hash',
          '--yes',
          '--target',
          'flutter',
        ]),
        0,
        reason: err.toString(),
      );
      expect(out.toString(), 'approved architecture:login\n');
      expect(
        readDoc(root, flutterArchitecture),
        isNot(contains('draft: true')),
      );
      expect(readDoc(root, jasprArchitecture), contains('draft: true'));
    });

    test(
      'at a terminal, y under --target jaspr approves that twin only',
      () async {
        final root = await twinDrafts();
        final (:runner, :out, :err) = writeRunner(
          root,
          console: FakeConsole(
            stdinIsTerminal: true,
            stdoutIsTerminal: true,
            answers: ['y'],
          ),
        );
        expect(
          await runner.run([
            'approve',
            'architecture:login',
            '--target',
            'jaspr',
          ]),
          0,
          reason: err.toString(),
        );
        expect('approve? [y/n/q] '.allMatches(out.toString()), hasLength(1));
        expect(
          readDoc(root, jasprArchitecture),
          matches(RegExp('approved: "[0-9a-f]{12}"')),
        );
        expect(readDoc(root, flutterArchitecture), contains('draft: true'));
      },
    );

    test('--yes on a name two targets share, with no --target, exits 64 listing both docs', () async {
      final root = await twinDrafts();
      final (:runner, :out, :err) = writeRunner(root);
      expect(
        await runner.run([
          'approve',
          'architecture:login@000000000000',
          '--yes',
        ]),
        64,
      );
      expect(
        err.toString(),
        'architecture:login names 2 docs: '
        '$flutterArchitecture, $jasprArchitecture\n',
      );
      expect(readDoc(root, flutterArchitecture), contains('draft: true'));
      expect(readDoc(root, jasprArchitecture), contains('draft: true'));
    });

    test('--target with no value exits 64 naming the targets', () async {
      final (:runner, :out, :err) = writeRunner(
        await twinDrafts(),
        console: FakeConsole(stdinIsTerminal: true, stdoutIsTerminal: true),
      );
      expect(await runner.run(['approve', '--dry-run', '--target']), 64);
      expect(
        err.toString(),
        '--target needs a code target name: the code targets are flutter, jaspr\n',
      );
    });
  });
  group('a draft named by the end of its name', () {
    Future<Directory> shop() => writeNestedProject(
      extra: {
        'docs/$cartFeature': '---\ndraft: true\nvision:\n  - PV-01\n---\n\n# Cart\n\n## Problem\nShoppers need it.\n',
      },
    );
    test('approve takes a unique suffix as it takes the full name', () async {
      final byFull = await shop();
      final full = writeRunner(byFull);
      expect(
        await full.runner.run([
          'approve',
          _seen(byFull, 'feature:shop/cart'),
          '--yes',
        ]),
        0,
      );
      final bySuffix = await shop();
      final hash = getDoc(bySuffix, 'feature:shop/cart')['base'];
      final short = writeRunner(bySuffix);
      expect(
        await short.runner.run(['approve', 'feature:cart@$hash', '--yes']),
        0,
      );
      expect(short.out.toString(), full.out.toString());
      expect(short.err.toString(), full.err.toString());
    });
    test('approve refuses a suffix of no identity, naming it', () async {
      final root = await shop();
      final (:runner, :out, :err) = writeRunner(root);
      expect(
        await runner.run(['approve', 'feature:art@000000000000', '--yes']),
        64,
      );
      expect(out.toString(), isEmpty);
      expect(err.toString(), 'no feature doc carries the name art\n');
    });
  });

  group('approve edge cases', () {
    const terminal = (stdin: true, stdout: true);
    const trustMessage =
        'lies outside the project; '
        'run specstone trust at a terminal to allow it\n';

    FakeConsole walkConsole({List<String?> answers = const []}) => FakeConsole(
      stdinIsTerminal: terminal.stdin,
      stdoutIsTerminal: terminal.stdout,
      noColor: true,
      answers: answers,
    );

    Future<({Directory clone, Directory docs})> awaitingTrust() async {
      final base = await writeTree({
        for (final MapEntry(:key, :value) in writeProject.entries)
          if (key.startsWith('docs/'))
            'ext/${key.substring(5)}': value
          else
            'src/clone/$key': value,
      });
      createRelativeLink('${base.path}/src/clone/docs', '../../ext');
      return (
        clone: Directory('${base.path}/src/clone'),
        docs: Directory('${base.path}/ext'),
      );
    }

    const approvedText =
        '---\napproved: true\n---\n\n# Signup\n\n## Problem\n'
        'Line one.\nLine two.\nLine three.\nLine four.\nLine five.\n'
        'Line six.\nLine seven.\n';
    const editedText =
        '---\ndraft: true\n---\n\n# Signup\n\n## Problem\n'
        'Line one.\nLine two.\nLine three.\nLine 4 changed.\nLine five.\n'
        'Line six.\nLine seven.\n';

    Future<Directory> editedFeature() async {
      final root = await writeWriteProject(
        extra: {'docs/$signupFeature': approvedText},
      );
      expect(git(root, ['init', '-q']).exitCode, 0);
      expect(git(root, ['config', 'core.autocrlf', 'false']).exitCode, 0);
      commitAll(root, 'approved');
      File('${root.path}/docs/$signupFeature').writeAsStringSync(editedText);
      commitAll(root, 'edited as a draft');
      return root;
    }

    test('at a terminal with no draft in scope the walk prints the no-draft line and exits 0', () async {
      final (:runner, :out, :err) = writeRunner(
        await writeWriteProject(),
        console: walkConsole(),
      );
      expect(await runner.run(['approve', 'architecture:login']), 0);
      expect(out.toString(), 'no draft waits for approval\n');
      expect(err.toString(), isEmpty);
    });

    test('a terminal on stdout alone, or on neither, is refused with exit 77 and no file changes', () async {
      final root = await writeWriteProject();
      final docs = Directory('${root.path}/docs');
      final before = treeBytes(docs);
      for (final console in [
        FakeConsole(),
        FakeConsole(stdoutIsTerminal: true),
      ]) {
        final (:runner, :out, :err) = writeRunner(root, console: console);
        expect(await runner.run(['approve']), 77);
        expect(out.toString(), isEmpty);
        expect(
          err.toString(),
          "approve runs only at an interactive terminal, or with --yes after the Owner's ok in the chat\n",
        );
        expect(treeBytes(docs), before);
      }
    });

    test('at a terminal a name no doc carries exits 64 naming it and shows nothing', () async {
      final root = await writeWriteProject();
      for (final (name, message) in [
        ('nosuch', 'no doc carries the name nosuch\n'),
        ('feature:nosuch', 'no feature doc carries the name nosuch\n'),
      ]) {
        final (:runner, :out, :err) = writeRunner(
          root,
          console: walkConsole(answers: ['y']),
        );
        expect(await runner.run(['approve', name]), 64, reason: name);
        expect(out.toString(), isEmpty, reason: name);
        expect(err.toString(), message, reason: name);
      }
    });

    test('at a terminal a name written with @<hash> is a usage error that leaves every doc as it was', () async {
      final root = await writeWriteProject();
      final docs = Directory('${root.path}/docs');
      final before = treeBytes(docs);
      final named = _seen(root, 'feature:signup');
      final (:runner, :out, :err) = writeRunner(
        root,
        console: walkConsole(answers: ['y', 'y']),
      );
      expect(await runner.run(['approve', named]), 64);
      expect(out.toString(), isEmpty);
      expect(
        err.toString(),
        startsWith('$named: a @<hash> goes only with --yes.\n'),
      );
      expect(treeBytes(docs), before);
    });

    group('roots awaiting the trust record', () {
      void expectRefusedAt(String err, String path) {
        expect(err, startsWith('$path: cannot write $path: the docs folder '));
        expect(err, endsWith(trustMessage));
      }

      const firstDraft =
          'docs/prds/features/f01_login/us01_email_login/USER_STORY.md';

      test(
        'the walk at a terminal refuses with exit 73 naming the first draft before it shows anything',
        () async {
          final (:clone, :docs) = await awaitingTrust();
          final before = treeBytes(docs);
          final (:runner, :out, :err) = writeRunner(
            clone,
            console: walkConsole(answers: ['y']),
          );
          expect(await runner.run(['approve']), 73);
          expect(out.toString(), isEmpty);
          expectRefusedAt(err.toString(), firstDraft);
          expect(treeBytes(docs), before);
        },
        skip: Platform.isWindows ? 'a link needs a privilege on Windows' : null,
      );

      test(
        'the walk at a terminal with no draft in scope prints the no-draft line and exits 0',
        () async {
          final (:clone, docs: _) = await awaitingTrust();
          final (:runner, :out, :err) = writeRunner(
            clone,
            console: walkConsole(),
          );
          expect(await runner.run(['approve', 'architecture:login']), 0);
          expect(out.toString(), 'no draft waits for approval\n');
          expect(err.toString(), isEmpty);
        },
        skip: Platform.isWindows ? 'a link needs a privilege on Windows' : null,
      );

      test(
        '--yes refuses with exit 73 at its first write and approves nothing',
        () async {
          final (:clone, :docs) = await awaitingTrust();
          final before = treeBytes(docs);
          final (:runner, :out, :err) = writeRunner(clone);
          expect(
            await runner.run([
              'approve',
              _seen(clone, 'feature:signup'),
              '--yes',
            ]),
            73,
          );
          expect(out.toString(), isEmpty);
          expectRefusedAt(
            err.toString(),
            'docs/prds/features/f02_signup/FEATURE.md',
          );
          expect(treeBytes(docs), before);
        },
        skip: Platform.isWindows ? 'a link needs a privilege on Windows' : null,
      );

      test(
        '--dry-run with a draft in scope refuses with exit 73 naming the first draft and prints no view',
        () async {
          final (:clone, docs: _) = await awaitingTrust();
          final (:runner, :out, :err) = writeRunner(clone);
          expect(await runner.run(['approve', '--dry-run']), 73);
          expect(out.toString(), isEmpty);
          expectRefusedAt(err.toString(), firstDraft);
        },
        skip: Platform.isWindows ? 'a link needs a privilege on Windows' : null,
      );

      test(
        '--dry-run with no draft in scope prints the no-draft line and exits 0',
        () async {
          final (:clone, docs: _) = await awaitingTrust();
          final (:runner, :out, :err) = writeRunner(clone);
          expect(
            await runner.run(['approve', '--dry-run', 'architecture:login']),
            0,
          );
          expect(out.toString(), 'no draft waits for approval\n');
          expect(err.toString(), isEmpty);
        },
        skip: Platform.isWindows ? 'a link needs a privilege on Windows' : null,
      );
    });

    test('--yes with a hash of uppercase hex or the wrong length is the usage error naming the argument', () async {
      final root = await writeWriteProject();
      final docs = Directory('${root.path}/docs');
      final before = treeBytes(docs);
      for (final argument in [
        'feature:signup@ABCDEF012345',
        'feature:signup@abc',
        'feature:signup@0123456789abcd',
      ]) {
        final (:runner, :out, :err) = writeRunner(root);
        expect(await runner.run(['approve', argument, '--yes']), 64);
        expect(out.toString(), isEmpty, reason: argument);
        expect(
          err.toString(),
          startsWith(
            '--yes needs each draft as <name>@<hash>, the hash from '
            'docs[0].base of specstone get <name> --json; got '
            '$argument.\n',
          ),
          reason: argument,
        );
        expect(treeBytes(docs), before, reason: argument);
      }
    });

    test('--yes on an untyped doc named with its hash exits 64 as untyped and approves nothing', () async {
      final root = await writeWriteProject(
        extra: {'docs/prds/notes.md': '---\ndraft: true\n---\n\n# Notes\n'},
      );
      final docs = Directory('${root.path}/docs');
      final before = treeBytes(docs);
      final (:runner, :out, :err) = writeRunner(root);
      expect(
        await runner.run([
          'approve',
          _seen(root, 'feature:signup'),
          'prds/notes.md@000000000000',
          '--yes',
        ]),
        64,
      );
      expect(out.toString(), isEmpty);
      expect(
        err.toString(),
        'prds/notes.md has no doc type; migrate it to one before a write\n',
      );
      expect(treeBytes(docs), before);
    });

    test('--dry-run on a name written with @<hash> prints nothing on stdout and gives the usage error', () async {
      final root = await writeWriteProject();
      final named = _seen(root, 'feature:signup');
      final (:runner, :out, :err) = writeRunner(root);
      expect(await runner.run(['approve', '--dry-run', named]), 64);
      expect(out.toString(), isEmpty);
      expect(
        err.toString(),
        startsWith('$named: a @<hash> goes only with --yes.\n'),
      );
    });

    test('a name no doc carries, written with @<hash> and no --yes, is the usage error and not a missing doc', () async {
      final (:runner, :out, :err) = writeRunner(await writeWriteProject());
      expect(await runner.run(['approve', 'feature:nosuch@000000000000']), 64);
      expect(out.toString(), isEmpty);
      expect(
        err.toString(),
        startsWith(
          'feature:nosuch@000000000000: a @<hash> goes only with --yes.\n',
        ),
      );
      expect(err.toString(), isNot(contains('no feature doc carries')));
    });

    test(
      '--dry-run --context n shows n unchanged lines either side of the change',
      () async {
        final root = await editedFeature();
        for (final (n, shown, hidden) in [
          (1, ['Line three.', 'Line five.'], ['Line two.', 'Line six.']),
          (2, ['Line two.', 'Line six.'], ['Line one.', 'Line seven.']),
        ]) {
          final (:runner, :out, :err) = writeRunner(root);
          expect(
            await runner.run([
              'approve',
              '--dry-run',
              '--context',
              '$n',
              'feature:signup',
            ]),
            0,
          );
          final diff = RegExp(
            r'```diff\n(.*?)```',
            dotAll: true,
          ).firstMatch(out.toString())!.group(1)!;
          expect(
            diff,
            contains('-Line four.\n+Line 4 changed.\n'),
            reason: '$n',
          );
          for (final line in shown) {
            expect(diff, contains(' $line\n'), reason: '$n $line');
          }
          for (final line in hidden) {
            expect(diff, isNot(contains(line)), reason: '$n $line');
          }
        }
      },
    );

    test('--context moves only the diff, never the dropped and new rows or sentence lists', () async {
      final root = await editedFeature();
      String stripped(String view) =>
          view.replaceAll(RegExp(r'```diff\n.*?```\n', dotAll: true), '');

      Future<String> viewOf(List<String> contextArgs) async {
        final (:runner, :out, :err) = writeRunner(root);
        expect(
          await runner.run([
            'approve',
            '--dry-run',
            ...contextArgs,
            'feature:signup',
          ]),
          0,
        );
        return stripped(out.toString());
      }

      final plain = await viewOf([]);
      expect(plain, contains('| dropped | 1 sentence dropped |\n'));
      expect(plain, contains('| new     | 1 sentence new |\n'));
      expect(plain, contains('Dropped sentences:\n- Line four.\n'));
      expect(plain, contains('New sentences:\n- Line 4 changed.\n'));
      expect(await viewOf(['--context', '0']), plain);
      expect(await viewOf(['--context', '1']), plain);
    });

    test('--dry-run --json lists, per draft, the dropped and new sentences its view prints', () async {
      final root = await editedFeature();
      var (:runner, :out, :err) = writeRunner(root);
      expect(await runner.run(['approve', '--dry-run', 'feature:signup']), 0);
      final blocks = out.toString().split('### Draft ').skip(1).toList();

      (:runner, :out, :err) = writeRunner(root);
      expect(
        await runner.run(['approve', '--dry-run', '--json', 'feature:signup']),
        0,
      );
      final drafts = ((jsonDecode(out.toString()) as Map)['drafts']! as List)
          .cast<Map<String, Object?>>();

      List<String> listed(String block, String heading) {
        final start = block.indexOf('$heading sentences:\n');
        if (start < 0) return const [];
        return [
          for (final line
              in block
                  .substring(start)
                  .split('\n')
                  .skip(1)
                  .takeWhile((line) => line.startsWith('- ')))
            line.substring(2),
        ];
      }

      expect(drafts, hasLength(blocks.length));
      expect(drafts.first['dropped'], ['Line four.']);
      expect(drafts.first['new'], ['Line 4 changed.']);
      for (final (i, draft) in drafts.indexed) {
        expect(draft['dropped'], listed(blocks[i], 'Dropped'), reason: '$i');
        expect(draft['new'], listed(blocks[i], 'New'), reason: '$i');
      }
    });

    test('the walk and the other commands neither read the approve mode variable nor print the mode', () async {
      final root = await writeWriteProject();
      for (final value in ['auto', 'yes']) {
        var (:runner, :out, :err) = writeRunner(
          root,
          console: FakeConsole(
            stdinIsTerminal: terminal.stdin,
            stdoutIsTerminal: terminal.stdout,
            noColor: true,
            approveModeVariable: value,
            answers: ['q'],
          ),
        );
        expect(await runner.run(['approve', 'signup']), 0);
        final walked = out.toString();
        expect(err.toString(), isEmpty);
        expect(walked, contains('### Draft 1/'));
        expect(walked, isNot(contains('approveMode')));
        expect(walked, isNot(contains('SPECSTONE_APPROVE_MODE')));

        (:runner, :out, :err) = writeRunner(
          root,
          console: FakeConsole(approveModeVariable: value),
        );
        expect(await runner.run(['list', 'feature']), 0);
        expect(err.toString(), isEmpty);
        expect(out.toString(), isNot(contains('approveMode')));
        expect(out.toString(), isNot(contains('SPECSTONE_APPROVE_MODE')));

        (:runner, :out, :err) = writeRunner(
          root,
          console: FakeConsole(approveModeVariable: value),
        );
        expect(await runner.run(['approve', '--dry-run', 'feature:signup']), 0);
        expect(err.toString(), isEmpty);
        expect(out.toString(), contains('### Draft 1/'));
        expect(out.toString(), isNot(contains('approveMode')));
        expect(out.toString(), isNot(contains('SPECSTONE_APPROVE_MODE')));
      }
    });

    test('--yes under the auto mode prints no mode line', () async {
      final root = await writeWriteProject();
      final (:runner, :out, :err) = writeRunner(
        root,
        console: FakeConsole(approveModeVariable: 'auto'),
      );

      expect(
        await runner.run(['approve', _seen(root, 'feature:signup'), '--yes']),
        0,
      );

      expect(err.toString(), isEmpty);
      expect(out.toString(), 'approved feature:signup\n');
    });

    test('the prompt holds no write lock, so another write lands while the Owner reads and the approval then acts', () async {
      final root = await writeWriteProject();
      final base = getDoc(root, 'feature:signup#problem')['base']! as String;
      final console = FakeConsole(
        stdinIsTerminal: terminal.stdin,
        stdoutIsTerminal: terminal.stdout,
        noColor: true,
        answers: ['y', 'y', 'q'],
        onReadLine: (call) {
          if (call != 0) return;
          writeIn(
            root,
            (session) => answerSet(
              session,
              SetRequest.parse('feature:signup#problem', base: base),
              'Users sign up.\n',
            ),
            busyTimeout: const Duration(milliseconds: 200),
          );
        },
      );
      final (:runner, :out, :err) = writeRunner(root, console: console);

      expect(await runner.run(['approve', 'feature:signup']), 0);

      expect(err.toString(), isEmpty);
      final text = File('${root.path}/docs/$signupFeature').readAsStringSync();
      expect(text, contains('Users sign up.\n'));
      expect(text, matches(RegExp(r'\napproved: "[0-9a-f]{12}"\n')));
      expect(text, isNot(contains('draft: true')));
    });
  });

  group('--auto', () {
    late String binary;
    setUpAll(() async {
      binary = await buildSpecstone();
    });

    Future<ProcessResult> run(
      Directory root,
      List<String> args, {
      String? mode = 'auto',
      Directory? from,
    }) => runSpecstone(
      binary,
      ['approve', ...args],
      workingDirectory: (from ?? root).path,
      environment: {'SPECSTONE_APPROVE_MODE': ?mode},
    );

    test('auto call with a clean draft and a draft with a finding', () async {
      final root = await _draftsProject(frHasFinding: true);
      final audit = _writeAudit(root, [_story, _fr]);

      final result = await run(root, [_story, _fr, '--auto', '--audit', audit]);

      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(
        result.stdout,
        'mode: auto\n'
        'approved $_story\n'
        'ask $_fr: check finding required_section_missing\n',
      );
      expect(_isApproved(root, check.loginStory), isTrue);
      expect(readDoc(root, check.loginFr), contains('draft: true'));
    });

    test('approve --auto approves when a later round of the writer lands its decision', () async {
      final root = await _draftsProject();
      final audit = _writeAudit(root, [_story]);
      final author = File('${root.path}/author.md')
        ..writeAsStringSync(
          [
            'Decision: D1 -> NOT LANDED',
            'Not landed: D1: no doc took it',
            '## Round 1',
            'Decision: D1 -> $_story#goals',
          ].join('\n'),
        );

      final result = await run(root, [
        _story,
        '--auto',
        '--audit',
        audit,
        '--author',
        author.path,
      ]);

      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(result.stdout, 'mode: auto\napproved $_story\n');
      expect(_isApproved(root, check.loginStory), isTrue);
    });

    test("approve --auto approves when one writer's report lands a decision another writer's report left open", () async {
      final root = await _draftsProject();
      final audit = _writeAudit(root, [_story]);
      final story = File('${root.path}/author-story.md')
        ..writeAsStringSync(
          [
            'Decision: D1 -> NOT LANDED',
            'Not landed: D1: outside my share',
          ].join('\n'),
        );
      final cross = File('${root.path}/author-cross.md')
        ..writeAsStringSync('Decision: D1 -> $_story#goals');

      final result = await run(root, [
        _story,
        '--auto',
        '--audit',
        audit,
        '--author',
        story.path,
        '--author',
        cross.path,
      ]);

      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(result.stdout, 'mode: auto\napproved $_story\n');
      expect(_isApproved(root, check.loginStory), isTrue);
    });

    test(
      "approve --auto approves a draft written from a later round's fix line",
      () async {
        final root = await _draftsProject();
        final audited = readDoc(root, check.loginFr);
        final hash = getDoc(root, _fr)['base'];
        File('${root.path}/.specstone/audited/${check.loginFr}/$hash.md')
          ..createSync(recursive: true)
          ..writeAsStringSync(audited);
        const body = 'A wrong password never signs in.';
        docFile(root, check.loginFr).writeAsStringSync(
          audited.replaceFirst('A wrong password must not sign in.', body),
        );
        String fix(String text) => [
          '- $_fr#rationale: too blunt',
          '  Fix: $_fr#rationale',
          '  ```',
          '  $text',
          '  ```',
        ].join('\n');
        final report = File('${root.path}/audit.md')
          ..writeAsStringSync(
            [
              'Audited: $_fr@$hash',
              'Findings:',
              fix('A wrong password is refused.'),
              '## Round 1',
              'Findings:',
              fix(body),
            ].join('\n'),
          );

        final result = await run(root, [_fr, '--auto', '--audit', report.path]);

        expect(result.exitCode, 0, reason: '${result.stderr}');
        expect(result.stdout, 'mode: auto\napproved $_fr\n');
        expect(_isApproved(root, check.loginFr), isTrue);
      },
    );

    test(
      'approve --auto prints a carried line after its approved line',
      () async {
        final bulky = [
          for (var i = 1; i <= 48; i++)
            'Case $i: ${'A wrong password must not sign in. ' * 13}'.trim(),
        ].join('\n\n');
        final root = await check.writeCheckProject(
          extra: check.edit(check.loginFr, [
            ('traced_from:\n', 'draft: true\ntraced_from:\n'),
            ('A wrong password must not sign in.\n', '$bulky\n'),
          ]),
        );
        final base = getDoc(root, _fr)['base']! as String;
        final approval = await run(root, ['$_fr@$base', '--yes']);
        expect(approval.exitCode, 0, reason: '${approval.stderr}');
        docFile(root, check.loginFr).writeAsStringSync(
          readDoc(
            root,
            check.loginFr,
          ).replaceFirst('---\n', '---\ndraft: true\n'),
        );
        final result = await run(root, [_fr, '--auto', '--no-audit']);

        expect(result.exitCode, 0, reason: '${result.stderr}');
        expect(
          result.stdout,
          'mode: auto\n'
          'approved $_fr\n'
          'carried $_fr: chars_over_limit at doc\n'
          'carried $_fr: chars_over_limit at rationale\n',
        );
      },
    );

    test('auto call under the ask mode writes no approval', () async {
      final root = await _draftsProject();
      final audit = _writeAudit(root, [_story, _fr]);
      final before = _docBytes(root);

      final result = await run(root, [
        _story,
        _fr,
        '--auto',
        '--audit',
        audit,
      ], mode: 'ask');

      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(
        result.stdout,
        'mode: ask\n'
        'ask $_story: approve mode is ask\n'
        'ask $_fr: approve mode is ask\n',
      );
      expect(_docBytes(root), before);
    });

    test('auto call with no report flag leaves each draft a draft', () async {
      final root = await _draftsProject();
      final before = _docBytes(root);

      final result = await run(root, [_story, _fr, '--auto']);

      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(
        result.stdout,
        'mode: auto\n'
        'ask $_story: no audit report names it\n'
        'ask $_fr: no audit report names it\n',
      );
      expect(_docBytes(root), before);
    });

    test('prints one JSON object under --json', () async {
      final root = await _draftsProject(frHasFinding: true);
      final audit = _writeAudit(root, [_story, _fr]);

      final result = await run(root, [
        _story,
        _fr,
        '--auto',
        '--audit',
        audit,
        '--json',
      ]);

      expect(result.exitCode, 0, reason: '${result.stderr}');
      final json = jsonDecode(result.stdout as String) as Map<String, Object?>;
      expect(json.keys, ['approveMode', 'approved', 'asked', 'warnings']);
      expect(json['approveMode'], 'auto');
      expect(json['approved'], [
        {'doc': _story, 'path': check.loginStory, 'carried': <Object>[]},
      ]);
      expect(json['asked'], [
        {
          'doc': _fr,
          'path': check.loginFr,
          'reason': 'check finding required_section_missing',
          'waitsFor': 'owner',
        },
      ]);
      expect(json['warnings'], isEmpty);
    });

    test('reads an audit path relative to the working directory', () async {
      final root = await _draftsProject();
      final sub = Directory('${root.path}/reports');
      _writeAudit(root, [_story, _fr], folder: sub);

      final result = await run(root, [
        _story,
        _fr,
        '--auto',
        '--audit',
        'audit.md',
      ], from: sub);

      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(result.stdout, 'mode: auto\napproved $_story\napproved $_fr\n');
    });

    test(
      'dry run reads an audit path relative to the working directory',
      () async {
        final root = await _draftsProject();
        final sub = Directory('${root.path}/reports');
        _writeAudit(root, [_fr], folder: sub);
        final saved = await run(root, [_fr, '--dry-run', '--json']);
        expect(saved.exitCode, 0, reason: '${saved.stderr}');
        docFile(root, check.loginFr).writeAsStringSync(
          readDoc(root, check.loginFr).replaceFirst(
            'A wrong password must not sign in.',
            'A wrong password never signs in.',
          ),
        );

        final result = await run(root, [
          _fr,
          '--dry-run',
          '--json',
          '--audit',
          'audit.md',
        ], from: sub);

        expect(result.exitCode, 0, reason: '${result.stderr}');
        final json = jsonDecode(result.stdout as String) as Map;
        expect(
          (json['drafts'] as List).single,
          containsPair('changedSections', ['rationale']),
        );
        expect(json['warnings'], isEmpty);
      },
    );

    test('reads an audit path holding a comma as one path', () async {
      final root = await _draftsProject();
      final audit = _writeAudit(root, [_story, _fr], name: 'audit,round1.md');

      final result = await run(root, [_story, _fr, '--auto', '--audit', audit]);

      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(result.stdout, 'mode: auto\napproved $_story\napproved $_fr\n');
    });

    test(
      'auto call prints the mode warning on stderr and in the JSON',
      () async {
        const warning =
            'SPECSTONE_APPROVE_MODE=yes is neither ask nor auto; ask is used';
        final root = await _draftsProject();
        final before = _docBytes(root);

        final text = await run(root, [
          _story,
          '--auto',
          '--no-audit',
        ], mode: 'yes');

        expect(text.exitCode, 0, reason: '${text.stderr}');
        expect(text.stdout, 'mode: ask\nask $_story: approve mode is ask\n');
        expect(text.stderr, contains(warning));

        final json = await run(root, [
          _story,
          '--auto',
          '--no-audit',
          '--json',
        ], mode: 'yes');
        expect(json.exitCode, 0, reason: '${json.stderr}');
        expect(
          (jsonDecode(json.stdout as String)
              as Map<String, Object?>)['warnings'],
          [warning],
        );
        expect(_docBytes(root), before);
      },
    );

    test('auto call names one of two docs only under --target', () async {
      const draft = '---\ndraft: true\n---\n\n# Login architecture\n';
      final root = await writeTwinProject(
        extra: {
          'docs/$flutterArchitecture': draft,
          'docs/$jasprArchitecture': draft,
        },
      );
      final before = _docBytes(root);

      final both = await run(root, [
        'architecture:login',
        '--auto',
        '--no-audit',
      ]);
      expect(both.exitCode, 64);
      expect(both.stdout, isEmpty);
      expect(
        both.stderr,
        'architecture:login names 2 docs: '
        '$flutterArchitecture, $jasprArchitecture\n',
      );
      expect(_docBytes(root), before);

      final one = await run(root, [
        'architecture:login',
        '--auto',
        '--no-audit',
        '--target',
        'jaspr',
      ]);
      expect(one.exitCode, 0, reason: '${one.stderr}');
      expect(one.stdout, startsWith('mode: auto\nask $jasprArchitecture: '));
      expect(one.stdout, isNot(contains(flutterArchitecture)));
      expect(_docBytes(root), before);
    });

    test(
      'auto call on an untyped doc exits 64 as untyped and approves nothing',
      () async {
        final root = await writeWriteProject(
          extra: {'docs/prds/notes.md': '---\ndraft: true\n---\n\n# Notes\n'},
        );
        final before = _docBytes(root);

        final result = await run(root, [
          'prds/notes.md',
          '--auto',
          '--no-audit',
        ]);

        expect(result.exitCode, 64);
        expect(result.stdout, isEmpty);
        expect(
          result.stderr,
          'prds/notes.md has no doc type; migrate it to one before a write\n',
        );
        expect(_docBytes(root), before);
      },
    );

    test('auto call runs with no terminal', () async {
      final root = await _draftsProject();

      final result = await run(root, [_story, '--auto', '--no-audit']);

      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(result.stdout, 'mode: auto\napproved $_story\n');
    });

    for (final (args, message) in [
      (['--auto'], '--auto needs the names of the drafts it approves.'),
      (
        ['$_story@0123456789ab', '--auto', '--no-audit'],
        '$_story@0123456789ab: a @<hash> goes only with --yes.',
      ),
      for (final flag in [
        ['--yes'],
        ['--dry-run'],
        ['--context', '1'],
      ])
        (
          [_story, '--auto', '--no-audit', ...flag],
          '--auto takes no --yes, --dry-run, or --context.',
        ),
      (
        [_story, '--auto', '--no-audit', '--audit', 'audit.md'],
        '--auto takes --audit <path> or --no-audit, not both.',
      ),
      (
        [_story, '--audit', 'audit.md'],
        '--audit goes only with --auto or --dry-run --json.',
      ),
      (
        [_story, '--dry-run', '--audit', 'audit.md'],
        '--audit goes only with --auto or --dry-run --json.',
      ),
      for (final flag in [
        ['--author', 'author.md'],
        ['--no-audit'],
      ])
        ([_story, ...flag], '--author and --no-audit need --auto.'),
    ]) {
      test(
        'approve ${args.join(' ')} under --auto exits 64 and writes no doc',
        () async {
          final root = await _draftsProject();
          final before = _docBytes(root);

          final result = await run(root, args);

          expect(result.exitCode, 64);
          expect(result.stdout, isEmpty);
          expect(result.stderr as String, startsWith('$message\n'));
          expect(_docBytes(root), before);
        },
      );
    }
  });

  group('--out', () {
    Map<String, List<int>> docBytes(Directory root) => {
      for (final MapEntry(:key, :value) in treeBytes(root).entries)
        if (key.startsWith('docs/')) key: value,
    };

    for (final (title, flags) in [
      (
        'approve --dry-run --out saves the drafts view and approves nothing',
        <String>[],
      ),
      (
        'approve --dry-run --json --out saves the drafts JSON and approves '
            'nothing',
        ['--json'],
      ),
      (
        'approve --dry-run --context 2 --out saves the drafts view and '
            'approves nothing',
        ['--context', '2'],
      ),
    ]) {
      test(title, () async {
        final root = await writeWriteProject();
        final before = docBytes(root);
        final call = ['approve', '--dry-run', ...flags];
        final (runner: plain, out: printed, err: _) = writeRunner(root);
        expect(await plain.run(call), 0);

        final (:runner, :out, :err) = writeRunner(root);
        expect(await runner.run([...call, '--out', 'dry.txt']), 0);

        expect(err.toString(), isEmpty);
        expect(
          File('${root.path}/dry.txt').readAsStringSync(),
          printed.toString(),
        );
        if (flags.contains('--json')) {
          expect(jsonDecode(out.toString()), containsPair('lines', isA<int>()));
        } else {
          expect(
            out.toString(),
            matches(RegExp(r'^==> approve: \d+ lines, \d+ tokens · ')),
          );
        }
        expect(docBytes(root), before);
      });
    }

    test('approve --dry-run --out at a terminal saves no color code', () async {
      final root = await writeWriteProject();
      final call = ['approve', '--dry-run'];
      final console = FakeConsole(stdoutIsTerminal: true);
      final (runner: plain, out: printed, err: _) = writeRunner(
        root,
        console: console,
      );
      expect(await plain.run(call), 0);
      expect(printed.toString(), contains('\x1b['));

      final (:runner, :out, :err) = writeRunner(root, console: console);
      expect(await runner.run([...call, '--out', 'dry.txt']), 0);

      expect(
        File('${root.path}/dry.txt').readAsStringSync(),
        isNot(contains('\x1b')),
      );
    });

    test(
      'approve --yes --out is argument_invalid and approves nothing',
      () async {
        final root = await writeWriteProject();
        final before = docBytes(root);
        final (:runner, :out, :err) = writeRunner(root);

        expect(
          await runner.run([
            'approve',
            _seen(root, 'feature:signup'),
            '--yes',
            '--out',
            'gone.txt',
          ]),
          64,
        );

        expect(out.toString(), isEmpty);
        expect(err.toString(), '--out goes with --dry-run\n');
        expect(File('${root.path}/gone.txt').existsSync(), isFalse);
        expect(docBytes(root), before);
      },
    );

    test(
      'approve --auto --out is argument_invalid and approves nothing',
      () async {
        final root = await writeWriteProject();
        final before = docBytes(root);
        final (:runner, :out, :err) = writeRunner(root);

        expect(
          await runner.run([
            'approve',
            'feature:signup',
            '--auto',
            '--no-audit',
            '--out',
            'gone.txt',
          ]),
          64,
        );

        expect(out.toString(), isEmpty);
        expect(err.toString(), '--out goes with --dry-run\n');
        expect(File('${root.path}/gone.txt').existsSync(), isFalse);
        expect(docBytes(root), before);
      },
    );
  });
}
