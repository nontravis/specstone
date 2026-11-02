import 'dart:convert';
import 'dart:io';

import 'package:specstone/src/command_runner.dart';
import 'package:test/test.dart';

import '../helpers/plugin_content.dart';
import '../helpers/temp_tree.dart';

Future<List<String>> _problemsOf(Map<String, String> files) async {
  final root = await writeTree(files);
  return unknownCliNames(root, SpecstoneCommandRunner());
}

void main() {
  test('f08/us01/fr04/e01, f08/us01/s5: a skill naming specstone check --fix '
      'fails naming its file and --fix', () async {
    expect(
      await _problemsOf({'skills/x/SKILL.md': 'Run `specstone check --fix`.'}),
      ['skills/x/SKILL.md: specstone check has no --fix'],
    );
  });

  test(
    'f08/us01/fr04, f08/us01/s5: a command the CLI lacks fails naming it',
    () async {
      expect(
        await _problemsOf({'skills/x/SKILL.md': 'Run `specstone lint docs`.'}),
        ['skills/x/SKILL.md: specstone has no command lint'],
      );
    },
  );

  test('f08/us01/fr04: a span with no specstone call, a skill name, a '
      'placeholder, and prose pass', () async {
    expect(
      await _problemsOf({
        'skills/x/SKILL.md':
            'Use `git diff --name-only`, `specstone:read-sdd`, and '
            '`specstone <command>` with the specstone CLI.',
      }),
      isEmpty,
    );
  });

  test('f08/us01/fr04: a flag a subcommand lacks fails naming the full '
      'command path', () async {
    expect(
      await _problemsOf({
        'skills/x/SKILL.md': 'Run `specstone hook post-edit --x`.',
      }),
      ['skills/x/SKILL.md: specstone hook post-edit has no --x'],
    );
  });

  test('f08/us01/fr04: an end-of-options -- names no flag', () async {
    expect(
      await _problemsOf({
        'skills/x/SKILL.md': 'Run `specstone set -- <path>`.',
      }),
      isEmpty,
    );
  });

  test('f08/us01/fr04: fenced lines and subcommands are checked', () async {
    expect(
      await _problemsOf({
        'skills/x/SKILL.md':
            '```sh\nspecstone hook post-edit\nspecstone hook nope\n```\n',
      }),
      ['skills/x/SKILL.md: specstone hook has no command nope'],
    );
  });

  test('f08/us01/fr04/e02, nfr-te01: a reference file of 1,620 est. tokens '
      'fails alone naming it', () async {
    final root = await writeTree({
      'skills/x/SKILL.md': 'a' * 4000,
      'skills/x/reference.md': 'b' * 6480,
    });
    expect(oversizedSkillFiles(root), [
      'skills/x/reference.md: 1620 est. tokens, over 1500',
    ]);
  });

  test('f08/us01/fr04, nfr-te01: files of one skill that sum past 1,500 est. '
      'tokens pass when each stays within it', () async {
    final root = await writeTree({
      'skills/x/SKILL.md': 'a' * 4000,
      'skills/x/reference.md': 'b' * 4000,
    });
    expect(oversizedSkillFiles(root), isEmpty);
  });

  test(
    'f08/us01/fr04/e03: an agent file is name-checked and never sized',
    () async {
      final valid =
          '${'a' * 8000}\n`specstone check` `specstone hook post-edit`';
      expect(await _problemsOf({'agents/a.md': valid}), isEmpty);
      expect(
        oversizedSkillFiles(
          await writeTree({'skills/x/SKILL.md': 'small', 'agents/a.md': valid}),
        ),
        isEmpty,
      );
      expect(await _problemsOf({'agents/a.md': '$valid `specstone nope`'}), [
        'agents/a.md: specstone has no command nope',
      ]);
    },
  );

  test('f08/us01/fr04, nfr-te01: oversized skill files list sorted, nested '
      'and non-md files are sized, exactly-limit files pass', () async {
    final root = await writeTree({
      'skills/y/b.md': 'a' * 6004,
      'skills/y/a.md': 'a' * 6004,
      'skills/y/sub/e.md': 'a' * 6004,
      'skills/y/c.txt': 'a' * 6004,
      'skills/y/d.md': 'a' * 6000,
    });
    expect(oversizedSkillFiles(root), [
      'skills/y/a.md: 1501 est. tokens, over 1500',
      'skills/y/b.md: 1501 est. tokens, over 1500',
      'skills/y/c.txt: 1501 est. tokens, over 1500',
      'skills/y/sub/e.md: 1501 est. tokens, over 1500',
    ]);
  });

  test(
    'f08/us01/fr04: no skills folder means no oversized skill file',
    () async {
      final root = await writeTree({'agents/a.md': 'text'});
      expect(oversizedSkillFiles(root), isEmpty);
    },
  );

  test('f08/us01/fr04/e04: CRLF line ends count as LF', () async {
    const text = 'one\ntwo\nthree\nfour\n';
    final lf = await writeTree({'skills/x/SKILL.md': text});
    final crlf = await writeTree({
      'skills/x/SKILL.md': text.replaceAll('\n', '\r\n'),
    });
    expect(estTokensOf(Directory('${crlf.path}/skills/x')), 4);
    expect(
      estTokensOf(Directory('${crlf.path}/skills/x')),
      estTokensOf(Directory('${lf.path}/skills/x')),
    );
  });

  test('f08/us01/fr04, f08/us01/s5: every shipped skill and agent names only '
      'commands and flags the CLI has', () {
    expect(unknownCliNames(pluginRoot(), SpecstoneCommandRunner()), isEmpty);
  });

  test('f08/us01/fr04, nfr-te01: every shipped skill file stays within '
      '1,500 est. tokens', () {
    expect(oversizedSkillFiles(pluginRoot()), isEmpty);
  });

  test(
    'f08/us02/fr05/e07: a line with a letter outside the Latin script '
    'fails naming its file and line; accents, emoji, and symbols pass',
    () async {
      final root = await writeTree({
        'skills/x/SKILL.md': 'Old text, café.\nMark it `เดิม:`.\n📜 ⊆ … —\n',
        'hooks/h.sh': '# 日本\n',
      });

      expect(nonLatinLetterLines(root), [
        'hooks/h.sh:1',
        'skills/x/SKILL.md:2',
      ]);
    },
  );

  test("f08/us02/fr05/e07: no shipped plugin file presumes the Owner's "
      'language with a letter outside the Latin script', () {
    expect(nonLatinLetterLines(pluginRoot()), isEmpty);
  });

  test('f08/us06/fr01, f09/us05/fr01/e05, ms-r12: hooks.json keeps only the '
      'PostToolUse Write|Edit hook beside the SessionStart entry', () {
    final decoded = jsonDecode(
      File.fromUri(pluginRoot().uri.resolve('hooks/hooks.json'))
          .readAsStringSync(),
    ) as Map<String, dynamic>;
    final hooks = decoded['hooks'] as Map<String, dynamic>;
    expect(hooks.keys, unorderedEquals(['PostToolUse', 'SessionStart']));
    expect(hooks['PostToolUse'], [
      {
        'matcher': 'Write|Edit',
        'hooks': [
          {'type': 'command', 'command': 'specstone hook post-edit'},
        ],
      },
    ]);
    final hook = SpecstoneCommandRunner().commands['hook'];
    expect(hook?.subcommands.keys, unorderedEquals(['post-edit']));
  });

  _shippedFileTests();
  _procedureTests();
  _handOffTests();
}

