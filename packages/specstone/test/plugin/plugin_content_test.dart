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
  _leadAndMermaidTests();
  _agentTests();
  _sizeFixTests();
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
    commands: ['context'],
  ),
  (
    file: 'skills/brainstorming-sdd/references/audit.md',
    tags: 'f08/us02/fr01, f08/us02/fr07',
    commands: ['context', 'list', 'check'],
  ),
  (
    file: 'skills/brainstorming-sdd/references/plan.md',
    tags: 'f08/us02/fr01, f08/us02/fr06',
    commands: ['context'],
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
    for (final mode in [
      'author',
      'design',
      'audit',
      'plan',
      'sync',
      'bootstrap',
    ]) {
      expect(
        output,
        contains('**${mode[0].toUpperCase()}${mode.substring(1)}'),
        reason: '$mode names its relay block',
      );
    }
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
      "report's Drafts line stays a bare list of names that the audit and "
      'plan dispatches take as it is, its counts on their own line', () {
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
}

/// The `sdd-engineer` modes that `brainstorming-sdd` dispatches, each with
/// its steps in the skill's `references/<mode>.md`.
const _brainstormModes = ['author', 'design', 'audit', 'plan'];

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
  test('f08/us02/fr02, f08/us02/fr06, f08/us02/fr07, sd-r9: the sdd-engineer '
      'Input Contract names exactly its six modes', () {
    final contract = _sectionOf(
      _pluginText('agents/sdd-engineer.md'),
      'Input Contract',
    );
    final bullet = _modeBullet.firstMatch(contract)?.group(1) ?? '';
    expect(
      [for (final span in _codeSpan.allMatches(bullet)) span.group(1)],
      unorderedEquals([
        'author',
        'sync',
        'bootstrap',
        'design',
        'audit',
        'plan',
      ]),
    );
  });

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

  test('f08/us02/fr02, f08/us02/fr06, f08/us02/fr07, f08/us03/fr01, '
      'f08/us05/fr01: the sdd-engineer description sends sync and bootstrap '
      'through their skills and names the four modes a caller may dispatch '
      'directly', () {
    final description = RegExp(
      r'^description:(.*)$',
      multiLine: true,
    ).firstMatch(_pluginText('agents/sdd-engineer.md'))?.group(1);
    expect(description, contains('`specstone:sync-sdd`'));
    expect(description, contains('`specstone:bootstrap-prd`'));
    for (final mode in _brainstormModes) {
      expect(description, contains('`$mode`'), reason: mode);
    }
  });

  test('inv-10, f08/us02/fr06, f08/us02/fr07: sdd-engineer holds Write and '
      'Edit for the one file under docs/superpowers/ a design or plan '
      'dispatch names, and audit, design, and plan mode write no other '
      'file but the report file', () {
    final agent = _pluginText('agents/sdd-engineer.md');
    final tools = RegExp(
      r'^tools:(.*)$',
      multiLine: true,
    ).firstMatch(agent)?.group(1)?.split(',').map((tool) => tool.trim());
    expect(tools, containsAll(['Write', 'Edit']));
    final scope = _sectionOf(agent, 'Scope Boundaries');
    expect(scope, contains('`docs/superpowers/specs/`'));
    expect(scope, contains('`docs/superpowers/plans/`'));
    expect(
      _pluginText('skills/brainstorming-sdd/references/audit.md'),
      contains("Write nothing but the agent's `report:`"),
    );
    for (final file in ['design.md', 'plan.md']) {
      final text = _pluginText('skills/brainstorming-sdd/references/$file');
      expect(
        text,
        contains("Write no other file but the agent's `report:` file"),
        reason: file,
      );
      expect(
        text,
        contains("write nothing but the agent's `report:` file"),
        reason: file,
      );
    }
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
}

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
