import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:specstone/src/command_runner.dart';
import 'package:specstone/src/commands/hook_command.dart' show isInsideProject;
import 'package:specstone_core/specstone_core.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import '../../../../specstone_core/test/helpers/check_fixture.dart';
import '../../../../specstone_core/test/helpers/posix_modes.dart';
import '../../../../specstone_core/test/helpers/shipped_pins.dart';
import '../../../../specstone_core/test/helpers/write_fixture.dart'
    show testHome;
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

/// The layer that lifts the title and name rules off the technical diagram
/// section, so only the parse finding is left to read.
const _parseOnlyLayer = '''
sections:
  - id: technical_diagram
    lint:
      diagram:
        title: false
        names: false
''';

/// Returns the architecture doc with one parsing and one refused block.
Map<String, String> _refusedArchitecture() => {
  '.specstone/templates/architecture.yaml': _parseOnlyLayer,
  'docs/$loginArchitecture':
      '# Login architecture\n\n'
      '## Technical diagram\n\n'
      '```mermaid\nsequenceDiagram\n  A->>B: ok\n```\n\n'
      '```mermaid\nsequenceDiagram\n  A->>B: ok\n  A->>B: x;y\n```\n\n'
      '## Components\n\n| Component | Responsibility |\n|---|---|\n'
      '| Sign-in page | Takes the form |\n',
};

/// Reports whether a `node` starts on this machine's `PATH`.
bool _nodeStarts() {
  try {
    return Process.runSync('node', ['--version']).exitCode == 0;
  } on ProcessException {
    return false;
  }
}

/// Returns an environment whose own `PATH` key holds no `node`.
Future<Map<String, String>> _environmentWithoutNode() async {
  final empty = await Directory.systemTemp.createTemp('specstone_no_node_');
  addTearDown(() => empty.delete(recursive: true));
  final key = Platform.environment.keys.firstWhere(
    (k) => k.toUpperCase() == 'PATH',
    orElse: () => 'PATH',
  );
  if (!Platform.isWindows) return {key: empty.path};
  final system32 = '${Platform.environment['SystemRoot']}\\System32';
  return {key: '${empty.path};$system32'};
}

void _expectE05(String out) {
  final decoded = jsonDecode(out) as Map<String, Object?>;
  final specific = decoded['hookSpecificOutput']! as Map<String, Object?>;
  expect(specific['hookEventName'], 'PostToolUse');
  expect(specific['additionalContext'], matches(_e05Context));
}

/// The api request example of `hook pre-shell`, running [command].
String _shellRequest(String command) => jsonEncode({
  'session_id': 'abc123',
  'cwd': '/Users/owner/shop',
  'hook_event_name': 'PreToolUse',
  'tool_name': 'Bash',
  'tool_input': {'command': command, 'description': 'List the drafts'},
  'tool_use_id': 'toolu_01ABC123',
});

/// The exit status and both streams of one `hook pre-shell` run.
final class _ShellRun {
  new(this.status, this.out, this.err);

  final int status;
  final String out;
  final String err;
}

Future<_ShellRun> _runPreShell(
  Directory cwd,
  String stdin, {
  Map<String, String> environment = const {},
}) async {
  final (:runner, :out, :err) = writeRunner(
    cwd,
    console: FakeConsole(input: stdin),
    environment: environment,
  );
  final status = await runner.run(['hook', 'pre-shell']);
  return _ShellRun(status, out.toString(), err.toString());
}

Future<_ShellRun> _shell(
  Directory cwd,
  String command, {
  Map<String, String> environment = const {},
}) => _runPreShell(cwd, _shellRequest(command), environment: environment);

/// The folder `specstone folder` prints for the project at [root].
String _specstoneFolder(Directory root) =>
    '${root.resolveSymbolicLinksSync()}${Platform.pathSeparator}.specstone';

/// The refusal line of the api doc for [target] in the project at [root].
String _refusal(String target, Directory root) =>
    'hook pre-shell refused a shell write to $target, a temp folder; '
    "save the output inside the project, by the command's --out or under "
    '${_specstoneFolder(root)}\n';

const _preShellExpected =
    'hook pre-shell expects one JSON object holding tool_input.command or '
    'command on stdin\n';

