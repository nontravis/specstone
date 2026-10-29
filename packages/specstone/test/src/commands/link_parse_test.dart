// The command lists and literals are plan text kept as written.

import 'dart:convert';
import 'dart:io';

import 'package:specstone/src/command_runner.dart';
import 'package:specstone_core/specstone_core.dart';
import 'package:test/test.dart';

import '../../helpers/fake_browser_host.dart';
import '../../helpers/read_fixture.dart';
import '../../helpers/write_runner.dart';

/// What one command run returns.
typedef CliRun = ({int code, String out, String err});

const fr = 'login/email_login/validate_credentials';
const story = 'login/email_login';
const frFile =
    'docs/prds/features/f01_login/us01_email_login/fr01_validate_credentials.md';

/// One command to run: its display name, its arguments, and a fresh console.
typedef CliCommand = ({
  String name,
  List<String> args,
  FakeConsole Function()? console,
});

/// Writes the read project plus the draft fr02, then `tail` under `frFile`.
Future<Directory> caseProject(String tail) async {
  final project = await writeReadProject(
    extra: {
      'docs/prds/features/f01_login/us01_email_login/fr02_draft_one.md':
          '---\ndraft: true\n---\n\n# Draft one\n\n## Statement\nA draft.\n',
    },
  );
  final doc = File.fromUri(project.uri.resolve(frFile));
  doc.writeAsStringSync('${doc.readAsStringSync()}$tail');
  return project;
}

/// Runs [args] in [project] and returns the exit code and both streams.
Future<CliRun> runIn(
  Directory project,
  List<String> args, {
  FakeConsole? console,
}) async {
  final out = StringBuffer();
  final err = StringBuffer();
  final runner = SpecstoneCommandRunner(
    out: out,
    err: err,
    templates: TemplateResolver(),
    workingDirectory: project,
    homeDirectory: null,
    console: console ?? FakeConsole(),
    browserHost: FakeBrowserHost.withChrome().host,
  );
  final code = await runner.run(args);
  return (code: code, out: out.toString(), err: err.toString());
}

final readWriteCommands = <CliCommand>[
  (name: 'structure', args: ['structure'], console: null),
  (
    name: 'context login --for query',
    args: ['context', 'login', '--for', 'query'],
    console: null,
  ),
  (name: 'get $fr', args: ['get', fr], console: null),
  (name: 'search password', args: ['search', 'password'], console: null),
  (name: 'list fr', args: ['list', 'fr'], console: null),
  (name: 'refs $story', args: ['refs', story], console: null),
  (name: 'check', args: ['check'], console: null),
  (name: 'format --check', args: ['format', '--check'], console: null),
  (
    name: 'new fr --parent $story --slug probe_x',
    args: ['new', 'fr', '--parent', story, '--slug', 'probe_x'],
    console: null,
  ),
  (
    name: 'set fr:$fr#statement --base <base>',
    args: ['set', 'fr:$fr#statement', '--base', 'PLACEHOLDER'],
    console: () => FakeConsole(input: 'New statement.\n'),
  ),
  (
    name: 'rename user_story:$story --to email_signin',
    args: ['rename', 'user_story:$story', '--to', 'email_signin'],
    console: null,
  ),
  (
    name: 'reorder fr:$fr --to 1',
    args: ['reorder', 'fr:$fr', '--to', '1'],
    console: null,
  ),
  (
    name: 'delete fr:$story/draft_one',
    args: ['delete', 'fr:$story/draft_one'],
    console: null,
  ),
  (
    name: 'approve',
    args: ['approve'],
    console: () => FakeConsole(
      stdinIsTerminal: true,
      stdoutIsTerminal: true,
      answers: ['n', 'n', 'n'],
    ),
  ),
];

final buildCommands = <CliCommand>[
  (
    name: 'build docs/prds/features/f01_login --output out.html',
    args: ['build', 'docs/prds/features/f01_login', '--output', 'out.html'],
    console: null,
  ),
  (
    name: 'build docs/prds/features/f01_login --format pdf --output out.pdf',
    args: [
      'build',
      'docs/prds/features/f01_login',
      '--format',
      'pdf',
      '--output',
      'out.pdf',
    ],
    console: null,
  ),
];

/// One test per command: the command answers the same on a doc holding
/// `tail` as on a clean one, with no unhandled exception on either run.
void everyCommandAnswers(
  String tail,
  List<CliCommand> commands, {
  required String tags,
}) {
  for (final command in commands) {
    test('$tags: ${command.name} answers', () async {
      final base = await statementBase();
      final args = [
        for (final arg in command.args)
          if (arg == 'PLACEHOLDER') base else arg,
      ];

      final withTail = await runIn(
        await caseProject(tail),
        args,
        console: command.console?.call(),
      );
      final clean = await runIn(
        await caseProject(''),
        args,
        console: command.console?.call(),
      );

      expect(withTail.code, clean.code, reason: withTail.out + withTail.err);
      expect(withTail.out, isNot(contains('Unhandled exception')));
      expect(withTail.err, isNot(contains('Unhandled exception')));
    });
  }
}

