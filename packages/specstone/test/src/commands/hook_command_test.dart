import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../../../specstone_core/test/helpers/check_fixture.dart';
import '../../helpers/built_cli.dart';
import '../../helpers/temp_tree.dart';
import '../../helpers/write_runner.dart';

const _brokenLink = '[reset](../us02_reset_password/USER_STORY.md)';

/// The s02 request example with `tool_input.file_path` set to [filePath].
String _request(String filePath) => jsonEncode({
  'session_id': 'abc123',
  'cwd': '/Users/owner/shop',
  'hook_event_name': 'PostToolUse',
  'tool_name': 'Edit',
  'tool_input': {
    'file_path': filePath,
    'old_string': '[reset](../us03_reset_password/USER_STORY.md)',
    'new_string': _brokenLink,
    'replace_all': false,
  },
  'tool_use_id': 'toolu_01ABC123',
});

Future<({int status, String out, String err})> _runHook(
  Directory cwd,
  String stdin,
) async {
  final (:runner, :out, :err) = writeRunner(
    cwd,
    console: FakeConsole(input: stdin),
  );
  final status = await runner.run(['hook', 'post-edit']);
  return (status: status, out: out.toString(), err: err.toString());
}

Future<({int status, String out, String err})> postEdit(
  Directory cwd,
  String filePath,
) => _runHook(cwd, _request(filePath));

String abs(Directory root, String docPath) =>
    [root.path, 'docs', ...docPath.split('/')].join(Platform.pathSeparator);

Map<String, String> _brokenStory() => {
  'docs/$loginStory':
      '${checkProjectFiles()['docs/$loginStory']}\nSee $_brokenLink.\n',
};

final _e05Context = RegExp(
  r'^prds/features/f01_login/us01_email_login/USER_STORY\.md:\d+: link_unresolved: link target \.\./us02_reset_password/USER_STORY\.md is no doc\n1 finding$',
);

void _expectE05(String out) {
  final decoded = jsonDecode(out) as Map<String, Object?>;
  final specific = decoded['hookSpecificOutput']! as Map<String, Object?>;
  expect(specific['hookEventName'], 'PostToolUse');
  expect(specific['additionalContext'], matches(_e05Context));
}

/// A PreToolUse request for a [tool] call running [command].
String _bash(String command, {String tool = 'Bash'}) => jsonEncode({
  'session_id': 'abc123',
  'cwd': '/Users/owner/shop',
  'hook_event_name': 'PreToolUse',
  'tool_name': tool,
  'tool_input': {'command': command, 'description': 'Run it'},
  'tool_use_id': 'toolu_01ABC123',
});

Future<({int status, String out, String err})> _preBash(String stdin) async {
  final (:runner, :out, :err) = writeRunner(
    await writeTree({'keep.txt': 'x\n'}),
    console: FakeConsole(input: stdin),
  );
  final status = await runner.run(['hook', 'pre-bash']);
  return (status: status, out: out.toString(), err: err.toString());
}

/// The one `ask` object pre-bash prints for [reason].
Map<String, Object?> _ask(String reason) => {
  'hookSpecificOutput': {
    'hookEventName': 'PreToolUse',
    'permissionDecision': 'ask',
    'permissionDecisionReason': reason,
  },
};