typedef _Shipped = ({
  String file,
  String name,
  String tags,
  List<String> commands,
});

const _shipped = <_Shipped>[
  (
    file: 'skills/expert-sdd/SKILL.md',
    name: 'expert-sdd',
    tags: 'f08/us02/fr04, f08/us01/fr03, f08/us02/s5',
    commands: ['guide', 'set', 'check'],
  ),
  (
    file: 'skills/read-sdd/SKILL.md',
    name: 'read-sdd',
    tags: 'f08/us01/fr01, f08/us01/fr03, f08/us01/s1',
    commands: ['context'],
  ),
  (
    file: 'agents/sdd-reader.md',
    name: 'sdd-reader',
    tags: 'f08/us01/fr02, f08/us01/fr03, f08/us01/s1',
    commands: ['context'],
  ),
  (
    file: 'skills/sync-sdd/SKILL.md',
    name: 'sync-sdd',
    tags:
        'f08/us03/fr01, f08/us03/fr02, f08/us03/fr03, f08/us01/fr03, '
        'f08/us03/s1',
    commands: ['check', 'get', 'set'],
  ),
  (
    file: 'agents/sdd-engineer.md',
    name: 'sdd-engineer',
    tags:
        'f08/us02/fr02, f08/us03/fr02, f08/us05/fr01, f08/us01/fr03, '
        'f08/us02/s1, f08/us03/s2',
    commands: ['guide', 'new', 'set', 'check'],
  ),
  (
    file: 'skills/brainstorming-sdd/SKILL.md',
    name: 'brainstorming-sdd',
    tags: 'f08/us02/fr01, f08/us01/fr03, f08/us02/s4',
    commands: ['context'],
  ),
  (
    file: 'skills/update-sdd/SKILL.md',
    name: 'update-sdd',
    tags: 'f08/us02/fr03, f08/us01/fr03, f08/us02/s2',
    commands: ['check', 'get', 'set', 'approve'],
  ),
  (
    file: 'skills/init/SKILL.md',
    name: 'init',
    tags: 'f08/us04/fr01, f08/us04/s1',
    commands: ['init', 'guide', 'set', 'approve'],
  ),
  (
    file: 'skills/bootstrap-prd/SKILL.md',
    name: 'bootstrap-prd',
    tags:
        'f08/us05/fr01, f08/us05/fr02, f08/us05/fr03, f08/us01/fr03, '
        'f08/us05/s1',
    commands: ['check'],
  ),
  (
    file: 'skills/bootstrap-spec/SKILL.md',
    name: 'bootstrap-spec',
    tags:
        'f08/us05/fr01, f08/us05/fr02, f08/us05/fr03, f08/us01/fr03, '
        'f08/us05/s1',
    commands: ['check'],
  ),
];

