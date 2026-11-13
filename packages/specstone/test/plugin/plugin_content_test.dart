import 'dart:convert';
import 'dart:io';

import 'package:specstone/src/command_runner.dart';
import 'package:test/test.dart';

import '../helpers/hook_command.dart';
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
    final root = await writeTree({
      'skills/x/at_limit.md': 'a\r\n' * 3000,
      'skills/x/over.md': 'a\r\n' * 3002,
    });
    expect(oversizedSkillFiles(root), [
      'skills/x/over.md: 1501 est. tokens, over 1500',
    ]);
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
          {
            'type': 'command',
            'command': r'/bin/sh "${CLAUDE_PLUGIN_ROOT}/hooks/post-edit.sh"',
          },
        ],
      },
    ]);
    final hook = SpecstoneCommandRunner().commands['hook'];
    expect(hook?.subcommands.keys, unorderedEquals(['post-edit']));
  });

  test('g8-r11: every script hooks.json names exists under hooks/', () {
    final decoded = jsonDecode(
      File.fromUri(pluginRoot().uri.resolve('hooks/hooks.json'))
          .readAsStringSync(),
    ) as Map<String, dynamic>;
    final scriptNamed = RegExp(r'/hooks/([\w.-]+\.sh)"$');

    for (final event in (decoded['hooks'] as Map<String, dynamic>).keys) {
      final name = scriptNamed.firstMatch(hookCommandOf(event))?.group(1);

      expect(name, isNotNull, reason: '$event names no script under hooks/');
      expect(
        File.fromUri(pluginRoot().uri.resolve('hooks/$name')).existsSync(),
        isTrue,
        reason: '$event names hooks/$name',
      );
    }
  });

  _shippedFileTests();
  _procedureTests();
  _handOffTests();
  _leadAndMermaidTests();
  _agentTests();
  _sizeFixTests();
  _batchGuideTests();
  _otherPluginSkillTests();
  _planTests();
  _codeParseTests();
}

const _nameOnly = 'agent_plugin/ground_a_task/name_only_existing_commands';

Future<List<String>> _skillProblemsOf(String markdown) async {
  final root = await writeTree({'skills/x/SKILL.md': markdown});
  return otherPluginSkillNames(root, shippedDocTypes());
}

const _otherSkill = "skills/x/SKILL.md: a:b is another plugin's skill";

void _codeParseTests() {
  test('$_nameOnly: a span wrapped over two lines is read whole, and the span '
      'after it is still read', () async {
    expect(await _skillProblemsOf('Run `specstone get\nfr:x` then `a:b`.'), [
      _otherSkill,
    ]);
    expect(
      await _problemsOf({'skills/x/SKILL.md': 'Run `specstone check\n--fix`.'}),
      ['skills/x/SKILL.md: specstone check has no --fix'],
    );
  });

  test('$_nameOnly: a ~~~ fence is a code block, so its text is no inline '
      'span and its lines are checked', () async {
    expect(await _skillProblemsOf('~~~\n`a:b`\n~~~\n'), isEmpty);
    expect(
      await _problemsOf({'skills/x/SKILL.md': '~~~sh\nspecstone nope\n~~~\n'}),
      ['skills/x/SKILL.md: specstone has no command nope'],
    );
  });

  test(
    '$_nameOnly: a fence inside a list item or a quote is a code block',
    () async {
      expect(await _skillProblemsOf('- ```\n  `a:b`\n  ```\n'), isEmpty);
      expect(await _skillProblemsOf('> ```\n> `a:b`\n> ```\n'), isEmpty);
      expect(
        await _problemsOf({
          'skills/x/SKILL.md': '- ```sh\n  specstone nope\n  ```\n',
        }),
        ['skills/x/SKILL.md: specstone has no command nope'],
      );
      expect(
        await _problemsOf({
          'skills/x/SKILL.md': '> ```sh\n> specstone nope\n> ```\n',
        }),
        ['skills/x/SKILL.md: specstone has no command nope'],
      );
    },
  );

  test('$_nameOnly: a four-backtick fence holding a three-backtick line stays '
      'one code block', () async {
    expect(await _skillProblemsOf('````\n```\n`a:b`\n```\n````\n'), isEmpty);
    expect(await _skillProblemsOf('````\n```\n````\n`a:b`\n'), [_otherSkill]);
  });

  test('$_nameOnly: an unclosed fence runs to the end of the file', () async {
    expect(await _skillProblemsOf('`a:b`\n```\n`c:d`\n'), [_otherSkill]);
    expect(
      await _problemsOf({'skills/x/SKILL.md': '- ```sh\n  specstone nope\n'}),
      ['skills/x/SKILL.md: specstone has no command nope'],
    );
  });
}

/// The spans E06 names that carry no skill-name form, or a doc type prefix.
const _docCitations = [
  '`domain:document_writing#invariants`',
  '`tech_stack:tech_stack`',
  '`fr:<name>`',
  '`<type>:<name>`',
  '`<path>:<line>`',
  '`project:project`',
  '`gnfr:gnfr`',
  '`features:features`',
  '`specstone:plan-sdd`',
];

