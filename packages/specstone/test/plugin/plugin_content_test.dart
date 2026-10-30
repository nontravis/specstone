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

  test('f08/us01/fr04/e02, nfr-te01: a reference file that brings a folder to '
      '1,620 est. tokens fails naming it', () async {
    final root = await writeTree({
      'skills/x/SKILL.md': 'a' * 4000,
      'skills/x/reference.md': 'b' * 2480,
    });
    expect(oversizedSkills(root), ['skills/x: 1620 est. tokens, over 1500']);
  });

  test(
    'f08/us01/fr04/e03: an agent file is name-checked and never sized',
    () async {
      final valid =
          '${'a' * 8000}\n`specstone check` `specstone hook post-edit`';
      expect(await _problemsOf({'agents/a.md': valid}), isEmpty);
      expect(oversizedSkills(await writeTree({'agents/a.md': valid})), isEmpty);
      expect(await _problemsOf({'agents/a.md': '$valid `specstone nope`'}), [
        'agents/a.md: specstone has no command nope',
      ]);
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

  test('f08/us01/fr04, nfr-te01: every shipped skill folder stays within '
      '1,500 est. tokens', () {
    expect(oversizedSkills(pluginRoot()), isEmpty);
  });

  test('f08/us06/fr01: hooks.json holds one PostToolUse Write|Edit command '
      'hook running specstone hook post-edit', () {
    final decoded = jsonDecode(
      File.fromUri(pluginRoot().uri.resolve('hooks/hooks.json'))
          .readAsStringSync(),
    );
    expect(decoded, {
      'hooks': {
        'PostToolUse': [
          {
            'matcher': 'Write|Edit',
            'hooks': [
              {'type': 'command', 'command': 'specstone hook post-edit'},
            ],
          },
        ],
      },
    });
    final hook = SpecstoneCommandRunner().commands['hook'];
    expect(hook?.subcommands, contains('post-edit'));
  });
}