/// Returns the statement base hash of the read fixture's fr01.
Future<String> statementBase() async {
  final run = await runIn(await caseProject(''), ['get', fr, '--json']);
  final docs = (jsonDecode(run.out) as Map)['docs']! as List;
  final bases = (docs.first as Map)['bases']! as Map;
  return (bases['sections'] as Map)['statement']! as String;
}

const unparsedWarning =
    '\u26A0\uFE0F WARNING: '
    'prds/features/f01_login/us01_email_login/fr01_validate_credentials.md: '
    'the markdown parser failed; its links are not indexed';

void main() {
  everyCommandAnswers('\n[x](%DB.md)\n', [
    ...readWriteCommands,
    ...buildCommands,
  ], tags: 'f01/us01/fr02, f05/us02/fr03/e10, LP1');

  test('f04/us02/fr04/e08, LP1: check reports the link as written', () async {
    final run = await runIn(await caseProject('\n[x](%DB.md)\n'), ['check']);

    expect(
      run.out,
      contains(
        'prds/features/f01_login/us01_email_login/fr01_validate_credentials.md'
        ':16: link_unresolved: link target %DB.md is no doc\n',
      ),
    );
    expect(run.err, isNot(contains('Unhandled exception')));
  });

  test('f05/us02/fr03/e10, LP1: build shows the path', () async {
    final project = await caseProject('\n[x](%DB.md)\n');
    final run = await runIn(project, [
      'build',
      'docs/prds/features/f01_login',
      '--output',
      'out.html',
    ]);

    expect(run.code, 0, reason: run.out + run.err);
    final html = File.fromUri(project.uri.resolve('out.html'))
        .readAsStringSync();
    expect(
      html,
      contains(
        '<code>prds/features/f01_login/us01_email_login/\u{FFFD}.md</code>',
      ),
    );
  });

  everyCommandAnswers(
    '\n[a]:<b\\',
    readWriteCommands,
    tags: 'f01/us01/fr03/e12, s03/inv24, LP3',
  );

  test('f01/us01/fr03/e12, s03/inv24, LP3: structure warns on each read until '
      'the doc is fixed', () async {
    const tail = '\n[a]:<b\\';
    final project = await caseProject(tail);

    final first = await runIn(project, ['structure']);
    final second = await runIn(project, ['structure']);

    expect(first.code, 0, reason: first.out + first.err);
    expect(first.err, contains(unparsedWarning));
    expect(second.code, 0, reason: second.out + second.err);
    expect(second.err, contains(unparsedWarning));

    final doc = File.fromUri(project.uri.resolve(frFile));
    final text = doc.readAsStringSync();
    doc.writeAsStringSync(text.substring(0, text.length - tail.length));
    final fixed = await runIn(project, ['structure']);

    expect(fixed.code, 0, reason: fixed.out + fixed.err);
    expect(fixed.out, isNot(contains('the markdown parser failed')));
    expect(fixed.err, isNot(contains('the markdown parser failed')));
  });

  for (final tail in [
    '\n[a]: <',
    '\n[^1]\n\n[^1]: - note\n',
    '\n[a]: /b (c\n| :--- | ---: |\n',
    '\n${'> ' * 100000}x\n',
  ]) {
    test(
      'f01/us01/fr03/e12, LP2: each parser fault class answers '
      '(${tail.length > 40 ? 'deep blockquote' : jsonEncode(tail)})',
      () async {
        final run = await runIn(await caseProject(tail), ['structure']);

        expect(run.code, 0, reason: run.out + run.err);
        expect(run.err, contains(unparsedWarning));
      },
    );
  }

  test(
    'f01/us07/fr01/e11, LP3: refs lists no link from the unparsed doc',
    () async {
      final unparsed = await runIn(await caseProject('\n[a]:<b\\'), [
        'refs',
        story,
        '--json',
      ]);
      final clean = await runIn(await caseProject(''), [
        'refs',
        story,
        '--json',
      ]);

      expect(unparsed.code, 0, reason: unparsed.out + unparsed.err);
      expect(_linkEntries(unparsed.out), isEmpty);
      expect(_linkEntries(clean.out), isNotEmpty);
    },
  );

  test('f02/us05/fr02/e08, dw-s03/inv10, LP3: a rename keeps every byte of the '
      'unparsed doc and warns', () async {
    final project = await caseProject('\n[a]:<b\\');
    final before = File.fromUri(project.uri.resolve(frFile)).readAsBytesSync();

    final run = await runIn(project, [
      'rename',
      'user_story:$story',
      '--to',
      'email_signin',
    ]);

    expect(run.code, 0, reason: run.out + run.err);
    expect(
      run.err,
      contains('the markdown parser failed; its links are not indexed'),
    );
    final moved = File.fromUri(
      project.uri.resolve(
        'docs/prds/features/f01_login/us01_email_signin/'
        'fr01_validate_credentials.md',
      ),
    );
    expect(moved.readAsBytesSync(), before);
  });
}

/// The entries of kind `link` in the `refs --json` output [out].
List<Object?> _linkEntries(String out) {
  final found = <Object?>[];
  void visit(Object? node) {
    if (node is Map) {
      if (node['kind'] == 'link') found.add(node);
      node.values.forEach(visit);
    } else if (node is List) {
      node.forEach(visit);
    }
  }

  visit(jsonDecode(out));
  return found;
}