void _otherPluginSkillTests() {
  test('$_nameOnly E05: a skill file naming superpowers:writing-plans fails '
      'naming the file and the span', () async {
    final root = await writeTree({
      'skills/x/SKILL.md': 'Then run `superpowers:writing-plans`.',
    });
    expect(otherPluginSkillNames(root, shippedDocTypes()), [
      "skills/x/SKILL.md: superpowers:writing-plans is another plugin's skill",
    ]);
  });

  test('$_nameOnly E03: an agent file holding path:line fails naming the '
      'file and the span', () async {
    final root = await writeTree({
      'agents/a.md': 'Cite each hit as `path:line`.',
    });
    expect(otherPluginSkillNames(root, shippedDocTypes()), [
      "agents/a.md: path:line is another plugin's skill",
    ]);
  });

  test('$_nameOnly E06: a doc citation, a placeholder, a doc-type prefix, and '
      'a specstone skill pass', () async {
    final root = await writeTree({
      'skills/x/SKILL.md': 'Cite ${_docCitations.join(', ')}.',
      'agents/a.md': 'Cite ${_docCitations.join(', ')}.',
    });
    expect(otherPluginSkillNames(root, shippedDocTypes()), isEmpty);
  });

  test('$_nameOnly: shippedDocTypes holds the doc types the packs define, '
      'project, features, and gnfr among them', () {
    expect(
      shippedDocTypes(),
      containsAll(['project', 'features', 'gnfr', 'fr', 'tech_stack']),
    );
  });

  test('$_nameOnly: a fenced line and a span holding a space never have the '
      'form, and a repeated span lists once', () async {
    final root = await writeTree({
      'skills/x/SKILL.md':
          '```\nsuperpowers:writing-plans\n```\n'
          '`superpowers:writing-plans now` `a:b` `a:b`\n',
    });
    expect(otherPluginSkillNames(root, shippedDocTypes()), [
      "skills/x/SKILL.md: a:b is another plugin's skill",
    ]);
  });

  test("$_nameOnly: no shipped plugin file names another plugin's skill", () {
    expect(otherPluginSkillNames(pluginRoot(), shippedDocTypes()), isEmpty);
  });
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
        'f08/us02/fr02, f08/us02/fr06, f08/us02/fr07, f08/us03/fr02, '
        'f08/us05/fr01, f08/us01/fr03, f08/us02/s1, f08/us03/s2',
    commands: ['new', 'set', 'check'],
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
  (
    file: 'skills/plan-sdd/SKILL.md',
    name: 'plan-sdd',
    tags: 'agent_plugin/plan_approved_stories/run_plan_skill',
    commands: ['check', 'list'],
  ),
  (
    file: 'agents/plan-engineer.md',
    name: 'plan-engineer',
    tags: 'agent_plugin/plan_approved_stories/write_grounded_plan',
    commands: ['context', 'check'],
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
  (
    file: 'skills/brainstorming-sdd/references/author.md',
    tags: 'f08/us02/fr01, f08/us02/fr02',
    commands: ['guide', 'new', 'get', 'set', 'search', 'check'],
  ),
  (
    file: 'skills/brainstorming-sdd/references/design.md',
    tags: 'f08/us02/fr01, f08/us02/fr06',
    commands: ['context', 'refs', 'search'],
  ),
  (
    file: 'skills/brainstorming-sdd/references/audit.md',
    tags: 'f08/us02/fr01, f08/us02/fr07',
    commands: ['get', 'context', 'list', 'check'],
  ),
];

void _procedureTests() {
  for (final procedure in _procedures) {
    test('${procedure.tags}, nfr-te01: ${procedure.file} exists, names its '
        'row commands, stays within 1,500 est. tokens, and names only '
        'commands and flags the CLI has', () {
      final file = File.fromUri(pluginRoot().uri.resolve(procedure.file));
      expect(file.existsSync(), isTrue, reason: '${procedure.file} is missing');
      expect(
        cliCommands(file.readAsStringSync()),
        containsAll(procedure.commands),
      );
      bool ofThisFile(String problem) =>
          problem.startsWith('${procedure.file}:');
      expect(oversizedSkillFiles(pluginRoot()).where(ofThisFile), isEmpty);
      expect(
        unknownCliNames(
          pluginRoot(),
          SpecstoneCommandRunner(),
        ).where(ofThisFile),
        isEmpty,
      );
    });
  }
}

/// [text] with every run of whitespace, a wrapped line end included, as one
/// space.
String _oneLine(String text) => text.replaceAll(RegExp(r'\s+'), ' ');

const _mermaidSentence =
    'Quote a node label that holds `(`, `)`, `[`, `]`, `{`, or `}`, as in '
    '`A["Save (draft)"]`; write `"` in it as `#quot;`.';

const _leadSentence =
    'The text between the title and the first `##` section is `#_lead`.';

void _leadAndMermaidTests() {
  for (final skill in ['bootstrap-prd', 'bootstrap-spec']) {
    final file = 'skills/$skill/references/procedure.md';
    test('d-ps2: $file holds the Mermaid quoting sentence and names the '
        '`#_lead` target of `specstone set`', () {
      final text = _oneLine(_pluginText(file));
      expect(text, contains(_mermaidSentence));
      expect(text, contains(_leadSentence));
    });
  }

  test('d-ps2: update-sdd names the `#_lead` target', () {
    expect(
      _oneLine(_pluginText('skills/update-sdd/SKILL.md')),
      contains(_leadSentence),
    );
  });
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

  test('f08/us02/fr05/e07: approval flows paste the printed view', () {
    for (final skill in _handOffs) {
      expect(
        _pluginText('skills/$skill/SKILL.md'),
        isNot(contains("Owner's language")),
        reason: skill,
      );
    }
    expect(
      _pluginText('agents/sdd-engineer.md'),
      isNot(contains("Owner's language")),
    );
    expect(_pluginText('agents/sdd-engineer.md'), contains('never their text'));
    for (final skill in ['expert-sdd', 'update-sdd']) {
      final text = _pluginText('skills/$skill/SKILL.md');
      expect(text, contains('--dry-run'), reason: skill);
      expect(text, contains('`Why:`'), reason: skill);
    }
    expect(
      _pluginText('skills/expert-sdd/SKILL.md'),
      contains('pasted verbatim'),
    );
  });

  test('f08/us02/fr01, f08/us03/fr01, f08/us05/fr01: each dispatching skill '
      'passes a mktemp report file and shows the reply word for word', () {
    for (final skill in [..._handOffs, 'brainstorming-sdd']) {
      final text = _pluginText('skills/$skill/SKILL.md');
      expect(text, contains('`report:`'), reason: skill);
      expect(text, contains('`mktemp`'), reason: skill);
      expect(text, contains('`Report:` line'), reason: skill);
      expect(
        text,
        contains('relay block word for word, before your own notes'),
        reason: skill,
      );
      expect(text, isNot(contains('to the Owner whole')), reason: skill);
    }
    for (final skill in ['bootstrap-prd', 'bootstrap-spec']) {
      expect(
        _pluginText('skills/$skill/SKILL.md'),
        contains('one file `mktemp` makes per batch'),
        reason: skill,
      );
      expect(
        _pluginText('skills/$skill/SKILL.md'),
        contains('`mode: bootstrap`'),
        reason: skill,
      );
    }
  });

  test('f08/us02/fr01, f08/us02/fr06, f08/us02/fr07: brainstorming-sdd '
      'dispatches specstone:sdd-engineer in each of its modes and names the '
      'reference of each mode it can run itself, as the agent does', () {
    final skill = _pluginText('skills/brainstorming-sdd/SKILL.md');
    final agent = _pluginText('agents/sdd-engineer.md');
    expect(skill, contains('`specstone:sdd-engineer`'));
    for (final mode in _brainstormModes) {
      expect(skill, contains('`mode: $mode`'), reason: mode);
      final path =
          '\${CLAUDE_PLUGIN_ROOT}/skills/brainstorming-sdd/references/$mode.md';
      expect(skill, contains(path), reason: 'brainstorming-sdd, $mode');
      expect(agent, contains(path), reason: 'agents/sdd-engineer.md, $mode');
    }
  });

  test('f08/us02/fr02, f08/us02/fr06, f08/us02/fr07, f08/us03/fr02, '
      'f08/us05/fr01: sdd-engineer writes its whole report to the report file '
      'and replies with the Report line and the relay block', () {
    final agent = _pluginText('agents/sdd-engineer.md');
    final input = _sectionOf(agent, 'Input Contract');
    expect(input, contains('**`report`**'));
    expect(input, contains('`mktemp`'));
    expect(input, contains('write `OPEN QUESTIONS:`'));
    final output = _sectionOf(agent, 'Output Format');
    expect(output, contains('`Report: <path>`'));
    expect(output, contains('relay block'));
    expect(output, contains('always including the `Findings:` line'));
    expect(output, contains('each pointer fixed'));
    expect(
      output,
      contains(
        'then `Findings:`, each finding left in `batch` '
        'or added by your writes',
      ),
    );
    expect(output, contains('never their text'));
    for (final mode in ['author', 'design', 'audit', 'sync', 'bootstrap']) {
      expect(
        output,
        contains('**${mode[0].toUpperCase()}${mode.substring(1)}'),
        reason: '$mode names its relay block',
      );
    }
    expect(
      output,
      isNot(contains('**Plan')),
      reason: 'plan-engineer owns the plan relay block',
    );
    expect(output, contains('Every stop, an early one included'));
    expect(output, contains('`## Round <n>`'));
    expect(_sectionOf(agent, 'Scope Boundaries'), contains('`report:`'));
    expect(
      _sectionOf(agent, 'Scope Boundaries'),
      contains(
        'Beyond the `report:` file, `Write` or `Edit` only the one file',
      ),
    );
  });

  test('f08/us02/fr02: no shipped plugin file holds the relay line or '
      'routed by', () {
    for (final file
        in pluginRoot().listSync(recursive: true).whereType<File>()) {
      final text = file.readAsStringSync();
      expect(text, isNot(contains(_relayLine)), reason: file.path);
      expect(text, isNot(contains('routed by')), reason: file.path);
    }
  });

  test('f08/us02/fr01, f08/us02/fr07: the audit report splits Findings, '
      'Waits on the Owner, and Outside the drafts, and only Findings drives '
      'a fix round', () {
    final report = _sectionOf(
      _pluginText('skills/brainstorming-sdd/references/audit.md'),
      '3. Report',
    );
    for (final heading in [
      'Findings:',
      'Waits on the Owner:',
      'Outside the drafts:',
    ]) {
      expect(report, contains('\n$heading\n'), reason: heading);
    }
    expect(
      _pluginText('skills/brainstorming-sdd/SKILL.md'),
      contains('`Findings:` lines'),
    );
  });

  test('agent_plugin/write_prd_and_spec/follow_cross_doc_rules E07, '
      'agent_plugin/write_prd_and_spec/audit_drafts_by_reading, '
      'agent_plugin/write_prd_and_spec/write_drafts_with_coverage E09, '
      'agent_plugin/fill_missing_format/fill_check_findings: each plugin '
      'reader of what waits for the Owner reads waitsFor or its tag, never '
      'message prose', () {
    for (final (file, section) in _ownerFindingReaders) {
      final text = _oneLine(_sectionOf(_pluginText(file), section));
      final where = '$file#$section';
      expect(
        text,
        anyOf(contains('`waitsFor`'), contains('`(waits for the Owner)`')),
        reason: where,
      );
      expect(text, isNot(contains('waits on the Owner')), reason: where);
      expect(
        text,
        isNot(contains("waits for the Owner's approval")),
        reason: where,
      );
    }
    final waits = _oneLine(
      _sectionOf(
        _pluginText('skills/brainstorming-sdd/references/audit.md'),
        '3. Report',
      ),
    );
    expect(
      waits,
      contains(
        'Waits on the Owner: - check: <each finding tagged '
        '(waits for the Owner), as printed>',
      ),
    );
    for (final file
        in pluginRoot().listSync(recursive: true).whereType<File>()) {
      expect(
        _oneLine(file.readAsStringSync().replaceAll('`', '')),
        isNot(contains('unconfirmed link on a draft')),
        reason: file.path,
      );
    }
  });

  test('f08/us02/fr02: author mode runs a bare specstone check before its '
      'first write and after its last', () {
    final check = _sectionOf(
      _pluginText('skills/brainstorming-sdd/references/author.md'),
      '4. Check',
    );
    expect(check, contains('`specstone check`'));
    expect(check, contains('before your first write'));
    expect(check, contains('after your last'));
  });

  test('agent_plugin/write_prd_and_spec/write_drafts_with_coverage E07: the '
      'author report holds the ready move command, and the skill runner runs '
      'it before the audit', () {
    final report = _sectionOf(
      _pluginText('skills/brainstorming-sdd/references/author.md'),
      '5. Report',
    );
    expect(
      report,
      contains(
        '\nMove: specstone move <story> … --under <feature>\n'
        'Move: specstone move <story> … --under <other feature>\n',
      ),
    );
    final flatReport = report.replaceAll(RegExp(r'\s+'), ' ');
    expect(
      flatReport,
      contains(
        'only when the design moves stories, one line per target feature; '
        'copy each into the relay block.',
      ),
    );
    expect(
      flatReport,
      contains(
        'Name each draft a `Move:` line moves, the story and its FRs, by the '
        'name it holds after the move.',
      ),
    );
    final drafts = _sectionOf(
      _pluginText('skills/brainstorming-sdd/SKILL.md'),
      '4. Write the drafts, then audit them',
    );
    final move = drafts.indexOf("Run the author's `Move:` commands");
    expect(move, isNonNegative);
    expect(move, lessThan(drafts.indexOf('`mode: audit`')));
  });

  test('agent_plugin/write_prd_and_spec/write_drafts_with_coverage E10, '
      'domain:agent_plugin INV-4: the drafts list and every count come from '
      'one approve --dry-run --json after the last write, other drafts '
      'named and never counted', () {
    for (final (file, section) in _draftCountReaders) {
      final text = _oneLine(_sectionOf(_pluginText(file), section))
          .toLowerCase();
      final where = '$file#$section';
      expect(
        text,
        contains('`specstone approve --dry-run --json`'),
        reason: where,
      );
      expect(text, contains('after your last write'), reason: where);
      expect(text, contains('every count'), reason: where);
      expect(
        text,
        contains('your drafts are the docs your own list names'),
        reason: where,
      );
      expect(text, contains('never counted'), reason: where);
      expect(text, contains('shows as no draft'), reason: where);
    }
    for (final (file, section) in [
      ('agents/sdd-engineer.md', 'Output Format'),
      ('skills/brainstorming-sdd/references/author.md', '5. Report'),
    ]) {
      final text = _oneLine(_sectionOf(_pluginText(file), section));
      expect(text, contains('never your own tally'), reason: '$file#$section');
    }
    final moved = _oneLine(
      _sectionOf(
        _pluginText('skills/brainstorming-sdd/references/author.md'),
        '5. Report',
      ),
    );
    expect(
      moved,
      contains(
        'while its `Move:` line is unrun, by its name before the move; once '
        'the runner runs it, by its name after',
      ),
    );
    expect(
      _oneLine(_sectionOf(_pluginText('skills/expert-sdd/SKILL.md'), 'Rules')),
      contains(
        'Run `specstone approve` only with `--dry-run`, or with `--yes` as '
        'Owner confirmation below says',
      ),
    );
  });

  test('agent_plugin/write_prd_and_spec/write_drafts_with_coverage E10, '
      'agent_plugin/write_prd_and_spec/run_brainstorm_to_design: the author '
      "report's Drafts line stays a bare list of names that the audit "
      'dispatch and plan-sdd take as it is, its counts on their own line', () {
    final report = _sectionOf(
      _pluginText('skills/brainstorming-sdd/references/author.md'),
      '5. Report',
    );
    expect(
      report,
      contains(
        "\nDrafts for the Owner's specstone approve <type>:<name>: "
        '<type>:<name>, ...\n'
        'Counts: <count> drafts; <type>:<name>: <d> dropped, <n> new; ...\n',
      ),
    );
    expect(
      _sectionOf(_pluginText('agents/sdd-engineer.md'), 'Output Format'),
      contains(
        "the `Drafts for the Owner's specstone approve` line, the `Counts:` "
        'line,',
      ),
    );
  });

  test('agent_plugin/write_prd_and_spec/confirm_gated_commands_with_the_owner: '
      'the Rules and Owner confirmation sections of expert-sdd gate the '
      'delete of a guarded doc', () {
    final skill = _pluginText('skills/expert-sdd/SKILL.md');
    for (final heading in ['Rules', 'Owner confirmation']) {
      expect(
        _sectionOf(skill, heading).replaceAll(RegExp(r'\s+'), ' '),
        contains(
          '`approve`, `delete` of a guarded doc, `migrate`, and `init` on a '
          'legacy tree',
        ),
        reason: heading,
      );
    }
  });

  test('agent_plugin/write_prd_and_spec/confirm_gated_commands_with_the_owner: '
      'the Owner confirmation section of expert-sdd leaves specstone trust to '
      "the Owner's own terminal", () {
    final section = _oneLine(
      _sectionOf(
        _pluginText('skills/expert-sdd/SKILL.md'),
        'Owner confirmation',
      ),
    );
    expect(
      section,
      contains(
        'Never run it or answer its prompt, even through a pty or a shell '
        'tool.',
      ),
    );
    expect(section, contains('`run specstone trust at a terminal`'));
    expect(section, contains("Claude Code's `!` prefix is not a terminal"));
  });

  test('agent_plugin/write_prd_and_spec/follow_cross_doc_rules E08, E09: '
      'the Rules section of expert-sdd holds the one-owner rule and its '
      'citation form and points to confirm-links.md, which alone holds the '
      'steps that confirm a traced link', () {
    final skill = _pluginText('skills/expert-sdd/SKILL.md');
    final rules = _oneLine(_sectionOf(skill, 'Rules'));
    for (final point in _oneOwnerPoints) {
      expect(rules, contains(point), reason: point);
    }
    expect(
      rules,
      contains(
        'When you write an FR, an nf, or an API row, follow '
        '`references/confirm-links.md`',
      ),
    );
    expect(_oneLine(_pluginText(_confirmLinks)), contains(_confirmLinkSteps));
    for (final step in ['bases.fields.confirmed', '--field confirmed']) {
      expect(skill, isNot(contains(step)), reason: step);
    }
  });
}

/// Each point of `follow_cross_doc_rules`' one-owner clause, E08, and E09, as
/// the Rules section of expert-sdd words it.
const _oneOwnerPoints = [
  'A rule has one owner doc.',
  'Every other doc cites it by name, `<type>:<name>` or',
  '`<type>:<name>` or `<type>:<name>#<section>` and the item ID inside it',
  '`domain:document_writing#invariants` INV-9',
  'states nothing of the rule',
  '`specstone refs <owner>` lists each citing doc',
  'a citation pins no hash: it never turns `suspect` when the owner changes',
];

/// The one home of expert-sdd's steps for confirming a traced link.
const _confirmLinks = 'skills/expert-sdd/references/confirm-links.md';

/// Rule 4 of expert-sdd as it read before its steps moved to [_confirmLinks].
const _confirmLinkSteps =
    'When you write an FR (`fr`), an nf (`nf`), or an API row (`api`), record '
    'its `confirmed` entries: run `specstone check <target>` to print each '
    'link it traces, its upstream block, then its fingerprint; read the '
    'block, then write the entries with `specstone set <target> --field '
    'confirmed --base <hash>`. Take `<hash>` from `bases.fields.confirmed` in '
    '`specstone get <target> --json`, never from a fingerprint `check` '
    "prints. A `suspect` link's upstream block moved on since the entry was "
    'recorded: re-read it and confirm again the same way. Your approval '
    'request to the Owner then says what changed upstream.';

/// The path a design document takes when the brainstorm skill keeps none of
/// its own.
const _designPath = 'docs/designs/<YYYY-MM-DD>-<topic>-design.md';

/// The `sdd-engineer` modes that `brainstorming-sdd` dispatches, each with
/// its steps in the skill's `references/<mode>.md`.
const _brainstormModes = ['author', 'design', 'audit'];

/// Each plugin file and `## ` section that says which `check` finding waits for
/// the Owner (`consistency_check/find_template_breaks/print_findings`).
const _ownerFindingReaders = [
  ('skills/expert-sdd/SKILL.md', 'Rules'),
  ('skills/brainstorming-sdd/references/author.md', '4. Check'),
  ('skills/brainstorming-sdd/references/audit.md', '1. Read'),
  ('skills/brainstorming-sdd/references/audit.md', '3. Report'),
  ('skills/bootstrap-prd/references/procedure.md', '2. One finding at a time'),
  ('skills/bootstrap-spec/references/procedure.md', '2. One finding at a time'),
  ('skills/bootstrap-prd/SKILL.md', '3. After the reports'),
  ('skills/bootstrap-spec/SKILL.md', '3. After the reports'),
  ('agents/sdd-engineer.md', 'Workflow'),
  ('agents/sdd-engineer.md', 'Output Format'),
];

/// Each plugin file and `## ` section that says where a writing mode's drafts
/// list and counts come from
/// (`agent_plugin/write_prd_and_spec/write_drafts_with_coverage` E10).
const _draftCountReaders = [
  ('agents/sdd-engineer.md', 'Output Format'),
  ('skills/brainstorming-sdd/references/author.md', '5. Report'),
  ('skills/sync-sdd/references/procedure.md', 'Report to the Owner'),
  (
    'skills/bootstrap-prd/references/procedure.md',
    '6. Fill the skeletons, then ask for approval',
  ),
  (
    'skills/bootstrap-spec/references/procedure.md',
    '6. Fill the tech stack, then ask for approval',
  ),
];

/// The relay line the report file replaced; no shipped file may hold it.
const _relayLine =
    'Main session: show this report to the Owner whole before you act on it.';

/// The body of the `## <heading>` section of [text], up to the next `## `
/// heading; empty when [text] has no such section.
String _sectionOf(String text, String heading) {
  final lines = text.replaceAll('\r\n', '\n');
  final start = lines.indexOf('\n## $heading\n');
  if (start < 0) return '';
  final body = lines.substring(start + '\n## $heading\n'.length);
  final end = body.indexOf('\n## ');
  return end < 0 ? body : body.substring(0, end);
}

/// The `- **`mode`**` bullet with its indented continuation lines, its label
/// left out.
final _modeBullet = RegExp(
  r'^- \*\*`mode`\*\*(.*(?:\n {2}.*)*)',
  multiLine: true,
);

final _codeSpan = RegExp(r'`([^`\n]+)`');

void _agentTests() {
  test(
    'agent_plugin/write_prd_and_spec/write_drafts_with_coverage E04, '
    'sd-r9: the sdd-engineer Input Contract names exactly its five modes',
    () {
      final contract = _sectionOf(
        _pluginText('agents/sdd-engineer.md'),
        'Input Contract',
      );
      final bullet = _modeBullet.firstMatch(contract)?.group(1) ?? '';
      expect([
        for (final span in _codeSpan.allMatches(bullet)) span.group(1),
      ], unorderedEquals(['author', 'sync', 'bootstrap', 'design', 'audit']));
    },
  );

  test('sd-r1: both agent descriptions ask to be used proactively', () {
    final proactive = RegExp(
      '^description:.*[Uu]se proactively',
      multiLine: true,
    );
    for (final agent in ['sdd-engineer', 'sdd-reader']) {
      expect(
        _pluginText('agents/$agent.md'),
        matches(proactive),
        reason: agent,
      );
    }
  });

  test(
    'agent_plugin/write_prd_and_spec/write_drafts_with_coverage E04: the '
    'sdd-engineer description sends sync and bootstrap through their skills '
    'and names the three modes a caller may dispatch directly, plan none',
    () {
      final description = RegExp(
        r'^description:(.*)$',
        multiLine: true,
      ).firstMatch(_pluginText('agents/sdd-engineer.md'))?.group(1);
      expect(description, contains('`specstone:sync-sdd`'));
      expect(description, contains('`specstone:bootstrap-prd`'));
      for (final mode in _brainstormModes) {
        expect(description, contains('`$mode`'), reason: mode);
      }
      expect(description, isNot(contains('`plan`')));
    },
  );

  test('domain:agent_plugin INV-10, '
      'agent_plugin/write_prd_and_spec/write_design_document statement: sdd-engineer holds Write and Edit for '
      'the one design document a design dispatch names, audit and design mode '
      'write no other file but the report file, and no file names '
      'docs/superpowers/', () {
    final agent = _pluginText('agents/sdd-engineer.md');
    final tools = RegExp(
      r'^tools:(.*)$',
      multiLine: true,
    ).firstMatch(agent)?.group(1)?.split(',').map((tool) => tool.trim());
    expect(tools, containsAll(['Write', 'Edit']));
    expect(
      _pluginText('skills/brainstorming-sdd/references/audit.md'),
      contains("Write nothing but the agent's `report:`"),
    );
    final design = _pluginText('skills/brainstorming-sdd/references/design.md');
    expect(
      design,
      contains("Write no other file but the agent's `report:` file"),
    );
    expect(design, contains("write nothing but the agent's `report:` file"));
    final skill = _pluginText('skills/brainstorming-sdd/SKILL.md');
    for (final (file, text) in [
      (
        'agents/sdd-engineer.md Scope Boundaries',
        _sectionOf(agent, 'Scope Boundaries'),
      ),
      ('references/design.md', design),
      ('brainstorming-sdd/SKILL.md', skill),
    ]) {
      expect(text, isNot(contains('docs/superpowers/')), reason: file);
    }
    for (final (file, text) in [
      (
        'agents/sdd-engineer.md Scope Boundaries',
        _sectionOf(agent, 'Scope Boundaries'),
      ),
      ('references/design.md', design),
      ('brainstorming-sdd/SKILL.md', skill),
    ]) {
      expect(text, contains(_designPath), reason: file);
    }
  });

  test('agent_plugin/write_prd_and_spec/run_brainstorm_to_design statement, '
      'E03, E14, E15: brainstorming-sdd hands the approved drafts to '
      'specstone:plan-sdd through Skill and runs no plan mode', () {
    final skill = _oneLine(_pluginText('skills/brainstorming-sdd/SKILL.md'));
    expect(skill, contains('`specstone:plan-sdd`'));
    expect(skill, contains('`Skill`'));
    expect(skill, isNot(contains('mode: plan')));
    expect(skill, isNot(contains('references/plan.md')));
    expect(
      _pluginText('agents/sdd-engineer.md'),
      isNot(contains('references/plan.md')),
    );
    expect(
      _pluginText('skills/brainstorming-sdd/references/author.md'),
      isNot(contains('plan mode')),
    );
  });

  test('agent_plugin/write_prd_and_spec/write_drafts_with_coverage E04: the '
      'plan procedure file is gone, as plan-engineer holds the steps', () {
    final plan = File.fromUri(
      pluginRoot().uri.resolve('skills/brainstorming-sdd/references/plan.md'),
    );
    expect(plan.existsSync(), isFalse);
  });

  test('agent_plugin/ground_a_task/ground_through_context E06: read-sdd names '
      'the context call it runs per cited story, NFR, and spec doc', () {
    expect(
      _oneLine(_pluginText('skills/read-sdd/SKILL.md')),
      contains('specstone context <target> --for implement --budget 20000'),
    );
  });

  test(
    'agent_plugin/ground_a_task/ground_through_context E14: read-sdd runs a '
    "plan task's read line with its --target as written and cites INV-25",
    () {
      final skill = _oneLine(_pluginText('skills/read-sdd/SKILL.md'));
      expect(
        skill,
        contains('specstone context <story> --for implement --target <name>'),
      );
      expect(skill, contains("a plan task's read line's, as written"));
      expect(skill, contains('`domain:agent_plugin` INV-25'));
    },
  );

  test('agent_plugin/ground_a_task/ground_through_context E15: read-sdd gives '
      'a task no plan wrote no --target in query or design mode', () {
    expect(
      _oneLine(_pluginText('skills/read-sdd/SKILL.md')),
      contains('none in `query` or `design`'),
    );
  });

  test('agent_plugin/ground_a_task/ground_through_context E16: read-sdd has a '
      'main session ask the Owner after argument_missing and rerun with '
      '--target', () {
    final skill = _oneLine(_pluginText('skills/read-sdd/SKILL.md'));
    expect(
      skill,
      contains(
        'In `implement` with no plan target and no `--code` path, an '
        '`argument_missing` refusal names the targets: a main session asks '
        'the Owner and reruns with `--target <name>`',
      ),
    );
  });

  test('agent_plugin/ground_a_task/ground_through_context E17: read-sdd has a '
      'Subagent stop and report the missing target to its dispatcher', () {
    expect(
      _oneLine(_pluginText('skills/read-sdd/SKILL.md')),
      contains(
        'a Subagent runs no further call and reports the missing target, '
        'naming them, to its dispatcher',
      ),
    );
  });

  test('agent_plugin/ground_a_task/ground_through_context E18: read-sdd '
      "hands the call's --target to sdd-reader on exit 1", () {
    final skill = _oneLine(_pluginText('skills/read-sdd/SKILL.md'));
    expect(
      skill,
      contains(
        'Dispatch `specstone:sdd-reader` with the same target IDs, '
        "the call's `--target`, the mode, and the task",
      ),
    );
    expect(
      skill,
      contains(
        "`--summary` beside each ID whose call used it, the call's "
        '`--target`, and no doc text',
      ),
    );
  });

  test('agent_plugin/ground_a_task/ground_through_context E05, E13: read-sdd '
      'allows one target a third call after an argument_missing refusal', () {
    expect(
      _oneLine(_pluginText('skills/read-sdd/SKILL.md')),
      contains(
        'one target takes two calls at most, three after an '
        '`argument_missing` refusal',
      ),
    );
  });

  test('agent_plugin/ground_a_task/return_whole_sections E06: sdd-reader runs '
      "context with the hand-off's --target in implement mode and cites "
      'INV-25', () {
    final reader = _oneLine(_pluginText('agents/sdd-reader.md'));
    expect(
      reader,
      contains('specstone context <target> --for <mode> [--summary] '),
    );
    expect(
      reader,
      contains(
        "Add `--target <name>` in `implement` mode: the hand-off's "
        '`--target`, as `domain:agent_plugin` INV-25 gives',
      ),
    );
  });

  test('agent_plugin/ground_a_task/return_whole_sections E07: sdd-reader '
      'passes no --target in query or design mode', () {
    expect(
      _oneLine(_pluginText('agents/sdd-reader.md')),
      contains('none in `query` or `design` mode'),
    );
  });

  test('agent_plugin/write_prd_and_spec/run_brainstorm_to_design E17: the '
      'first design call passes no --budget without the Agent tool and no '
      '--target', () {
    final skill = _oneLine(_pluginText('skills/brainstorming-sdd/SKILL.md'));
    expect(skill, contains('Without the `Agent` tool, pass no `--budget`'));
    expect(
      skill,
      contains(
        'Pass no `--target`: a design read spans every code target '
        '(`domain:agent_plugin` INV-25).',
      ),
    );
  });

  test('agent_plugin/write_prd_and_spec/write_drafts_with_coverage E13: '
      'author takes a per-target doc from the design row, or its DocPath, and '
      'keeps the drafts list free of --target', () {
    final author = _oneLine(
      _pluginText('skills/brainstorming-sdd/references/author.md'),
    );
    expect(
      author,
      contains(
        '**Code target** (two or more `targets:`): pass `--target <name>`, '
        "the one its design document's row names, on each `new`, `get`, and "
        '`set` of a per-target spec doc, or address an existing doc by its '
        'DocPath (`domain:agent_plugin` INV-25).',
      ),
    );
    expect(author, contains('names only, no `--target`'));
    expect(
      author,
      contains('hit in a doc the design changes, as step 2 writes.'),
    );
    expect(
      _oneLine(_pluginText('agents/sdd-engineer.md')),
      contains('each write leaves a draft; never clear its flag'),
    );
    expect(
      _oneLine(_pluginText('agents/sdd-engineer.md')),
      contains(
        '**Code target** (two or more `targets:`, `domain:agent_plugin` '
        'INV-25): author passes `--target <name>`, the code target its '
        "design document's row names, or the doc's DocPath, on each "
        'per-target `new`, `get`, and `set`;',
      ),
    );
  });

  test('agent_plugin/write_prd_and_spec/take_small_edit_to_draft E07: '
      'update-sdd asks which code target for a name in two or more, then '
      "reads and writes on the doc's DocPath", () {
    final skill = _oneLine(_pluginText('skills/update-sdd/SKILL.md'));
    expect(
      skill,
      contains(
        'A name that matches docs in two or more code targets: ask the Owner '
        'which one, as `specstone:plan-sdd` does, then run `get` and `set` '
        "on that doc's DocPath, the one `get`'s doc header prints, such as "
        '`specs/jaspr/f02_feedback/f03_toast/ARCHITECTURE.md` '
        '(`domain:agent_plugin` INV-25). A name that matches one doc asks '
        'nothing.',
      ),
    );
  });

  test('agent_plugin/write_prd_and_spec/follow_cross_doc_rules E02, E06, E09: '
      'expert-sdd gives set (a confirmed write included), structure, and refs '
      'the target of its loader, with no Owner question, and approve and '
      'delete none', () {
    final skill = _oneLine(_pluginText('skills/expert-sdd/SKILL.md'));
    expect(
      skill,
      contains(
        '**Code target.** With two or more code targets, `new`, `get`, `set` '
        '(a `confirmed` write included), `structure <doc>`, and '
        '`refs <owner>` take the `--target` of the surface that loads this '
        'skill, never an Owner question; `approve` and `delete` take none '
        '(`domain:agent_plugin` INV-25).',
      ),
    );
  });

  test('agent_plugin/write_prd_and_spec/write_design_document E17: design '
      'mode runs refs on a per-target owner by its DocPath', () {
    expect(
      _oneLine(_pluginText('skills/brainstorming-sdd/references/design.md')),
      contains('A per-target owner goes to `refs` by its DocPath.'),
    );
  });

  test('agent_plugin/write_prd_and_spec/write_design_document E20: design '
      'mode grounds with no --target and names a code target on each '
      'per-target row', () {
    final design = _oneLine(
      _pluginText('skills/brainstorming-sdd/references/design.md'),
    );
    expect(
      design,
      contains(
        'Pass no `--target`: a design read spans every code target '
        '(`domain:agent_plugin` INV-25).',
      ),
    );
    expect(
      design,
      contains(
        "With two or more `targets:`, a per-target spec doc's row also names "
        'its code target, a row with none an open question '
        '(`domain:agent_plugin` INV-25).',
      ),
    );
  });

  test('agent_plugin/write_prd_and_spec/audit_drafts_by_reading E16: audit '
      'mode passes no --target on its design bundles or its drafts get', () {
    final audit = _oneLine(
      _pluginText('skills/brainstorming-sdd/references/audit.md'),
    );
    expect(
      audit,
      contains(
        "Pass no `--target`: the bundle takes every code target's spec docs "
        '(`domain:agent_plugin` INV-25).',
      ),
    );
    expect(
      audit,
      contains(
        "The drafts list's names need no `--target` (`domain:agent_plugin` "
        'INV-25).',
      ),
    );
    expect(
      _oneLine(_pluginText('agents/sdd-engineer.md')),
      contains(
        'design writes a code target on each per-target spec doc row; design '
        'and audit pass no `--target` on `context --for design`.',
      ),
    );
  });

  test('agent_plugin/write_prd_and_spec/run_brainstorm_to_design E13: the '
      're-audit get of the drafts list needs no --target', () {
    expect(
      _oneLine(_pluginText('skills/brainstorming-sdd/references/rounds.md')),
      contains(
        "The drafts list's names need no `--target` (`domain:agent_plugin` "
        'INV-25).',
      ),
    );
  });

  group('agent_plugin/sync_code_and_docs', () {
    const targetLine =
        '**Code target** (two or more `targets:`, `domain:agent_plugin` '
        "INV-25): a changed path's target is the `code target:` line, or the "
        '`codeTarget` key under `--json`, of its `context --code` call, '
        "covered or not, and a deleted path's is the finding DocPath's, so "
        'ask the Owner nothing; each `get`, `set`, and `new` of a per-target '
        'doc carries `--target <name>`, or addresses the doc by its DocPath.';
    const recordWrite =
        '`specstone set implementation:<feature> --field implements '
        '--target <name> --base <hash>`';

    String procedure() =>
        _oneLine(_pluginText('skills/sync-sdd/references/procedure.md'));

    test('find_specs_for_changed_code E02: a deleted file shows as a record '
        'entry in check, fixed in step 4.3', () {
      expect(
        procedure(),
        contains(
          '`specstone check` lists the record entries that still name it; '
          'step 4.3 fixes them.',
        ),
      );
    });

    test("domain:agent_plugin INV-25: the sync procedure takes the path's "
        'target by the longest code root and asks the Owner nothing', () {
      expect(procedure(), contains(targetLine));
      expect(
        procedure(),
        contains(
          "takes its path's code target, prints it, and carries no `--target`",
        ),
      );
    });

    test('update_covering_docs E01: a moved file takes the new path in its '
        "target's record, and the stories and FRs stay as they are", () {
      final text = procedure();
      expect(text, contains(recordWrite));
      expect(
        text,
        contains(
          'moved file: point each record entry that names it at the new side '
          "of its rename pair, relative to that target's code root; the "
          'stories and FRs, which name no code, stay as they are;',
        ),
      );
    });

    test('update_covering_docs E03: a record code-path write leaves the '
        'draft flag untouched', () {
      expect(
        procedure(),
        contains(
          'A record code-path or `covers:` write leaves the draft flag '
          'untouched: an approved doc keeps its approval.',
        ),
      );
    });

    test('update_covering_docs E05: a path in one target compares and fixes '
        "that target's record and covers entries alone", () {
      expect(
        procedure(),
        contains(
          "A changed path's target alone: compare and fix its record and "
          "`covers:` entries, never another target's.",
        ),
      );
    });

    test("update_covering_docs pointers row: the skill's waiting pointer "
        'goes to the target record, each form with its base and --target', () {
      final skill = _oneLine(_pluginText('skills/sync-sdd/SKILL.md'));
      expect(
        skill,
        contains(
          'pipe the corrected list to `specstone set implementation:<feature> '
          '--field implements --base <hash>` (or `specstone set <type>:<name> '
          '--field covers --base <hash>`), each with `--target <name>`, the '
          'target the report gives for that pointer, when the project has '
          'two or more '
          '(`domain:agent_plugin` INV-25), the hash from '
          '`bases.fields.implements` (or `bases.fields.covers`) of '
          '`specstone get <doc> --json` for the same doc, with the same '
          '`--target`.',
        ),
      );
    });

    test('update_covering_docs pointers row: the report lists each waiting '
        'pointer with its doc and its code path', () {
      expect(
        procedure(),
        contains(
          'and each pointer that waits on an approval, with its doc, its code '
          'target, and its code path.',
        ),
      );
    });

    test('draft_spec_for_uncovered_code E03: a new or set draft carries the '
        "--code path's target, one target none", () {
      expect(
        procedure(),
        contains(
          '`specstone new <type>` (`--parent <name>`, `--slug <slug>`, '
          "`--target <name>`, the path's code target, as the type takes them)",
        ),
      );
    });

    test('draft_spec_for_uncovered_code E02: no record code path names the '
        'new code before approval; the pointer goes to the target record '
        'after it', () {
      expect(
        procedure(),
        contains(
          'Write no record code path or `covers:` entry that names this code '
          'until the Owner approves the draft. Then add the entry at once '
          "with the step 4.3 `specstone set --field` write, on the path's "
          "target's record:",
        ),
      );
    });

    test('sdd-engineer names the sync target source and the record entry '
        'write on its Code target line', () {
      expect(
        _oneLine(_pluginText('agents/sdd-engineer.md')),
        contains(
          "sync takes the `--code` path's code target, or the finding "
          "DocPath's, on each per-target `get`, `set`, and `new`, and writes "
          "code paths to that target's record entry, never to an FR;",
        ),
      );
    });
  });

  group('agent_plugin/set_up_new_project', () {
    String init() => _oneLine(_pluginText('skills/init/SKILL.md'));

    test('set_up_and_fill_drafts E04: a code root with no folder draws no '
        'finding until a record entry is implemented', () {
      expect(
        init(),
        contains(
          'A listed folder that does not exist yet draws no finding while no '
          'record entry of its code target is `implemented`, and '
          '`code_root_missing` once one is and the folder is still missing; '
          'keep the entry either way.',
        ),
      );
      expect(init(), isNot(contains('that is expected in a new project')));
    });

    test('domain:agent_plugin INV-25: init passes no --target, a new '
        'project having one code target', () {
      expect(
        init(),
        contains(
          'A new project has one code target, so no `set` here carries '
          '`--target` (`domain:agent_plugin` INV-25).',
        ),
      );
    });
  });

  group('agent_plugin/fill_missing_format', () {
    const procedureTargetLine =
        '**Code target** (two or more `targets:`, `domain:agent_plugin` '
        'INV-25): each `new`, `get`, and `set` of a per-target doc carries '
        "`--target <name>`, the finding DocPath's code target, else the first "
        'listed one.';

    String text(String file) => _oneLine(_pluginText(file));

    for (final skill in ['bootstrap-prd', 'bootstrap-spec']) {
      test('fill_check_findings and merge_old_files, INV-25: the $skill '
          "procedure takes each write's target from the finding DocPath, else "
          'the first listed', () {
        expect(
          text('skills/$skill/references/procedure.md'),
          contains(procedureTargetLine),
        );
      });

      test('fill_check_findings, INV-25: $skill names the batch target '
          'source, so a bootstrap batch never asks the Owner', () {
        expect(
          text('skills/$skill/SKILL.md'),
          contains(
            '**Code target** (two or more `targets:`, `domain:agent_plugin` '
            "INV-25): a finding's code target is its DocPath's, and an old "
            'file whose path names none merges into the first listed one, so '
            'a batch never asks the Owner.',
          ),
        );
      });
    }

    test('fill_check_findings E01 and E08: a feature code pointer goes to '
        "the first target's record entry, and is not written again when the "
        'entry holds it', () {
      expect(
        text('skills/bootstrap-prd/references/procedure.md'),
        contains(
          'Give each `implements:` entry of a `FEATURE.md` to the record '
          'entry of the story or FR whose behavior that code does, in the '
          'first listed code target, unless it holds it already;',
        ),
      );
      expect(
        text('skills/bootstrap-prd/references/procedure.md'),
        contains(
          'to `specstone set implementation:<feature> --field implements '
          '--base <hash>`.',
        ),
      );
    });

    test('fill_check_findings: a spec doc implements pointer goes to the '
        'record entry of its story or FR', () {
      expect(
        text('skills/bootstrap-spec/references/procedure.md'),
        contains('move each entry to the record entry of the story or FR'),
      );
    });

    test("R-T33-1: bootstrap-spec fills each target's tech stack doc, its "
        'rest batch naming each', () {
      expect(
        text('skills/bootstrap-spec/references/procedure.md'),
        contains(
          "fill each target's `tech_stack:tech_stack` per the guide you "
          'loaded, and its `code`,',
        ),
      );
      expect(
        text('skills/bootstrap-spec/SKILL.md'),
        contains("names each target's `tech_stack:tech_stack`"),
      );
    });

    test('fill_check_findings: a spec doc implements pointer is written with '
        'the record command', () {
      expect(
        text('skills/bootstrap-spec/references/procedure.md'),
        contains(
          'with `specstone set implementation:<feature> --field implements '
          '--base <hash>`, then drop the key.',
        ),
      );
    });

    test("R-T33-1: bootstrap-spec takes each target's tech stack code roots "
        "from that target's code root", () {
      expect(
        text('skills/bootstrap-spec/references/procedure.md'),
        contains(
          "each code folder under that target's code root in the "
          "config's `targets:`, or `code_root` for an unnamed one, else the "
          'project root.',
        ),
      );
    });

    for (final skill in ['bootstrap-prd', 'bootstrap-spec']) {
      test('retire_old_files E09: $skill lists each untyped referrer outside '
          'the batch with the file it names', () {
        expect(
          text('skills/$skill/references/procedure.md'),
          contains(
            'list each untyped referrer outside it, with the file it names, '
            'for its owner to merge.',
          ),
        );
      });

      test('Code target line of $skill starts its own block', () {
        expect(
          _pluginText('skills/$skill/references/procedure.md'),
          contains('\n\n**Code target** (two or more'),
        );
      });

      test('fill_check_findings E14, refuse_stale_base: $skill retries a '
          'write a parallel batch made stale', () {
        expect(
          _oneLine(
            _sectionOf(
              _pluginText('skills/$skill/references/procedure.md'),
              '2. One finding at a time',
            ),
          ),
          contains('Exit 75 `base_mismatch`: read again, merge, retry.'),
        );
      });
    }

    test('sdd-engineer names the bootstrap target source on its Code target '
        'line', () {
      expect(
        text('agents/sdd-engineer.md'),
        contains(
          "bootstrap takes the finding DocPath's code target on each "
          'per-target `new`, `get`, and `set`, else the first listed one for a '
          'code pointer on a shared doc or an old file whose path names none;',
        ),
      );
    });
  });

  test('f08/us02/fr01, db-r5, db-r6: brainstorming-sdd targets the smallest '
      'doc and adds a story with --summary', () {
    final text = _pluginText('skills/brainstorming-sdd/SKILL.md')
        .replaceAll(RegExp(r'\s+'), ' ');
    expect(
      text,
      contains('Target the smallest doc that holds the whole change'),
    );
    expect(text, contains('the feature with `--summary` to add a story'));
  });

  test('f08/us02/fr01/e11, sf-r8: brainstorming-sdd step 1 runs specstone '
      'guide feature for a new story or feature', () {
    final step = _sectionOf(
      _pluginText('skills/brainstorming-sdd/SKILL.md'),
      '1. Ground: the first call',
    ).replaceAll(RegExp(r'\s+'), ' ');
    expect(
      step,
      contains(
        'For a change that adds a story or a feature, run `specstone guide '
        'feature` after that call, answer its placement questions, and show '
        'the Owner each answer; go on only after their yes.',
      ),
    );
  });

  test('f08/us01/fr02/e05, db-r1: sdd-reader still pulls a target an earlier '
      'bundle listed in summary', () {
    expect(_pluginText('agents/sdd-reader.md'), contains('· summary'));
  });

  test('f08/us01/fr02/e02, sf-r3: sdd-reader runs no write command, move '
      'included', () {
    expect(
      _sectionOf(_pluginText('agents/sdd-reader.md'), 'Scope Boundaries'),
      contains(
        "**DON'T:**\n\n- Run a write command: `new`, `set`, `approve`, "
        '`delete`, `reorder`, `rename`, or `move`.\n',
      ),
    );
  });

  test('agent_plugin/write_prd_and_spec/write_drafts_with_coverage E02, '
      'sf-r3: sdd-engineer runs approve only with --dry-run, and no delete, '
      'rename, reorder, or move', () {
    expect(
      _sectionOf(_pluginText('agents/sdd-engineer.md'), 'Scope Boundaries'),
      contains(
        "**DON'T:**\n\n- Run `specstone approve` without `--dry-run` "
        "(approving is the Owner's), `delete`, `rename`, `reorder`, or "
        '`move`.\n',
      ),
    );
  });

  test('f08/us01/fr02, db-r6: sdd-reader takes --summary per target and the '
      'design callers hand it over beside each target on the over-budget '
      'route', () {
    String flat(String f) => _pluginText(f).replaceAll(RegExp(r'\s+'), ' ');
    final reader = flat('agents/sdd-reader.md');
    expect(reader, contains('Each may come marked `--summary`'));
    expect(reader, contains('[--summary]'));
    expect(
      reader,
      contains('only on the call for a target the dispatch marks with it'),
    );
    expect(reader, isNot(contains('**`--summary`** (optional)')));
    expect(
      flat('skills/brainstorming-sdd/SKILL.md'),
      contains('`--summary` beside each target whose call used it'),
    );
    expect(
      flat('skills/read-sdd/SKILL.md'),
      contains('`--summary` beside each ID whose call used it'),
    );
  });

  test('f08/us02/fr01, db-r5: design.md names the smallest doc itself, as the '
      'design-mode agent never reads SKILL.md', () {
    final text = _pluginText('skills/brainstorming-sdd/references/design.md')
        .replaceAll(RegExp(r'\s+'), ' ');
    expect(
      text,
      contains(
        "on the smallest doc that holds the brief's whole change: the story "
        'for a change inside one story, the feature for one across stories, '
        'the feature with `--summary` to add a story, and `project` to add a '
        'feature.',
      ),
    );
  });

  test('agent_plugin/write_prd_and_spec/write_design_and_plan E09-E12, '
      'agent_plugin/write_prd_and_spec/audit_drafts_by_reading E10-E13: '
      "design mode searches each decision's dependents, and the audit hashes "
      'its targets in one get and tags behavior findings', () {
    final design = _pluginText('skills/brainstorming-sdd/references/design.md');
    final write = _oneLine(_sectionOf(design, '3. Write the document'));
    for (final point in _dependentsSearchPoints) {
      expect(write, contains(point), reason: point);
    }
    final audit = _pluginText('skills/brainstorming-sdd/references/audit.md');
    final read = _oneLine(_sectionOf(audit, '1. Read'));
    for (final point in _auditReadPoints) {
      expect(read, contains(point), reason: point);
    }
    final compare = _oneLine(_sectionOf(audit, '2. Compare'));
    for (final point in _restatementGapPoints) {
      expect(compare, contains(point), reason: point);
    }
    final report = _sectionOf(audit, '3. Report');
    expect(report, contains('\nAudited: <type>:<name>@<hash>\nFindings:\n'));
    for (final point in _auditReportPoints) {
      expect(_oneLine(report), contains(point), reason: point);
    }
    for (final restated in _ownedElsewhere) {
      expect(
        _oneLine('$design\n$audit'),
        isNot(contains(restated)),
        reason: restated,
      );
    }
    expect(
      _oneLine(
        _sectionOf(_pluginText('agents/sdd-engineer.md'), 'Output Format'),
      ),
      contains('- **Audit**: the `Audited:` lines, `Findings:`,'),
    );
  });

  test('agent_plugin/write_prd_and_spec/run_brainstorm_to_design E05, E06, '
      "E07, E10, E12, E13: rounds.md holds the runner's dispatch, fix-round, "
      'amend, and re-audit rules, and steps 3 and 4.3 of brainstorming-sdd '
      'point to it', () {
    final rounds = _oneLine(_pluginText(_rounds));
    for (final point in _roundsPoints) {
      expect(rounds, contains(point), reason: point);
    }
    for (final restated in _roundsOwnedElsewhere) {
      expect(rounds, isNot(contains(restated)), reason: restated);
    }
    expect(
      _bareStep.allMatches(rounds).map((match) => match[0]),
      isEmpty,
      reason:
          "rounds.md names its own parts as sections; only the skill's "
          'steps are steps',
    );
    final skill = _pluginText('skills/brainstorming-sdd/SKILL.md');
    final design = _sectionOf(skill, '3. Write the document: design mode');
    expect(design, contains('`$_roundsPath`'));
    expect(_oneLine(design), contains('Dispatch `mode: design` once'));
    expect(_oneLine(design), isNot(contains('dispatch again')));
    final fixRounds = _sectionOf(
      skill,
      '4. Write the drafts, then audit them',
    ).split('\n').where((line) => line.startsWith('3. '));
    expect(fixRounds, hasLength(1));
    expect(fixRounds.single, contains('`Findings:` lines'));
    expect(fixRounds.single, contains('`$_roundsPath`'));
    expect(_oneLine(skill), isNot(contains('two fix rounds')));
    for (final file in ['SKILL.md', 'references/rounds.md']) {
      expect(
        _pluginText('skills/brainstorming-sdd/$file'),
        isNot(contains('while it is live')),
        reason: file,
      );
    }
    expect(cliCommands(_pluginText(_rounds)), contains('get'));
    bool ofRounds(String problem) => problem.startsWith('$_rounds:');
    expect(oversizedSkillFiles(pluginRoot()).where(ofRounds), isEmpty);
    expect(
      unknownCliNames(pluginRoot(), SpecstoneCommandRunner()).where(ofRounds),
      isEmpty,
    );
  });

  test('agent_plugin/start_from_another_tools_spec/take_in_a_source '
      'verification, E01 to E03, E05 to E07, E10 to E12; map_source_items '
      'verification, E01 to E05; domain:agent_plugin INV-23: source.md holds '
      'the take-in and Source map rules, the gate before any source read, and '
      'is no Procedure', () {
    final text = _oneLine(_pluginText(_source));
    for (final point in _sourcePoints) {
      expect(text, contains(point), reason: point);
    }
    final takeIn = _oneLine(
      _sectionOf(_pluginText(_source), 'Take in the source'),
    );
    final gate = takeIn.indexOf('specstone context project --for design');
    expect(gate, isNonNegative);
    for (final later in ['**Judge the path.**', '**Read the source**']) {
      expect(takeIn.indexOf(later), greaterThan(gate), reason: later);
    }
    expect(
      "never the copy's path".allMatches(text),
      hasLength(1),
      reason: 'the Source line form is stated once',
    );
    for (final token in [
      '## Take in the source',
      '## Map the source',
      'specstone context project --for design',
      '--no-project',
      'untyped_target',
      '`specstone:bootstrap-prd`',
      '`specstone:bootstrap-spec`',
      '`specstone:sdd-reader`',
      'mktemp',
      'NFR-Pr01',
      'Source map',
      'not taken',
      'open question',
      '`FR-###`',
      '`SC-###`',
      'specstone guide user_story',
      'specstone guide fr',
      'specstone guide feature',
    ]) {
      expect(text, contains(token), reason: token);
    }
    expect(text, isNot(contains('specstone get')));
    expect(text, isNot(contains('context project --for design --budget')));
    expect(_procedures.map((p) => p.file), isNot(contains(_source)));
    bool ofSource(String problem) => problem.startsWith('$_source:');
    expect(oversizedSkillFiles(pluginRoot()).where(ofSource), isEmpty);
    expect(
      unknownCliNames(pluginRoot(), SpecstoneCommandRunner()).where(ofSource),
      isEmpty,
    );
    expect(nonLatinLetterLines(pluginRoot()).where(ofSource), isEmpty);
  });

  test('agent_plugin/start_from_another_tools_spec/take_in_a_source E04, '
      'verification; run_brainstorm_to_design E26: step 1 makes the gate '
      'call, with no budget, before it points to source.md', () {
    final skill = _pluginText('skills/brainstorming-sdd/SKILL.md');
    final step = _oneLine(_sectionOf(skill, '1. Ground: the first call'));
    const gate = 'specstone context project --for design';
    const pointer =
        r'${CLAUDE_PLUGIN_ROOT}/skills/brainstorming-sdd/references/source.md';
    expect(step, contains(gate));
    expect(step, contains(pointer));
    expect(step.indexOf(gate), lessThan(step.indexOf(pointer)));
    expect(step, contains('before any other command or file read'));
    expect(_oneLine(skill), isNot(contains('$gate --budget')));
    expect(_frontmatter.firstMatch(skill)![0], contains('another tool'));
  });

  test('agent_plugin/start_from_another_tools_spec/map_source_items '
      'verification; write_design_document input_output; take_in_a_source '
      'E08: design.md points design mode to source.md, and the runner takes '
      'both bundles', () {
    final design = _pluginText('skills/brainstorming-sdd/references/design.md');
    expect(
      _oneLine(_sectionOf(design, '1. Check the inputs')),
      contains(
        r'${CLAUDE_PLUGIN_ROOT}/skills/brainstorming-sdd/references/source.md',
      ),
    );
    expect(
      _oneLine(_sectionOf(design, '2. Ground each claim')),
      contains('--no-project'),
    );
    expect(_pluginText('agents/sdd-engineer.md'), isNot(contains('source.md')));
  });

  test('agent_plugin/write_prd_and_spec/write_drafts_with_coverage E01, E03, '
      'E11, E12, domain:agent_plugin INV-10: the author re-reads its drafts '
      'in one get, loads every guide in one call, writes several docs '
      'through one set --batch, and sdd-engineer allows only the redirect '
      'that makes a batch file', () {
    final author = _pluginText(_author);
    final read = _oneLine(_sectionOf(author, '1. Read'));
    for (final point in _authorRereadPoints) {
      expect(read, contains(point), reason: point);
    }
    final place = _oneLine(_sectionOf(author, '2. Place each decision'));
    for (final point in _authorBatchPoints) {
      expect(place, contains(point), reason: point);
    }
    expect('specstone guide'.allMatches(author), hasLength(1));
    expect(
      _oneLine(author).indexOf('`specstone guide'),
      lessThan(_oneLine(author).indexOf('`specstone new')),
    );
    expect(
      _sectionOf(author, '4. Check'),
      contains('- **In one of your drafts:** fix it there.\n'),
    );
    expect(
      _sectionOf(author, '5. Report'),
      contains(
        '```\nNot landed: <decision>: <why no doc took it>\n'
        'Not landed: <type>:<name>: listed and never created\n',
      ),
    );
    for (final restated in _batchTableText) {
      expect(author, isNot(contains(restated)), reason: restated);
    }
    final agent = _pluginText('agents/sdd-engineer.md');
    final contract = _oneLine(_sectionOf(agent, 'Input Contract'));
    for (final input in _laterPassInputs) {
      expect(contract, contains(input), reason: input);
    }
    expect(
      _oneLine(_sectionOf(agent, 'Output Format')),
      isNot(contains('a fix round, the Owner')),
      reason: 'each pass after the first is a fresh dispatch',
    );
    final scope = _sectionOf(agent, 'Scope Boundaries');
    expect(_oneLine(scope), contains(_batchFileRedirect));
    expect(_redirectSpan.allMatches(scope).map((span) => span[0]), [
      '`specstone get … > <file>`',
    ]);
    expect(
      _oneLine(scope),
      contains('- Write a file by any other shell redirect, or a PRD or spec'),
    );
    bool ofAuthor(String problem) => problem.startsWith('$_author:');
    expect(oversizedSkillFiles(pluginRoot()).where(ofAuthor), isEmpty);
    expect(
      unknownCliNames(
        pluginRoot(),
        SpecstoneCommandRunner(),
      ).where((problem) => problem.startsWith('agents/sdd-engineer.md:')),
      isEmpty,
    );
  });
}

/// Each point of `write_design_and_plan`'s dependents search and state-table
/// clauses, E09-E12, as step 3 of design.md words it, cut at line width.
const _dependentsSearchPoints = [
  "its rule's owner doc (`none` for a decision with no rule, such as a pure",
  'ruling or an approach pick), and the terms you searched for it.',
  'A decision whose rule has states, such as a refusal set or a set of name',
  'forms, also gets a table of each state against each command or skill',
  "Before the Docs to change table closes, search each decision's dependents:",
  "Name the owner doc of the decision's rule (`specstone:expert-sdd` rule 7).",
  'Run `specstone refs <owner>` for the docs that cite it, and',
  "`specstone search` on the decision's terms and on the wording it supersedes",
  'Each doc found that restates the rule instead of citing its owner gets a',
  'Docs to change row: its change cites the owner by name, or rewrites the',
  "doc when that doc owns a rule that reads the decision's rule.",
  'When `refs` lists no typed citer, as in a tree that still cites by number',
  'labels, the search carries the decision, as it does for the limit of',
  '`refs` that rule 7 names.',
  'Record the searched terms either way, so the audit sees what was searched.',
  'An amend for an Owner decision that adds or changes behavior, as',
  '`agent_plugin/write_prd_and_spec/run_brainstorm_to_design` E12 defines it,',
  "runs the same search on that decision's terms and adds its rows and",
  'searched terms before the author writes it.',
];

/// Each point of `audit_drafts_by_reading`'s one `get` call, E11, and E12, as
/// step 1 of audit.md words it, cut at line width.
const _auditReadPoints = [
  'An audit after a fix round, or after the author pass that follows an',
  'amend, takes the drafts',
  '`agent_plugin/write_prd_and_spec/run_brainstorm_to_design` E13 names, each',
  'read whole and audited again.',
  'run one `specstone get <targets> --json` on every target.',
  "Each doc's `Audited:` line joins its JSON `docType` and `name` with `:`,",
  'then `@` and its `bases.doc`.',
  'When it refuses with `doc_not_found`',
  'drop each name the refusal names and list it under `Outside the drafts:`,',
  'with no `Audited:` line.',
  'Any other refusal, such as `doc_type_unknown` or a section fault, is a',
  'finding and drops each name it names too.',
  'Run the call again on the rest; when no target is left, skip the rerun and',
  'the steps below.',
  'A dropped name is no target for the steps below: no bundle and no `check`',
];

/// The restatement gap of `audit_drafts_by_reading` E10, as step 2 of
/// audit.md words it, cut at line width.
const _restatementGapPoints = [
  '| Rule restated | a draft stating a rule another doc owns instead of',
  'citing it (`specstone:expert-sdd` rule 7) |',
  '**Rule restated:** name the owner doc and the item; its fix is a citation',
  'in the draft.',
];

/// The `Audited:` lines, E11's lists, and E13's `[behavior]` tag of
/// `audit_drafts_by_reading`, as step 3 of audit.md words them, cut at line
/// width.
const _auditReportPoints = [
  '- <type>:<name>#<section>: <gap> [behavior]',
  '- <type>:<name>: no draft',
  '- <name>: names no doc',
  '**`Audited:`**: one line per target that names a doc, a draft or not, its',
  "hash that doc's `bases.doc` from the `get` of step 1; each replaces the",
  'line an earlier audit wrote for that draft.',
  'End a `Findings:` line with `[behavior]` when its fix needs behavior the',
  'design does not state, behavior as',
  '`agent_plugin/write_prd_and_spec/run_brainstorm_to_design` E12 defines it;',
  'a line whose fix only corrects text against the design stays untagged.',
  'each target that is no draft, and each name dropped from the `get` call;',
  'A fix round takes only the untagged `Findings:` lines; a `[behavior]` line',
  'goes to a design-mode amend.',
];

/// Text that `specstone:expert-sdd` rule 7 or `run_brainstorm_to_design` E13
/// owns, which design.md and audit.md cite and never restate.
const _ownedElsewhere = [
  'A rule has one owner doc',
  'pins no hash',
  'differs from their last',
  'each doc the round or pass added',
];

/// The runner's fix-round and ruling procedure of `brainstorming-sdd`, under
/// the plugin folder.
const _rounds = 'skills/brainstorming-sdd/references/rounds.md';

/// [_rounds] by the path the skill's runner reads it from.
const _roundsPath = '\${CLAUDE_PLUGIN_ROOT}/$_rounds';

/// The take-in and Source map reference file of `brainstorming-sdd`, which
/// its runner and design mode both read, under the plugin folder.
const _source = 'skills/brainstorming-sdd/references/source.md';

/// Each rule of `take_in_a_source` and `map_source_items` as source.md words
/// it, tagged with the edge case it proves.
const _sourcePoints = [
  // take_in_a_source E01, BR-01: the gate before any read; the file unread.
  'Read no source and open no link or issue before it.',
  'Read none of it with any tool',
  // E02: a source that adds a feature runs no narrow call.
  'no second call runs (E02)',
  // E03: the narrow call's budget and over-budget hand-off.
  'specstone context <target> --for design --no-project',
  "the gate's bundle plus the whole sections it returns (E03)",
  'Without the `Agent` tool, pass no `--budget` and take both whole bundles',
  // E06: only the gaps, one at a time, nothing invented.
  'Ask the Owner only what the source leaves open, one question at a time',
  'invent nothing (E06)',
  // E07, NFR-Pr01: only a link the Owner gave.
  'Open a link or issue only because the Owner gave it',
  'a link written inside the source is none the Owner gave',
  // E10: the copy is no source.
  'the copy is no source (E10)',
  // E11: an untyped file is refused and never named.
  'Run no other command on its path; the brief never names it (E11)',
  // E12: a typed doc is the change's target, its path call the narrow call.
  'no source, no copy, no Source map',
  'That call was your narrow call',
  'run no further `context` call (E12)',
  // map_source_items E01 to E05 and the Source map's place.
  'after Docs to change and before Open questions',
  'one row per source item, 0 items left out',
  'its reason that task management is out of scope',
  'an open question in your report, as for any gap (E02)',
  'never recorded as the source (E03)',
  'A brief with no source gets no Source map (E04)',
  'Never edit, move, or delete the source; write only your `report:` file',
  'and the one design document (E05)',
];

/// Each point of `run_brainstorm_to_design`'s dispatch, fix-round, amend, and
/// re-audit clauses, E05, E06, E07, E10, E12, and E13, as rounds.md words
/// them, cut at line width.
const _roundsPoints = [
  'adds or changes behavior when it brings a new state, input, output,',
  'edge case, error, or reader of a rule (E12).',
  "append it to the design document's Rulings yourself",
  'the author, or the fix round under way, goes on (E07, E12).',
  'or needs more PRD or spec grounding',
  "dispatch `mode: design` again with the brief's path and the document's",
  'path, an amend of the same file.',
  "Design mode searches the decision's terms (`references/design.md`)",
  'before the author writes it (E07, E12).',
  'after an append or an amend, ask for the approval again (E07).',
  "When the design report holds open questions, gather the Owner's answers,",
  'append each that only words or records one, send the rest to one amend,',
  'and ask for the approval only after it (E10).',
  '**During fix rounds**, a decision that adds or changes behavior takes',
  'an amend, then one fresh author pass and a re-audit, as section 2 says',
  '**After the second fix round**, a decision that adds or changes',
  "behavior, the Owner's decision on a finding past the cap included (E06),",
  'takes an amend, then one author pass that carries the amend alone and is',
  'no fix round, then a re-audit (section 3) whose findings reach the Owner',
  'with the drafts, with no further round.',
  'Fix an Owner change that only corrects text per `specstone:expert-sdd`,',
  'with no amend (E12).',
  "The drafts list is the first author report's drafts plus each doc a fix",
  'round or pass added, renamed or dropped as section 3 says.',
  'every author pass after the first, each fix round and the pass that',
  'follows an amend, is a new `mode: author` dispatch, never the resumed',
  'one (E05).',
  "a fix round adds the audit's `Findings:` lines that carry no `[behavior]`",
  'The author re-reads those drafts before its first write',
  '`agent_plugin/write_prd_and_spec/write_drafts_with_coverage` E12) and',
  'fixes only those findings, in those drafts.',
  'never goes to a fix round: put it, with the decision that answers it,',
  'in the brief for an amend (section 1).',
  'that pass takes them too and counts as a fix round; a pass that carries',
  'the amend alone is no fix round (E12).',
  'run at most two fix rounds, counted across an amend.',
  'Lines left after the second get no third round: the Owner sees them',
  'with the drafts before approving any',
  "and their decision on one takes section 1's route (E06).",
  'After each fix round, and after each pass that follows an amend,',
  're-audit as section 3 says.',
  "Run one `specstone get <drafts list> --json` and keep each draft's",
  'When it refuses with `doc_not_found`, update the drafts list',
  'takes the new name `move` printed (`moved <from> to <to>`), and a doc',
  'deleted, or listed and never created, drops out.',
  'Run the call again on that list.',
  "Dispatch a fresh `mode: audit` with the document's path and, as its",
  'targets, the drafts whose `bases.doc` differs from their last',
  '`Audited:` hash, plus each doc the round or pass added.',
  'A draft whose hash equals its last `Audited:` hash is not read again;',
  'its earlier finding stands.',
  'A doc of the list that is no draft, approved between rounds or listed',
  'and never written, is no target.',
  'name each doc approved between rounds and each name item 2 renamed or',
  'dropped (E13).',
];

/// A step number not preceded by "skill's"; in rounds.md it could mean a step
/// of SKILL.md or one of the file's own sections.
final _bareStep = RegExp(r"(?<!skill's )\bsteps? \d");

/// Text that audit.md or design.md owns, which rounds.md cites and never
/// restates.
const _roundsOwnedElsewhere = [
  'one line per target',
  'End a `Findings:` line with `[behavior]`',
  'Run `specstone refs <owner>`',
];

/// The author's procedure for `sdd-engineer`'s author mode, under the plugin
/// folder.
const _author = 'skills/brainstorming-sdd/references/author.md';

/// Each point of `write_drafts_with_coverage`'s re-read clause and E12, as
/// step 1 of author.md words it, cut at line width.
const _authorRereadPoints = [
  'each pass after the first: a fix round, or the pass after an amend',
  "the first author report's drafts plus each doc a fix round or pass added;",
  "in a fix round, the audit's `Findings:` lines too.",
  'Before your first write, re-read the drafts in one',
  '`specstone get <drafts list>` call.',
  'When it refuses with `doc_not_found`, drop each name it names and run it',
  'again on the rest; list each dropped name under `Findings:`, or as',
  '`Not landed:` when listed and never created.',
  'After an amend, write the amended design into the drafts through steps 2',
  'Fix only those findings, only in those drafts, as step 2 writes;',
  'List each finding outside those drafts under `Findings:`, unfixed.',
];

/// Each point of `write_drafts_with_coverage`'s guide and batch clauses, E03,
/// and E11, as step 2 of author.md words it, cut at line width.
const _authorBatchPoints = [
  'A decision no doc can take is not landed: flag it, never force it.',
  '**Guide**: before your first write, run `specstone guide <type> …` once,',
  'naming every type you write.',
  '**Several docs in one step**: run `specstone get <names> > <file>`,',
  '`<file>` a `mktemp` file outside the repository; edit its blocks with',
  '`Edit`, each naming line kept; then run `specstone set --batch <file>`.',
  'A block printed ` · unchanged` wrote nothing and adds no draft.',
  '**A refused batch** writes nothing',
  '(`document_writing/edit_one_section_or_field/write_a_batch`), but exit 73',
  'leaves docs half written until a write command ends its journal: run',
  'one, or `get` again, first. Per fault, then run it again:',
  '- Stale block: replace the block with the one the reply prints, your',
  'edit merged in; run no `get`.',
  "- Gone block: re-read its doc by name; a moved doc's new block takes",
  'the edit; a name naming no doc drops the block, its doc listed under',
  '- Untyped block: drop it, its doc listed under `Findings:`.',
  '- One part twice, or a whole-doc block beside another',
  'block beside another of its doc: join them.',
  "- Field or title block: write it inside its doc's whole-doc block.",
  '- Removed required section: restore it; a field only the Owner or',
  'Specstone sets: restore its value; open fence: close it.',
  '- Any other refusal a single `set` of that part makes, such as',
  "`field_unknown` or a section block's stray `##` line: fix that part as",
  'line: fix that part as the refusal names.',
  '- Refused path or line: rebuild the file from `get` text output',
  'alone.',
];

/// Text of `write_a_batch`'s fault table, which author.md handles through
/// E11's points and never restates.
const _batchTableText = ['exit status', '`75`', 'argument_invalid'];

/// Each point of `write_drafts_with_coverage` E12's inputs, as the Input
/// Contract of sdd-engineer words them, cut at line width.
const _laterPassInputs = [
  '(author, required in each pass after the first, a fresh dispatch: a fix',
  'round, or the pass after a design-mode amend)',
  "the drafts list, the first author report's drafts plus each doc a fix",
  "round or pass added; in a fix round, the audit's `Findings:` lines too.",
];

/// The one shell redirect sdd-engineer may run (`domain:agent_plugin` INV-10),
/// as its Scope Boundaries word it.
const _batchFileRedirect =
    'and a batch file: made by `specstone get … > <file>`, `<file>` outside '
    'the repository, the one shell redirect you run, and passed to '
    '`specstone set --batch <file>`.';

/// A code span that redirects output into a file.
final _redirectSpan = RegExp(r'`[^`\n]* >>? [^`\n]*`');

/// The one home of the size-fix rule, under the plugin folder.
const _sizeFix = 'skills/expert-sdd/references/size-fix.md';

/// [_sizeFix] by the path a dispatched agent reads it from.
const _sizeFixPath = '\${CLAUDE_PLUGIN_ROOT}/$_sizeFix';

const _sizeFindings = [
  '`chars_over_limit`',
  '`lines_over_limit`',
  '`item_over_limit`',
];

/// The statement's split clause of
/// `agent_plugin/fill_missing_format/fill_check_findings`, as size-fix.md
/// words it.
const _sizeAnswerRule =
    'Answer each `chars_over_limit` or `lines_over_limit` finding once in your '
    'report, though `check` tags it `(waits for the Owner)`: a split '
    'proposal, or why none applies. Give `item_over_limit` neither: it needs '
    'no answer';

/// Each point of `fill_check_findings` E13's item rewrite, held only by
/// size-fix.md.
const _itemRewritePoints = [
  "in its doc type's item shape, as `specstone guide <type>` gives it",
  'one rule per ID',
  'each rule split off takes the next free ID of its section',
  'a bound stays in its rule',
  'its mechanics, known limits, and trace move to the homes the guide names',
  'no statement is dropped',
];

/// The `item_over_limit` Input row of `fill_check_findings`, as each
/// bootstrap skill words it.
const _itemBatchRule =
    "An `item_over_limit` finding joins its doc's batch only when the Owner "
    'named `item_over_limit` when starting the run';

/// Each bootstrap procedure and the sentences by which it skipped or dropped
/// old text on judgement, or wrote its own proposal for a gap.
const _droppedTextReasons = {
  'skills/bootstrap-prd/references/procedure.md': [
    "propose it from the project's own text",
    'unless a project doc holds it already',
    'Write nothing it holds already',
  ],
  'skills/bootstrap-spec/references/procedure.md': [
    "propose it from the project's own text",
    'write nothing a project doc holds already',
    'drop, as a step 6 proposal, what only describes the old index',
  ],
};

void _sizeFixTests() {
  test('agent_plugin/fill_missing_format/fill_check_findings E06, E07, '
      'E10-E12, agent_plugin/fill_missing_format/merge_old_files E02, E07: '
      'each bootstrap procedure moves old text, marks a gap TBR, and has one '
      'finding row sending the three size findings to size-fix.md', () {
    for (final MapEntry(key: file, value: reasons)
        in _droppedTextReasons.entries) {
      final text = _pluginText(file);
      final sizeRows = [
        for (final line in text.split('\n'))
          if (line.startsWith('|') &&
              [..._sizeFindings, '`$_sizeFixPath`'].every(line.contains))
            line,
      ];
      expect(sizeRows, hasLength(1), reason: file);
      final flat = _oneLine(text);
      expect(flat, contains('`TBR — <why>`'), reason: file);
      expect(flat, contains('even if another doc holds it'), reason: file);
      expect(flat, contains('word for word'), reason: file);
      expect(
        _oneLine(_sectionOf(text, '2. One finding at a time')),
        contains(
          'is tagged `(waits for the Owner)`, except an unanswered size '
          'finding.',
        ),
        reason: file,
      );
      for (final reason in reasons) {
        expect(flat, isNot(contains(reason)), reason: '$file: $reason');
      }
    }
  });

  test('agent_plugin/write_prd_and_spec/follow_cross_doc_rules E05, E06, '
      'agent_plugin/fill_missing_format/fill_check_findings E10-E12: '
      "size-fix.md names the three findings, the split proposal's ready "
      'commands in run order, and the case no split applies to', () {
    final text = _oneLine(_pluginText(_sizeFix));
    for (final finding in _sizeFindings) {
      expect(text, contains(finding), reason: finding);
    }
    expect(text, contains(_sizeAnswerRule));
    expect(
      text,
      contains('`item_over_limit` skips this step: a split never shrinks one'),
    );
    final newFeature = text.indexOf(
      'specstone new feature --parent <feature> --slug <slug>',
    );
    expect(newFeature, isNonNegative);
    expect(
      text.indexOf('specstone move <story> … --under <sub-feature>'),
      greaterThan(newFeature),
    );
    expect(text, contains('fewer than 4 stories'));
    expect(text, isNot(contains('Cite a size only')));
    expect(text, isNot(contains('Never cut meaning')));
  });

  test('agent_plugin/fill_missing_format/fill_check_findings E12, E13: '
      'size-fix.md asks a split answer of the two other size findings only '
      'and holds the item rewrite, each bootstrap skill batches an '
      'item_over_limit finding only in a run the Owner names it in, and '
      'sdd-engineer lists the rest under Waits on the Owner', () {
    final sizeFix = _pluginText(_sizeFix);
    expect(_oneLine(sizeFix), contains(_sizeAnswerRule));
    expect(
      _sectionOf(sizeFix, 'No split applies'),
      isNot(contains('`item_over_limit`')),
    );
    final item = _oneLine(_sectionOf(sizeFix, 'An item over its limit'));
    for (final point in _itemRewritePoints) {
      expect(item, contains(point), reason: point);
    }
    expect(item, contains('`Waits on the Owner:`'));
    expect(item, contains('a dispatched agent sees the name in `batch:`'));
    for (final skill in ['bootstrap-prd', 'bootstrap-spec']) {
      final text = _pluginText('skills/$skill/SKILL.md');
      final handOff = _oneLine(_sectionOf(text, '2. Hand off in batches'));
      expect(handOff, contains(_itemBatchRule), reason: skill);
      expect(handOff, isNot(contains('`Waits on the Owner:`')), reason: skill);
      expect(
        _oneLine(_sectionOf(text, '3. After the reports')),
        contains(
          'list under `Waits on the Owner:` each `item_over_limit` finding no '
          "report's `Waits on the Owner:` line named",
        ),
        reason: skill,
      );
      for (final point in _itemRewritePoints) {
        expect(
          _oneLine(text),
          isNot(contains(point)),
          reason: '$skill: $point',
        );
      }
    }
    final agent = _pluginText('agents/sdd-engineer.md');
    expect(
      _oneLine(_sectionOf(agent, 'Input Contract')),
      contains(
        'the finding paths you fix, and `item_over_limit` when the '
        'Owner named it for the run and a `batch` path holds one',
      ),
    );
    final output = _oneLine(_sectionOf(agent, 'Output Format'));
    expect(
      output.substring(output.indexOf('- **Bootstrap**')),
      contains(
        '`Waits on the Owner:`, each `item_over_limit` finding on a `batch` '
        'path when `batch` does not name `item_over_limit`',
      ),
    );
    for (final point in _itemRewritePoints) {
      expect(_oneLine(agent), isNot(contains(point)), reason: point);
    }
  });

  test('agent_plugin/write_prd_and_spec/follow_cross_doc_rules, '
      'agent_plugin/fill_missing_format/fill_check_findings: every other file '
      'points to size-fix.md and none restates its commands', () {
    final rules = _oneLine(
      _sectionOf(_pluginText('skills/expert-sdd/SKILL.md'), 'Rules'),
    );
    expect(rules, contains('`references/size-fix.md`'));
    expect(
      rules,
      contains(
        'Cite a size only as `specstone structure <doc>` or `specstone check` '
        'prints it.',
      ),
    );
    expect(rules, contains('never cut meaning'));
    expect(
      rules,
      contains(
        'layout, then a sub-feature split the Owner approves, then text '
        'moved to its home',
      ),
    );
    for (final skill in ['bootstrap-prd', 'bootstrap-spec']) {
      final after = _oneLine(
        _sectionOf(
          _pluginText('skills/$skill/SKILL.md'),
          '3. After the reports',
        ),
      );
      expect(after, contains('`$_sizeFixPath`'), reason: skill);
      expect(after, contains('in run order'), reason: skill);
    }
    expect(_pluginText('agents/sdd-engineer.md'), contains('`$_sizeFixPath`'));
    for (final file
        in pluginRoot().listSync(recursive: true).whereType<File>()) {
      if (file.uri.path.endsWith(_sizeFix)) continue;
      expect(
        _oneLine(file.readAsStringSync()),
        isNot(contains('new feature --parent')),
        reason: file.path,
      );
    }
  });
}

/// Each bootstrap procedure and its est. tokens at `e8262ba`, which its one
/// guide call per batch leaves no higher.
const _bootstrapProcedureTokens = {
  'skills/bootstrap-prd/references/procedure.md': 1497,
  'skills/bootstrap-spec/references/procedure.md': 1499,
};

/// The one guide call of a bootstrap batch
/// (`agent_plugin/fill_missing_format/fill_check_findings` E25), and the call
/// a type first met after it takes.
const _batchGuideCall =
    'before the first, run `specstone guide <type> …` once, naming every type '
    'you write; a type met later gets its own call before its first write.';

/// Rule 3 of expert-sdd, the guide-first rule's owner, on a call naming
/// several types.
const _guideCallCountsForEach =
    'One call naming several types counts for each type it names, so a batch '
    'never repeats it per write.';

void _batchGuideTests() {
  test('agent_plugin/fill_missing_format/fill_check_findings E25, '
      'agent_plugin/write_prd_and_spec/follow_cross_doc_rules: each '
      'bootstrap procedure runs one guide call for every type its batch '
      'writes before the first write and its own call for a type met later, '
      'points each finding fix to it, and stays within its e8262ba est. '
      'tokens; expert-sdd counts one call for each type it names', () {
    final expert = _pluginText('skills/expert-sdd/SKILL.md');
    final rules = _oneLine(_sectionOf(expert, 'Rules'));
    expect(rules, contains(_guideCallCountsForEach));
    expect(rules, isNot(contains('earlier in the session')));
    expect(
      expert,
      contains(
        '| "I read this type\'s guide in an earlier task." | Run '
        '`specstone guide <type>` again. |',
      ),
    );
    for (final MapEntry(key: file, value: tokens)
        in _bootstrapProcedureTokens.entries) {
      final text = _pluginText(file);
      final call = _oneLine(text).indexOf(_batchGuideCall);
      expect(call, isNonNegative, reason: file);
      for (final write in ['`specstone set', '`specstone new']) {
        expect(
          call,
          lessThan(_oneLine(text).indexOf(write)),
          reason: '$file: $write',
        );
      }
      expect(
        'specstone guide'.allMatches(text),
        hasLength(1),
        reason: '$file names one guide call',
      );
      expect(
        _oneLine(_sectionOf(text, '2. One finding at a time')),
        contains('| rewrite what it names per the guide you loaded;'),
        reason: file,
      );
      expect(_oneLine(text), isNot(contains('per its guide')), reason: file);
      expect(
        oversizedSkillFiles(
          pluginRoot(),
          limit: tokens,
        ).where((problem) => problem.startsWith('$file:')),
        isEmpty,
      );
    }
  });
}

const _runPlanSkill = 'agent_plugin/plan_approved_stories/run_plan_skill';
const _writePlan = 'agent_plugin/plan_approved_stories/write_grounded_plan';

/// The plan skill and the plan agent, under the plugin folder.
const _planSkill = 'skills/plan-sdd/SKILL.md';
const _planAgent = 'agents/plan-engineer.md';

/// [_planAgent] by the path the plan skill's runner reads it from.
const _planAgentPath = '\${CLAUDE_PLUGIN_ROOT}/$_planAgent';

/// The lead and source 1 of the plan agent's `## Ground`, as the plan-sdd
/// design's ground ruling words them, cut at line width.
const _groundLead =
    'Read sources in this order; read a later source only for what the '
    'earlier ones leave out.';
const _groundSpecstone =
    '1. Specstone, always first: `specstone context <story> --for implement` '
    'for each story the plan builds. The bundle holds the story, its FRs, NFR '
    'overrides, and specs (ARCHITECTURE, API, DOMAIN, TECH_STACK). Never open '
    'a doc file by path.';

/// The line between sources 1 and 2: the plan-sdd design's line for a target
/// that is no story, opening with a capital where the design's colon let it
/// open on a lowercase word.
const _groundNonStoryTarget =
    'For a target that is no story, an NFR or a spec doc, `specstone context '
    '<target> --for implement` on that doc itself. An FR target grounds '
    "through its story's step-1 call, as "
    '`fr:agent_plugin/ground_a_task/ground_through_context#edge_cases` E01 '
    'grounds a task citing a story and its FRs.';

/// Sources 2 to 4, then the three closing paragraphs the design's later ruling
/// put in place of the ground ruling's last two.
const _groundSources =
    '2. The code the specs point at: each `implements` and `covers` path, then '
    'its direct callers. '
    "3. The project's own instruction files (`CLAUDE.md`, `AGENTS.md`): "
    'commands, branch flow, gotchas. '
    "4. Library docs for each dependency TECH_STACK names (the host's doc "
    'tool, when it has one).';
const _groundClosing =
    'When the code differs from a spec, the spec wins (code ⊆ spec ⊆ PRD): '
    'plan the task that brings the code to it. '
    'When another source (instructions, library docs) contradicts a spec on '
    'behavior, write no task around it; list the conflict under Open '
    'questions for the Owner. A later source wins only on process (commands, '
    'branch, CI). '
    'Every task names the doc it builds (a story, FR, NFR, or spec doc), by '
    "doc name, and takes its test from that doc's Verification field, or the "
    'TECH_STACK CI commands when it has none. A task that would build '
    'behavior no doc states is a spec gap: list it, never plan it.';

/// Text of the ground ruling's last two paragraphs, which the later ruling
/// replaced.
const _groundSuperseded = [
  'When a later source contradicts a spec on behavior',
  'Every task names the story and FR it builds',
];

final _frontmatterBlock = RegExp(r'^---\r?\n((?:.*\r?\n)*?)---\r?\n');

/// The comma-separated tools of the frontmatter line `<key>:` in [agent];
/// null when the frontmatter has no such line.
List<String>? _toolsOf(String agent, String key) {
  final frontmatter = _frontmatterBlock.firstMatch(agent)?.group(1) ?? '';
  final line = RegExp('^$key:(.*)\$', multiLine: true).firstMatch(frontmatter);
  return line?.group(1)?.split(',').map((tool) => tool.trim()).toList();
}

void _planTests() {
  test('$_runPlanSkill, domain:agent_plugin INV-1: plan-sdd makes specstone '
      'check its first CLI call', () {
    final body = _bodyOf(_pluginText(_planSkill));
    expect(cliCommands(body).first, 'check');
  });

  test('$_runPlanSkill E02: plan-sdd lists the approved stories still planned '
      'when no target is given', () {
    expect(
      _oneLine(_pluginText(_planSkill)),
      contains('specstone list user_story --status planned'),
    );
  });

  test('$_runPlanSkill E05, E07, verification: plan-sdd dispatches '
      'specstone:plan-engineer with a mktemp report: file, shows the Report: '
      "line, follows the agent file itself, loads the Owner's pick with "
      'Skill, and names no plan mode', () {
    final text = _oneLine(_pluginText(_planSkill));
    for (final point in [
      'specstone:plan-engineer',
      '`report:`',
      '`mktemp`',
      '`Report:`',
      '`Skill`',
      _planAgentPath,
    ]) {
      expect(text, contains(point), reason: point);
    }
    expect(text, isNot(contains('mode: plan')));
  });

  test('$_writePlan statement, E16, verification: the Ground section of '
      'plan-engineer holds the four sources in order, the line for a target '
      'that is no story between sources 1 and 2, and the closing paragraphs '
      "in place of the ground ruling's last two", () {
    final ground = _oneLine(_sectionOf(_pluginText(_planAgent), 'Ground'));
    final parts = [
      _groundLead,
      _groundSpecstone,
      _groundNonStoryTarget,
      _groundSources,
      _groundClosing,
    ];
    for (final part in parts) {
      expect(ground, contains(part), reason: part);
    }
    expect(ground, contains(parts.join(' ')));
    for (final superseded in _groundSuperseded) {
      expect(ground, isNot(contains(superseded)), reason: superseded);
    }
  });

  test('$_writePlan statement, E20: plan-engineer names a bare specstone '
      'check, the sync-sdd last task, the plan path outside the '
      'CheckedFolders, the NOT PLANNED row, and the reply lines', () {
    final agent = _oneLine(_pluginText(_planAgent));
    for (final point in [
      '`specstone check`',
      'specstone:sync-sdd',
      'docs/plans/<YYYY-MM-DD>-<slug>.md',
      'NOT PLANNED',
      'Report: <path>',
      'Plan:',
      'Findings:',
    ]) {
      expect(agent, contains(point), reason: point);
    }
  });

  test('$_writePlan statement: the Ground and Workflow sections of '
      'plan-engineer name only the context and check commands', () {
    final agent = _pluginText(_planAgent);
    final sections =
        '${_sectionOf(agent, 'Ground')}\n${_sectionOf(agent, 'Workflow')}';
    expect(cliCommands(sections).toSet(), {'context', 'check'});
  });

  test('$_writePlan, domain:agent_plugin INV-10: plan-engineer lists no tools '
      'line, denies only Agent and NotebookEdit, and its Scope Boundaries '
      'name the report: file and the one plan file', () {
    final agent = _pluginText(_planAgent);
    expect(_toolsOf(agent, 'tools'), isNull);
    final denied = _toolsOf(agent, 'disallowedTools');
    expect(denied?.toSet(), {'Agent', 'NotebookEdit'});
    expect(
      denied!.toSet().intersection({'Write', 'Edit', 'Skill', 'Bash', 'Read'}),
      isEmpty,
    );
    final scope = _oneLine(_sectionOf(agent, 'Scope Boundaries'));
    expect(scope, contains('`report:`'));
    expect(scope, contains('the one plan file'));
  });

  test('$_runPlanSkill E17, S4, domain:agent_plugin INV-25: plan-sdd runs the '
      'planned-story list after the gate, given targets or not and with no '
      '--target, and learns it must ask from its argument_missing refusal', () {
    final skill = _oneLine(_pluginText(_planSkill));
    expect(
      skill,
      contains(
        'Run this next, given targets or not, with no `--target`: ``` '
        'specstone list user_story --status planned --json ```',
      ),
    );
    expect(
      skill,
      contains(
        '**Code target** (`domain:agent_plugin` INV-25): when the list '
        'refuses `argument_missing` naming two or more code targets, ask the '
        'Owner which code target the plan is for, given target names and a '
        'drafts list alike',
      ),
    );
    expect(skill, contains('never from `.specstone/config.yaml`'));
  });

  test('$_runPlanSkill E17: a one-target project asks nothing and passes no '
      'code target', () {
    expect(
      _oneLine(_pluginText(_planSkill)),
      contains(
        "A one-target project's list refuses nothing: ask nothing, pass none.",
      ),
    );
  });

  test('$_runPlanSkill E02, S6: after the ask the list runs again with the '
      "Owner's --target, and the answer is the dispatch's code target", () {
    final skill = _oneLine(_pluginText(_planSkill));
    expect(
      skill,
      contains(
        'the answer is `code target:` in step 3, and `--target <name>` on a '
        'rerun of this list when no target is given',
      ),
    );
    expect(
      skill,
      contains(
        'Offer the Owner each story of the list, rerun with `--target '
        '<name>` after the ask, whose `draft` is `false`',
      ),
    );
  });

  test('$_runPlanSkill E07, dispatch row: the dispatch carries `code target:` '
      'when one was asked, and an answers round writes it out again', () {
    final skill = _oneLine(_pluginText(_planSkill));
    expect(
      skill,
      contains(
        "`code target:` the Owner's answer; leave the line out when none was "
        'asked',
      ),
    );
    expect(
      skill,
      contains(
        "with step 3's inputs written out again, `targets:` whole and `code "
        'target:`, never "unchanged"',
      ),
    );
  });

  test('$_writePlan E29, domain:agent_plugin INV-25: plan-engineer takes the '
      'code target as an input and carries it as --target on every Ground '
      "call and each task's read line, none when no target is given", () {
    final agent = _pluginText(_planAgent);
    expect(
      _oneLine(_sectionOf(agent, 'Input Contract')),
      contains(
        "**`code target`** (optional): `specstone:plan-sdd`'s answer, given "
        'when the project has two or more code targets',
      ),
    );
    expect(
      _oneLine(_sectionOf(agent, 'Ground')).trimRight(),
      endsWith(
        '**Code target** (`domain:agent_plugin` INV-25): with one given, '
        "every Ground `context` call and each task's read line adds "
        "`--target <code target>`, and the plan holds that target's tasks "
        'alone. With none given, add no `--target`.',
      ),
    );
    expect(
      _oneLine(_sectionOf(agent, 'Workflow')),
      contains(
        '`specstone context <target> --for implement`, with `--target <code '
        "target>` when one is given, the FR's story as `<target>` for an FR",
      ),
    );
  });

  test('$_writePlan E30: plan-engineer gives a doc the code target skips no '
      'task and a NOT PLANNED row naming the skip, read from the bundle', () {
    final agent = _pluginText(_planAgent);
    expect(
      _oneLine(_sectionOf(agent, 'Workflow')),
      contains(
        '**A doc the plan would build that the code target skips**, by its own '
        'record entry or one above it, read from its bundle: no task, and a '
        '`NOT PLANNED` row naming the skip and its reason; a skipped doc the '
        'plan only reads gets no row.',
      ),
    );
    expect(
      _oneLine(_sectionOf(agent, 'Output Format')),
      contains(
        'NOT PLANNED: <draft, approval_stale, skip, spec gap, conflict, or '
        'CLI error>',
      ),
    );
  });

  test('$_runPlanSkill, $_writePlan: neither plan-sdd nor plan-engineer names '
      "another plugin's skill", () {
    for (final file in [_planSkill, _planAgent]) {
      final shipped = File.fromUri(pluginRoot().uri.resolve(file));
      expect(shipped.existsSync(), isTrue, reason: '$file is missing');
    }
    expect(
      otherPluginSkillNames(pluginRoot(), shippedDocTypes()).where(
        (problem) =>
            problem.startsWith('skills/plan-sdd/') ||
            problem.startsWith('$_planAgent:'),
      ),
      isEmpty,
    );
  });
}