Future<Directory> _projectRoot([String? config]) =>
    writeTree({'.specstone/config.yaml': config ?? shippedPinsConfig()});

void _expectRefused(_ShellRun result, String target, Directory root) {
  expect(result.status, 2, reason: '${result.out}\n${result.err}');
  expect(result.out, isEmpty);
  expect(result.err, _refusal(target, root));
}

void _expectPass(_ShellRun result) {
  expect(result.status, 0, reason: '${result.out}\n${result.err}');
  expect(result.out, isEmpty);
  expect(result.err, isEmpty);
}

void main() {
  test('a doc that passes prints nothing, exit 0', () async {
    final root = await writeCheckProject();
    final result = await postEdit(root, abs(root, loginFr));
    expect(result.status, 0);
    expect(result.out, isEmpty);
    expect(result.err, isEmpty);
  });

  test('a broken link hands back the findings object, exit 0', () async {
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

  test("another doc's findings stay out", () async {
    final original = checkProjectFiles()['docs/$loginFr']!;
    final root = await writeCheckProject(
      extra: {'docs/$loginFr': '$original\nSee $_brokenLink.\n'},
    );
    final result = await postEdit(root, abs(root, loginStory));
    expect(result.status, 0);
    expect(result.out, isEmpty);
  });

  test('a design document under docs/designs gets no check', () async {
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
  });

  test('a design document under a nested docs/superpowers/specs '
      'folder gets no check', () async {
    final root = await writeCheckProject(
      extra: {'docs/superpowers/specs/x.md': '# X\n\nSee $_brokenLink.\n'},
    );
    final result = await postEdit(root, abs(root, 'superpowers/specs/x.md'));
    expect(result.status, 0);
    expect(result.out, isEmpty);
  });

  test('a code file prints nothing', () async {
    final root = await writeCheckProject();
    final result = await postEdit(
      root,
      [root.path, 'app', 'lib', 'login.dart'].join(Platform.pathSeparator),
    );
    expect(result.status, 0);
    expect(result.out, isEmpty);
  });

  test('outside a project nothing prints, exit 0', () async {
    final root = await writeTree({'docs/prds/x.md': '# X\n'});
    final result = await postEdit(
      root,
      [root.path, 'docs', 'prds', 'x.md'].join(Platform.pathSeparator),
    );
    expect(result.status, 0);
    expect(result.out, isEmpty);
    expect(result.err, isEmpty);
  });

  test(
    'an untyped .md in measurements/ hands back its untyped_doc finding',
    () async {
      final root = await writeCheckProject(
        extra: {'docs/measurements/notes.md': '# Notes\n'},
      );
      final result = await postEdit(root, abs(root, 'measurements/notes.md'));
      expect(result.status, 0);
      final decoded = jsonDecode(result.out) as Map<String, Object?>;
      final context =
          (decoded['hookSpecificOutput']!
                  as Map<String, Object?>)['additionalContext']!
              as String;
      expect(
        context,
        matches(RegExp(r'^measurements/notes\.md:\d+: untyped_doc: ')),
      );
      expect(context, endsWith('\n1 finding'));
    },
  );

  test('an owner '
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

  test("the platform's separators read as the same DocPath", () async {
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

  test('no project exits 0 with nothing printed where search refuses with '
      'project_not_found, exit 78', () async {
    final root = await writeTree({'docs/prds/x.md': '# X\n'});
    final hook = await postEdit(
      root,
      [root.path, 'docs', 'prds', 'x.md'].join(Platform.pathSeparator),
    );
    expect(hook.status, 0);
    expect(hook.out, isEmpty);
    expect(hook.err, isEmpty);

    final (:runner, :out, :err) = writeRunner(root);
    expect(await runner.run(['search', 'login', '--json']), 78);
    expect(
      ((jsonDecode(err.toString()) as Map)['error'] as Map)['code'],
      'project_not_found',
    );
    expect(out.toString(), isEmpty);
  });

  test('an index_busy fault prints its line on stderr and exits 75, '
      'never 2', () async {
    final root = await writeCheckProject();
    final path = abs(root, loginFr);
    expect((await postEdit(root, path)).status, 0);
    final holder = sqlite3.open('${root.path}/.specstone/index.sqlite')
      ..execute('BEGIN IMMEDIATE');
    addTearDown(
      () => holder
        ..execute('ROLLBACK')
        ..close(),
    );
    File(path).writeAsStringSync('${File(path).readAsStringSync()}\nMore.\n');
    final out = StringBuffer();
    final err = StringBuffer();
    final runner = SpecstoneCommandRunner(
      out: out,
      err: err,
      templates: TemplateResolver(),
      workingDirectory: root,
      homeDirectory: testHome(),
      console: FakeConsole(input: _request(path)),
      busyTimeout: const Duration(milliseconds: 200),
    );

    final status = await runner.run(['hook', 'post-edit']);

    expect(status, 75);
    expect(out.toString(), isEmpty);
    expect(err.toString().trimRight(), isNotEmpty);
    expect(err.toString().trimRight().split('\n'), hasLength(1));
  });

  test('a run with findings prints no decision key and exits 0, never '
      '2', () async {
    final root = await writeCheckProject(extra: _brokenStory());

    final result = await postEdit(root, abs(root, loginStory));

    expect(result.status, 0);
    final decoded = jsonDecode(result.out) as Map<String, Object?>;
    expect(decoded.keys, ['hookSpecificOutput']);
    expect((decoded['hookSpecificOutput']! as Map<String, Object?>).keys, [
      'hookEventName',
      'additionalContext',
    ]);
    expect(result.out, isNot(contains('decision')));
    expect(result.out, isNot(contains('block')));
  });

  test('hook post-edit takes no argument', () async {
    final root = await writeCheckProject();
    final (:runner, :out, :err) = writeRunner(
      root,
      console: FakeConsole(input: _request(abs(root, loginFr))),
    );
    expect(await runner.run(['hook', 'post-edit', 'x']), 64);
  });

  test('the hook group holds the post-edit and pre-shell commands', () async {
    final (:runner, :out, :err) = writeRunner(await writeCheckProject());

    expect(
      runner.commands['hook']?.subcommands.keys,
      unorderedEquals(['post-edit', 'pre-shell']),
    );
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

  test('a hand edit of a record doc hands back its findings', () async {
    final root = await writeCheckProject(
      extra: {
        loginRecord:
            "---\nstatuses:\n  - 'email_login:implemented'\n"
            "  - 'email_login/check_password:implemented'\nimplements:\n"
            "  - 'email_login:app/lib/gone.dart:SignInPage'\n"
            '---\n\n# Login implementation\n',
      },
    );
    final result = await postEdit(
      root,
      [root.path, ...loginRecord.split('/')].join(Platform.pathSeparator),
    );
    expect(result.status, 0);
    final decoded = jsonDecode(result.out) as Map<String, Object?>;
    final specific = decoded['hookSpecificOutput']! as Map<String, Object?>;
    final lines = (specific['additionalContext']! as String).split('\n');
    expect(lines.first, startsWith('$loginRecord:'));
    expect(lines.last, matches(RegExp(r'^\d+ findings?$')));
  });

  test('a .md file under .specstone outside records prints nothing', () async {
    final root = await writeCheckProject(
      extra: {'.specstone/reports/x.md': '# Report\n\nSee [gone](gone.md).\n'},
    );
    final result = await postEdit(
      root,
      [root.path, '.specstone', 'reports', 'x.md'].join(Platform.pathSeparator),
    );
    expect(result.status, 0);
    expect(result.out, isEmpty);
  });

  test('a file_path that no longer exists prints nothing, exit 0', () async {
    final root = await writeCheckProject();
    final result = await postEdit(
      root,
      abs(root, 'prds/features/f01_login/gone.md'),
    );
    expect(result.status, 0);
    expect(result.out, isEmpty);
  });

  group('isInsideProject', () {
    late Directory root;
    setUp(() async => root = await _projectRoot());

    // The answer a Windows host gives when it joins `/tmp/a` to the working
    // directory: a place inside the root.
    String underRoot(String path) => '${root.path}/tmp/a';

    test('a path that starts with one separator has no known place on '
        'Windows, so it is never inside', () {
      for (final path in ['/tmp/a', r'\tmp\a', '/var/tmp/a', '//host/a']) {
        expect(
          isInsideProject(
            root,
            path,
            root,
            isWindows: true,
            canonical: underRoot,
          ),
          isFalse,
          reason: path,
        );
      }
    });

    test('a path the disk cannot resolve has no known place, so it is never '
        'inside, and nothing is thrown', () {
      String loops(String path) =>
          throw FileSystemException('too many levels of symbolic links', path);

      expect(
        isInsideProject(root, '${root.path}/loop/a', root, canonical: loops),
        isFalse,
      );
    });

    test('the same text is a path under the root where the disk says so', () {
      expect(
        isInsideProject(
          root,
          '/tmp/a',
          root,
          isWindows: false,
          canonical: underRoot,
        ),
        isTrue,
      );
    });

    test('the given path style also splits the root, whatever the host', () {
      final windowsRoot = Directory(r'C:\project');
      for (final (isWindows, root, resolved) in [
        (true, windowsRoot, r'C:\project\tmp\a'),
        (false, Directory('/project'), '/project/tmp/a'),
      ]) {
        expect(
          isInsideProject(
            root,
            'tmp/a',
            root,
            isWindows: isWindows,
            canonical: (_) => resolved,
          ),
          isTrue,
          reason: resolved,
        );
      }
    });
  });

  group('hook pre-shell', () {
    late Directory root;
    setUp(() async => root = await _projectRoot());

    test('a write into a temp folder is refused with the api refusal '
        'line, exit 2, stdout empty', () async {
      final result = await _shell(
        root,
        'specstone approve --dry-run > /tmp/drafts.txt',
      );

      _expectRefused(result, '/tmp/drafts.txt', root);
      expect(result.err.trimRight().split('\n'), hasLength(1));
    });

    test('the refusal line names the first temp-folder target, as '
        'written, and no earlier target', () async {
      final result = await _shell(
        root,
        'ls > docs/a.txt; ls > /tmp/b; ls > /var/tmp/c',
      );

      _expectRefused(result, '/tmp/b', root);
    });

    test(
      "Cursor's own shell hook passes the command at the top level",
      () async {
        final result = await _runPreShell(
          root,
          jsonEncode({'command': 'ls > /tmp/a', 'cwd': root.path}),
        );

        _expectRefused(result, '/tmp/a', root);
      },
    );

    test('a tool_input holding no command leaves the top-level command to '
        'read', () async {
      final result = await _runPreShell(
        root,
        jsonEncode({
          'tool_input': {'file_path': 'x'},
          'command': 'ls > /tmp/a',
        }),
      );

      _expectRefused(result, '/tmp/a', root);
    });

    test('tool_input.command wins over the top-level command', () async {
      final result = await _runPreShell(
        root,
        jsonEncode({
          'tool_input': {'command': 'ls'},
          'command': 'ls > /tmp/a',
        }),
      );

      _expectPass(result);
    });

    group('a write of the Writes block is refused', () {
      const refused = {
        'echo hi > /tmp/a': '/tmp/a',
        'echo hi >/tmp/a': '/tmp/a',
        'echo hi >> /tmp/a': '/tmp/a',
        'echo hi >| /tmp/a': '/tmp/a',
        'echo hi &> /tmp/a': '/tmp/a',
        'echo hi &>> /tmp/a': '/tmp/a',
        'ls 2> /tmp/a': '/tmp/a',
        'ls 2>/tmp/a': '/tmp/a',
        'ls 1>> /tmp/a': '/tmp/a',
        'ls 2>&1 > /tmp/a': '/tmp/a',
        'ls | tee /tmp/a': '/tmp/a',
        'ls |tee /tmp/a': '/tmp/a',
        'ls | tee -a /tmp/a': '/tmp/a',
        'ls | tee --append /tmp/a': '/tmp/a',
        'ls | tee docs/a.txt /tmp/b': '/tmp/b',
        'ls | tee -a docs/a.txt /tmp/b': '/tmp/b',
        '(ls | tee /tmp/a)': '/tmp/a',
        'ls; echo hi > /tmp/a': '/tmp/a',
        'true && echo hi > /tmp/a': '/tmp/a',
        'false || echo hi > /tmp/a': '/tmp/a',
        'ls\necho hi > /tmp/a': '/tmp/a',
        'ls & echo hi > /tmp/a': '/tmp/a',
        r'echo $(ls > /tmp/a)': '/tmp/a',
        r'echo $(ls | tee /tmp/a)': '/tmp/a',
        r'echo "$(ls > /tmp/a)"': '/tmp/a',
        'echo hi > "/tmp/a b"': '"/tmp/a b"',
        "echo hi > '/tmp/a b'": "'/tmp/a b'",
        'ls | tee "/tmp/a"': '"/tmp/a"',
        r'echo hi > "$TMPDIR/a"': r'"$TMPDIR/a"',
        'cat <<EOF > /tmp/a\nbody\nEOF': '/tmp/a',
        'cat <<EOF\n> /tmp/x\nEOF\nls > /tmp/a': '/tmp/a',
        'echo hi > "/tmp/a\nb"': r'"/tmp/a\nb"',
        'echo hi > "/tmp/a\rb"': r'"/tmp/a\rb"',
        'cat <<\\EOF > docs/a.md\nx > /tmp/a\nEOF\nls > /tmp/b': '/tmp/b',
        'echo \$((1<<2))\nls > /tmp/a': '/tmp/a',
        '((x = 1<<2))\nls > /tmp/a': '/tmp/a',
        r'echo $((cd d; ls) > /tmp/a)': '/tmp/a',
        '((ls) > /tmp/a)': '/tmp/a',
        '((x\nls > /tmp/a': '/tmp/a',
        '((ls) ; (ls > /tmp/a))': '/tmp/a',
        r'echo $((ls) ; (ls > /tmp/a))': '/tmp/a',
        'cat <<"E\\"F"\nx\nE"F\nls > /tmp/a': '/tmp/a',
        "cat <<'E\\F'\nx\nE\\F\nls > /tmp/a": '/tmp/a',
        'echo a#b > /tmp/a': '/tmp/a',
        r'echo $# > /tmp/a': '/tmp/a',
        'echo "it\'s" > /tmp/a': '/tmp/a',
        'echo \'say "hi"\' > /tmp/a': '/tmp/a',
        'cat <<-EOF > docs/a.md\n\tEOF\nls > /tmp/a': '/tmp/a',
        'echo hi >& /tmp/a': '/tmp/a',
        'echo hi >&/tmp/a': '/tmp/a',
        'echo hi >& "/tmp/a b"': '"/tmp/a b"',
        'ls 2>&1 >& /tmp/a': '/tmp/a',
      };
      for (final MapEntry(key: command, value: target) in refused.entries) {
        test(jsonEncode(command), () async {
          _expectRefused(await _shell(root, command), target, root);
        });
      }
    });

    group('a command with no temp-folder write runs, with nothing shown', () {
      const passes = [
        'ls -la',
        'echo hi > notes.txt',
        'echo hi > docs/out.txt',
        'echo hi > ./tmp/a',
        'echo hi > /tmpfoo/a',
        'echo hi > /tmp2',
        'echo hi > /home/tmp/a',
        'echo hi > ~/notes.txt',
        r'echo hi > $TMPDIRX/a',
        r'echo hi > $TMPX',
        'echo hi >&2',
        'echo hi >&-',
        'echo hi >& 2',
        'echo hi >& docs/a.txt',
        'ls 2>&-',
        'ls 2>&1',
        'ls 2>&1 | head',
        'ls > /dev/null',
        'ls >/dev/null 2>&1',
        'ls > /dev/stdout',
        'ls 2> /dev/stderr',
        'ls > NUL',
        'echo "> /tmp/a"',
        "echo '> /tmp/a'",
        'echo "a > /tmp/a" > docs/out.txt',
        'grep ">" /tmp/a',
        'sort < /tmp/a',
        'ls # > /tmp/a',
        'ls\n# > /tmp/a\nls',
        'git log --format=tee',
        'git log --format=tee > docs/log.txt',
        'echo tee /tmp/a',
        'ls | tee',
        'ls | tee -i',
        'ls | tee docs/a.txt',
        'cat <<EOF > docs/a.md\nrun x > /tmp/a\nEOF',
        "cat <<'EOF' > docs/a.md\nx > /tmp/a\nEOF",
        'cat <<-EOF\n\tx > /tmp/a\n\tEOF',
        'cat <<EOF > docs/a.md\n\tEOF\nx > /tmp/a\nEOF',
        'cat <<< "> /tmp/a"',
        'cp a /tmp/b',
        'mv a /tmp/b',
        'mktemp',
        'mktemp -d /tmp/abc.XXXX',
        'Out-File -FilePath /tmp/a',
        'Set-Content /tmp/a hi',
        'python3 -c "open(\'/tmp/a\', \'w\').write(\'x\')"',
      ];
      for (final command in passes) {
        test(jsonEncode(command), () async {
          _expectPass(await _shell(root, command));
        });
      }
    });

    group('a target that starts with a temp prefix is a temp folder', () {
      const targets = [
        '/tmp',
        '/tmp/a',
        '/private/tmp/a',
        '/var/tmp/a',
        '/var/folders/ab/cd/T/a',
        r'$TMPDIR',
        r'$TMPDIR/a',
        r'${TMPDIR}/a',
        r'$TMP/a',
        r'${TMP}/a',
        r'$TEMP/a',
        r'${TEMP}/a',
        r'$TMPDIR\a',
        r'%TEMP%\a',
        r'%temp%\a',
        '%Tmp%/a',
        r'$env:TEMP\a',
        r'$env:temp\a',
        r'$env:Tmp/a',
      ];
      for (final target in targets) {
        test(target, () async {
          _expectRefused(await _shell(root, 'echo hi > $target'), target, root);
        });
      }
    });

    group("the hook process's own temp variables add temp folders", () {
      for (final name in ['TMPDIR', 'TMP', 'TEMP']) {
        test('$name with an absolute value', () async {
          final environment = {name: '/scratch/t'};
          for (final target in [
            '/scratch/t',
            '/scratch/t/a',
            r'/scratch/t\a',
          ]) {
            _expectRefused(
              await _shell(root, 'echo hi > $target', environment: environment),
              target,
              root,
            );
          }
          for (final command in [
            'echo hi > /scratch/t2/a',
            'echo hi > /scratch/tx',
            'echo hi > /scratch/a',
          ]) {
            _expectPass(await _shell(root, command, environment: environment));
          }
        });
      }

      test('a value with a trailing separator names the same folder', () async {
        final result = await _shell(
          root,
          'echo hi > /scratch/t/a',
          environment: {'TMPDIR': '/scratch/t/'},
        );

        _expectRefused(result, '/scratch/t/a', root);
      });

      test('a value that is no absolute path, or only the root, adds '
          'nothing', () async {
        for (final value in ['scratch', '', '/']) {
          _expectPass(
            await _shell(
              root,
              'echo hi > scratch/a; echo hi > /home/a',
              environment: {'TMPDIR': value, 'TEMP': value},
            ),
          );
        }
      });

      test('a drive root adds nothing, in any letter case', () async {
        for (final value in [r'C:\', 'C:/', r'c:\']) {
          for (final target in [r'C:\Users\a.txt', r'c:\users\a.txt']) {
            _expectPass(
              await _shell(
                root,
                'echo hi > $target',
                environment: {'TEMP': value},
              ),
            );
          }
        }
      });

      test('a network share root value names a temp folder, as a path '
          'under it does', () async {
        const environment = {'TEMP': r'\\srv\tmp'};
        for (final target in [r'\\srv\tmp\a', r'\\SRV\Tmp/a', r'\\srv\tmp']) {
          _expectRefused(
            await _shell(root, 'echo hi > $target', environment: environment),
            target,
            root,
          );
        }
        _expectPass(
          await _shell(
            root,
            r'echo hi > \\srv\tmp2\a',
            environment: environment,
          ),
        );
      });

      test('a Windows value matches in any letter case and either '
          'separator', () async {
        const environment = {'TEMP': r'C:\Users\Me\AppData\Local\Temp'};
        for (final target in [
          r'C:\Users\Me\AppData\Local\Temp\a.txt',
          r'c:\users\me\appdata\local\temp\a.txt',
          'C:/Users/Me/AppData/Local/Temp/a.txt',
          r'"c:\USERS\Me\AppData\Local\Temp\a.txt"',
        ]) {
          _expectRefused(
            await _shell(root, 'echo hi > $target', environment: environment),
            target,
            root,
          );
        }
        for (final target in [
          r'C:\Users\Me\AppData\Local\Temporary\a.txt',
          r'C:\Users\Me\Documents\a.txt',
        ]) {
          _expectPass(
            await _shell(root, 'echo hi > $target', environment: environment),
          );
        }
      });
    });

    group('a project under a temp folder', () {
      // The default temp folder holds the project, as on a client scratch
      // folder. The POSIX prefixes name it on Linux and macOS; Windows names
      // it only by its TEMP value, so the by-prefix runs give that value
      // there, and the variable form adds the same folder by TMPDIR.
      final byPrefix = Platform.isWindows
          ? {'TEMP': Directory.systemTemp.path}
          : <String, String>{};
      final environments = [
        byPrefix,
        {'TMPDIR': Directory.systemTemp.path},
      ];

      for (final environment in environments) {
        final label = environment.containsKey('TMPDIR')
            ? 'by TMPDIR'
            : 'by prefix';

        test('a write inside the project is never refused, '
            '$label', () async {
          for (final command in [
            'echo hi > ${root.path}/.specstone/x',
            'echo hi >> "${root.path}/.specstone/reports/a.txt"',
            'ls | tee ${root.path}/docs/a.txt',
            'echo hi > ${root.path}/notes/x.txt',
            'echo hi > notes/x.txt',
            'echo hi > ./.specstone/x',
          ]) {
            _expectPass(await _shell(root, command, environment: environment));
          }
        });

        test('a relative target resolves against the working directory, '
            '$label', () async {
          final inside = Directory('${root.path}/sub')..createSync();

          _expectPass(
            await _shell(
              inside,
              'echo hi > ../notes/x.txt',
              environment: environment,
            ),
          );
        });

        test('a write into the temp folder outside the project is still '
            'refused, $label', () async {
          final outside = '${root.parent.path}/outside.txt';

          _expectRefused(
            await _shell(root, 'echo hi > $outside', environment: environment),
            outside,
            root,
          );
          for (final target in [
            '${root.path}/../outside.txt',
            '${root.path}/.specstone/../../outside.txt',
            '${root.path}-sibling/a.txt',
          ]) {
            _expectRefused(
              await _shell(root, 'echo hi > $target', environment: environment),
              target,
              root,
            );
          }
        });
      }

      test('a variable or command substitution inside the path has no known '
          'place, so the prefix rule refuses it', () async {
        for (final tail in [
          r'.specstone/$X',
          r'.specstone/${X}/a',
          r'.specstone/$(pwd)/a',
          '.specstone/`pwd`/a',
          r'notes/$X.txt',
        ]) {
          final target = '${root.path}/$tail';

          _expectRefused(
            await _shell(root, 'echo hi > $target', environment: byPrefix),
            target,
            root,
          );
        }
      });

      test('a temp variable stays a temp folder, whatever the working '
          'directory', () async {
        _expectRefused(
          await _shell(root, r'echo hi > $TMPDIR/a'),
          r'$TMPDIR/a',
          root,
        );
      });
    });

    test('no project runs the command and prints nothing', () async {
      final outside = await writeTree({'docs/x.md': '# X\n'});

      _expectPass(await _shell(outside, 'echo hi > /tmp/a'));
    });

    test('a project whose agent files are old and whose pack pin is refused '
        'gets only the refusal line', () async {
      final stale = await _projectRoot(
        'packs:\n  prd-core: 9.9.9\nagent_files_version: 0.0.1\n',
      );

      _expectRefused(await _shell(stale, 'echo hi > /tmp/a'), '/tmp/a', stale);
      _expectPass(await _shell(stale, 'echo hi > docs/a'));
    });

    group('stdin that is not one JSON object holding a command exits 64', () {
      for (final stdin in [
        '',
        'not json',
        '[]',
        '{}',
        '{"tool_input": {}}',
        '{"tool_input": {"command": 3}}',
        '{"tool_input": {"command": ""}}',
        '{"command": ""}',
        '{"command": 3}',
      ]) {
        test(jsonEncode(stdin), () async {
          for (final cwd in [
            root,
            await writeTree({'docs/x.md': '# X\n'}),
          ]) {
            final result = await _runPreShell(cwd, stdin);

            expect(result.status, 64);
            expect(result.out, isEmpty);
            expect(result.err, _preShellExpected);
          }
        });
      }
    });

    test('hook pre-shell takes no argument', () async {
      final (:runner, :out, :err) = writeRunner(
        root,
        console: FakeConsole(input: _shellRequest('ls > /tmp/a')),
      );

      expect(await runner.run(['hook', 'pre-shell', 'x']), 64);
    });
  });

  group('the built binary', () {
    late String bin;
    setUpAll(() async => bin = await buildSpecstone());

    Future<({int status, String out, String err})> spawn(
      Directory root,
      String stdin, {
      Map<String, String>? environment,
    }) async {
      final process = await Process.start(
        bin,
        ['hook', 'post-edit'],
        workingDirectory: root.path,
        environment: environment,
      );
      process.stdin.write(stdin);
      await process.stdin.close();
      final out = process.stdout.transform(utf8.decoder).join();
      final err = process.stderr.transform(utf8.decoder).join();
      return (status: await process.exitCode, out: await out, err: await err);
    }

    test('the built binary reads the hook JSON on its own stdin', () async {
      final root = await writeCheckProject(extra: _brokenStory());
      final result = await spawn(root, _request(abs(root, loginStory)));
      expect(result.status, 0);
      _expectE05(result.out);
    });

    test('a refused Mermaid block hands back its finding, exit 0', () async {
      final root = await writeCheckProject(extra: _refusedArchitecture());

      final result = await spawn(root, _request(abs(root, loginArchitecture)));

      expect(result.status, 0, reason: '${result.out}\n${result.err}');
      final decoded = jsonDecode(result.out) as Map<String, Object?>;
      final specific = decoded['hookSpecificOutput']! as Map<String, Object?>;
      expect(
        specific['additionalContext'],
        matches(
          RegExp(
            '^${RegExp.escape(loginArchitecture)}:17: diagram_parse_failed: '
            r'Parse error on line 3: .*\n1 finding$',
          ),
        ),
      );
    }, skip: _nodeStarts() ? null : 'node is not on PATH');

    test(
      'with no Node the hook reports a stored row and prints no warning',
      () async {
        final root = await writeCheckProject(extra: _refusedArchitecture());
        final request = _request(abs(root, loginArchitecture));
        final stored = await spawn(root, request);

        final result = await spawn(
          root,
          request,
          environment: await _environmentWithoutNode(),
        );

        expect(result.status, 0, reason: '${result.out}\n${result.err}');
        expect(result.out, stored.out);
        expect(result.out, contains('diagram_parse_failed'));
        expect(result.err, isEmpty);
      },
      skip: _nodeStarts() ? null : 'node is not on PATH',
    );

    test(
      'with no Node and no stored row the hook prints no skip warning, exit 0',
      () async {
        final root = await writeCheckProject(extra: _refusedArchitecture());

        final result = await spawn(
          root,
          _request(abs(root, loginArchitecture)),
          environment: await _environmentWithoutNode(),
        );

        expect(result.status, 0);
        expect(result.out, isEmpty);
        expect(result.err, isEmpty);
      },
    );

    test(
      'with an index the hook cannot write it hands back the finding and '
      'prints no not-stored warning, exit 0',
      () async {
        final root = await writeCheckProject(extra: _refusedArchitecture());
        final made = await runSpecstone(bin, [
          'structure',
        ], workingDirectory: root.path);
        expect(made.exitCode, 0, reason: '${made.stdout}\n${made.stderr}');
        final index = File('${root.path}/.specstone/index.sqlite');
        expect(index.existsSync(), isTrue);
        Process.runSync('chmod', ['444', index.path]);
        addTearDown(() => Process.runSync('chmod', ['644', index.path]));

        final check = await runSpecstone(bin, [
          'check',
        ], workingDirectory: root.path);
        expect(check.stderr, contains('Mermaid parse results not stored'));

        final result = await spawn(
          root,
          _request(abs(root, loginArchitecture)),
        );

        expect(result.status, 0, reason: '${result.out}\n${result.err}');
        expect(result.out, contains('diagram_parse_failed'));
        expect(result.out, isNot(contains('not stored')));
        expect(result.err, isEmpty);
      },
      skip:
          unreadablePathSkipReason() ??
          (_nodeStarts() ? null : 'node is not on PATH'),
    );

    test('the built binary exits 64 on stdin that is no JSON', () async {
      final root = await writeCheckProject();
      final result = await spawn(root, 'not json');
      expect(result.status, 64);
      expect(result.out, isEmpty);
      expect(result.err, contains('tool_input.file_path'));
    });
  });
}