final _frontmatterName = RegExp(r'^---\r?\n(?:.*\r?\n)*?name:\s*(\S+)');

void _shippedFileTests() {
  for (final shipped in _shipped) {
    test('${shipped.tags}: ${shipped.file} carries its frontmatter name and '
        'row commands, and a skill opens on a specstone command', () {
      final file = File.fromUri(pluginRoot().uri.resolve(shipped.file));
      expect(file.existsSync(), isTrue, reason: '${shipped.file} is missing');
      final text = file.readAsStringSync();
      expect(_frontmatterName.firstMatch(text)?.group(1), shipped.name);
      final commands = cliCommands(text);
      expect(commands, containsAll(shipped.commands));
      if (shipped.file.startsWith('skills/')) {
        final first = commands.first;
        if (shipped.name == 'init') {
          expect(first, 'init');
        } else {
          expect(SpecstoneCommandRunner().commands, contains(first));
        }
      }
    });
  }
}

typedef _Procedure = ({String file, String tags, List<String> commands});

const _procedures = <_Procedure>[
  (
    file: 'skills/sync-sdd/references/procedure.md',
    tags: 'f08/us03/fr01, f08/us03/fr02, f08/us03/fr03',
    commands: ['context', 'set', 'check'],
  ),
  (
    file: 'skills/bootstrap-prd/references/procedure.md',
    tags: 'f08/us05/fr01, f08/us05/fr02, f08/us05/fr03',
    commands: ['check', 'guide', 'new', 'set', 'delete'],
  ),
  (
    file: 'skills/bootstrap-spec/references/procedure.md',
    tags: 'f08/us05/fr01, f08/us05/fr02, f08/us05/fr03',
    commands: ['check', 'guide', 'new', 'set', 'delete'],
  ),
];

void _procedureTests() {
  for (final procedure in _procedures) {
    test('${procedure.tags}: ${procedure.file} exists and names its row '
        'commands', () {
      final file = File.fromUri(pluginRoot().uri.resolve(procedure.file));
      expect(file.existsSync(), isTrue, reason: '${procedure.file} is missing');
      expect(
        cliCommands(file.readAsStringSync()),
        containsAll(procedure.commands),
      );
    });
  }
}

/// Each skill that hands its work to `specstone:sdd-engineer`; both read the
/// skill's `references/procedure.md`.
const _handOffs = ['sync-sdd', 'bootstrap-prd', 'bootstrap-spec'];

String _pluginText(String file) =>
    File.fromUri(pluginRoot().uri.resolve(file)).readAsStringSync();

final _frontmatter = RegExp(r'^---\r?\n(?:.*\r?\n)*?---\r?\n');

/// [text] without its frontmatter: a `description` may name a command, such
/// as `specstone migrate`, that the skill never calls.
String _bodyOf(String text) => text.replaceFirst(_frontmatter, '');

void _handOffTests() {
  test('f08/us03/fr01, f08/us05/fr01: a hand-off skill opens on check, '
      'dispatches specstone:sdd-engineer, and names the procedure the agent '
      'reads', () {
    final agent = _pluginText('agents/sdd-engineer.md');
    for (final skill in _handOffs) {
      final path =
          '\${CLAUDE_PLUGIN_ROOT}/skills/$skill/references/procedure.md';
      final text = _pluginText('skills/$skill/SKILL.md');
      expect(text, contains('`specstone:sdd-engineer`'), reason: skill);
      expect(text, contains(path), reason: skill);
      expect(cliCommands(_bodyOf(text)).first, 'check', reason: skill);
      expect(agent, contains(path), reason: 'agents/sdd-engineer.md, $skill');
    }
  });
}