void main() {
  test(
    'f08/us06/fr02/e01, f08/us06/s1: a doc that passes prints nothing, exit 0',
    () async {
      final root = await writeCheckProject();
      final result = await postEdit(root, abs(root, loginFr));
      expect(result.status, 0);
      expect(result.out, isEmpty);
      expect(result.err, isEmpty);
    },
  );

  test('f08/us06/fr02/e05, f08/us06/s2: a broken link hands back the s02 findings object, exit 0', () async {
    final root = await writeCheckProject(extra: _brokenStory());
    final result = await postEdit(root, abs(root, loginStory));
    expect(result.status, 0);
    _expectE05(result.out);
    expect(result.out, endsWith('\n'));
    expect(
      File(abs(root, loginStory)).readAsStringSync(),
      contains(_brokenLink),
    );
  });

  test(
    "f08/us06/fr02/e06, f08/us06/s3: another doc's findings stay out",
    () async {
      final original = checkProjectFiles()['docs/$loginFr']!;
      final root = await writeCheckProject(
        extra: {'docs/$loginFr': '$original\nSee $_brokenLink.\n'},
      );
      final result = await postEdit(root, abs(root, loginStory));
      expect(result.status, 0);
      expect(result.out, isEmpty);
    },
  );

  test('f08/us06/fr02/e03, f08/us06/s4: a design doc under docs/superpowers is not checked', () async {
    final root = await writeCheckProject(
      extra: {'docs/superpowers/specs/x.md': '# X\n\nSee $_brokenLink.\n'},
    );
    final result = await postEdit(root, abs(root, 'superpowers/specs/x.md'));
    expect(result.status, 0);
    expect(result.out, isEmpty);
  });

  test('f08/us06/fr02/e04: a code file prints nothing', () async {
    final root = await writeCheckProject();
    final result = await postEdit(
      root,
      [root.path, 'app', 'lib', 'login.dart'].join(Platform.pathSeparator),
    );
    expect(result.status, 0);
    expect(result.out, isEmpty);
  });

  test('f08/us06/fr02/e02, f08/us06/s5, f08/us01/fr03/e04: outside a project nothing prints, exit 0', () async {
    final root = await writeTree({'docs/prds/x.md': '# X\n'});
    final result = await postEdit(
      root,
      [root.path, 'docs', 'prds', 'x.md'].join(Platform.pathSeparator),
    );
    expect(result.status, 0);
    expect(result.out, isEmpty);
    expect(result.err, isEmpty);
  });

  test('f08/us06/fr02/e07: an untyped .md in prds/ hands back its untyped_doc finding', () async {
    final root = await writeCheckProject(
      extra: {'docs/prds/notes.md': '# Notes\n'},
    );
    final result = await postEdit(root, abs(root, 'prds/notes.md'));
    expect(result.status, 0);
    final decoded = jsonDecode(result.out) as Map<String, Object?>;
    final context =
        (decoded['hookSpecificOutput']!
                as Map<String, Object?>)['additionalContext']!
            as String;
    expect(context, matches(RegExp(r'^prds/notes\.md:\d+: untyped_doc: ')));
    expect(context, endsWith('\n1 finding'));
  });

  test("f08/us06/fr02/e08, f08/us06/s6: the platform's separators read as the same DocPath", () async {
    final root = await writeCheckProject(extra: _brokenStory());
    final result = await postEdit(root, abs(root, loginStory));
    expect(result.status, 0);
    _expectE05(result.out);
  });

  test('f08/us06/fr02/e09: a template fault prints its line on stderr and exits 78, never 2', () async {
    final base = checkProjectFiles()['.specstone/config.yaml']!;
    final root = await writeCheckProject(
      extra: {'.specstone/config.yaml': '$base\npacks:\n  prd-core: 9.9.9\n'},
    );
    final result = await postEdit(root, abs(root, loginFr));
    expect(result.status, 78);
    expect(result.out, isEmpty);
    expect(result.err, isNotEmpty);
  });

  for (final stdin in [
    '',
    '[]',
    '{}',
    '{"tool_input": {}}',
    '{"tool_input": {"file_path": 3}}',
  ]) {
    test(
      'f08/us06/fr02/e10: stdin that is not one JSON object holding tool_input.file_path exits 64 (${jsonEncode(stdin)})',
      () async {
        final root = await writeCheckProject();
        final result = await _runHook(root, stdin);
        expect(result.status, 64);
        expect(result.out, isEmpty);
        expect(result.err.trimRight().split('\n'), hasLength(1));
        expect(result.err, contains('tool_input.file_path'));
      },
    );
  }

  test('f08/us06/fr02: hook post-edit takes no argument', () async {
    final root = await writeCheckProject();
    final (:runner, :out, :err) = writeRunner(
      root,
      console: FakeConsole(input: _request(abs(root, loginFr))),
    );
    expect(await runner.run(['hook', 'post-edit', 'x']), 64);
  });

  test(
    'f08/us06/fr02: a file path through a symbolic link reads as its DocPath',
    () async {
      final root = await writeCheckProject(extra: _brokenStory());
      final holder = await Directory.systemTemp.createTemp('specstone_link_');
      addTearDown(() => holder.delete(recursive: true));
      final link = Link([holder.path, 'shop'].join(Platform.pathSeparator));
      try {
        link.createSync(root.path);
      } on FileSystemException {
        markTestSkipped('symbolic links are unavailable here');
        return;
      }
      final result = await postEdit(
        root,
        abs(Directory(link.path), loginStory),
      );
      expect(result.status, 0);
      _expectE05(result.out);
    },
  );

  test('f08/us06/fr02: a subfolder working directory and a relative file_path find the doc', () async {
    final root = await writeCheckProject(extra: _brokenStory());
    final cwd = Directory([root.path, 'app'].join(Platform.pathSeparator));
    final result = await postEdit(
      cwd,
      '../docs/prds/features/f01_login/us01_email_login/USER_STORY.md'
          .replaceAll('/', Platform.pathSeparator),
    );
    expect(result.status, 0);
    _expectE05(result.out);
  });

  test('f08/us06/fr02/e01: a file_path that no longer exists prints nothing, exit 0', () async {
    final root = await writeCheckProject();
    final result = await postEdit(
      root,
      abs(root, 'prds/features/f01_login/gone.md'),
    );
    expect(result.status, 0);
    expect(result.out, isEmpty);
  });

  group('hook pre-bash', () {
    const signup = 'Owner confirmation: specstone approve feature:signup';
    for (final (shape, command, reason) in [
      (
        'names after the subcommand',
        'specstone approve feature:signup user_story:login/email_login --yes',
        '$signup user_story:login/email_login',
      ),
      (
        'hash suffixes',
        'specstone approve feature:signup@1a2b3c4d5e6f '
            'user_story:login/email_login@0123456789ab --yes',
        '$signup user_story:login/email_login',
      ),
      (
        '--yes before the names',
        'specstone approve --yes feature:signup@1a2b3c4d5e6f '
            'user_story:login/email_login@0123456789ab',
        '$signup user_story:login/email_login',
      ),
      (
        'a full path to the binary',
        '/Users/owner/.pub-cache/bin/specstone approve '
            'feature:signup@1a2b3c4d5e6f --yes',
        signup,
      ),
      (
        'cd and &&',
        'cd /Users/owner/shop && specstone approve '
            'feature:signup@1a2b3c4d5e6f --yes',
        signup,
      ),
      (
        'newline-separated commands',
        'cd /Users/owner/shop\nspecstone approve feature:signup@1a2b3c4d5e6f '
            '--yes\ngit status',
        signup,
      ),
      (
        "bash -c '…'",
        "bash -c 'specstone approve feature:signup@1a2b3c4d5e6f --yes'",
        signup,
      ),
      (
        'sh -c "…"',
        'sh -c "specstone delete prds/a.md --yes --plan 1a2b3c4d5e6f"',
        'Owner confirmation: specstone delete prds/a.md',
      ),
      (
        '--yes at the end followed by &&',
        'specstone approve feature:signup@1a2b3c4d5e6f --yes&& echo done',
        signup,
      ),
      (
        'delete with --json',
        'specstone delete prds/a.md prds/b.md --yes --plan 1a2b3c4d5e6f '
            '--json',
        'Owner confirmation: specstone delete prds/a.md prds/b.md',
      ),
      (
        'migrate with its plan',
        'specstone migrate --yes --plan 1a2b3c4d5e6f',
        'Owner confirmation: specstone migrate',
      ),
      (
        'init with its plan',
        'specstone init --yes --plan 1a2b3c4d5e6f',
        'Owner confirmation: specstone init',
      ),
      (
        'two gated commands',
        'specstone approve feature:signup@1a2b3c4d5e6f --yes && specstone '
            'delete prds/a.md --yes --plan 1a2b3c4d5e6f',
        '$signup; specstone delete prds/a.md',
      ),
      (
        'a gated word with no specstone call',
        'npm   init --yes',
        'Owner confirmation: npm init --yes',
      ),
    ]) {
      test('ms-r10, ms-r11: $shape asks the Owner, one reason segment per '
          'gated call', () async {
        final result = await _preBash(_bash(command));
        expect(result.status, 0);
        expect(result.err, isEmpty);
        expect(jsonDecode(result.out), _ask(reason));
      });
    }

    const hidden =
        'names come from a shell expansion the Owner cannot see; write them '
        'out';
    for (final (shape, command, reason) in [
      (
        'the 2026-11-01 repro, a command substitution reading a file',
        r'''specstone approve $(tr '\n' ' ' < "$L/f02-approve-hashes.txt") --yes''',
        'Owner confirmation: specstone approve: $hidden',
      ),
      (
        'a plain variable',
        r'specstone approve $DRAFTS --yes',
        'Owner confirmation: specstone approve: $hidden',
      ),
      (
        'a braced variable',
        r'specstone approve ${DRAFTS} --yes',
        'Owner confirmation: specstone approve: $hidden',
      ),
      (
        'a variable named with an underscore',
        r'specstone approve $_drafts --yes',
        'Owner confirmation: specstone approve: $hidden',
      ),
      (
        'a backtick substitution',
        'specstone approve `cat hashes.txt` --yes',
        'Owner confirmation: specstone approve: $hidden',
      ),
      (
        'a <(…) process substitution',
        'specstone approve <(cat hashes.txt) --yes',
        'Owner confirmation: specstone approve: $hidden',
      ),
      (
        'a < redirect',
        'specstone approve --yes < hashes.txt',
        'Owner confirmation: specstone approve: $hidden',
      ),
      (
        'an @ file reference',
        'specstone approve @hashes.txt --yes',
        'Owner confirmation: specstone approve: $hidden',
      ),
      (
        'xargs feeding the call',
        'cat f | xargs specstone approve --yes',
        'Owner confirmation: specstone approve: $hidden',
      ),
      (
        'xargs with options and a placeholder',
        'cat f | xargs -I{} specstone approve {} --yes',
        'Owner confirmation: specstone approve: $hidden',
      ),
      (
        'a hidden plan hash on delete',
        r'specstone delete prds/a.md --yes --plan $(cat plan.txt)',
        'Owner confirmation: specstone delete: $hidden',
      ),
      (
        'a hidden plan hash on migrate',
        r'specstone migrate --yes --plan $PLAN',
        'Owner confirmation: specstone migrate: $hidden',
      ),
      (
        'a hidden plan hash on init',
        r'specstone init --yes --plan "$PLAN"',
        'Owner confirmation: specstone init: $hidden',
      ),
      (
        'only the expanding call among two',
        'specstone approve feature:signup@1a2b3c4d5e6f --yes; '
            r'specstone delete $(cat paths.txt) --yes --plan 1a2b3c4d5e6f',
        'Owner confirmation: specstone approve feature:signup; '
            'specstone delete: $hidden',
      ),
      (
        'a bash -c call with a variable',
        r"""bash -c 'specstone approve $DRAFTS --yes'""",
        'Owner confirmation: specstone approve: $hidden',
      ),
    ]) {
      test('D6: $shape asks the Owner to write the names out', () async {
        final result = await _preBash(_bash(command));
        expect(result.status, 0);
        expect(result.err, isEmpty);
        expect(jsonDecode(result.out), _ask(reason));
      });
    }

    for (final (shape, command, reason) in [
      (
        'names with hash suffixes and a plan',
        'specstone approve feature:signup@1a2b3c4d5e6f '
            'user_story:login/email_login@0123456789ab --yes',
        '$signup user_story:login/email_login',
      ),
      (
        'delete with a literal plan',
        'specstone delete prds/a.md --yes --plan 1a2b3c4d5e6f',
        'Owner confirmation: specstone delete prds/a.md',
      ),
      (
        'a variable before the call, not in its arguments',
        r'cd "$HOME/shop" && specstone approve feature:signup@1a2b3c4d5e6f '
            '--yes',
        signup,
      ),
    ]) {
      test('D6: $shape keeps the literal reason', () async {
        final result = await _preBash(_bash(command));
        expect(result.status, 0);
        expect(jsonDecode(result.out), _ask(reason));
      });
    }

    for (final (tool, command) in [
      ('PowerShell', 'specstone.exe approve feature:signup@1a2b3c4d5e6f --yes'),
      (
        'PowerShell',
        r"& 'C:\Tools\specstone.exe' approve feature:signup@1a2b3c4d5e6f "
            '--yes',
      ),
      ('Monitor', 'specstone approve feature:signup@1a2b3c4d5e6f --yes'),
    ]) {
      test('ms-r11: a $tool call `$command` asks the Owner', () async {
        final result = await _preBash(_bash(command, tool: tool));
        expect(result.status, 0);
        expect(jsonDecode(result.out), _ask(signup));
      });
    }

    for (final command in [
      'specstone approve feature:signup',
      'specstone delete prds/a.md --json',
      'specstone set feature:signup#problem --base 1a2b --yes',
      'specstone reinit --yes',
      'specstone approve feature:signup --yesterday',
      'specstone approve feature:signup@1a2b3c4d5e6f && echo --yes-not',
      'git status',
    ]) {
      test('ms-r10, ms-r11: `$command` prints nothing, exit 0', () async {
        final result = await _preBash(_bash(command));
        expect(result.status, 0);
        expect(result.out, isEmpty);
        expect(result.err, isEmpty);
      });
    }

    test('ms-r10: the reason is cut to 300 characters', () async {
      final names = [for (var i = 0; i < 40; i++) 'user_story:login/story_$i'];
      final result = await _preBash(
        _bash('specstone approve ${names.join(' ')} --yes'),
      );
      expect(result.status, 0);
      final specific =
          (jsonDecode(result.out)
                  as Map<String, Object?>)['hookSpecificOutput']!
              as Map<String, Object?>;
      final reason = specific['permissionDecisionReason']! as String;
      expect(reason, hasLength(300));
      expect(
        reason,
        startsWith(
          'Owner confirmation: specstone approve user_story:login/story_0 ',
        ),
      );
    });

    for (final stdin in [
      '',
      'not json',
      '[]',
      '{}',
      '{"tool_input": {}}',
      '{"tool_input": {"command": 3}}',
    ]) {
      test('ms-r10: stdin with no tool_input.command string '
          '(${jsonEncode(stdin)}) prints nothing, exit 0', () async {
        final result = await _preBash(stdin);
        expect(result.status, 0);
        expect(result.out, isEmpty);
        expect(result.err, isEmpty);
      });
    }

    test('ms-r10: hook pre-bash takes no argument', () async {
      final (:runner, :out, :err) = writeRunner(
        await writeTree({'keep.txt': 'x\n'}),
        console: FakeConsole(input: _bash('specstone approve x --yes')),
      );
      expect(await runner.run(['hook', 'pre-bash', 'x']), 64);
      expect(out.toString(), isEmpty);
    });
  });

  group('the built binary', () {
    late String bin;
    setUpAll(() async => bin = await buildSpecstone());

    Future<({int status, String out, String err})> spawn(
      Directory root,
      String stdin, {
      String hook = 'post-edit',
    }) async {
      final process = await Process.start(bin, [
        'hook',
        hook,
      ], workingDirectory: root.path);
      process.stdin.write(stdin);
      await process.stdin.close();
      final out = process.stdout.transform(utf8.decoder).join();
      final err = process.stderr.transform(utf8.decoder).join();
      return (status: await process.exitCode, out: await out, err: await err);
    }

    test('f08/us06/s6, f08/us06/fr02: the built binary reads the hook JSON on its own stdin', () async {
      final root = await writeCheckProject(extra: _brokenStory());
      final result = await spawn(root, _request(abs(root, loginStory)));
      expect(result.status, 0);
      _expectE05(result.out);
    });

    test(
      'f08/us06/fr02/e10: the built binary exits 64 on stdin that is no JSON',
      () async {
        final root = await writeCheckProject();
        final result = await spawn(root, 'not json');
        expect(result.status, 64);
        expect(result.out, isEmpty);
        expect(result.err, contains('tool_input.file_path'));
      },
    );

    test('ms-r10: the built binary reads the PreToolUse JSON on its own '
        'stdin and asks', () async {
      final root = await writeTree({'keep.txt': 'x\n'});
      final result = await spawn(
        root,
        _bash('specstone approve feature:signup --yes'),
        hook: 'pre-bash',
      );
      expect(result.status, 0);
      expect(
        jsonDecode(result.out),
        _ask('Owner confirmation: specstone approve feature:signup'),
      );
    });
  });
}
