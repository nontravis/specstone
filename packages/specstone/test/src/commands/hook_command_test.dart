import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/consistency_check/fingerprint.dart';
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

  test(
    'api:agent_plugin: a design document under docs/designs gets no check',
    () async {
      final root = await writeCheckProject(
        extra: {
          'docs/designs/2026-11-11-x-design.md': '# X\n\nSee $_brokenLink.\n',
        },
      );
      final result = await postEdit(
        root,
        abs(root, 'designs/2026-11-11-x-design.md'),
      );
      expect(result.status, 0);
      expect(result.out, isEmpty);
    },
  );

  test(
    'api:agent_plugin: a design document under a nested docs/superpowers/specs '
    'folder gets no check',
    () async {
      final root = await writeCheckProject(
        extra: {'docs/superpowers/specs/x.md': '# X\n\nSee $_brokenLink.\n'},
      );
      final result = await postEdit(root, abs(root, 'superpowers/specs/x.md'));
      expect(result.status, 0);
      expect(result.out, isEmpty);
    },
  );

  test('a code file prints nothing', () async {
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

  test('an untyped .md in prds/ hands back its untyped_doc finding', () async {
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

  test('E08: an owner '
      "finding's line keeps its tag in the hook context", () async {
    final root = await writeCheckProject(
      extra: editedAfterApproval(loginStory, [('Sign in', 'Sign in again')]),
    );
    final result = await postEdit(root, abs(root, loginStory));
    expect(result.status, 0);
    final decoded = jsonDecode(result.out) as Map<String, Object?>;
    final context =
        (decoded['hookSpecificOutput']!
                as Map<String, Object?>)['additionalContext']!
            as String;
    expect(context, contains(': approval_stale: '));
    expect(context, endsWith(' (waits for the Owner)\n1 finding'));
  });

  test('E12: a suspect '
      'finding holds its upstream block, then the fingerprint, in the hook '
      'context', () async {
    final edited = loginScenario2.replaceFirst('wrong password', 'wrong pass');
    final root = await writeCheckProject(
      extra: doc(loginStory, loginScenario2, edited),
    );
    final result = await postEdit(root, abs(root, loginFr));
    expect(result.status, 0);
    final decoded = jsonDecode(result.out) as Map<String, Object?>;
    final context =
        (decoded['hookSpecificOutput']!
                as Map<String, Object?>)['additionalContext']!
            as String;
    final block = printedBlockOf(edited);
    expect(
      context,
      endsWith(
        '${block.split('\n').map((l) => '    $l\n').join()}'
        '    fingerprint ${fingerprintOf(edited)}\n1 finding',
      ),
    );
    expect(context.split('\n').first, isNot(contains(fingerprintOf(edited))));
  });

  test("f08/us06/fr02/e08, f08/us06/s6: the platform's separators read as the same DocPath", () async {
    final root = await writeCheckProject(extra: _brokenStory());
    final result = await postEdit(root, abs(root, loginStory));
    expect(result.status, 0);
    _expectE05(result.out);
  });

  test(
    'a template fault prints its line on stderr and exits 78, never 2',
    () async {
      final base = checkProjectFiles()['.specstone/config.yaml']!;
      final root = await writeCheckProject(
        extra: {'.specstone/config.yaml': '$base\npacks:\n  prd-core: 9.9.9\n'},
      );
      final result = await postEdit(root, abs(root, loginFr));
      expect(result.status, 78);
      expect(result.out, isEmpty);
      expect(result.err, isNotEmpty);
    },
  );

  for (final stdin in [
    '',
    '[]',
    '{}',
    '{"tool_input": {}}',
    '{"tool_input": {"file_path": 3}}',
  ]) {
    test(
      'stdin that is not one JSON object holding tool_input.file_path exits 64 '
      '(${jsonEncode(stdin)})',
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

  test('hook post-edit takes no argument', () async {
    final root = await writeCheckProject();
    final (:runner, :out, :err) = writeRunner(
      root,
      console: FakeConsole(input: _request(abs(root, loginFr))),
    );
    expect(await runner.run(['hook', 'post-edit', 'x']), 64);
  });

  test('a file path through a symbolic link reads as its DocPath', () async {
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
    final result = await postEdit(root, abs(Directory(link.path), loginStory));
    expect(result.status, 0);
    _expectE05(result.out);
  });

  test(
    'a subfolder working directory and a relative file_path find the doc',
    () async {
      final root = await writeCheckProject(extra: _brokenStory());
      final cwd = Directory([root.path, 'app'].join(Platform.pathSeparator));
      final result = await postEdit(
        cwd,
        '../docs/prds/features/f01_login/us01_email_login/USER_STORY.md'
            .replaceAll('/', Platform.pathSeparator),
      );
      expect(result.status, 0);
      _expectE05(result.out);
    },
  );

  test('a file_path that no longer exists prints nothing, exit 0', () async {
    final root = await writeCheckProject();
    final result = await postEdit(
      root,
      abs(root, 'prds/features/f01_login/gone.md'),
    );
    expect(result.status, 0);
    expect(result.out, isEmpty);
  });

  group('the built binary', () {
    late String bin;
    setUpAll(() async => bin = await buildSpecstone());

    Future<({int status, String out, String err})> spawn(
      Directory root,
      String stdin,
    ) async {
      final process = await Process.start(bin, [
        'hook',
        'post-edit',
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

    test('the built binary exits 64 on stdin that is no JSON', () async {
      final root = await writeCheckProject();
      final result = await spawn(root, 'not json');
      expect(result.status, 64);
      expect(result.out, isEmpty);
      expect(result.err, contains('tool_input.file_path'));
    });
  });
}
