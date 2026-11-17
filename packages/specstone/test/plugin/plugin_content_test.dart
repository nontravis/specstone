import 'dart:io';

import 'package:specstone/src/command_runner.dart';
import 'package:specstone_core/src/setup_migration/agent_assets.dart';
import 'package:specstone_core/src/setup_migration/host_render.dart';
import 'package:test/test.dart';

import '../helpers/plugin_content.dart';
import '../helpers/temp_tree.dart';

Future<List<String>> _problemsOf(Map<String, String> files) async {
  final root = await writeTree(files);
  return unknownCliNames(contentFilesOf(root), SpecstoneCommandRunner());
}

void main() {
  test('f08/us01/fr04/e01, f08/us01/s5: a skill naming specstone check --fix '
      'fails naming its file and --fix', () async {
    expect(
      await _problemsOf({
        'specstone-x/SKILL.md': 'Run `specstone check --fix`.',
      }),
      ['specstone-x/SKILL.md: specstone check has no --fix'],
    );
  });

  test(
    'f08/us01/fr04, f08/us01/s5: a command the CLI lacks fails naming it',
    () async {
      expect(
        await _problemsOf({
          'specstone-x/SKILL.md': 'Run `specstone lint docs`.',
        }),
        ['specstone-x/SKILL.md: specstone has no command lint'],
      );
    },
  );

  test('a span with no specstone call, a skill name, a '
      'placeholder, and prose pass', () async {
    expect(
      await _problemsOf({
        'specstone-x/SKILL.md':
            'Use `git diff --name-only`, `specstone:read-sdd`, and '
            '`specstone <command>` with the specstone CLI.',
      }),
      isEmpty,
    );
  });

  test('a flag a subcommand lacks fails naming the full '
      'command path', () async {
    expect(
      await _problemsOf({
        'specstone-x/SKILL.md': 'Run `specstone hook post-edit --x`.',
      }),
      ['specstone-x/SKILL.md: specstone hook post-edit has no --x'],
    );
  });

  test('an end-of-options -- names no flag', () async {
    expect(
      await _problemsOf({
        'specstone-x/SKILL.md': 'Run `specstone set -- <path>`.',
      }),
      isEmpty,
    );
  });

  test('fenced lines and subcommands are checked', () async {
    expect(
      await _problemsOf({
        'specstone-x/SKILL.md':
            '```sh\nspecstone hook post-edit\nspecstone hook nope\n```\n',
      }),
      ['specstone-x/SKILL.md: specstone hook has no command nope'],
    );
  });

  test('f08/us01/fr04/e02, nfr-te01: a reference file of 1,620 est. tokens '
      'fails alone naming it', () async {
    final root = await writeTree({
      'specstone-x/SKILL.md': 'a' * 4000,
      'specstone-x/reference.md': 'b' * 6480,
    });
    expect(oversizedSkillFiles(contentFilesOf(root)), [
      'specstone-x/reference.md: 1620 est. tokens, over 1500',
    ]);
  });

  test('f08/us01/fr04, nfr-te01: files of one skill that sum past 1,500 est. '
      'tokens pass when each stays within it', () async {
    final root = await writeTree({
      'specstone-x/SKILL.md': 'a' * 4000,
      'specstone-x/reference.md': 'b' * 4000,
    });
    expect(oversizedSkillFiles(contentFilesOf(root)), isEmpty);
  });

  test('an agent file is name-checked and never sized', () async {
    final valid = '${'a' * 8000}\n`specstone check` `specstone hook post-edit`';
    expect(await _problemsOf({'specstone-a.md': valid}), isEmpty);
    expect(
      oversizedSkillFiles(
        contentFilesOf(
          await writeTree({
            'specstone-x/SKILL.md': 'small',
            'specstone-a.md': valid,
          }),
        ),
      ),
      isEmpty,
    );
    expect(await _problemsOf({'specstone-a.md': '$valid `specstone nope`'}), [
      'specstone-a.md: specstone has no command nope',
    ]);
  });

  test('f08/us01/fr04, nfr-te01: oversized skill files list sorted, nested '
      'and non-md files are sized, exactly-limit files pass', () async {
    final root = await writeTree({
      'specstone-y/b.md': 'a' * 6004,
      'specstone-y/a.md': 'a' * 6004,
      'specstone-y/sub/e.md': 'a' * 6004,
      'specstone-y/c.txt': 'a' * 6004,
      'specstone-y/d.md': 'a' * 6000,
    });
    expect(oversizedSkillFiles(contentFilesOf(root)), [
      'specstone-y/a.md: 1501 est. tokens, over 1500',
      'specstone-y/b.md: 1501 est. tokens, over 1500',
      'specstone-y/c.txt: 1501 est. tokens, over 1500',
      'specstone-y/sub/e.md: 1501 est. tokens, over 1500',
    ]);
  });

  test('no skills folder means no oversized skill file', () async {
    final root = await writeTree({'specstone-a.md': 'text'});
    expect(oversizedSkillFiles(contentFilesOf(root)), isEmpty);
  });

  test('CRLF line ends count as LF', () async {
    final root = await writeTree({
      'specstone-x/at_limit.md': 'a\r\n' * 3000,
      'specstone-x/over.md': 'a\r\n' * 3002,
    });
    expect(oversizedSkillFiles(contentFilesOf(root)), [
      'specstone-x/over.md: 1501 est. tokens, over 1500',
    ]);
  });

  test('f08/us01/fr04, f08/us01/s5: every shipped skill and agent names only '
      'commands and flags the CLI has', () {
    expect(unknownCliNames(contentFiles(), SpecstoneCommandRunner()), isEmpty);
  });

  test('f08/us01/fr04, nfr-te01: every shipped skill file stays within '
      '1,500 est. tokens', () {
    expect(oversizedSkillFiles(contentFiles()), isEmpty);
  });

  test(
    'a line with a letter outside the Latin script '
    'fails naming its file and line; accents, emoji, and symbols pass',
    () async {
      final root = await writeTree({
        'specstone-x/SKILL.md': 'Old text, café.\nMark it `เดิม:`.\n📜 ⊆ … —\n',
        'hooks/h.sh': '# 日本\n',
      });

      expect(nonLatinLetterLines(root), [
        'hooks/h.sh:1',
        'specstone-x/SKILL.md:2',
      ]);
    },
  );

  test('a folder in a git work tree lists tracked files only: an ignored or '
      'untracked file is left out', () async {
    final root = await writeTree({
      '.gitignore': '.DS_Store\n',
      'hooks/hooks.json': '{}',
      'hooks/.DS_Store': 'ignored',
      'hooks/new.sh': 'untracked',
    });
    void git(List<String> args) => expect(
      Process.runSync('git', args, workingDirectory: root.path).exitCode,
      0,
      reason: 'git ${args.join(' ')}',
    );
    git(['init', '-q']);
    git(['add', '.gitignore', 'hooks/hooks.json']);

    expect(trackedFiles(root).map((file) => file.uri.pathSegments.last), [
      '.gitignore',
      'hooks.json',
    ]);
  });

  test("no shipped file presumes the Owner's "
      'language with a letter outside the Latin script', () {
    expect(nonLatinLetterLines(agentAssetsRoot()), isEmpty);
  });

  _assetLayoutTests();
  _shippedFileTests();
  _procedureTests();
  _handOffTests();
  _leadAndMermaidTests();
  _agentTests();
  _sizeFixTests();
  _readabilityFixTests();
  _batchGuideTests();
  _repeatsBatchTests();
  _goalMoveTests();
  _glossaryMoveTests();
  _otherPluginSkillTests();
  _planTests();
  _codeParseTests();
  _agentFileTests();
  _hostRenderTests();
  _dispatchReferenceTests();
  _groundInitUpdateTests();
  _brainstormTests();
  _designBriefTests();
  _syncBootstrapTests();
  _planFilesTests();
  _shippedTreeTests();
  _outAndReplaceTests();
  _docLevelPointTests();
}

/// Each plugin file that names a file for an agent's run, and the
/// AgentFileName forms it names under `<folder>/reports/`.
const _agentFileNames = <String, List<String>>{
  'specstone-plan-engineer.md': ['plan-engineer.plan.<XXXXXX>.md'],
  'specstone-sdd-engineer.md': [
    'sdd-engineer.<mode>.<XXXXXX>.md',
    'sdd-engineer.<mode>.batch.<XXXXXX>.txt',
  ],
  'specstone-bootstrap-prd/SKILL.md': ['sdd-engineer.bootstrap.<XXXXXX>.md'],
  _goalMove: ['sdd-engineer.bootstrap.batch.<XXXXXX>.txt'],
  _glossaryMove: ['sdd-engineer.bootstrap.batch.<XXXXXX>.txt'],
  'specstone-bootstrap-spec/SKILL.md': ['sdd-engineer.bootstrap.<XXXXXX>.md'],
  'specstone-brainstorming-sdd/SKILL.md': ['sdd-engineer.<mode>.<XXXXXX>.md'],
  'specstone-brainstorming-sdd/references/author.md': [
    'sdd-engineer.author.batch.<XXXXXX>.txt',
  ],
  'specstone-brainstorming-sdd/references/source.md': [
    'sdd-engineer.design.source.<XXXXXX>.md',
  ],
  'specstone-plan-sdd/SKILL.md': ['plan-engineer.plan.<XXXXXX>.md'],
  'specstone-sync-sdd/SKILL.md': ['sdd-engineer.sync.<XXXXXX>.md'],
};

const _reportsFolder = '<folder>/reports/';

/// A code span naming an agent file by its AgentFileName under
/// [_reportsFolder].
final _agentFileSpan = RegExp(
  r'^<folder>/reports/(?:sdd|plan)-engineer\.(?:<mode>|[a-z]+)\.'
  r'(?:(?:batch|source)\.)?<XXXXXX>\.(?:md|txt)$',
);

final _contextRun = RegExp(r'specstone context\s+\S');

/// The `context` call of a plan task's read line, which plan-sdd names for
/// the task's implementer and never runs itself.
const _implementerReadLine = 'specstone context <target> --for implement --out';

final _folderRun = RegExp(r'specstone folder\b');

/// A code line run in a shell: a `specstone` call or a redirect.
final _shellLine = RegExp(r'^\s*specstone |\s>>?\s');

/// An agent file placeholder, `<file>` or a `<folder>` path, with no `"`
/// before it.
final _unquotedAgentFile = RegExp('(?<!")<(?:file|folder)>');

/// Each inline code span of [markdown] outside its fenced blocks, a span
/// wrapped over lines read whole, with its offset in [markdown].
List<({int offset, String code})> _inlineSpans(String markdown) {
  final blanked = markdown
      .replaceAllMapped(_fencedBlock, (block) => ' ' * block[0]!.length)
      .replaceAll('\n', ' ');
  return [
    for (final span in _codeSpan.allMatches(blanked))
      (offset: span.start, code: span.group(1)!),
  ];
}

/// The offset in [markdown] of each fenced block and inline code span that
/// holds [call], sorted.
List<int> _callOffsets(String markdown, RegExp call) => [
  for (final block in _fencedBlock.allMatches(markdown))
    if (call.hasMatch(block.group(1)!)) block.start,
  for (final span in _inlineSpans(markdown))
    if (call.hasMatch(span.code)) span.offset,
]..sort();

void _agentFileTests() {
  test('no plugin file names '
      'mktemp or a file outside the repository', () {
    final problems = <String>[];
    for (final file in agentSourceFiles(agentAssetsRoot())) {
      final path = shippedPathOf(file);
      final text = _oneLine(file.readAsStringSync());
      for (final banned in ['mktemp', 'outside the repository']) {
        if (text.contains(banned)) problems.add('$path: $banned');
      }
    }
    expect(problems, isEmpty);
  });

  test('each agent file a plugin file names starts '
      'from the specstone folder output, by its AgentFileName', () {
    final named = <String, List<String>>{};
    final problems = <String>[];
    for (final file in _skillAndAgentFiles()) {
      for (final span in _inlineSpans(_pluginText(file))) {
        if (!span.code.contains('reports/')) continue;
        if (_agentFileSpan.hasMatch(span.code)) {
          named
              .putIfAbsent(file, () => [])
              .add(span.code.substring(_reportsFolder.length));
        } else {
          problems.add('$file: ${span.code}');
        }
      }
    }
    expect(problems, isEmpty);
    expect(named.keys, unorderedEquals(_agentFileNames.keys));
    for (final MapEntry(key: file, value: names) in _agentFileNames.entries) {
      expect(named[file], containsAll(names), reason: file);
      expect(
        _oneLine(_pluginText(file)),
        contains('`<folder>` the path `specstone folder` prints'),
        reason: file,
      );
    }
  });

  test('each shell line quotes the agent file '
      'it names, an absolute path that may hold a space', () {
    final problems = <String>[];
    for (final file in _skillAndAgentFiles()) {
      final text = _pluginText(file);
      final codes = [
        for (final block in _fencedBlock.allMatches(text))
          ...block.group(1)!.split('\n'),
        for (final span in _inlineSpans(text)) span.code,
      ];
      for (final code in codes) {
        if (!_shellLine.hasMatch(code)) continue;
        if (_unquotedAgentFile.hasMatch(code)) problems.add('$file: $code');
      }
    }
    expect(problems, isEmpty);
  });

  test('each file that names an agent file runs '
      'specstone folder after its context calls', () {
    final problems = <String>[];
    for (final file in _agentFileNames.keys) {
      var text = _pluginText(file);
      if (file == _planSkill) {
        expect(text, contains(_implementerReadLine));
        text = text.replaceAll(_implementerReadLine, 'its read line');
      }
      final folder = _callOffsets(text, _folderRun);
      final context = _callOffsets(text, _contextRun);
      if (folder.isEmpty) {
        problems.add('$file: no specstone folder');
      } else if (context.isNotEmpty && folder.first < context.last) {
        problems.add('$file: specstone folder before a context call');
      }
    }
    expect(problems, isEmpty);
  });
}

const _nameOnly = 'agent_plugin/ground_a_task/name_only_existing_commands';

Future<List<String>> _skillProblemsOf(String markdown) async {
  final root = await writeTree({'specstone-x/SKILL.md': markdown});
  return otherPluginSkillNames(contentFilesOf(root), shippedDocTypes());
}

const _otherSkill = "specstone-x/SKILL.md: a:b is another plugin's skill";

/// The other-plugin problems of every shipped source and render.
List<String> _shippedOtherPluginSkills() =>
    otherPluginSkillNames(contentFiles(), shippedDocTypes());

void _codeParseTests() {
  test('$_nameOnly: a span wrapped over two lines is read whole, and the span '
      'after it is still read', () async {
    expect(await _skillProblemsOf('Run `specstone get\nfr:x` then `a:b`.'), [
      _otherSkill,
    ]);
    expect(
      await _problemsOf({
        'specstone-x/SKILL.md': 'Run `specstone check\n--fix`.',
      }),
      ['specstone-x/SKILL.md: specstone check has no --fix'],
    );
  });

  test('$_nameOnly: a ~~~ fence is a code block, so its text is no inline '
      'span and its lines are checked', () async {
    expect(await _skillProblemsOf('~~~\n`a:b`\n~~~\n'), isEmpty);
    expect(
      await _problemsOf({
        'specstone-x/SKILL.md': '~~~sh\nspecstone nope\n~~~\n',
      }),
      ['specstone-x/SKILL.md: specstone has no command nope'],
    );
  });

  test(
    '$_nameOnly: a fence inside a list item or a quote is a code block',
    () async {
      expect(await _skillProblemsOf('- ```\n  `a:b`\n  ```\n'), isEmpty);
      expect(await _skillProblemsOf('> ```\n> `a:b`\n> ```\n'), isEmpty);
      expect(
        await _problemsOf({
          'specstone-x/SKILL.md': '- ```sh\n  specstone nope\n  ```\n',
        }),
        ['specstone-x/SKILL.md: specstone has no command nope'],
      );
      expect(
        await _problemsOf({
          'specstone-x/SKILL.md': '> ```sh\n> specstone nope\n> ```\n',
        }),
        ['specstone-x/SKILL.md: specstone has no command nope'],
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
      await _problemsOf({
        'specstone-x/SKILL.md': '- ```sh\n  specstone nope\n',
      }),
      ['specstone-x/SKILL.md: specstone has no command nope'],
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
  '`specstone-plan-sdd`',
];

void _otherPluginSkillTests() {
  test('$_nameOnly E05: a skill file naming superpowers:writing-plans fails '
      'naming the file and the span', () async {
    final root = await writeTree({
      'specstone-x/SKILL.md': 'Then run `superpowers:writing-plans`.',
    });
    expect(otherPluginSkillNames(contentFilesOf(root), shippedDocTypes()), [
      "specstone-x/SKILL.md: superpowers:writing-plans is another plugin's skill",
    ]);
  });

  test('$_nameOnly E03: an agent file holding path:line fails naming the '
      'file and the span', () async {
    final root = await writeTree({
      'specstone-a.md': 'Cite each hit as `path:line`.',
    });
    expect(otherPluginSkillNames(contentFilesOf(root), shippedDocTypes()), [
      "specstone-a.md: path:line is another plugin's skill",
    ]);
  });

  test('$_nameOnly E06: a doc citation, a placeholder, a doc-type prefix, and '
      'a hyphenated specstone skill name pass', () async {
    final root = await writeTree({
      'specstone-x/SKILL.md': 'Cite ${_docCitations.join(', ')}.',
      'specstone-a.md': 'Cite ${_docCitations.join(', ')}.',
    });
    expect(
      otherPluginSkillNames(contentFilesOf(root), shippedDocTypes()),
      isEmpty,
    );
  });

  test('$_nameOnly: a backticked specstone:<name> fails in a skill file and '
      'an agent file, and the hyphenated name passes', () async {
    final root = await writeTree({
      'specstone-x/SKILL.md': 'Follow `specstone:read-sdd`.',
      'specstone-a.md':
          'Follow `specstone:read-sdd`, not `specstone-read-sdd`.',
    });
    expect(otherPluginSkillNames(contentFilesOf(root), shippedDocTypes()), [
      "specstone-a.md: specstone:read-sdd is another plugin's skill",
      "specstone-x/SKILL.md: specstone:read-sdd is another plugin's skill",
    ]);
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
      'specstone-x/SKILL.md':
          '```\nsuperpowers:writing-plans\n```\n'
          '`superpowers:writing-plans now` `a:b` `a:b`\n',
    });
    expect(otherPluginSkillNames(contentFilesOf(root), shippedDocTypes()), [
      "specstone-x/SKILL.md: a:b is another plugin's skill",
    ]);
  });

  test("$_nameOnly: no shipped plugin file names another plugin's skill", () {
    expect(_shippedOtherPluginSkills(), isEmpty);
  });
}

const _skillNames = [
  'bootstrap-prd',
  'bootstrap-spec',
  'brainstorming-sdd',
  'expert-sdd',
  'init',
  'plan-sdd',
  'read-sdd',
  'sync-sdd',
  'update-sdd',
];

const _agentNames = ['plan-engineer', 'sdd-engineer', 'sdd-reader'];

/// The base name of [entity]'s path, its `.md` ending cut.
String _baseNameOf(FileSystemEntity entity) {
  final segments = entity.uri.pathSegments.where((s) => s.isNotEmpty);
  return segments.last.replaceFirst(RegExp(r'\.md$'), '');
}

void _assetLayoutTests() {
  final skillFolders = {
    for (final file in agentSourceFiles(agentAssetsRoot()))
      if (isSkillSourcePath(shippedPathOf(file)))
        shippedPathOf(file).split('/').first,
  }.map((name) => Directory.fromUri(agentAssetsRoot().uri.resolve('$name/')));
  final agentFiles = agentSourceFiles(agentAssetsRoot())
      .where((file) => !isSkillSourcePath(shippedPathOf(file)));

  test('the plugin folder holds no skills folder and no agents folder', () {
    final shipped = agentSourceFiles(agentAssetsRoot()).map(shippedPathOf);
    for (final folder in const ['skills', 'agents']) {
      expect(
        shipped.where((path) => path.startsWith('$folder/')),
        isEmpty,
        reason: '$folder/ is shipped',
      );
    }
  });

  test('each specstone-<name> folder holds a SKILL.md named as the folder', () {
    expect(skillFolders, isNotEmpty);
    for (final folder in skillFolders) {
      final skill = File.fromUri(folder.uri.resolve('SKILL.md'));
      expect(skill.existsSync(), isTrue, reason: '${folder.path} has no skill');
      expect(
        _frontmatterName.firstMatch(skill.readAsStringSync())?.group(1),
        _baseNameOf(folder),
      );
    }
  });

  test('each specstone-<name>.md agent file is named as its base name', () {
    expect(agentFiles, isNotEmpty);
    for (final file in agentFiles) {
      expect(
        _frontmatterName.firstMatch(file.readAsStringSync())?.group(1),
        _baseNameOf(file),
      );
    }
  });

  test(
    'the source walk sees the twelve sources and leaves AGENT.md out',
    () async {
      final seen = agentSourceFiles(agentAssetsRoot()).map(shippedPathOf);
      expect(seen.where((path) => path.endsWith('/SKILL.md')), hasLength(9));
      expect(
        seen.where((path) => !isSkillSourcePath(path)),
        unorderedEquals([for (final name in _agentNames) 'specstone-$name.md']),
      );
      expect(seen, isNot(contains('AGENT.md')));

      final root = await writeTree({
        'AGENT.md': 'text',
        'specstone-x/SKILL.md': 'text',
        'specstone-y.md': 'text',
        'other/SKILL.md': 'text',
        'other.md': 'text',
      });
      expect(agentSourceFiles(root).map((file) => file.uri.pathSegments.last), [
        'SKILL.md',
        'specstone-y.md',
      ]);
    },
  );

  test('the nine skills and three agents are all there', () {
    expect(
      skillFolders.map(_baseNameOf),
      unorderedEquals([for (final name in _skillNames) 'specstone-$name']),
    );
    expect(
      agentFiles.map(_baseNameOf),
      unorderedEquals([for (final name in _agentNames) 'specstone-$name']),
    );
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
    file: 'specstone-expert-sdd/SKILL.md',
    name: 'specstone-expert-sdd',
    tags: 'f08/us02/fr04, f08/us01/fr03, f08/us02/s5',
    commands: ['guide', 'set', 'check'],
  ),
  (
    file: 'specstone-read-sdd/SKILL.md',
    name: 'specstone-read-sdd',
    tags: 'f08/us01/fr01, f08/us01/fr03, f08/us01/s1',
    commands: ['context'],
  ),
  (
    file: 'specstone-sdd-reader.md',
    name: 'specstone-sdd-reader',
    tags: 'f08/us01/fr02, f08/us01/fr03, f08/us01/s1',
    commands: ['context'],
  ),
  (
    file: 'specstone-sync-sdd/SKILL.md',
    name: 'specstone-sync-sdd',
    tags:
        'f08/us03/fr01, f08/us03/fr02, f08/us03/fr03, f08/us01/fr03, '
        'f08/us03/s1',
    commands: ['check', 'get', 'set'],
  ),
  (
    file: 'specstone-sdd-engineer.md',
    name: 'specstone-sdd-engineer',
    tags:
        'f08/us02/fr02, f08/us02/fr06, f08/us02/fr07, f08/us03/fr02, '
        'f08/us05/fr01, f08/us01/fr03, f08/us02/s1, f08/us03/s2',
    commands: ['new', 'set', 'check'],
  ),
  (
    file: 'specstone-brainstorming-sdd/SKILL.md',
    name: 'specstone-brainstorming-sdd',
    tags: 'f08/us02/fr01, f08/us01/fr03, f08/us02/s4',
    commands: ['context'],
  ),
  (
    file: 'specstone-update-sdd/SKILL.md',
    name: 'specstone-update-sdd',
    tags: 'f08/us02/fr03, f08/us01/fr03, f08/us02/s2',
    commands: ['check', 'get', 'set', 'approve'],
  ),
  (
    file: 'specstone-init/SKILL.md',
    name: 'specstone-init',
    tags: 'f08/us04/fr01, f08/us04/s1',
    commands: ['init', 'guide', 'set', 'approve'],
  ),
  (
    file: 'specstone-bootstrap-prd/SKILL.md',
    name: 'specstone-bootstrap-prd',
    tags:
        'f08/us05/fr01, f08/us05/fr02, f08/us05/fr03, f08/us01/fr03, '
        'f08/us05/s1',
    commands: ['check'],
  ),
  (
    file: 'specstone-bootstrap-spec/SKILL.md',
    name: 'specstone-bootstrap-spec',
    tags:
        'f08/us05/fr01, f08/us05/fr02, f08/us05/fr03, f08/us01/fr03, '
        'f08/us05/s1',
    commands: ['check'],
  ),
  (
    file: 'specstone-plan-sdd/SKILL.md',
    name: 'specstone-plan-sdd',
    tags: 'agent_plugin/plan_approved_stories/run_plan_skill',
    commands: ['check', 'list'],
  ),
  (
    file: 'specstone-plan-engineer.md',
    name: 'specstone-plan-engineer',
    tags: 'agent_plugin/plan_approved_stories/write_grounded_plan',
    commands: ['context', 'check'],
  ),
];

final _frontmatterName = RegExp(r'^---\r?\n(?:.*\r?\n)*?name:\s*(\S+)');

void _shippedFileTests() {
  for (final shipped in _shipped) {
    test('${shipped.tags}: ${shipped.file} carries its frontmatter name and '
        'row commands, and a skill opens on a specstone command', () {
      final file = File.fromUri(agentAssetsRoot().uri.resolve(shipped.file));
      expect(file.existsSync(), isTrue, reason: '${shipped.file} is missing');
      final text = file.readAsStringSync();
      expect(_frontmatterName.firstMatch(text)?.group(1), shipped.name);
      final commands = cliCommands(text);
      expect(commands, containsAll(shipped.commands));
      if (isSkillSourcePath(shipped.file)) {
        final first = commands.first;
        if (shipped.name == 'specstone-init') {
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
    file: 'specstone-sync-sdd/references/procedure.md',
    tags: 'f08/us03/fr01, f08/us03/fr02, f08/us03/fr03',
    commands: ['context', 'set', 'check'],
  ),
  (
    file: 'specstone-sync-sdd/references/task-refs.md',
    tags: 'the sync removes the refs of a closed task',
    commands: ['set'],
  ),
  (
    file: 'specstone-bootstrap-prd/references/procedure.md',
    tags: 'f08/us05/fr01, f08/us05/fr02, f08/us05/fr03',
    commands: ['check', 'guide', 'new', 'set', 'delete'],
  ),
  (
    file: 'specstone-bootstrap-spec/references/procedure.md',
    tags: 'f08/us05/fr01, f08/us05/fr02, f08/us05/fr03',
    commands: ['check', 'guide', 'new', 'set', 'delete'],
  ),
  (
    file: _goalMove,
    tags: 'f08/us05/fr01',
    commands: ['new', 'get', 'set', 'refs'],
  ),
  (
    file: 'specstone-brainstorming-sdd/references/author.md',
    tags: 'f08/us02/fr01, f08/us02/fr02',
    commands: ['guide', 'new', 'get', 'set', 'search', 'check'],
  ),
  (
    file: 'specstone-brainstorming-sdd/references/design.md',
    tags: 'f08/us02/fr01, f08/us02/fr06',
    commands: ['check'],
  ),
  (
    file: 'specstone-brainstorming-sdd/references/audit.md',
    tags: 'f08/us02/fr01, f08/us02/fr07',
    commands: ['get', 'context', 'list', 'check'],
  ),
];

void _procedureTests() {
  for (final procedure in _procedures) {
    test('${procedure.tags}, nfr-te01: ${procedure.file} exists, names its '
        'row commands, stays within 1,500 est. tokens, and names only '
        'commands and flags the CLI has', () {
      final file = File.fromUri(agentAssetsRoot().uri.resolve(procedure.file));
      expect(file.existsSync(), isTrue, reason: '${procedure.file} is missing');
      expect(
        cliCommands(file.readAsStringSync()),
        containsAll(procedure.commands),
      );
      bool ofThisFile(String problem) =>
          problem.startsWith('${procedure.file}:');
      expect(oversizedSkillFiles(contentFiles()).where(ofThisFile), isEmpty);
      expect(
        unknownCliNames(
          contentFiles(),
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
    final file = 'specstone-$skill/references/procedure.md';
    test('d-ps2: $file points to writes.md, which holds the Mermaid quoting '
        'sentence and names the `#_lead` target of `specstone set`', () {
      expect(
        _pluginText(file),
        contains('`$_writesFromReference`'),
        reason: file,
      );
      final text = _oneLine(_pluginText(_writes));
      expect(text, contains(_mermaidSentence));
      expect(text, contains(_leadSentence));
    });
  }

  test('d-ps2: update-sdd names the `#_lead` target', () {
    expect(
      _oneLine(_pluginText('specstone-update-sdd/SKILL.md')),
      contains(_leadSentence),
    );
  });
}

/// Each skill that hands its work to `specstone:sdd-engineer`; both read the
/// skill's `references/procedure.md`.
const _handOffs = ['sync-sdd', 'bootstrap-prd', 'bootstrap-spec'];

/// The text of plugin [file] with `\n` line ends, as a Windows checkout's
/// `\r\n` would otherwise fail every multi-line match.
String _pluginText(String file) =>
    File.fromUri(agentAssetsRoot().uri.resolve(file))
        .readAsStringSync()
        .replaceAll('\r\n', '\n');

final _frontmatter = RegExp(r'^---\r?\n(?:.*\r?\n)*?---\r?\n');

/// [text] without its frontmatter: a `description` may name a command, such
/// as `specstone migrate`, that the skill never calls.
String _bodyOf(String text) => text.replaceFirst(_frontmatter, '');

void _handOffTests() {
  test('f08/us03/fr01, f08/us05/fr01: a hand-off skill opens on check, '
      'dispatches specstone-sdd-engineer, and names the procedure the agent '
      'reads', () {
    final agent = _pluginText('specstone-sdd-engineer.md');
    for (final skill in _handOffs) {
      final text = _pluginText('specstone-$skill/SKILL.md');
      expect(text, contains('`specstone-sdd-engineer`'), reason: skill);
      expect(text, contains('`references/procedure.md`'), reason: skill);
      expect(cliCommands(_bodyOf(text)).first, 'check', reason: skill);
      expect(
        agent,
        contains('`.agents/skills/specstone-$skill/references/procedure.md`'),
        reason: 'specstone-sdd-engineer.md, $skill',
      );
    }
  });

  test('approval flows paste the printed view', () {
    for (final skill in _handOffs) {
      expect(
        _pluginText('specstone-$skill/SKILL.md'),
        isNot(contains("Owner's language")),
        reason: skill,
      );
    }
    expect(
      _pluginText('specstone-sdd-engineer.md'),
      isNot(contains("Owner's language")),
    );
    expect(
      _pluginText('specstone-sdd-engineer.md'),
      contains('never their text'),
    );
    for (final skill in ['expert-sdd', 'update-sdd']) {
      final text = _pluginText('specstone-$skill/SKILL.md');
      expect(text, contains('--dry-run'), reason: skill);
      expect(text, contains('`Why:`'), reason: skill);
    }
    expect(
      _pluginText('specstone-expert-sdd/SKILL.md'),
      contains('pasted verbatim'),
    );
  });

  test('f08/us02/fr01, f08/us03/fr01, f08/us05/fr01: each dispatching skill '
      'passes a report file under the reports folder and shows the reply '
      'word for word', () {
    for (final skill in [..._handOffs, 'brainstorming-sdd']) {
      final text = _pluginText('specstone-$skill/SKILL.md');
      expect(text, contains('`report:`'), reason: skill);
      expect(text, contains('`$_reportsFolder'), reason: skill);
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
        _pluginText('specstone-$skill/SKILL.md'),
        contains('a new name per batch'),
        reason: skill,
      );
      expect(
        _pluginText('specstone-$skill/SKILL.md'),
        contains('`mode: bootstrap`'),
        reason: skill,
      );
    }
  });

  test('f08/us02/fr01, f08/us02/fr06, f08/us02/fr07: brainstorming-sdd '
      'dispatches specstone-sdd-engineer in author and audit mode, writes the '
      'design document itself, and names the reference of each mode, as the '
      'agent does', () {
    final skill = _pluginText('specstone-brainstorming-sdd/SKILL.md');
    final agent = _pluginText('specstone-sdd-engineer.md');
    expect(skill, contains('`specstone-sdd-engineer`'));
    expect(skill, isNot(contains('`mode: design`')));
    for (final mode in _brainstormModes) {
      if (mode != 'design') {
        expect(skill, contains('`mode: $mode`'), reason: mode);
      }
      expect(
        skill,
        contains('`references/$mode.md`'),
        reason: 'brainstorming-sdd, $mode',
      );
      expect(
        agent,
        mode == 'design'
            ? isNot(contains('references/$mode.md'))
            : contains(
                '`.agents/skills/specstone-brainstorming-sdd/references/'
                '$mode.md`',
              ),
        reason: 'specstone-sdd-engineer.md, $mode',
      );
    }
  });

  test('f08/us02/fr02, f08/us02/fr06, f08/us02/fr07, f08/us03/fr02, '
      'sdd-engineer writes its whole report to the report file '
      'and replies with the Report line and the relay block', () {
    final agent = _pluginText('specstone-sdd-engineer.md');
    final input = _sectionOf(agent, 'Input Contract');
    expect(input, contains('**`report`**'));
    expect(
      input,
      contains('`${_reportsFolder}sdd-engineer.<mode>.<XXXXXX>.md`'),
    );
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
    for (final mode in ['author', 'audit', 'sync', 'bootstrap']) {
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
      contains('Beyond the `report:` file, write or edit only a batch file'),
    );
  });

  test('no shipped plugin file holds the relay line or '
      'routed by', () {
    for (final file in agentSourceFiles(agentAssetsRoot())) {
      final text = file.readAsStringSync();
      expect(text, isNot(contains(_relayLine)), reason: file.path);
      expect(text, isNot(contains('routed by')), reason: file.path);
    }
  });

  test('f08/us02/fr01, f08/us02/fr07: the audit report splits Findings, '
      'Waits on the Owner, and Outside the drafts, and only Findings drives '
      'a fix round', () {
    final report = _sectionOf(
      _pluginText('specstone-brainstorming-sdd/references/audit.md'),
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
      _pluginText('specstone-brainstorming-sdd/SKILL.md'),
      contains('`Findings:` lines'),
    );
  });

  test('E07, '
      'agent_plugin/write_prd_and_spec/audit_drafts_by_reading, '
      'E09, '
      'each plugin '
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
        _pluginText('specstone-brainstorming-sdd/references/audit.md'),
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
    for (final file in agentSourceFiles(agentAssetsRoot())) {
      expect(
        _oneLine(file.readAsStringSync().replaceAll('`', '')),
        isNot(contains('unconfirmed link on a draft')),
        reason: file.path,
      );
    }
  });

  test('author mode runs a bare specstone check before its '
      'first write and after its last', () {
    final check = _sectionOf(
      _pluginText('specstone-brainstorming-sdd/references/author.md'),
      '4. Check',
    );
    expect(check, contains('`specstone check`'));
    expect(check, contains('before your first write'));
    expect(check, contains('after your last'));
  });

  test('E07: the '
      'author report holds the ready move command, and the skill runner runs '
      'it before the audit', () {
    final report = _sectionOf(
      _pluginText('specstone-brainstorming-sdd/references/author.md'),
      '5. Report',
    );
    for (final line in [
      'Move: specstone move <story> … --under <feature>\n',
      'Move: specstone move <fr or nf> … --under <story>\n',
      'Move: specstone move feature:<name> … --under <feature>\n',
      'Move: specstone move feature:<name> … --top\n',
      'Move: specstone move <doc>#<ID> … --under <doc>\n',
      'Move: specstone move <story>#S<N> … --under <story>\n',
    ]) {
      expect(report, contains('\n$line'), reason: line);
    }
    final flatReport = report.replaceAll(RegExp(r'\s+'), ' ');
    expect(
      flatReport,
      contains(
        'only for a moved doc, item, or scenario: one line per target parent '
        'or `--top`; copy each into the relay block.',
      ),
    );
    expect(
      flatReport,
      contains(
        'Name each draft a `Move:` line moves, the moved doc and its '
        'children, by the name it holds after the move.',
      ),
    );
    final drafts = _sectionOf(
      _pluginText('specstone-brainstorming-sdd/SKILL.md'),
      '4. Write the drafts, then audit them',
    );
    final move = drafts.indexOf("Run the author's `Move:` commands");
    expect(move, isNonNegative);
    expect(move, lessThan(drafts.indexOf('`mode: audit`')));
  });

  test('E10, '
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
      ('specstone-sdd-engineer.md', 'Output Format'),
      ('specstone-brainstorming-sdd/references/author.md', '5. Report'),
    ]) {
      final text = _oneLine(_sectionOf(_pluginText(file), section));
      expect(text, contains('never your own tally'), reason: '$file#$section');
    }
    final moved = _oneLine(
      _sectionOf(
        _pluginText('specstone-brainstorming-sdd/references/author.md'),
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
      _oneLine(
        _sectionOf(_pluginText('specstone-expert-sdd/SKILL.md'), 'Rules'),
      ),
      contains(
        'Run `specstone approve` only with `--dry-run`, or with `--yes` as '
        'Owner confirmation below says',
      ),
    );
  });

  test('E10, '
      'the author '
      "report's Drafts line stays a bare list of names that the audit "
      'dispatch and plan-sdd take as it is, its counts on their own line', () {
    final report = _sectionOf(
      _pluginText('specstone-brainstorming-sdd/references/author.md'),
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
      _sectionOf(_pluginText('specstone-sdd-engineer.md'), 'Output Format'),
      contains(
        "the `Drafts for the Owner's specstone approve` line, the `Counts:` "
        'line,',
      ),
    );
  });

  test("Run an Owner-gated command only after the Owner's ok: "
      'the Rules and Owner confirmation sections of expert-sdd gate the '
      'delete of a guarded doc', () {
    final skill = _pluginText('specstone-expert-sdd/SKILL.md');
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

  test("Run an Owner-gated command only after the Owner's ok: "
      'the Owner confirmation section of expert-sdd leaves specstone trust to '
      "the Owner's own terminal", () {
    final section = _oneLine(
      _sectionOf(
        _pluginText('specstone-expert-sdd/SKILL.md'),
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

  test('E08, E09: '
      'the Rules section of expert-sdd holds the one-owner rule and its '
      'citation form and points to confirm-links.md, which alone holds the '
      'steps that confirm a traced link', () {
    final skill = _pluginText('specstone-expert-sdd/SKILL.md');
    final rules = _oneLine(_sectionOf(skill, 'Rules'));
    for (final point in _oneOwnerPoints) {
      expect(rules, contains(point), reason: point);
    }
    expect(
      rules,
      contains(
        'To write an FR, an nf, an API row, or an `Overrides:` line, follow '
        '`references/confirm-links.md`',
      ),
    );
    final links = _oneLine(_pluginText(_confirmLinks));
    expect(links, contains(_confirmLinkSteps));
    for (final point in _citedLinkPoints) {
      expect(links, contains(point), reason: point);
    }
    expect(rules, contains('Its links: `references/confirm-links.md`.'));
    expect(skill, isNot(contains('pins no hash')));
    for (final step in ['bases.fields.confirmed', '--field confirmed']) {
      expect(skill, isNot(contains(step)), reason: step);
    }
  });

  test('expert-sdd tells the agent to record an override entry with each '
      'override line', () {
    final rules = _oneLine(
      _sectionOf(_pluginText('specstone-expert-sdd/SKILL.md'), 'Rules'),
    );
    expect(rules, contains('an `Overrides:` line, follow'));
    final links = _oneLine(_pluginText(_confirmLinks));
    for (final point in _overrideEntryPoints) {
      expect(links, contains(point), reason: point);
    }
  });

  test('the Rules section of expert-sdd has a new feature pick its patterns '
      'with guide --pattern and cover each checklist item or name it in the '
      "feature's Out-of-scope", () {
    final rules = _oneLine(
      _sectionOf(_pluginText('specstone-expert-sdd/SKILL.md'), 'Rules'),
    );
    expect(
      rules,
      contains(
        'For a new feature, pick its patterns with `specstone guide '
        "--pattern`; cover each checklist item or name it in the feature's "
        'Out-of-scope as a skip line.',
      ),
    );
  });

  test('step 2 of brainstorming-sdd has the design document propose each '
      "new or reshaped feature's patterns from guide --pattern", () {
    final step = _oneLine(
      _sectionOf(
        _pluginText('specstone-brainstorming-sdd/SKILL.md'),
        '2. Reach an approved design document',
      ),
    );
    expect(
      step,
      contains(
        "The design document proposes each new or reshaped feature's "
        '`patterns:` value, picked from `specstone guide --pattern`.',
      ),
    );
  });

  test('the audit compares each feature pattern item of a design bundle with '
      'the docs and reports an item neither covered nor skipped', () {
    final compare = _oneLine(
      _sectionOf(
        _pluginText('specstone-brainstorming-sdd/references/audit.md'),
        '2. Compare',
      ),
    );
    expect(
      compare,
      contains(
        "- **Feature pattern:** for each item of a bundle's pattern part, "
        'search the doc listing the pattern, its subtree, and its '
        "feature's spec folder, if any, for covering text or a skip line in "
        "that doc's `out_of_scope`; else report `<type>:<name>#out_of_scope: "
        '<pattern>/<item> neither covered nor skipped`, `<type>:<name>` '
        "the listing doc, typed as the part's bundle line.",
      ),
    );
  });

  test('the audit reports a dropped or departed decision once and names the '
      'citer commands', () {
    final compare = _oneLine(
      _sectionOf(
        _pluginText('specstone-brainstorming-sdd/references/audit.md'),
        '2. Compare',
      ),
    );
    String bullet(String label) {
      final start = compare.indexOf('- **$label:**');
      expect(start, isNonNegative, reason: label);
      final next = compare.indexOf(' - **', start + 1);
      return compare.substring(start, next < 0 ? compare.length : next);
    }

    expect(compare, isNot(contains('Draft and decision')));
    expect(compare, isNot(contains('draft-and-decision')));
    expect(bullet('Decision dropped'), contains('departs'));
    expect(bullet('Repoint'), contains('specstone refs'));
    expect(bullet('Repoint'), contains('specstone list --cites'));
  });

  test('audit reference reads for example and clause order', () {
    final compare = _oneLine(
      _sectionOf(
        _pluginText('specstone-brainstorming-sdd/references/audit.md'),
        '2. Compare',
      ),
    );
    expect(
      compare,
      contains(
        'Record one gap per line, `<type>:<name>#<section>: <gap>`, for each '
        'of these:',
      ),
    );
    expect(
      compare,
      contains(
        'Read each draft item for two gaps `check` never names, each a '
        '`Findings:` line naming its ID or first words: - **No example:**',
      ),
    );
    expect(
      compare,
      contains(
        'a non-obvious rule whose result on one concrete '
        'input you cannot state after one read.',
      ),
    );
    expect(
      compare,
      contains(
        '**Clause order:** a condition after its rule, or clauses nested '
        'inside one sentence.',
      ),
    );
  });

  test('no plugin '
      'file tells an agent to cite a rule by doc name', () {
    final hits = <String>[];
    for (final file in agentSourceFiles(agentAssetsRoot())) {
      final path = shippedPathOf(file);
      final text = _oneLine(file.readAsStringSync());
      for (final match in _nameCite.allMatches(text)) {
        hits.add('$path: ${match[0]}');
      }
    }
    expect(hits..sort(), unorderedEquals(_ownTextNameCites.keys));
  });

  group('the auto approve branch', () {
    test("expert-sdd's Owner confirmation points the approve item to "
        'references/approve-mode.md', () {
      final section = _oneLine(
        _sectionOf(
          _pluginText('specstone-expert-sdd/SKILL.md'),
          'Owner confirmation',
        ),
      );
      final approveItem = section.substring(
        section.indexOf('- `approve`:'),
        section.indexOf('- `delete`:'),
      );
      expect(approveItem, contains('follow `references/approve-mode.md`'));
    });

    test("expert-sdd's step 3 runs the --yes command only after the ok, a "
        'clean draft under auto excepted', () {
      final section = _oneLine(
        _sectionOf(
          _pluginText('specstone-expert-sdd/SKILL.md'),
          'Owner confirmation',
        ),
      );
      expect(
        section,
        contains(
          'Run the `--yes` command, a clean draft under `auto` excepted, only '
          "after the Owner's `ok`",
        ),
      );
    });

    test('the approve-mode reference asks no ok, passes an unconfirmed '
        'finding that waits for the owner, and names the upstream change in '
        'its list', () {
      final text = _pluginText(_approveMode);
      expect(_oneLine(text), contains('Ask no `ok`'));
      final tests = _oneLine(_sectionOf(text, 'Clean-draft tests'));
      expect(tests, contains('`unconfirmed` with `waitsFor` `owner`'));
      final list = _oneLine(_sectionOf(text, 'Approved list'));
      expect(list, contains('name the upstream change it was checked against'));
    });

    test('the approve-mode reference runs the dry run, reads approveMode, '
        'checks, and approves the clean drafts in one --yes call', () {
      final text = _oneLine(_pluginText(_approveMode));
      for (final token in [
        '--dry-run --json',
        'approveMode',
        '`ask`',
        '`auto`',
        'check --json',
        '@<hash>',
        '--yes',
        'Owner confirmation',
      ]) {
        expect(text, contains(token), reason: token);
      }
    });

    test('the approve-mode reference holds five numbered clean-draft tests, '
        'the last reading Not landed: lines', () {
      final tests = _sectionOf(_pluginText(_approveMode), 'Clean-draft tests');
      final numbered = RegExp(
        r'^\d+\. .*',
        multiLine: true,
      ).allMatches(tests).map((match) => match[0]!).toList();
      expect(numbered, hasLength(5));
      for (final (at, line) in numbered.indexed) {
        expect(line, startsWith('${at + 1}. '));
      }
      expect(numbered.last, contains('Not landed:'));
      expect(_oneLine(tests), contains('Not landed: none'));
    });

    test('the approve-mode reference retries once on exit 75 and makes one '
        'last call', () {
      final exit = _oneLine(_sectionOf(_pluginText(_approveMode), 'Exit 75'));
      for (final token in [
        '75',
        '`base_mismatch`',
        '`index_busy`',
        'retry once',
        'one last',
        'never retried',
        'the retry',
      ]) {
        expect(exit, contains(token), reason: token);
      }
      final sentences = _oneLine(_pluginText(_approveMode))
          .split(RegExp(r'(?<=\.) '));
      final withThird = sentences.where((line) => line.contains('third'));
      expect(withThird, isNotEmpty);
      for (final line in withThird) {
        expect(line.toLowerCase(), contains('never'), reason: line);
      }
    });

    test('the approve-mode reference names docPath and Why: for its list', () {
      final list = _oneLine(
        _sectionOf(_pluginText(_approveMode), 'Approved list'),
      );
      expect(list, contains('docPath'));
      expect(list, contains('Why:'));
    });

    test('only expert-sdd holds the auto rule', () {
      final holders = [
        for (final file in _skillAndAgentFiles())
          if (_pluginText(file).contains('approveMode')) file,
      ];
      expect(holders, [_approveMode]);
    });

    test('no skill reads the approve mode from a shell', () {
      final holders = [
        for (final file in agentSourceFiles(agentAssetsRoot()))
          if (file.readAsStringSync().contains('SPECSTONE_APPROVE_MODE'))
            shippedPathOf(file),
      ];
      expect(holders, isEmpty);
    });

    test('confirm-links names the approved list for a re-confirmation under '
        'auto', () {
      expect(_pluginText(_confirmLinks), contains('approve-mode.md'));
    });

    for (final skill in ['update-sdd', 'init']) {
      test("$skill's approve red flag waits for the ok under ask and defers "
          'to Owner confirmation under auto', () {
        final row = _oneLine(
          _sectionOf(_pluginText('specstone-$skill/SKILL.md'), 'Red flags')
              .split('\n')
              .singleWhere((line) => line.contains('specstone approve')),
        );
        expect(row, contains('`ask`'));
        expect(row, contains('Owner confirmation'));
      });
    }

    test("update-sdd's step 4 limits waiting for the ok to the ask mode", () {
      final step = _oneLine(
        _sectionOf(
          _pluginText('specstone-update-sdd/SKILL.md'),
          '4. Name the change for the Owner',
        ),
      );
      expect(step, contains('`ask`'));
    });

    test("init's approval section names Owner confirmation and the auto "
        'mode', () {
      final section = _oneLine(
        _sectionOf(
          _pluginText('specstone-init/SKILL.md'),
          '3. Get the drafts approved',
        ),
      );
      expect(section, contains('Owner confirmation'));
      expect(section, contains('`auto`'));
    });

    test('every pointing skill names Owner confirmation for its drafts and '
        'holds no auto copy', () {
      for (final skill in [
        'bootstrap-prd',
        'bootstrap-spec',
        'init',
        'sync-sdd',
        'update-sdd',
      ]) {
        final text = _oneLine(_pluginText('specstone-$skill/SKILL.md'));
        expect(text, contains('Owner confirmation'), reason: skill);
        expect(text, isNot(contains('approveMode')), reason: skill);
      }
    });

    String draftsStep() => _sectionOf(
      _pluginText('specstone-brainstorming-sdd/SKILL.md'),
      '4. Write the drafts, then audit them',
    );

    test("brainstorming-sdd hands the last audit's relay block and the author "
        'replies to Owner confirmation', () {
      final step = _oneLine(draftsStep());
      expect(step, contains('relay block'));
      expect(step, contains('Owner confirmation'));
    });

    test("brainstorming-sdd's approval step names the auto mode", () {
      expect(draftsStep(), contains('`auto`'));
    });

    test("the audit's Waits on the Owner bullet names Owner confirmation as "
        'its clearer and no sole approver', () {
      final audit = _oneLine(
        _pluginText('specstone-brainstorming-sdd/references/audit.md'),
      );
      expect(
        audit,
        contains("`specstone-expert-sdd`'s Owner confirmation clears it"),
      );
      expect(audit, isNot(contains('only the Owner clears')));
    });

    test("the approve-mode reference takes its drafts only from the run's "
        'own list or the report lines that name them', () {
      final step = _oneLine(_sectionOf(_pluginText(_approveMode), 'Dry run'));
      for (final token in [
        "`Drafts for the Owner's specstone approve`",
        'author report',
        'sync or bootstrap report',
        'drafts lines',
        'other drafts',
      ]) {
        expect(step, contains(token), reason: token);
      }
    });
  });
}

const _approveMode = 'specstone-expert-sdd/references/approve-mode.md';

/// An instruction to cite by a name: a cite word, then `by` a name, within
/// one clause, or a citation of a doc name.
final _nameCite = RegExp(
  r'\bcit(?:e|es|ed|ing|ations?)\b[^.;:]*?\bby (?:(?:its|the|their|a|doc|'
  r'Specstone) )*name\b|\bcitation of the doc name\b',
  caseSensitive: false,
);

/// Each name cite a plugin file keeps, by `<file>: <match>`, with its reason:
/// a design document or plan is no Specstone doc, so the item-link rule
/// never binds its own text.
const _ownTextNameCites = {
  'specstone-brainstorming-sdd/references/design.md: Cite each story, FR, and '
          'section by its Specstone name':
      "the design document's own cites (`write_design_document` Statement)",
  'specstone-brainstorming-sdd/references/design.md: cited by name':
      "the design document's Constraints list",
  'specstone-plan-engineer.md: citation of the doc name':
      "a plan step's own cite of the point it would restate",
};

/// Each point of the one-owner clause and the item-link rule, and of
/// the `check` findings that read its link, as the Rules section of
/// expert-sdd words them, cut at line width.
const _oneOwnerPoints = [
  'A rule has one owner doc.',
  'Every other doc cites it by a link to the item that holds it,',
  '`[<ID>](<path>#<section heading anchor>)`, or by a section or doc link when',
  'no item holds it, and states nothing of the rule.',
  '`specstone check` reports an old cite form as `cite_unlinked` and a link to',
  'an item its section lacks as `link_item_missing`.',
];

/// The cite rule's traced-link points, which `references/confirm-links.md` holds
/// beside the traced links, as it words them, cut at line width.
const _citedLinkPoints = [
  '`specstone refs <owner>` lists each doc that cites it by a link, and',
  '`specstone context` follows the link,',
  'but a citation pins no hash: it never turns `suspect` when the owner',
  'changes, and takes no `confirmed` entry.',
];

/// The one home of expert-sdd's steps for confirming a traced link.
const _confirmLinks = 'specstone-expert-sdd/references/confirm-links.md';

/// What [_confirmLinks] says about the entry an `Overrides:` line takes.
const _overrideEntryPoints = <String>[
  '`overrides` entry',
  '`<doc type>:<name>#<ID> <fingerprint>`',
  '`specstone set <target> --field overrides --base <hash>`',
  '`bases.fields.overrides`',
  _overrideDraftSentence,
];

const String _overrideDraftSentence =
    'Until the entry matches, `check` reports the line `unconfirmed`; in a '
    'draft the line stays `unconfirmed` even when the entry matches, and '
    "waits for the Owner's approval.";

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
  ('specstone-expert-sdd/SKILL.md', 'Rules'),
  ('specstone-brainstorming-sdd/references/author.md', '4. Check'),
  ('specstone-brainstorming-sdd/references/audit.md', '1. Read'),
  ('specstone-brainstorming-sdd/references/audit.md', '3. Report'),
  (
    'specstone-bootstrap-prd/references/procedure.md',
    '2. One finding at a time',
  ),
  (
    'specstone-bootstrap-spec/references/procedure.md',
    '2. One finding at a time',
  ),
  ('specstone-bootstrap-prd/SKILL.md', '3. After the reports'),
  ('specstone-bootstrap-spec/SKILL.md', '3. After the reports'),
  ('specstone-sdd-engineer.md', 'Workflow'),
  ('specstone-sdd-engineer.md', 'Output Format'),
];

/// Each plugin file and `## ` section that says where a writing mode's drafts
/// list and counts come from
/// (`agent_plugin/write_prd_and_spec/write_drafts_with_coverage` E10).
const _draftCountReaders = [
  ('specstone-sdd-engineer.md', 'Output Format'),
  ('specstone-brainstorming-sdd/references/author.md', '5. Report'),
  ('specstone-sync-sdd/references/procedure.md', 'Report to the Owner'),
  (
    'specstone-bootstrap-prd/references/procedure.md',
    '6. Fill the skeletons, then ask for approval',
  ),
  (
    'specstone-bootstrap-spec/references/procedure.md',
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

/// The unknown-mode bullet of the engineer's Input Contract with its
/// continuation lines.
String _designStopBullet() {
  final contract = _sectionOf(
    _pluginText('specstone-sdd-engineer.md'),
    'Input Contract',
  );
  return RegExp(r'- \*\*Any other `mode`\*\*(?:.|\n(?!- |\n))*')
      .firstMatch(contract)!
      .group(0)!;
}

String _designStop() => _oneLine(_designStopBullet());

/// The `- **`mode`**` bullet with its indented continuation lines, its label
/// left out.
final _modeBullet = RegExp(
  r'^- \*\*`mode`\*\*(.*(?:\n {2}.*)*)',
  multiLine: true,
);

final _codeSpan = RegExp(r'`([^`\n]+)`');

final _fencedBlock = RegExp(r'^ *```[^\n]*\n([\s\S]*?)^ *```', multiLine: true);

final _contextCall = RegExp(r'specstone context\b(.*?)(?=specstone |$)');

/// Each `.md` file of the skill and agent sources, relative to the assets
/// folder with `/` separators, sorted.
List<String> _skillAndAgentFiles() => [
  for (final file in agentSourceFiles(agentAssetsRoot()))
    if (file.path.endsWith('.md')) shippedPathOf(file),
];

/// The skill and agent files that ground through their own `context` call.
const _groundingFiles = [
  'specstone-read-sdd/SKILL.md',
  'specstone-sdd-reader.md',
  'specstone-brainstorming-sdd/SKILL.md',
  'specstone-brainstorming-sdd/references/audit.md',
  'specstone-brainstorming-sdd/references/source.md',
  'specstone-plan-sdd/SKILL.md',
  'specstone-plan-engineer.md',
  'specstone-sync-sdd/references/procedure.md',
];

/// The words after `specstone context` of each call with arguments in
/// [markdown]'s fenced code lines and inline code spans, a span wrapped over
/// lines read whole.
List<List<String>> _contextCalls(String markdown) {
  final text = markdown.replaceAll('\r\n', '\n');
  final codes = [
    for (final block in _fencedBlock.allMatches(text))
      ...block.group(1)!.split('\n'),
    for (final span in _codeSpan.allMatches(
      _oneLine(text.replaceAll(_fencedBlock, '')),
    ))
      span.group(1)!,
  ];
  return [
    for (final code in codes)
      for (final call in _contextCall.allMatches(code))
        if (call.group(1)!.trim().isNotEmpty)
          call.group(1)!.trim().split(RegExp(r'\s+')),
  ];
}

void _agentTests() {
  test(
    'E04, '
    'sd-r9: the sdd-engineer Input Contract names exactly its four modes',
    () {
      final contract = _sectionOf(
        _pluginText('specstone-sdd-engineer.md'),
        'Input Contract',
      );
      final bullet = _modeBullet.firstMatch(contract)?.group(1) ?? '';
      expect([
        for (final span in _codeSpan.allMatches(bullet)) span.group(1),
      ], unorderedEquals(['author', 'sync', 'bootstrap', 'audit']));
    },
  );

  test('sd-r1: both agent descriptions ask to be used proactively', () {
    final proactive = RegExp(
      '^description:.*[Uu]se proactively',
      multiLine: true,
    );
    for (final agent in ['sdd-engineer', 'sdd-reader']) {
      expect(
        _pluginText('specstone-$agent.md'),
        matches(proactive),
        reason: agent,
      );
    }
  });

  test('E04: the '
      'sdd-engineer description sends sync and bootstrap through their skills '
      'and names the two modes a caller may dispatch directly, plan none', () {
    final description = RegExp(
      r'^description:(.*)$',
      multiLine: true,
    ).firstMatch(_pluginText('specstone-sdd-engineer.md'))?.group(1);
    expect(description, contains('`specstone-sync-sdd`'));
    expect(description, contains('`specstone-bootstrap-prd`'));
    for (final mode in ['author', 'audit']) {
      expect(description, contains('`$mode`'), reason: mode);
    }
    expect(description, isNot(contains('`plan`')));
  });

  test('domain:agent_plugin INV-10, '
      'statement: sdd-engineer holds Write and Edit for its report and batch '
      'files, audit mode writes no other file but the report file, and no '
      'file names docs/superpowers/', () {
    final agent = _pluginText('specstone-sdd-engineer.md');
    final tools = RegExp(
      r'^tools:(.*)$',
      multiLine: true,
    ).firstMatch(agent)?.group(1)?.split(',').map((tool) => tool.trim());
    expect(tools, containsAll(['Write', 'Edit']));
    expect(
      _pluginText('specstone-brainstorming-sdd/references/audit.md'),
      contains("Write nothing but the agent's `report:`"),
    );
    final design = _pluginText(
      'specstone-brainstorming-sdd/references/design.md',
    );
    expect(design, contains('Write no other file, and no PRD or spec doc.'));
    expect(design, contains('write nothing; the path is an open question'));
    final skill = _pluginText('specstone-brainstorming-sdd/SKILL.md');
    for (final (file, text) in [
      (
        'specstone-sdd-engineer.md Scope Boundaries',
        _sectionOf(agent, 'Scope Boundaries'),
      ),
      ('references/design.md', design),
      ('brainstorming-sdd/SKILL.md', skill),
    ]) {
      expect(text, isNot(contains('docs/superpowers/')), reason: file);
    }
    for (final (file, text) in [
      ('references/design.md', design),
      ('brainstorming-sdd/SKILL.md', skill),
    ]) {
      expect(text, contains(_designPath), reason: file);
    }
    expect(_sectionOf(agent, 'Scope Boundaries'), isNot(contains(_designPath)));
  });

  test('statement, '
      'E03, E14, E15: brainstorming-sdd hands the approved drafts to '
      'specstone-plan-sdd by following it and runs no plan mode', () {
    final skill = _oneLine(_pluginText('specstone-brainstorming-sdd/SKILL.md'));
    expect(skill, contains('follow the `specstone-plan-sdd` skill'));
    expect(skill, isNot(contains('mode: plan')));
    expect(skill, isNot(contains('references/plan.md')));
    expect(
      _pluginText('specstone-sdd-engineer.md'),
      isNot(contains('references/plan.md')),
    );
    expect(
      _pluginText('specstone-brainstorming-sdd/references/author.md'),
      isNot(contains('plan mode')),
    );
  });

  test('E04: the '
      'plan procedure file is gone, as plan-engineer holds the steps', () {
    final plan = File.fromUri(
      agentAssetsRoot().uri.resolve(
        'specstone-brainstorming-sdd/references/plan.md',
      ),
    );
    expect(plan.existsSync(), isFalse);
  });

  test('E06: read-sdd names '
      'the context call it runs per cited story, NFR, and spec doc', () {
    final skill = _oneLine(_pluginText('specstone-read-sdd/SKILL.md'));
    expect(skill, contains('specstone context <story> --for implement --out'));
    expect(skill, contains('specstone context <target> --for implement --out'));
  });

  test('no skill or agent context call '
      'passes --budget, and each ends with a bare --out', () {
    final problems = <String>[];
    for (final file in _skillAndAgentFiles()) {
      for (final call in _contextCalls(_pluginText(file))) {
        final shown = 'specstone context ${call.join(' ')}';
        if (call.any((token) => token.startsWith('--budget')) ||
            call.last != '--out') {
          problems.add('$file: $shown');
        }
      }
    }
    expect(problems, isEmpty);
    for (final file in _groundingFiles) {
      expect(_contextCalls(_pluginText(file)), isNotEmpty, reason: file);
    }
  });

  test('each file that '
      'grounds through a saved bundle names read-sdd for its read, and each '
      'agent that reads one holds Grep for the search', () {
    for (final file in _groundingFiles) {
      if (!isSkillSourcePath(file) || file == 'specstone-read-sdd/SKILL.md') {
        continue;
      }
      expect(_pluginText(file), contains('`specstone-read-sdd`'), reason: file);
    }
    final engineer = _pluginText('specstone-sdd-engineer.md');
    expect(_toolsOf(engineer, 'tools'), contains('Grep'));
    expect(
      _oneLine(_sectionOf(engineer, 'Scope Boundaries')),
      contains(
        'Read the files each `context --out` call saves per the '
        '`specstone-read-sdd` skill.',
      ),
    );
    expect(
      _oneLine(_sectionOf(_pluginText(_planAgent), 'Workflow')),
      contains(
        'the saved files are the docs, as they stand: read them per the '
        '`specstone-read-sdd` skill, the read-first file whole and the refs '
        'file by line range, searching them with `Grep` before any `get`.',
      ),
    );
  });

  test('plan-engineer may run each command its read path '
      'names, get after the Grep search, and no write command', () {
    final agent = _pluginText(_planAgent);
    expect(
      _toolsOf(agent, 'disallowedTools'),
      isNot(anyOf(contains('Grep'), contains('Bash'), contains('Read'))),
    );
    final scope = _oneLine(_sectionOf(agent, 'Scope Boundaries'));
    expect(
      scope,
      contains(
        '- Run `specstone context` for the Ground, `specstone get` only after '
        'searching its saved files with `Grep`, and one `specstone check`,',
      ),
    );
    expect(
      scope,
      contains(
        '- Run `specstone new`, `specstone set`, or `specstone approve`',
      ),
    );
  });

  test("plan-engineer writes each task's read "
      'line with a bare --out last, its --target before it', () {
    expect(
      _oneLine(_sectionOf(_pluginText(_planAgent), 'Workflow')),
      contains(
        '`specstone context <target> --for implement --out`, with `--target '
        "<code target>` before `--out` when one is given, the FR's story as "
        '`<target>` for an FR',
      ),
    );
  });

  test('read-sdd names no mktemp, no budget figure, and no '
      'hand-off by bundle size', () {
    final skill = _oneLine(_pluginText('specstone-read-sdd/SKILL.md'));
    expect(skill, isNot(contains('mktemp')));
    expect(skill, isNot(contains('20000')));
    expect(skill, isNot(contains('over the budget')));
    expect(skill, contains('No bundle size calls for it.'));
  });

  test('read-sdd searches the saved '
      'file before any get and finds a section by its header', () {
    final skill = _oneLine(_pluginText('specstone-read-sdd/SKILL.md'));
    expect(
      skill,
      contains(
        "search the saved files with the host's text search before any "
        '`specstone get`. Never `get` a doc the files hold',
      ),
    );
    expect(
      skill,
      contains('find a section by searching the files for its `## ` header'),
    );
  });

  test('sdd-reader reads the saved file its '
      'hand-off names and runs no context of its own', () {
    final reader = _oneLine(_pluginText('specstone-sdd-reader.md'));
    expect(
      reader,
      contains(
        "the paths of the bundle files the main session's `context --out` "
        'call saved, the read-first file and, in `implement` or `design`, the '
        'refs file, each exactly as its header printed it',
      ),
    );
    expect(
      reader,
      contains(
        "read them with the host's file read, the read-first file whole and "
        "the refs file by line range, found with `Grep` by its parts' headers, "
        'and run no `context`',
      ),
    );
    expect(
      _sectionOf(_pluginText('specstone-sdd-reader.md'), 'Scope Boundaries'),
      contains('- Run `context` when the hand-off names a saved file.\n'),
    );
  });

  test('sdd-reader holds the search '
      'tool its read path names, and stays read-only', () {
    final reader = _pluginText('specstone-sdd-reader.md');
    final tools = _toolsOf(reader, 'tools');
    expect(tools, containsAll(['Read', 'Grep']));
    expect(tools, isNot(anyOf(contains('Write'), contains('Edit'))));
    expect(_oneLine(reader), contains('searching the files with `Grep`'));
    expect(
      _oneLine(_sectionOf(reader, 'Scope Boundaries')),
      contains('search them with `Grep`'),
    );
  });

  test('an indented fence is a code block, so its call is read and the span '
      'after it keeps its backtick pairs', () {
    expect(
      _contextCalls(
        '1. Pull:\n\n'
        '   ```\n'
        '   specstone context a --for query --out\n'
        '   ```\n\n'
        '   Add `--summary` only, then '
        '`specstone context b --for query --out`.\n',
      ),
      [
        ['a', '--for', 'query', '--out'],
        ['b', '--for', 'query', '--out'],
      ],
    );
  });

  test('E14: read-sdd runs a '
      "plan task's read line with its --target as written", () {
    final skill = _oneLine(_pluginText('specstone-read-sdd/SKILL.md'));
    expect(
      skill,
      contains('specstone context <story> --for implement --target <name>'),
    );
    expect(skill, contains("a plan task's read line's, as written"));
  });

  test('E15: read-sdd gives '
      'a task no plan wrote no --target in query or design mode', () {
    expect(
      _oneLine(_pluginText('specstone-read-sdd/SKILL.md')),
      contains('none in `query` or `design`'),
    );
  });

  test('E16: read-sdd has a '
      'main session ask the Owner after argument_missing and rerun with '
      '--target', () {
    final skill = _oneLine(_pluginText('specstone-read-sdd/SKILL.md'));
    expect(
      skill,
      contains(
        'In `implement` with no plan target and no `--code` path, an '
        '`argument_missing` refusal names the targets: a main session asks '
        'the Owner and reruns with `--target <name>`',
      ),
    );
  });

  test('E17: read-sdd has a '
      'Subagent stop and report the missing target to its dispatcher', () {
    expect(
      _oneLine(_pluginText('specstone-read-sdd/SKILL.md')),
      contains(
        'a Subagent runs no further call and reports the missing target, '
        'naming them, to its dispatcher',
      ),
    );
  });

  test('E18: read-sdd '
      "hands sdd-reader the saved file's path as the header printed it", () {
    expect(
      _oneLine(_pluginText('specstone-read-sdd/SKILL.md')),
      contains(
        "Hand it each saved file's path exactly as its header printed it, the "
        'mode, and the task: no doc text, no index lines, and no path you '
        'join yourself.',
      ),
    );
  });

  test('read-sdd takes the read-first file in full and the refs file in '
      'ranges, and grounds a doc design work lacks with its own context', () {
    final skill = _oneLine(_pluginText('specstone-read-sdd/SKILL.md'));
    expect(
      skill,
      contains('the read-first file whole and the refs file by line range'),
    );
    expect(
      skill,
      contains(
        'in design work, ground a doc they lack with its own `specstone '
        'context <doc> --for design --out`, never `get`',
      ),
    );
  });

  test('read-sdd finds the refs parts of an implement bundle by the refs '
      "file's head and those of a design bundle by the stdout index", () {
    final step = _oneLine(
      _sectionOf(
        _pluginText('specstone-read-sdd/SKILL.md'),
        'Ground in one call',
      ),
    );
    expect(
      step,
      contains(
        "found in `implement` by the refs file's head, one index line per "
        'doc and part, and in `design` by the stdout index',
      ),
    );
    expect(
      step,
      contains('in `implement` the refs file prints its header alone'),
    );
    expect(step, contains('an `implement` refs head keeps its sections'));
  });

  test('the reader takes both saved paths', () {
    final reader = _oneLine(_pluginText('specstone-sdd-reader.md'));
    expect(
      reader,
      contains(
        'the read-first file and, in `implement` or `design`, the refs file',
      ),
    );
  });

  test('the plan engineer reads both files', () {
    expect(
      _oneLine(_sectionOf(_pluginText(_planAgent), 'Workflow')),
      contains('the read-first file whole and the refs file by line range'),
    );
  });

  test('the sync procedure names both files', () {
    expect(
      _oneLine(_pluginText('specstone-sync-sdd/references/procedure.md')),
      contains('parts of its read-first and refs files'),
    );
  });

  test('read-sdd '
      'bounds one target at three tool calls, a refusal and part reads '
      'included', () {
    expect(
      _oneLine(_pluginText('specstone-read-sdd/SKILL.md')),
      contains(
        "One target takes three tool calls at most up to the task's first "
        'other action',
      ),
    );
    expect(
      _oneLine(_pluginText('specstone-read-sdd/SKILL.md')),
      contains('an `argument_missing` refusal counts among them'),
    );
    expect(
      _oneLine(_pluginText('specstone-read-sdd/SKILL.md')),
      contains(
        'the `context` call and each search or part read before that '
        'action',
      ),
    );
  });

  test('E06: sdd-reader runs '
      "context with the hand-off's --target in implement mode", () {
    final reader = _oneLine(_pluginText('specstone-sdd-reader.md'));
    expect(
      reader,
      contains('specstone context <target> --for <mode> [--summary] '),
    );
    expect(
      reader,
      contains(
        "Add `--target <name>` in `implement` mode: the hand-off's "
        '`--target`, on each call',
      ),
    );
  });

  test('E07: sdd-reader '
      'passes no --target in query or design mode', () {
    expect(
      _oneLine(_pluginText('specstone-sdd-reader.md')),
      contains('none in `query` or `design` mode'),
    );
  });

  test('E17: the '
      'first design call keeps a bare --out last and passes no --budget on any '
      'host, and no --target', () {
    final skill = _oneLine(_pluginText('specstone-brainstorming-sdd/SKILL.md'));
    expect(
      skill,
      contains(
        'Keep `--out` bare and last, and pass no `--budget` on any host.',
      ),
    );
    expect(
      skill,
      contains('Pass no `--target`: a design read spans every code target.'),
    );
  });

  test('E13: '
      'author takes a per-target doc from the design row, or its DocPath, and '
      'keeps the drafts list free of --target', () {
    final author = _oneLine(
      _pluginText('specstone-brainstorming-sdd/references/author.md'),
    );
    expect(
      author,
      contains(
        '**Code target** (two or more `targets:`): pass `--target <name>`, '
        "the one its design document's row names, on each `new`, `get`, and "
        '`set` of a per-target spec doc, or address an existing doc by its '
        'DocPath.',
      ),
    );
    expect(author, contains('names only, no `--target`'));
    expect(
      author,
      contains('hit in a doc the design changes, as step 2 writes.'),
    );
    expect(
      _oneLine(_pluginText('specstone-sdd-engineer.md')),
      contains('each write leaves a draft; never clear its flag'),
    );
    expect(
      _oneLine(_pluginText('specstone-sdd-engineer.md')),
      contains(
        '**Code target** (two or more `targets:`): author passes '
        '`--target <name>`, the code target its '
        "design document's row names, or the doc's DocPath, on each "
        'per-target `new`, `get`, and `set`;',
      ),
    );
  });

  test('E07: '
      'update-sdd asks which code target for a name in two or more, then '
      "reads and writes on the doc's DocPath", () {
    final skill = _oneLine(_pluginText('specstone-update-sdd/SKILL.md'));
    expect(
      skill,
      contains(
        'A name that matches docs in two or more code targets: ask the Owner '
        'which one, as `specstone-plan-sdd` does, then run `get` and `set` '
        "on that doc's DocPath, the one `get`'s doc header prints, such as "
        '`specs/jaspr/f02_feedback/f03_toast/ARCHITECTURE.md`'
        '. A name that matches one doc asks '
        'nothing.',
      ),
    );
  });

  test('E02, E06, E09: '
      'expert-sdd gives set (a confirmed write included), structure, and refs '
      'the target of its loader, with no Owner question, and approve and '
      'delete none', () {
    final skill = _oneLine(_pluginText('specstone-expert-sdd/SKILL.md'));
    expect(
      skill,
      contains(
        '**Code target.** With two or more code targets, `new`, `get`, `set` '
        '(a `confirmed` write included), `structure <doc>`, and '
        '`refs <owner>` take the `--target` of the surface that loads this '
        'skill, never an Owner question; `approve` and `delete` take none.',
      ),
    );
  });

  test('the design reference finds dependents in the saved files and through '
      'check --repeats, and runs no refs or search', () {
    final design = _pluginText(
      'specstone-brainstorming-sdd/references/design.md',
    );
    expect(cliCommands(design), isNot(contains('refs')));
    expect(cliCommands(design), isNot(contains('search')));
    expect(cliCommands(design), contains('check'));
    expect(
      _oneLine(design),
      contains('Run no `get`, no `search`, and no `refs` for a doc'),
    );
    expect(_oneLine(design), contains('`specstone check <feature> --repeats`'));
  });

  test('design mode links every design a doc still states: the design '
      "references line names no link count and takes the guide's section", () {
    final design = _oneLine(
      _pluginText('specstone-brainstorming-sdd/references/design.md'),
    );
    expect(
      design,
      isNot(matches(RegExp(r'\b(?:one|two|three|four|five|\d+) links\b'))),
      reason: 'a link count evicts a design a doc still states',
    );
    expect(design, isNot(contains('this replaces')));
    expect(
      design,
      contains(
        'a link to this document, kept or dropped as the `Design references` '
        'section of `specstone guide architecture` says.',
      ),
    );
  });

  test('E20: design '
      'mode names a code target on each per-target row', () {
    final design = _oneLine(
      _pluginText('specstone-brainstorming-sdd/references/design.md'),
    );
    expect(
      design,
      contains(
        "With two or more `targets:`, a per-target spec doc's row also names "
        'its code target, a row with none an open question.',
      ),
    );
  });

  test('E16: audit '
      'mode passes no --target on its design bundles or its drafts get', () {
    final audit = _oneLine(
      _pluginText('specstone-brainstorming-sdd/references/audit.md'),
    );
    expect(
      audit,
      contains(
        "Pass no `--target`: the bundle takes every code target's spec docs.",
      ),
    );
    expect(audit, contains("The drafts list's names need no `--target`."));
    expect(
      _oneLine(_pluginText('specstone-sdd-engineer.md')),
      contains('audit passes no `--target` on `context --for design`.'),
    );
  });

  test('E13: the '
      're-audit get of the drafts list needs no --target', () {
    expect(
      _oneLine(_pluginText('specstone-brainstorming-sdd/references/rounds.md')),
      contains("The drafts list's names need no `--target`."),
    );
  });

  group('Agent brings the docs in line with changed code', () {
    const targetLine =
        "**Code target** (two or more `targets:`): a changed path's target "
        'is the `code target:` line, or the '
        '`codeTarget` key under `--json`, of its `context --code --out` call, '
        "covered or not, and a deleted path's is the finding DocPath's; each "
        '`get`, `set`, and `new` of a per-target '
        'doc carries `--target <name>`, or addresses the doc by its DocPath.';
    const recordWrite =
        '`specstone set implementation:<feature> --field implements '
        '--target <name> --base <hash>`';

    String procedure() =>
        _oneLine(_pluginText('specstone-sync-sdd/references/procedure.md'));

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

    test("the sync procedure takes the path's "
        'target by the longest code root and asks the Owner nothing', () {
      expect(procedure(), contains(targetLine));
      expect(
        procedure(),
        contains("which takes its path's target and no `--target`"),
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
          "Write by outcome through step 4.3's `set --field`, which leaves "
          'the draft flag as it was.',
        ),
      );
    });

    test('update_covering_docs E05: a path in one target compares and fixes '
        "that target's record and covers entries alone", () {
      expect(
        procedure(),
        contains(
          "Compare and fix only that target's record and `covers:` entries.",
        ),
      );
    });

    test("update_covering_docs pointers row: the skill's waiting pointer "
        'goes to the target record, each form with its base and --target', () {
      final skill = _oneLine(_pluginText('specstone-sync-sdd/SKILL.md'));
      expect(
        skill,
        contains(
          'pipe the corrected list to `specstone set implementation:<feature> '
          '--field implements --base <hash>` (or `specstone set <type>:<name> '
          '--field covers --base <hash>`), each with `--target <name>`, the '
          'target the report gives for that pointer, when the project has '
          'two or more, the hash from '
          '`bases.fields.implements` (or `bases.fields.covers`) of '
          '`specstone get <doc> --json` for the same doc, with the same '
          '`--target`.',
        ),
      );
    });

    test('the report lists each waiting pointer with its code target and its '
        'doc and code path', () {
      expect(
        procedure(),
        contains(
          'and each waiting pointer: its code target, and its doc and code '
          'path, or its tasks.',
        ),
      );
    });

    test('draft_spec_for_uncovered_code E03: a new or set draft carries the '
        "--code path's target, one target none", () {
      expect(
        procedure(),
        contains(
          "`specstone new <type>` (`--target <name>`, the path's code target, "
          'as the type takes it)',
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
          'until it is approved. Then add it at once by step '
          "4.3, on the path's target's record.",
        ),
      );
    });

    test('sdd-engineer names the sync target source and the record entry '
        'write on its Code target line', () {
      expect(
        _oneLine(_pluginText('specstone-sdd-engineer.md')),
        contains(
          "sync takes the `--code` path's code target, or the finding "
          "DocPath's, on each per-target `get`, `set`, and `new`, and writes "
          "code paths to that target's record entry, never to an FR;",
        ),
      );
    });

    String skill() => _oneLine(_pluginText('specstone-sync-sdd/SKILL.md'));

    test('the sync skill runs the check as its gate and takes its work list '
        "from the check's code findings or from a named feature", () {
      expect(
        skill(),
        contains(
          "The work list is the gate's `code_suspect`, `code_unconfirmed`, "
          '`implements_path_unresolved`, `implements_symbol_unresolved`, '
          '`covers_path_missing`, `code_uncovered`, and `tests_unresolved` '
          'findings, never a `tests_missing` one.',
        ),
      );
      expect(
        skill(),
        contains(
          'When the Owner names a feature, it is every code link of that '
          'feature that takes a state, findings or not.',
        ),
      );
    });

    test('the sync skill stops with no dispatch on an empty work list and '
        'hands the engineer no list of paths', () {
      expect(
        skill(),
        contains(
          'With an empty list, tell the Owner no code changed since its docs '
          'were compared, and stop with no dispatch and no further call.',
        ),
      );
      expect(
        skill(),
        contains(
          'dispatch `specstone-sdd-engineer` for each group in turn, one at a '
          'time, as `../specstone-expert-sdd/references/dispatch.md` gives, '
          'with `mode: sync`, `report:` '
          "`<folder>/reports/sdd-engineer.sync.<XXXXXX>.md`, and the group's "
          'input',
        ),
      );
      expect(skill(), contains('Send no list of paths or doc text'));
    });

    test('the sync skill sorts the work list into groups by scope', () {
      final text = skill();
      expect(text, contains('With a feature named, it is one group.'));
      expect(
        text,
        contains(
          'goes to the group of the top-level feature whose doc holds its '
          "code link, a sub-feature's finding to its top-level feature",
        ),
      );
      expect(
        text,
        contains(
          'a finding on a doc under no feature, such as a topic, goes to '
          "that doc's own group",
        ),
      );
      expect(
        text,
        contains('a `code_uncovered` finding goes to one `uncovered` group'),
      );
      expect(
        text,
        contains(
          'A finding with no code link, such as a `tests_unresolved` line, '
          'goes by the doc that holds the finding',
        ),
      );
    });

    test('the sync skill dispatches one engineer per group in turn, with '
        'scope: and never feature:', () {
      final text = skill();
      expect(
        text,
        contains(
          '`scope: feature:<name>`, `scope: <type>:<name>`, or '
          '`scope: uncovered`',
        ),
      );
      expect(
        text,
        contains(
          'pass `feature: <name>` only for a feature the Owner named, as its '
          'one group, with no `scope:`',
        ),
      );
      expect(
        text,
        contains(
          "Show each report's `Report:` line and relay block before the next "
          'dispatch.',
        ),
      );
    });

    test("the sync skill splits the runner's own procedure run by case", () {
      final text = skill();
      expect(
        text,
        contains(
          'With no subagent on the host, follow the procedure yourself once '
          "per group, in the same order, taking only that group's findings.",
        ),
      );
      expect(
        text,
        contains(
          'After a dispatch that fails, follow it for that group alone, then '
          'dispatch the next group again.',
        ),
      );
    });

    test('the sync procedure finds the covering docs of each listed code path '
        "but a tests_unresolved line's, and compares a changed folder on the "
        'files changed since its stamp', () {
      expect(
        procedure(),
        contains(
          "For each listed code path but a `tests_unresolved` line's (step "
          '4.4), run `specstone context --code <code root>/<path> --for '
          "implement --out`, which takes its path's target and no "
          '`--target`; read parts of its read-first and refs files per '
          '`specstone-read-sdd`.',
        ),
      );
      expect(
        procedure(),
        contains(
          "A `code_suspect` folder's code is the files changed under it since "
          'its stamp: '
          "`git log -1 --format=%H -S '<recorded>' -- docs/<DocPath>` gives "
          '`<base>`, then `git diff --name-only <base> -- <prefix>` and '
          '`git ls-files --others --exclude-standard -- <prefix>`; with no '
          'such commit, or on a `code_unconfirmed` folder, every file under '
          'the prefix',
        ),
      );
    });

    test('the sync procedure joins the code root to a finding path for --code '
        'and every git pathspec, and stops on any other exit', () {
      final text = procedure();
      expect(
        text,
        contains(
          "A finding's `path` is relative to its target's code root "
          '(`code_root:` per `targets:` entry in `.specstone/config.yaml`; '
          'default `.`). From the project root, `--code` and each '
          'git pathspec take `<code root>/<path>`.',
        ),
      );
      final step = _oneLine(
        _sectionOf(
          _pluginText('specstone-sync-sdd/references/procedure.md'),
          '3. Find the covering docs',
        ),
      );
      expect(
        step,
        contains("**Any other exit:** report the CLI's error and stop."),
      );
    });

    test('the sync procedure names the base hash source of a field write, a '
        'tests repoint included, and of a section draft', () {
      final text = procedure();
      expect(text, contains('(hash: `bases.fields.<field>` of `get --json`;'));
      expect(
        text,
        contains(
          '`specstone set <doc>#<section key> --base <hash>` (hash: the '
          '`base` of `specstone get <doc>#<key>`)',
        ),
      );
    });

    test('the sync procedure takes its work list from the gate check and '
        'neither sync file takes a list of changed paths or a base commit', () {
      expect(
        procedure(),
        contains(
          'Your gate `check` gives it: each '
          '`code_suspect`, `code_unconfirmed`, `implements_path_unresolved`, '
          '`implements_symbol_unresolved`, `covers_path_missing`, '
          '`code_uncovered`, and `tests_unresolved` finding, never a '
          '`tests_missing` one.',
        ),
      );
      for (final text in [skill(), procedure()]) {
        for (final input in [
          'changed paths',
          'base commit',
          'base branch',
          'merge-base',
          'task lists',
          'start commit',
        ]) {
          expect(text, isNot(contains(input)), reason: input);
        }
      }
    });

    test(
      'the sync procedure compares each link with the approved text of '
      'every covering doc and takes a doc printing draft: true as pending',
      () {
        expect(
          procedure(),
          contains(
            "Compare the approved text of every covering doc with each link's "
            'code, its file; a doc printing `draft: true` is a pending draft.',
          ),
        );
      },
    );

    test('the sync procedure writes on a match the finding fingerprint, any '
        "pointer fix, and a planned entry's implemented status, never "
        'skipped or deprecated, and none for a clean link', () {
      final text = procedure();
      expect(
        text,
        contains(
          "a named feature's `clean` link takes no fingerprint, only a "
          "`planned` entry's `implemented`:",
        ),
      );
      expect(
        text,
        contains(
          "**Match:** the finding's `fingerprint` ending the link's entry, "
          'any pointer fix, and for a `planned` entry `implemented` in its '
          '`statuses`; never `skipped` or `deprecated`.',
        ),
      );
    });

    test('the sync procedure writes nothing for a link while a covering doc '
        'is a pending draft and lists a match as a waiting pointer', () {
      final text = procedure();
      expect(
        text,
        contains(
          'A pending draft among the covering docs holds every write of a '
          "match and of a `planned` entry's fingerprint: list a match as a "
          'waiting pointer, written whole once it is approved '
          '(fingerprint, and on a `planned` entry `implemented`).',
        ),
      );
      expect(
        text.indexOf('A pending draft among the covering docs holds'),
        lessThan(text.indexOf('**Match:**')),
        reason: 'the wait applies before the outcome bullets',
      );
    });

    test('the sync skill writes a waiting match whole once its draft is '
        "approved, a planned entry's implemented status included", () {
      expect(
        skill(),
        contains(
          'A waiting match is written whole: the fingerprint ends the entry, '
          "and a `planned` entry's `implemented` goes to `statuses` through "
          '`--field statuses` with `bases.fields.statuses`.',
        ),
      );
    });

    test('the sync procedure sends the new side of a rename pair to the '
        'pointer fix before it reports a warning path as uncovered', () {
      expect(
        procedure(),
        contains(
          'The new side of a rename pair goes to step 4.3. Else read the file '
          'and write nothing for it;',
        ),
      );
    });

    test('the sync procedure keeps each command code span on one line and '
        'loops the check only until no pointer finding of those docs is '
        'left', () {
      for (final line in _pluginText(
        'specstone-sync-sdd/references/procedure.md',
      ).split('\n')) {
        expect('`'.allMatches(line).length.isEven, isTrue, reason: line);
      }
      expect(
        procedure(),
        contains('until no such finding of those docs is left:'),
      );
    });

    test('the sync procedure writes the fingerprint alone for a planned entry '
        'whose code lacks its planned behavior and asks nothing', () {
      expect(
        procedure(),
        contains(
          "**A `planned` entry's code lacking its planned behavior yet** is "
          'no mismatch, no question: the fingerprint alone; the entry stays '
          '`planned`.',
        ),
      );
    });

    test('the sync procedure writes nothing on a mismatch, reports each '
        'point under Mismatches:, and drafts a spec only on the fix-the-spec '
        'pick, a story or FR going to the brainstorm', () {
      final text = procedure();
      expect(
        text,
        contains(
          '**Mismatch**, code behavior the approved text contradicts: '
          'nothing for the link; report each point under `Mismatches:`: doc '
          'and section, what the spec states, what the code does. A '
          'fix-the-spec pick sent to you: write each stale section as a spec '
          'draft (step 5); the fingerprint waits for its approval.',
        ),
      );
      expect(
        text,
        contains(
          "On the Owner's write-a-spec or fix-the-spec pick sent to you, a "
          'story or FR it needs goes to `specstone-brainstorming-sdd`.',
        ),
      );
    });

    test('the sync procedure repoints a moved file found by git rename '
        'detection with no fingerprint, and a tests_unresolved line with no '
        'new tests line', () {
      final text = procedure();
      expect(
        text,
        contains(
          'find the pair with `git log -1 -M --diff-filter=R --name-status '
          '--format= -- <old path>`, or `git diff -M --name-status HEAD` '
          'while the move is uncommitted; write no fingerprint;',
        ),
      );
      expect(
        text,
        contains(
          'A `tests_unresolved` line: repoint it with `specstone set '
          'implementation:<feature> --field tests --target <name> --base '
          "<hash>` to the moved file of step 4.3 or the test's current name "
          'in it; one you cannot place stays as written, among the waiting '
          'pointers. Write no `tests` line for a test a change adds or '
          'moves.',
        ),
      );
    });

    test('the sync procedure reports each draft by name with one sentence on '
        'why it changed, never its text', () {
      expect(
        _oneLine(
          _sectionOf(
            _pluginText('specstone-sync-sdd/references/procedure.md'),
            'Report to the Owner',
          ),
        ),
        contains(
          "each one's dropped and new sentence counts, and one sentence on "
          'why it changed, never its text;',
        ),
      );
    });

    test("the sync skill gathers every group's picks and asks them after the "
        'last report', () {
      final after = _oneLine(
        _sectionOf(
          _pluginText('specstone-sync-sdd/SKILL.md'),
          '3. After the report',
        ),
      );
      expect(
        after,
        contains(
          'Run item 1 for each group as its report comes in, and items 2 and '
          "3 once, after the last group's report, over the picks of every "
          'group.',
        ),
      );
      expect(
        after,
        contains(
          'A group you followed yourself stands in for item 1 by its own '
          'changes.',
        ),
      );
    });

    test("the sync skill asks the Owner's pick on each mismatch and routes a "
        'fix that lands in a spec doc to an agent, one that lands in a PRD '
        'doc to the brainstorm', () {
      expect(
        skill(),
        contains(
          'Ask the Owner, per point under `Mismatches:`, fix the code or fix '
          'the spec. Fix the code writes nothing: the next `check` lists the '
          'link again.',
        ),
      );
      expect(
        skill(),
        contains(
          'When a fix lands in a spec doc, send the picks to a new '
          '`specstone-sdd-engineer` per group that holds picks, one at a '
          "time, each with `mode: sync`, `picks`, and that group's `scope:` "
          '(`scope: uncovered` for an `Uncovered:` file), never `feature:` '
          'unless the Owner named the feature.',
        ),
      );
      expect(skill(), isNot(contains('the same agent while it is live')));
      expect(
        skill(),
        contains(
          'Follow the `specstone-brainstorming-sdd` skill for each behavior '
          'the report hands over and each pick that lands in a story or FR, '
          'since the sync writes no PRD doc.',
        ),
      );
    });

    test('the sync procedure reads each uncovered file, writes nothing for it, '
        'and reports it under Uncovered: with what it does that no spec '
        'states and whether that needs a new story or FR', () {
      final text = procedure();
      expect(
        text,
        contains(
          'Else read the file and write nothing for it; report it under '
          '`Uncovered:`: its path, what it does that no spec states, and '
          'whether that needs a new story or FR.',
        ),
      );
      expect(
        _oneLine(
          _sectionOf(
            _pluginText('specstone-sync-sdd/references/procedure.md'),
            'Report to the Owner',
          ),
        ),
        contains('each `Mismatches:` point, each `Uncovered:` file,'),
      );
    });

    test('the sync procedure writes a spec draft only on the write-a-spec '
        'pick, in the path code target, and writes no pointer to the code '
        'before the draft is approved', () {
      final text = procedure();
      expect(
        text,
        contains(
          "On the Owner's write-a-spec or fix-the-spec pick sent to you,",
        ),
      );
      expect(
        text,
        contains(
          'it waits for approval. Write no record code path or `covers:` '
          'entry that names this code until it is approved.',
        ),
      );
    });

    test('the sync skill asks the Owner per uncovered file to write a spec or '
        'change or remove the code, and routes the spec pick as a '
        'fix-the-spec pick', () {
      expect(
        skill(),
        contains(
          'Ask the Owner, per file under `Uncovered:`, write a spec or change '
          'or remove the code; change or remove writes nothing, and a '
          'write-a-spec pick routes as a fix-the-spec pick does.',
        ),
      );
    });

    test('sdd-engineer takes a feature name and the Owner picks in sync mode '
        'and names no changed-path or base-commit input', () {
      final agent = _oneLine(_pluginText('specstone-sdd-engineer.md'));
      final input = _oneLine(
        _sectionOf(_pluginText('specstone-sdd-engineer.md'), 'Input Contract'),
      );
      expect(
        input,
        contains(
          '- **`feature`** (sync, optional): the feature name the Owner gave, '
          'never sent with `scope`; absent, your gate `check` gives the work '
          'list.',
        ),
      );
      expect(
        input,
        contains(
          '- **`picks`** (sync, bootstrap, optional): each Owner pick whose '
          'fix lands in a spec doc. Sync: a fix-the-spec pick per '
          '`Mismatches:` point or a write-a-spec pick per `Uncovered:` file. '
          'Bootstrap: a write-a-spec pick per `Uncovered:` file.',
        ),
      );
      for (final phrase in ['changed paths', 'base commit', 'given paths']) {
        expect(agent, isNot(contains(phrase)), reason: phrase);
      }
    });

    test('sdd-engineer takes a scope input in sync mode in each of its three '
        'forms, apart from feature', () {
      final input = _oneLine(
        _sectionOf(_pluginText('specstone-sdd-engineer.md'), 'Input Contract'),
      );
      expect(input, contains('- **`scope`** (sync, optional):'));
      for (final form in [
        '`feature:<name>`',
        '`<type>:<name>`',
        '`uncovered`',
      ]) {
        expect(input, contains(form), reason: form);
      }
    });

    test('sdd-engineer runs its gate check on its scope, bare for uncovered, '
        'and draws its work list from it', () {
      final workflow = _oneLine(
        _sectionOf(_pluginText('specstone-sdd-engineer.md'), 'Workflow'),
      );
      expect(workflow, contains('`specstone check <scope>`'));
      expect(
        workflow,
        contains(
          'bare `specstone check` for `scope: uncovered`, keeping its '
          '`code_uncovered` findings',
        ),
      );
      expect(
        workflow,
        contains("on your gate `check`'s work list, scoped by `scope`,"),
      );
    });

    test('sdd-engineer syncs on its gate check work list or a named feature '
        "and writes each pick by the procedure's step 5", () {
      expect(
        _oneLine(
          _sectionOf(_pluginText('specstone-sdd-engineer.md'), 'Workflow'),
        ),
        contains(
          '2. **Sync**: follow the On-Demand procedure from its step 2, on '
          "your gate `check`'s work list, scoped by `scope`, or on every code "
          'link of `feature`; write each of `picks` by its step 5. Then '
          'Workflow step 5.',
        ),
      );
    });

    test('sdd-engineer writes each pick in bootstrap mode by the procedure '
        'step that covers code, as it does in sync mode', () {
      expect(
        _oneLine(
          _sectionOf(_pluginText('specstone-sdd-engineer.md'), 'Workflow'),
        ),
        contains(
          '3. **Bootstrap**: follow the On-Demand procedure from its step 2 '
          'on `batch`, its step 6 only for docs `batch` names, each write '
          'through `--base`; write each of `picks` by its step 3; list other '
          'findings. Then Workflow step 5.',
        ),
      );
    });

    test('sdd-engineer reports each Mismatches: point, each Uncovered: file, '
        'and each waiting pointer in sync mode, and each Uncovered: file in '
        'bootstrap mode', () {
      final output = _oneLine(
        _sectionOf(_pluginText('specstone-sdd-engineer.md'), 'Output Format'),
      );
      expect(
        output,
        contains(
          'each pointer fixed; each task whose refs the sync removed; each '
          '`Mismatches:` point and each `Uncovered:` '
          'file; each behavior handed to `specstone-brainstorming-sdd`; each '
          'pointer that waits on an approval; open questions; then '
          '`Findings:`.',
        ),
      );
      expect(
        output,
        contains(
          'split proposals, or why none applies; open questions; each '
          '`Uncovered:` file; one `specstone delete …` line;',
        ),
      );
    });
  });

  group('Agent sets up a new project with no code', () {
    String init() => _oneLine(_pluginText('specstone-init/SKILL.md'));

    test('set_up_and_fill_drafts S1: init skill fills the six drafts, the '
        'glossary doc right after the goal doc', () {
      expect(
        init(),
        contains(
          'Take the drafts one at a time, in this order: the project, goal, '
          'glossary, features, gnfr, and tech stack docs.',
        ),
      );
      expect(
        init(),
        contains('The goal doc holds the goals the Owner names, or none.'),
      );
      expect(
        init(),
        contains(
          'The glossary doc, titled `# Domain glossary`, holds the terms the '
          'Owner names, or none.',
        ),
      );
      expect(init(), contains('six drafts'));
      expect(init(), isNot(contains('five drafts')));
      expect(init(), isNot(contains('five starting drafts')));
    });

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

    test('init passes no --target, a new '
        'project having one code target', () {
      expect(
        init(),
        contains(
          'A new project has one code target, so no `set` here carries '
          '`--target`.',
        ),
      );
    });
  });

  group('Agent fills what the new format lacks after a migration or a pack '
      'upgrade', () {
    const procedureTargetLine =
        '**Code target** (two or more `targets:`): each `new`, `get`, and '
        '`set` of a per-target doc carries '
        "`--target <name>`, the finding DocPath's code target, else the first "
        'listed one.';

    String text(String file) => _oneLine(_pluginText(file));

    for (final skill in ['bootstrap-prd', 'bootstrap-spec']) {
      test('fill_check_findings and merge_old_files: the $skill '
          "procedure takes each write's target from the finding DocPath, else "
          'the first listed', () {
        expect(
          text('specstone-$skill/references/procedure.md'),
          contains(procedureTargetLine),
        );
      });

      test('fill_check_findings: $skill names the batch target '
          'source, so a bootstrap batch never asks the Owner', () {
        expect(
          text('specstone-$skill/SKILL.md'),
          contains(
            "**Code target** (two or more `targets:`): a finding's code "
            "target is its DocPath's, and an old "
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
        text('specstone-bootstrap-prd/references/procedure.md'),
        contains(
          'Give each `implements:` entry of a `FEATURE.md` to the record '
          'entry of the story or FR whose behavior that code does, in the '
          'first listed code target, unless it holds it already;',
        ),
      );
      expect(
        text('specstone-bootstrap-prd/references/procedure.md'),
        contains(
          'to `specstone set implementation:<feature> --field implements '
          '--base <hash>`.',
        ),
      );
    });

    test('fill_check_findings: a spec doc implements pointer goes to the '
        'record entry of its story or FR', () {
      expect(
        text('specstone-bootstrap-spec/references/procedure.md'),
        contains('move each entry to the record entry of the story or FR'),
      );
    });

    test("R-T33-1: bootstrap-spec fills each target's tech stack doc, its "
        'rest batch naming each', () {
      expect(
        text('specstone-bootstrap-spec/references/procedure.md'),
        contains(
          "fill each target's tech stack doc per the guide you "
          'loaded, and its `code`,',
        ),
      );
      expect(
        text('specstone-bootstrap-spec/SKILL.md'),
        contains("names each target's tech stack doc"),
      );
    });

    test('fill_check_findings: a spec doc implements pointer is written with '
        'the record command', () {
      expect(
        text('specstone-bootstrap-spec/references/procedure.md'),
        contains(
          'with `specstone set implementation:<feature> --field implements '
          '--base <hash>`, then drop the key.',
        ),
      );
    });

    test("R-T33-1: bootstrap-spec takes each target's tech stack code roots "
        "from that target's code root", () {
      expect(
        text('specstone-bootstrap-spec/references/procedure.md'),
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
          text('specstone-$skill/references/procedure.md'),
          contains(
            'list each untyped referrer outside it, with the file it names, '
            'for its owner to merge.',
          ),
        );
      });

      test('Code target line of $skill starts its own block', () {
        expect(
          _pluginText('specstone-$skill/references/procedure.md'),
          contains('\n\n**Code target** (two or more'),
        );
      });

      test('fill_check_findings E14, refuse_stale_base: $skill sends its '
          'writes to writes.md, which retries a write a parallel batch made '
          'stale', () {
        expect(
          _pluginText('specstone-$skill/references/procedure.md'),
          contains('`$_writesFromReference`'),
        );
        expect(
          _oneLine(_pluginText(_writes)),
          contains('Exit 75 `base_mismatch`: read again, merge, retry.'),
        );
      });
    }

    test('sdd-engineer names the bootstrap target source on its Code target '
        'line', () {
      expect(
        text('specstone-sdd-engineer.md'),
        contains(
          "bootstrap takes the finding DocPath's code target on each "
          'per-target `new`, `get`, and `set`, else the first listed one for a '
          'code pointer on a shared doc or an old file whose path names none;',
        ),
      );
    });

    group('uncovered code in a fill run', () {
      const procedureFile = 'specstone-bootstrap-spec/references/procedure.md';

      String afterReports() => _oneLine(
        _sectionOf(
          _pluginText('specstone-bootstrap-spec/SKILL.md'),
          '3. After the reports',
        ),
      );

      test('the procedure reads a code_uncovered file, writes nothing for it, '
          'and reports it under Uncovered:', () {
        expect(
          text(procedureFile),
          contains(
            '- **`code_uncovered`:** read the file and write nothing for it; '
            'report it under `Uncovered:` in the form of step 3 of '
            '`../../specstone-sync-sdd/references/procedure.md`.',
          ),
        );
      });

      test('the procedure writes a covers entry or a topic doc only on a '
          'write-a-spec pick sent to it, and takes a reported file as '
          'handled', () {
        final procedure = text(procedureFile);
        expect(
          procedure,
          contains(
            'On a write-a-spec pick sent to you, with its file: add the file '
            'or its folder to `covers` on the architecture or topic doc '
            'describing it; with none, `specstone new topic --slug <slug>`.',
          ),
        );
        expect(
          _oneLine(
            _sectionOf(_pluginText(procedureFile), '3. Point and cover code'),
          ),
          isNot(contains('ask the Owner')),
        );
        expect(
          procedure,
          contains(
            'clears with no write, is a reported `code_uncovered`, or is '
            'tagged `(waits for the Owner)`, except an unanswered size '
            'finding.',
          ),
        );
      });

      test('the skill asks the Owner once per batch, every file in one '
          'question, and writes nothing on change or remove', () {
        expect(
          afterReports(),
          contains(
            'once per batch, every file under its `Uncovered:` in one '
            'question: write a spec for it, or change or remove the code. '
            'Change or remove writes nothing.',
          ),
        );
      });

      test('the skill sends a write-a-spec pick that needs a new story or FR '
          'to the brainstorm, and any other with its file to the next '
          "round's agent as picks", () {
        expect(
          afterReports(),
          contains(
            'A write-a-spec pick whose behavior needs a new story or FR hands '
            'over by following the `specstone-brainstorming-sdd` skill; any '
            'other goes with its file '
            "to the next round's agent of that batch as `picks:`, which "
            'writes the draft and does not report the file.',
          ),
        );
        expect(
          text('specstone-bootstrap-spec/SKILL.md'),
          contains(
            "`batch:` the batch's paths, `picks:` each write-a-spec pick of "
            "step 3 for the batch's files, and `report:`",
          ),
        );
      });

      test('the rest batch runs in a later round while a write-a-spec pick '
          'awaits its file, even with no other finding', () {
        expect(
          text('specstone-bootstrap-spec/SKILL.md'),
          contains(
            'In a later round it runs only when findings it owns remain or a '
            'write-a-spec pick awaits.',
          ),
        );
      });

      test("the skill keeps each answered file out of the run's later "
          'reports and questions, and names it once at the end with what it '
          'waits on', () {
        final skill = text('specstone-bootstrap-spec/SKILL.md');
        expect(
          afterReports(),
          contains(
            'Keep each answered file, whatever the pick, for the run: no '
            'later batch reports it and the Owner is not asked again.',
          ),
        );
        expect(
          skill,
          contains(
            '`code_uncovered` included except a file the Owner answered in '
            'this run.',
          ),
        );
        expect(
          afterReports(),
          contains(
            'it is an answered `code_uncovered` file, which starts a round '
            'only through a write-a-spec pick,',
          ),
        );
        expect(
          afterReports(),
          contains(
            'name once each answered `code_uncovered` file the last `check` '
            'still lists, with what it waits on: the code change, the '
            'brainstorm, or the approval of its draft,',
          ),
        );
      });

      test('the sibling merge and retire clauses stay in both bootstrap '
          'procedures', () {
        for (final skill in ['bootstrap-prd', 'bootstrap-spec']) {
          final procedure = text('specstone-$skill/references/procedure.md');
          expect(procedure, contains('Name the set in one '), reason: skill);
          expect(
            procedure,
            contains('On a batch, delete nothing: hand that line to'),
            reason: skill,
          );
          expect(
            procedure,
            contains('Add its path to this run'),
            reason: skill,
          );
        }
      });
    });
  });

  test('f08/us02/fr01, db-r5, db-r6: brainstorming-sdd targets the smallest '
      'doc and adds a story with --summary', () {
    final text = _pluginText('specstone-brainstorming-sdd/SKILL.md')
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
      _pluginText('specstone-brainstorming-sdd/SKILL.md'),
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
    expect(_pluginText('specstone-sdd-reader.md'), contains('· summary'));
  });

  test('f08/us01/fr02/e02, sf-r3: sdd-reader runs no write command, move '
      'included', () {
    expect(
      _sectionOf(_pluginText('specstone-sdd-reader.md'), 'Scope Boundaries'),
      contains(
        "**DON'T:**\n\n- Run a write command: `new`, `set`, `approve`, "
        '`delete`, `reorder`, `rename`, or `move`.\n',
      ),
    );
  });

  test('sdd-engineer runs approve only with --dry-run, and no delete, '
      'rename, reorder, or move', () {
    expect(
      _sectionOf(_pluginText('specstone-sdd-engineer.md'), 'Scope Boundaries'),
      contains(
        "**DON'T:**\n\n- Run `specstone approve` without `--dry-run` "
        '(the main session that dispatched you approves, never you), '
        '`delete`, `rename`, `reorder`, or `move`.\n',
      ),
    );
  });

  test("sdd-engineer's role names the main session, not the Owner, as the "
      'one that gets its drafts approved', () {
    final role = _sectionOf(_pluginText('specstone-sdd-engineer.md'), 'Role');
    expect(role, isNot(contains('the Owner approves your drafts')));
    expect(role, contains('main session'));
  });

  test('sdd-reader takes --summary '
      'per target, and no design caller hands it targets on an over-budget '
      'route', () {
    String flat(String f) => _pluginText(f).replaceAll(RegExp(r'\s+'), ' ');
    final reader = flat('specstone-sdd-reader.md');
    expect(reader, contains('Each may come marked `--summary`'));
    expect(reader, contains('[--summary]'));
    expect(
      reader,
      contains('only on the call for a target the dispatch marks with it'),
    );
    expect(reader, isNot(contains('**`--summary`** (optional)')));
    for (final file in [
      'specstone-brainstorming-sdd/SKILL.md',
      'specstone-brainstorming-sdd/references/source.md',
    ]) {
      expect(flat(file), isNot(contains('over budget')), reason: file);
    }
  });

  test('agent_plugin/write_prd_and_spec/write_design_and_plan E09-E12, '
      'E10-E13: '
      "design mode searches each decision's dependents, and the audit hashes "
      'its targets in one get and tags behavior findings', () {
    final design = _pluginText(
      'specstone-brainstorming-sdd/references/design.md',
    );
    final write = _oneLine(_sectionOf(design, '3. Write the document'));
    for (final point in _dependentsSearchPoints) {
      expect(write, contains(point), reason: point);
    }
    final audit = _pluginText(
      'specstone-brainstorming-sdd/references/audit.md',
    );
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
        _sectionOf(_pluginText('specstone-sdd-engineer.md'), 'Output Format'),
      ),
      contains('- **Audit**: the `Audited:` lines, `Findings:`,'),
    );
  });

  test('write_design_document E10, E25, E27 to E30: design.md grounds a '
      'dependency by a cited run, tables each new input, searches the E29 '
      'forms, and holds the E28 check', () {
    final design = _pluginText(
      'specstone-brainstorming-sdd/references/design.md',
    );
    final ground = _oneLine(_sectionOf(design, '2. Ground each claim'));
    expect(ground, contains('`Run:`'));
    expect(ground, contains('read-only'));
    for (final point in _dependencyRunPoints) {
      expect(ground, contains(point), reason: point);
    }
    final write = _oneLine(_sectionOf(design, '3. Write the document'));
    for (final point in [..._inputTablePoints, ..._writtenFormPoints]) {
      expect(write, contains(point), reason: point);
    }
    final check = _oneLine(_sectionOf(design, '4. Check before you ask'));
    for (final point in _approvalCheckPoints) {
      expect(check, contains(point), reason: point);
    }
  });

  test('E05, E06, '
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
    final skill = _pluginText('specstone-brainstorming-sdd/SKILL.md');
    final design = _sectionOf(skill, '3. Write the document');
    expect(design, contains('`$_roundsPath`'));
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
        _pluginText('specstone-brainstorming-sdd/$file'),
        isNot(contains('while it is live')),
        reason: file,
      );
    }
    expect(cliCommands(_pluginText(_rounds)), contains('get'));
    bool ofRounds(String problem) => problem.startsWith('$_rounds:');
    expect(oversizedSkillFiles(contentFiles()).where(ofRounds), isEmpty);
    expect(
      unknownCliNames(contentFiles(), SpecstoneCommandRunner()).where(ofRounds),
      isEmpty,
    );
  });

  test('Take in a source another tool wrote '
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
      '`specstone-bootstrap-prd`',
      '`specstone-bootstrap-spec`',
      '`specstone-read-sdd`',
      '`<folder>/reports/sdd-engineer.design.source.<XXXXXX>.md`',
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
    expect(oversizedSkillFiles(contentFiles()).where(ofSource), isEmpty);
    expect(
      unknownCliNames(contentFiles(), SpecstoneCommandRunner()).where(ofSource),
      isEmpty,
    );
    expect(nonLatinLetterLines(agentAssetsRoot()).where(ofSource), isEmpty);
  });

  test('source.md names the runner as its one reader and holds no brief and '
      'no design mode, the Source map being the runner own step', () {
    final text = _oneLine(_pluginText(_source));
    expect(
      text,
      contains(
        'The runner of `specstone-brainstorming-sdd` follows '
        '`## Take in the source` and `## Map the source`.',
      ),
    );
    for (final stale in [
      'brief',
      'mode: design',
      'design mode',
      'specstone-sdd-engineer',
      '`report:`',
      'As the agent',
    ]) {
      expect(text, isNot(contains(stale)), reason: stale);
    }
    final map = _oneLine(_sectionOf(_pluginText(_source), 'Map the source'));
    expect(map, contains('at each write and amend of the design document'));
  });

  test('E04, '
      'verification; agent_plugin/write_prd_and_spec/run_brainstorm_to_design '
      'E26: step 1 makes the gate call, with no budget, opens no link or '
      'issue before it exits 0, and then points to source.md', () {
    final skill = _pluginText('specstone-brainstorming-sdd/SKILL.md');
    final step = _oneLine(_sectionOf(skill, '1. Ground: the first call'));
    const gate = 'specstone context project --for design';
    const pointer = '`references/source.md`';
    expect(step, contains(gate));
    expect(step, contains(pointer));
    expect(step.indexOf(gate), lessThan(step.indexOf(pointer)));
    expect(step, contains('before any other command or file read'));
    expect(
      step,
      contains(
        'Read or open the source, a link or an issue included, only after it '
        'exits 0',
      ),
    );
    expect(_oneLine(skill), isNot(contains('$gate --budget')));
    expect(_frontmatter.firstMatch(skill)![0], contains('another tool'));
  });

  test('Map each source item in the design document '
      'verification; write_design_document input_output; take_in_a_source '
      'E02, E03, E08: design.md points the runner to source.md, and the '
      "runner grounds on its saved files and the Owner's answers", () {
    final design = _pluginText(
      'specstone-brainstorming-sdd/references/design.md',
    );
    expect(
      _oneLine(_sectionOf(design, '1. Check the inputs')),
      contains('`source.md`'),
    );
    final ground = _oneLine(_sectionOf(design, '2. Ground each claim'));
    expect(
      ground,
      contains(
        'Ground each claim in the saved bundle files of your `context` calls '
        "or in an Owner's answer",
      ),
    );
    expect(ground, isNot(contains('--for design --no-project')));
    expect(
      _pluginText('specstone-sdd-engineer.md'),
      isNot(contains('source.md')),
    );
  });

  test('E01, E03, '
      'E11, E12, domain:agent_plugin INV-10: the author re-reads its drafts '
      'in one get, loads every guide in one call, writes several docs '
      'through one set --batch, and sdd-engineer makes its batch file '
      'with get --out', () {
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
    final agent = _pluginText('specstone-sdd-engineer.md');
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
    expect(_redirectSpan.allMatches(scope), isEmpty);
    expect(
      _oneLine(scope),
      contains('- Write a file by a shell redirect, or a PRD or spec'),
    );
    bool ofAuthor(String problem) => problem.startsWith('$_author:');
    expect(oversizedSkillFiles(contentFiles()).where(ofAuthor), isEmpty);
    expect(
      unknownCliNames(
        contentFiles(),
        SpecstoneCommandRunner(),
      ).where((problem) => problem.startsWith('specstone-sdd-engineer.md:')),
      isEmpty,
    );
  });
}

/// Each point of the design document's dependents clauses, as step 3 of
/// design.md words it, cut at line width.
const _dependentsSearchPoints = [
  "its rule's owner doc (`none` for a decision with no rule, such as a pure",
  'ruling or an approach pick), and the terms you searched for it.',
  "Before the Docs to change table closes, find each decision's dependents in",
  'your saved files:',
  "Name the owner doc of the decision's rule (`specstone-expert-sdd` rule 7).",
  "The owner item's cited-by lines in the saved files give the docs that link",
  'it.',
  'Run `specstone check <feature> --repeats` for the repeat groups that hold',
  'the owner item.',
  'Each doc found that restates the rule gets a Docs to change row: its',
  "change links the owner's item that holds the rule, or rewrites the doc",
  "when it owns a rule that reads the decision's rule.",
  'With no cited-by line on the owner item, as in a tree that still cites by',
  'number labels, the repeat groups and the text search carry the decision.',
  'Record the searched terms either way, so the audit sees them.',
  'An amend for a decision that adds or changes behavior runs these steps on',
  'its terms and adds its rows and searched terms before the author writes it.',
];

/// Each point of `write_design_document` E25 and E27 as step 2 of design.md
/// words it: a dependency's behavior grounded by a cited read-only run, cut at
/// line width.
const _dependencyRunPoints = [
  'Ground a claim about how a library, parser, or tool the change calls',
  'behaves only by a read-only run in a scratch folder outside the docs,',
  'cited in one `Run:` line: the command and its output line.',
  'With no run, the claim is an open question.',
  'The saved files ground a claim about the Specstone CLI.',
];

/// Each point of `write_design_document` E10 and E30 as the Decisions item of
/// step 3 words it, cut at line width.
const _inputTablePoints = [
  'A decision that takes inputs or states (a rule with states, or one that',
  'adds a key, a flag, a link form, a refusal, or a doc type target)',
  'also gets an input table:',
  'one row per input or state, the result it gives, and each command or',
  'skill that reads it.',
  "A refusal's row quotes its message literal.",
];

/// Each point of `write_design_document` E29 as the dependents bullets of
/// step 3 word it, cut at line width.
const _writtenFormPoints = [
  "Search the saved files' text for the decision's terms and for the wording",
  'it supersedes, each in every written form: with and without a',
  'trailing `/`, in backticks or not, singular and plural, and a short form.',
  'Search every section of each doc in a Docs to change row.',
];

/// Each point of `write_design_document` E28 as step 4 of design.md words it,
/// with the exemption of the design document itself, cut at line width.
const _approvalCheckPoints = [
  "Before the approval ask, check each saved file's sections outside the Docs",
  'to change rows for a wording a decision supersedes: each found gets a row.',
  'Ask only once none is left.',
  'This document is outside the check: it quotes that wording.',
];

/// Each point of `audit_drafts_by_reading`'s one `get` call, E11, and E12, as
/// step 1 of audit.md words it, cut at line width.
const _auditReadPoints = [
  'An audit after a fix round, or after the author pass that follows an',
  'amend, takes the drafts list, each',
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
  '**Rule restated:** a draft stating a rule another doc owns instead of',
  'citing it (`specstone-expert-sdd` rule 7); name the owner doc and the item;',
  'its fix is an item link in the draft.',
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
  'End a `Findings:` line with `[behavior]` when its fix brings a new state,',
  'input, output, edge case, error, or reader of a rule the design does not',
  'state;',
  'a line whose fix only corrects text against the design stays untagged.',
  'each target that is no draft, and each name dropped from the `get` call;',
  'A fix round takes only the untagged `Findings:` lines; a `[behavior]` line',
  "goes to the runner's design amend.",
];

/// Text that `specstone-expert-sdd` rule 7 or `run_brainstorm_to_design` E13
/// owns, which design.md and audit.md cite and never restate.
const _ownedElsewhere = [
  'A rule has one owner doc',
  'pins no hash',
  'differs from their last',
  'each doc the round or pass added',
];

/// The runner's fix-round and ruling procedure of `brainstorming-sdd`, under
/// the plugin folder.
const _rounds = 'specstone-brainstorming-sdd/references/rounds.md';

/// [_rounds] by the path the skill's runner reads it from.
const _roundsPath = 'references/rounds.md';

/// The take-in and Source map reference file of `brainstorming-sdd`, which
/// its runner alone reads, under the plugin folder.
const _source = 'specstone-brainstorming-sdd/references/source.md';

/// Each rule of `take_in_a_source` and `map_source_items` as source.md words
/// it, tagged with the edge case it proves.
const _sourcePoints = [
  // take_in_a_source E01, BR-01: the gate before any read; the file unread.
  'Read no source and open no link or issue before it.',
  'Read none of it with any tool',
  // E02: a source that adds a feature runs no narrow call.
  'no second narrow call runs',
  // The narrow call's bare --out, and both saved bundles whatever size.
  'specstone context <target> --for design --no-project --out',
  'both saved bundles are the grounding, whatever their size',
  'read them per the `specstone-read-sdd` skill, searching them before any',
  '`get`.',
  // E06: only the gaps, one at a time, nothing invented.
  'Ask the Owner only what the source leaves open, one question at a time',
  'invent nothing',
  // E07, NFR-Pr01: only a link the Owner gave.
  'Open a link or issue only because the Owner gave it',
  'a link written inside the source is none the Owner gave',
  // E10: the copy is no source.
  'the copy is no source',
  // E11: an untyped file is refused and never named.
  'Run no other command on its path.',
  // E12: a typed doc is the change's target, its path call the narrow call.
  'no source, no copy, no Source map',
  'That call was your narrow call',
  'run no further narrow `context` call',
  // map_source_items E01 to E05 and the Source map's place.
  'after Docs to change and before Open questions',
  'one row per source item, 0 items left out',
  'its reason that task management is out of scope',
  'an open question in the design document, as for any gap',
  'never recorded as the source',
  'A change with no source gets no Source map',
  'Never edit, move, or delete the source;',
  'write only the copy and the one design document.',
];

/// Each point of `run_brainstorm_to_design`'s dispatch, fix-round, amend, and
/// re-audit clauses, E05, E06, E07, E10, E12, and E13, as rounds.md words
/// them, cut at line width.
const _roundsPoints = [
  'adds or changes behavior when it brings a new state, input, output,',
  'edge case, error, or reader of a rule.',
  "append it to the design document's Rulings yourself, as `design.md` writes",
  'them, and dispatch nothing;',
  'the author, or the fix round under way, goes on.',
  'or needs more PRD or spec grounding',
  'amend the same file yourself',
  "`design.md` finds the decision's dependents before the author writes it.",
  'after an append or an amend, ask for the approval again.',
  "When the design document holds open questions, gather the Owner's answers,",
  'append each that only words or records one, send the rest to one amend,',
  'and ask for the approval only after it.',
  '**During fix rounds**, a decision that adds or changes behavior takes',
  'an amend, then one fresh author pass and a re-audit, as section 2 says',
  '**After the second fix round**, a decision that adds or changes',
  "behavior, the Owner's decision on a finding past the cap included,",
  'takes an amend, then one author pass that carries the amend alone and is',
  'no fix round, then a re-audit (section 3) whose findings reach the Owner',
  'with the drafts, with no further round.',
  'Fix an Owner change that only corrects text per the `specstone-expert-sdd`',
  'skill, with no amend.',
  "The drafts list is the first author report's drafts plus each doc a fix",
  'round or pass added, renamed or dropped as section 3 says.',
  'every author pass after the first, each fix round and the pass that',
  'follows an amend, is a new `mode: author` dispatch, never the resumed',
  'one.',
  "a fix round adds the audit's `Findings:` lines that carry no `[behavior]`",
  'The author re-reads those drafts before its first write',
  'and fixes only those findings, in those drafts.',
  'never goes to a fix round: take it, with the decision that answers it,',
  'to an amend (section 1).',
  'that pass takes them too and counts as a fix round; a pass that carries',
  'the amend alone is no fix round.',
  'run at most two fix rounds, counted across an amend.',
  'Lines left after the second get no third round: the Owner sees them',
  'with the drafts before approving any',
  "and their decision on one takes section 1's route.",
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
  'dropped.',
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
const _author = 'specstone-brainstorming-sdd/references/author.md';

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
  '**Several docs in one step**: run `specstone get <names> --out "<file>"`,',
  '`<file>` `<folder>/reports/sdd-engineer.author.batch.<XXXXXX>.txt`,',
  '`<folder>` the path `specstone folder` prints; edit its blocks, each',
  'naming line kept; then run `specstone set --batch "<file>"`.',
  'A block printed ` · unchanged` wrote nothing and adds no draft.',
  '**A refused batch** writes nothing, but exit 73',
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
  'round, or the pass after an amend of the design document)',
  "the drafts list, the first author report's drafts plus each doc a fix",
  "round or pass added; in a fix round, the audit's `Findings:` lines too.",
];

/// The batch file sdd-engineer makes, as its Scope Boundaries word it.
const _batchFileRedirect =
    'a batch file: made by `specstone get … --out "<file>"`, `<file>` '
    '`<folder>/reports/sdd-engineer.<mode>.batch.<XXXXXX>.txt`, and passed to '
    '`specstone set --batch "<file>"`.';

/// A code span that redirects output into a file.
final _redirectSpan = RegExp(r'`[^`\n]* >>? [^`\n]*`');

/// The one home of the size-fix rule, under the plugin folder.
const _sizeFix = 'specstone-expert-sdd/references/size-fix.md';

/// [_sizeFix] by the path a bootstrap skill's `SKILL.md` names it by.
const _sizeFixFromSkill = '../specstone-expert-sdd/references/size-fix.md';

/// [_sizeFix] by the path a bootstrap procedure names it by.
const _sizeFixFromReference =
    '../../specstone-expert-sdd/references/size-fix.md';

/// The one home of the bootstrap write block, under the plugin folder.
const _writes = 'specstone-expert-sdd/references/writes.md';

/// [_writes] by the path a bootstrap procedure names it by.
const _writesFromReference = '../../specstone-expert-sdd/references/writes.md';

/// The one home of the readability-fix rewrite, under the plugin folder.
const _readabilityFix = 'specstone-expert-sdd/references/readability-fix.md';

/// [_readabilityFix] by the path a bootstrap procedure names it by.
const _readabilityFixFromReference =
    '../../specstone-expert-sdd/references/readability-fix.md';

const _sizeFindings = [
  '`chars_over_limit`',
  '`lines_over_limit`',
  '`item_over_limit`',
  '`bundle_over_limit`',
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
  'specstone-bootstrap-prd/references/procedure.md': [
    "propose it from the project's own text",
    'unless a project doc holds it already',
    'Write nothing it holds already',
  ],
  'specstone-bootstrap-spec/references/procedure.md': [
    "propose it from the project's own text",
    'write nothing a project doc holds already',
    'drop, as a step 6 proposal, what only describes the old index',
  ],
};

/// The four readability findings a bootstrap batch rewrites in place.
const _readabilityFindings = [
  '`words_over_limit`',
  '`sentence_chars_over_limit`',
  '`trace_note_not_last`',
  '`sentences_over_limit`',
];

/// Each point of `fill_check_findings` E48, then E49, then E50, by the phrase
/// readability-fix.md writes for it.
const _readabilityRewritePoints = [
  "in its doc type's item shape, as `specstone guide <type>` gives it",
  'with no Owner naming',
  'takes the next free ID of its section',
  'each citation that means the moved rule is repointed',
  'conditions go in a nested list',
  "a trace group before the item's end moves to the end",
  'merged with any other group there into one group',
  'an ownership clause before the last clause moves to be the last clause',
  'no statement is dropped',
  'a paragraph with no ID and a count of 1',
  "rewrite it in place into sentences within their language's cap",
  'its detail moves to the section of the same doc that owns it',
  'it never turns into a sub-list',
  "Give a split proposal or the report's why, as `size-fix.md` gives it",
  'no rewrite keeps the meaning or a size finding is left',
  'The finding waits for the Owner.',
];

void _readabilityFixTests() {
  test('E48-E50: each bootstrap procedure has one row sending the four '
      'readability findings to readability-fix.md, above the catch-all row '
      'and with no rewrite text', () {
    for (final file in _droppedTextReasons.keys) {
      final text = _pluginText(file);
      final rows = _sectionOf(
        text,
        '2. One finding at a time',
      ).split('\n').where((line) => line.startsWith('|')).toList();
      final readability = [
        for (final row in rows)
          if ([
            ..._readabilityFindings,
            '`$_readabilityFixFromReference`',
          ].every(row.contains))
            row,
      ];
      expect(readability, hasLength(1), reason: file);
      expect(
        rows.indexOf(readability.single),
        lessThan(rows.indexWhere((line) => line.startsWith('| any other'))),
        reason: '$file: the catch-all row comes last',
      );
      for (final point in _readabilityRewritePoints) {
        expect(_oneLine(text), isNot(contains(point)), reason: '$file: $point');
      }
    }
  });

  test('E48-E50: readability-fix.md names the four findings, holds the '
      'points of E48, E49, and E50 in that order, and sends a size finding '
      'to size-fix.md without its order or commands', () {
    final raw = _pluginText(_readabilityFix);
    final text = _oneLine(raw);
    for (final finding in _readabilityFindings) {
      expect(text, contains(finding), reason: finding);
    }
    var from = 0;
    for (final point in _readabilityRewritePoints) {
      final at = text.indexOf(point, from);
      expect(at, isNonNegative, reason: 'after offset $from: $point');
      from = at + point.length;
    }
    expect(text, contains('`size-fix.md`'));
    expect(text, isNot(contains('new feature --parent')));
    expect(text, isNot(contains('specstone move')));
  });

  test('only the two bootstrap procedures name readability-fix.md', () {
    final namers = [
      for (final file in agentSourceFiles(agentAssetsRoot()))
        if (file.readAsStringSync().contains('readability-fix.md'))
          shippedPathOf(file),
    ];
    expect(namers, unorderedEquals(_droppedTextReasons.keys));
    for (final file in _droppedTextReasons.keys) {
      expect(
        _pluginText(file),
        contains('`$_readabilityFixFromReference`'),
        reason: file,
      );
    }
  });

  test('only the two bootstrap procedures name writes.md, each in one line '
      'that replaces its write block', () {
    final namers = [
      for (final file in agentSourceFiles(agentAssetsRoot()))
        if (file.readAsStringSync().contains('writes.md')) shippedPathOf(file),
    ];
    expect(namers, unorderedEquals(_droppedTextReasons.keys));
    for (final file in _droppedTextReasons.keys) {
      final text = _pluginText(file);
      expect(text.split('\n').where((line) => line.contains('writes.md')), [
        'Write each fix as `$_writesFromReference` says.',
      ], reason: file);
      for (final held in ['base_mismatch', '#quot;', '#_lead']) {
        expect(text, isNot(contains(held)), reason: '$file: $held');
      }
    }
  });
}

void _sizeFixTests() {
  test('E06, E07, '
      'E10-E12, agent_plugin/fill_missing_format/merge_old_files E02, E07: '
      'each bootstrap procedure moves old text, marks a gap TBR, and has one '
      'finding row sending the three size findings to size-fix.md', () {
    for (final MapEntry(key: file, value: reasons)
        in _droppedTextReasons.entries) {
      final text = _pluginText(file);
      final sizeRows = [
        for (final line in text.split('\n'))
          if (line.startsWith('|') &&
              [
                ..._sizeFindings,
                '`$_sizeFixFromReference`',
              ].every(line.contains))
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

  test('E05, E06, '
      'E10-E12: '
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

  test('size-fix.md answers bundle_over_limit with the split alone, no '
      'layout step and no text moved, and the finding waits for the Owner', () {
    final sizeFix = _pluginText(_sizeFix);
    final order = _oneLine(_sectionOf(sizeFix, 'The order'));
    expect(
      order,
      contains('A `bundle_over_limit` finding skips steps 1, 3, and 4'),
    );
    final bundle = _oneLine(_sectionOf(sizeFix, 'A bundle over its limit'));
    expect(bundle, contains('`bundle_over_limit`'));
    expect(bundle, contains('sub-feature split'));
    expect(bundle, contains('no layout step'));
    expect(bundle, contains('no text moved'));
    expect(bundle, contains('waits for the Owner'));
  });

  test('E12, E13: '
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
      final text = _pluginText('specstone-$skill/SKILL.md');
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
    final agent = _pluginText('specstone-sdd-engineer.md');
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
      'every other file '
      'points to size-fix.md and none restates its commands', () {
    final rules = _oneLine(
      _sectionOf(_pluginText('specstone-expert-sdd/SKILL.md'), 'Rules'),
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
          _pluginText('specstone-$skill/SKILL.md'),
          '3. After the reports',
        ),
      );
      expect(after, contains('`$_sizeFixFromSkill`'), reason: skill);
      expect(after, contains('in run order'), reason: skill);
    }
    expect(
      _pluginText('specstone-sdd-engineer.md'),
      contains('`.agents/skills/$_sizeFix`'),
    );
    for (final file in agentSourceFiles(agentAssetsRoot())) {
      if (file.uri.path.endsWith(_sizeFix)) continue;
      expect(
        _oneLine(file.readAsStringSync()),
        isNot(contains('new feature --parent')),
        reason: file.path,
      );
    }
  });

  test('size-fix.md routes a finding with candidates or split, and an FR '
      'over its character cap, to item moves in run order', () {
    final sizeFix = _pluginText(_sizeFix);
    final moves = _oneLine(
      _sectionOf(sizeFix, 'A finding that names items to move'),
    );
    expect(moves, contains('`candidates`'));
    expect(moves, contains('`split`'));
    expect(moves, contains('an FR over its character cap'));
    expect(
      moves,
      contains('one `specstone move <doc>#<ID> … --under <doc>` per'),
    );
    expect(moves, contains("that sub-feature's doc of the same type"));
    final newFr = moves.indexOf(
      '`specstone new fr --parent <story> --slug <slug>`',
    );
    expect(newFr, isNonNegative);
    expect(
      moves,
      contains(
        'when it cannot be formed, as with fewer stories than it needs, the '
        'finding keeps `No split applies`',
      ),
    );
    expect(
      moves.indexOf('`specstone move <fr>#<edge case ID> … --under <new fr>`'),
      greaterThan(newFr),
    );
    expect(moves, contains("the Owner's ok"));
    expect(moves, contains('in run order'));
    expect(
      _oneLine(sizeFix),
      contains('every other size finding keeps its route above'),
    );
  });

  test('each bootstrap skill runs a split or move proposal after the '
      "Owner's ok, naming its new, story move, and item move commands", () {
    for (final skill in ['bootstrap-prd', 'bootstrap-spec']) {
      final after = _oneLine(
        _sectionOf(
          _pluginText('specstone-$skill/SKILL.md'),
          '3. After the reports',
        ),
      );
      expect(
        after,
        contains('ask the Owner to approve each proposal'),
        reason: skill,
      );
      expect(after, contains('`new feature`'), reason: skill);
      expect(after, contains('`move <story> …`'), reason: skill);
      expect(after, contains('`move <doc>#<ID> …`'), reason: skill);
      expect(after, contains('in run order'), reason: skill);
    }
  });
}

/// Each bootstrap procedure and its est. tokens once the write block moved to
/// writes.md, which its one guide call per batch leaves no higher.
const _bootstrapProcedureTokens = {
  'specstone-bootstrap-prd/references/procedure.md': 1402,
  'specstone-bootstrap-spec/references/procedure.md': 1416,
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
  test('E25, '
      'each '
      'bootstrap procedure runs one guide call for every type its batch '
      'writes before the first write and its own call for a type met later, '
      'points each finding fix to it, and stays within its e8262ba est. '
      'tokens; expert-sdd counts one call for each type it names', () {
    final expert = _pluginText('specstone-expert-sdd/SKILL.md');
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
          contentFiles(),
          limit: tokens,
        ).where((problem) => problem.startsWith('$file:')),
        isEmpty,
      );
    }
  });
}

/// Each bootstrap skill and the docs tree whose repeat groups it takes.
const _repeatsTrees = {'bootstrap-prd': 'prds', 'bootstrap-spec': 'specs'};

/// The folder text a skill's repeats phrase adds after its tree.
const _repeatsExtraTrees = {'bootstrap-prd': ' or `measurements/`'};

/// The shared repeats-batch reference both fill skills point to.
const _repeats = 'specstone-expert-sdd/references/repeats.md';

/// [_repeats] by the path a bootstrap skill's `SKILL.md` names it by.
const _repeatsFromSkill = '../specstone-expert-sdd/references/repeats.md';

/// [_repeats] by the path a bootstrap procedure names it by.
const _repeatsFromReference =
    '../../specstone-expert-sdd/references/repeats.md';

/// How the repeats batch's agent merges one group or keeps it.
const _repeatMergePoints = [
  'Per group, judge whether its items state one rule.',
  "keep the item in the doc that owns the rule's subject",
  'replace each other copy in a doc your skill takes with a link to that item',
  "name the owner in each draft's reason.",
  'keep each item and report the group as kept.',
];

void _repeatsBatchTests() {
  test('repeats.md holds the cite_unlinked '
      'fix and the repeats batch once, for both fill skills', () {
    final text = _pluginText(_repeats);
    final batch = _oneLine(_sectionOf(text, 'A repeats batch'));
    for (final point in _repeatMergePoints) {
      expect(batch, contains(point), reason: point);
    }
    for (final MapEntry(key: skill, value: tree) in _repeatsTrees.entries) {
      expect(
        batch,
        contains(
          'under `$tree/`${_repeatsExtraTrees[skill] ?? ''} for `$skill`',
        ),
        reason: skill,
      );
    }
    expect(
      _oneLine(_sectionOf(text, 'A `cite_unlinked` finding')),
      contains(
        'Rewrite the cite as a link to the one doc or item its text '
        'means.',
      ),
    );
  });

  for (final MapEntry(key: skill, value: tree) in _repeatsTrees.entries) {
    test('$skill runs one check --repeats after '
        'the last round, right before its one repeats batch, keeps the groups '
        'with an item under $tree/, and points to repeats.md', () {
      final text = _pluginText('specstone-$skill/SKILL.md');
      expect(
        'specstone check --repeats'.allMatches(_bodyOf(text)),
        hasLength(1),
      );
      expect(
        _sectionOf(text, '1. Gate: the first call'),
        isNot(contains('--repeats')),
      );
      final after = _oneLine(_sectionOf(text, '3. After the reports'));
      final round = after.indexOf('starts another round at step 2');
      final listing = after.indexOf('`specstone check --repeats`');
      final batch = after.indexOf('`batch: repeats`');
      expect(round, isNonNegative);
      expect(listing, greaterThan(round));
      expect(batch, greaterThan(listing));
      expect(after.indexOf('Then stop;'), greaterThan(batch));
      expect(after, contains('With none left, go to item 6.'));
      expect(after, contains('each group with an item under `$tree/`'));
      expect(
        after,
        contains('A group it keeps stays listed and never starts a round.'),
      );
      expect(_repeatsFromSkill.allMatches(text), hasLength(1));
    });

    test('the $skill procedure points cite_unlinked '
        'and a repeats batch to repeats.md in one row and copies no step', () {
      final text = _pluginText('specstone-$skill/references/procedure.md');
      final findings = _sectionOf(text, '2. One finding at a time');
      expect(
        findings.split('\n').where((line) => line.contains('`cite_unlinked`')),
        ['| `cite_unlinked`, a repeats batch | `$_repeatsFromReference` |'],
      );
      for (final point in _repeatMergePoints) {
        expect(_oneLine(text), isNot(contains(point)), reason: point);
      }
      expect(text, isNot(contains('--repeats')), reason: 'main runs it');
    });
  }

  test('each bootstrap procedure merges only its own '
      "tree's untyped referrers and leaves the other tree's to its owner", () {
    final spec = _oneLine(
      _sectionOf(
        _pluginText('specstone-bootstrap-spec/references/procedure.md'),
        '5. Retire the old files',
      ),
    );
    expect(
      spec,
      contains(
        'An old untyped doc under `specs/` joins the set: merge it first.',
      ),
    );
    expect(spec, isNot(contains('under `prds/` or `specs/` joins the set')));
    expect(
      _oneLine(
        _sectionOf(
          _pluginText('specstone-bootstrap-prd/references/procedure.md'),
          '5. Retire the old files',
        ),
      ),
      contains(
        'merge it first (`specstone-bootstrap-spec` takes one under `specs/`).',
      ),
    );
  });

  test('the plan-engineer and brainstorm design glosses name prds/, specs/, '
      'and measurements/ as the checked folders', () {
    for (final file in [
      _planAgent,
      'specstone-brainstorming-sdd/references/design.md',
    ]) {
      final text = _oneLine(_pluginText(file));
      expect(
        text,
        contains('`prds/`, `specs/`, and `measurements/` with the shipped'),
        reason: file,
      );
    }
  });

  test('no routing line sends PRD findings by prds/ alone', () {
    final aloneAfterUnder = RegExp(
      'under `prds/`(?! or `measurements/`|, `measurements/`)',
    );
    for (final file in [
      'specstone-bootstrap-prd/SKILL.md',
      'specstone-bootstrap-prd/references/procedure.md',
      'specstone-bootstrap-spec/SKILL.md',
      'specstone-bootstrap-spec/references/procedure.md',
      'specstone-expert-sdd/references/repeats.md',
    ]) {
      expect(
        aloneAfterUnder.hasMatch(_oneLine(_pluginText(file))),
        isFalse,
        reason: file,
      );
    }
  });

  test("bootstrap-spec's repeats batch runs after "
      "bootstrap-prd's", () {
    expect(
      _oneLine(_pluginText('specstone-bootstrap-spec/SKILL.md')),
      contains(
        '6. Once per run, after the last round and '
        "`specstone-bootstrap-prd`'s repeats batch,",
      ),
    );
  });

  test('sdd-engineer takes batch: repeats, loads '
      'repeats.md for it, and reports each kept group', () {
    final agent = _pluginText('specstone-sdd-engineer.md');
    expect(
      _oneLine(_sectionOf(agent, 'Input Contract')),
      contains('or `batch: repeats` and the repeat groups to merge;'),
    );
    expect(
      _sectionOf(
        agent,
        'On-Demand Loads',
      ).split('\n').where((line) => line.startsWith('| `batch: repeats`')),
      [
        predicate<String>(
          (line) => line.contains('`.agents/skills/$_repeats`'),
          'names .agents/skills/$_repeats',
        ),
      ],
    );
    expect(
      _oneLine(_sectionOf(agent, 'Workflow')),
      contains(
        'A `batch: repeats` follows its On-Demand reference in place of the '
        'procedure, then Workflow step 5.',
      ),
    );
    final output = _oneLine(_sectionOf(agent, 'Output Format'));
    expect(
      output.substring(output.indexOf('- **Bootstrap**')),
      contains('each repeat group kept;'),
    );
  });
}

/// The goal-move reference of bootstrap-prd, under the plugin folder.
const _goalMove = 'specstone-bootstrap-prd/references/goal-move.md';

/// The commands of the goal move, in the order its steps run them.
const _goalMoveCommands = [
  'specstone new goal',
  'specstone new <type>',
  'specstone get',
  '--base',
  'set --batch',
  'specstone refs project',
];

/// The bootstrap-spec procedure's **Code target** paragraph, on one line.
const _specCodeTarget =
    '**Code target** (two or more `targets:`): each `new`, `get`, and `set` of '
    "a per-target doc carries `--target <name>`, the finding DocPath's code "
    'target, else the first listed one.';

/// The lines of the `## 2. One finding at a time` section of [file].
List<String> _findingRows(String file) =>
    _sectionOf(_pluginText(file), '2. One finding at a time').split('\n');

void _goalMoveTests() {
  test('bootstrap-prd procedure points singular_doc_missing and the project '
      'goals section to goal-move.md in one row and copies no step', () {
    const file = 'specstone-bootstrap-prd/references/procedure.md';
    final rows = _findingRows(file);
    final pointers = rows
        .where((line) => line.contains('`singular_doc_missing`'))
        .toList();
    expect(pointers, hasLength(1));
    final pointer = pointers.single;
    expect(pointer, contains('`goal-move.md`'));
    expect(pointer, contains('`section_undeclared`'));
    final general = rows.indexWhere(
      (line) => line.startsWith('| `section_undeclared` |'),
    );
    expect(general, isNonNegative);
    expect(rows.indexOf(pointer), lessThan(general));
    final text = _pluginText(file);
    for (final step in ['new goal', 'set --batch', 'refs project']) {
      expect(text, isNot(contains(step)), reason: step);
    }
  });

  test('goal-move.md states the goal move', () {
    final text = _oneLine(_pluginText(_goalMove));
    var previous = -1;
    for (final command in _goalMoveCommands) {
      final at = text.indexOf(command);
      expect(at, greaterThan(previous), reason: command);
      previous = at;
    }
    expect(RegExp(r'\bE\d\d\b').hasMatch(text), isFalse);
    expect(RegExp(r'\]\([^)]*\b(?:prds|specs)/').hasMatch(text), isFalse);
  });

  test('goal-move.md titles the goal doc per its guide', () {
    final move = _oneLine(
      _sectionOf(_pluginText(_goalMove), '2. Move each answered goal'),
    );
    final read = move.indexOf('`specstone get goal:goal --json`');
    expect(read, isNonNegative);
    final skip = move.indexOf(
      'Unless its title already reads `Project goals`',
      read,
    );
    expect(skip, isNonNegative);
    final guide = move.indexOf('`specstone guide goal`', skip);
    expect(guide, isNonNegative);
    final title = move.indexOf(
      '`specstone set goal:goal --title --base <hash>`',
      guide,
    );
    expect(title, isNonNegative);
    expect(move.indexOf('`bases.title`', title), isNonNegative);
    expect(move, contains('pipe `Project goals`, with no `#`,'));
    expect(title, lessThan(move.indexOf('specstone set goal:goal#<key>')));
    final missing = _oneLine(
      _sectionOf(_pluginText(_goalMove), '1. A missing singular doc'),
    );
    final created = missing.indexOf('run `specstone new goal`');
    expect(created, isNonNegative);
    final titled = missing.indexOf("title it as section 2's first step says");
    expect(titled, greaterThan(created));
    expect(titled, lessThan(missing.indexOf('stop there')));
  });

  test("bootstrap-prd SKILL.md asks each goal's horizon before the rest "
      "batch's dispatch and keeps a kept goal out of the run's later "
      'questions and rounds', () {
    final text = _pluginText('specstone-bootstrap-prd/SKILL.md');
    final handOff = _oneLine(_sectionOf(text, '2. Hand off in batches'));
    final dispatch = handOff.indexOf('Dispatch one');
    final by = handOff.indexOf('`**By:**`');
    expect(by, isNonNegative);
    expect(handOff.lastIndexOf('horizon', by), isNonNegative);
    expect(by, lessThan(dispatch));
    final after = _sectionOf(text, '3. After the reports');
    final item = _oneLine(
      after.substring(after.indexOf('\n5. '), after.indexOf('\n6. ')),
    );
    final goals = item.indexOf(
      "the `section_undeclared` on PROJECT's goals section",
    );
    expect(goals, greaterThan(item.indexOf('unless it is tagged')));
    expect(goals, lessThan(item.indexOf('With none left, go to item 6.')));
    expect(item.indexOf('horizon', goals), isNonNegative);
  });

  test("bootstrap-prd SKILL.md item 3 shows a kept goal's question without "
      'asking it and counts it settled for item 4', () {
    final after = _sectionOf(
      _pluginText('specstone-bootstrap-prd/SKILL.md'),
      '3. After the reports',
    );
    final item = _oneLine(
      after.substring(after.indexOf('\n3. '), after.indexOf('\n4. ')),
    );
    final kept = item.indexOf('a goal move kept in PROJECT');
    expect(kept, isNonNegative);
    final unasked = item.indexOf('without asking it', kept);
    expect(unasked, isNonNegative);
    expect(item.indexOf('settled for item 4', unasked), isNonNegative);
  });

  test('bootstrap-spec procedure creates a missing singular doc with new', () {
    const file = 'specstone-bootstrap-spec/references/procedure.md';
    expect(
      _findingRows(file)
          .where((line) => line.contains('`singular_doc_missing`')),
      [contains('`specstone new <type>`')],
    );
    expect(_oneLine(_pluginText(file)), contains(_specCodeTarget));
  });

  test("goal-move.md repoints PROJECT's own goal links in its drop write", () {
    final drop = _oneLine(
      _sectionOf(
        _pluginText(_goalMove),
        '3. Drop the moved blocks, then repoint',
      ),
    );
    const own =
        'point each `#pg-…` link PROJECT keeps to a moved goal at '
        '`GOAL.md#pg-…`';
    const section =
        'once the goals section drops, each link PROJECT keeps to it at '
        '`GOAL.md`';
    final at = drop.indexOf(own);
    expect(at, isNonNegative);
    expect(drop.indexOf(section, at), isNonNegative);
    expect(drop, contains('`refs` lists no link of PROJECT to itself'));
    expect(at, lessThan(drop.indexOf('run `specstone set --batch')));
    final refs = drop.substring(drop.indexOf('Run `specstone refs project`'));
    expect(refs, isNot(contains('in-file')));
    expect(refs, contains('A link to a kept goal keeps its target.'));
  });
}

/// The glossary-move reference of bootstrap-prd, under the plugin folder.
const _glossaryMove = 'specstone-bootstrap-prd/references/glossary-move.md';

/// The commands of the glossary move, in the order its steps run them.
const _glossaryMoveCommands = [
  'specstone new glossary',
  'specstone get glossary:glossary --json',
  'specstone set glossary:glossary --title --base <hash>',
  'specstone set glossary:glossary#terms --base <hash>',
  'set --batch',
  'specstone refs project',
];

void _glossaryMoveTests() {
  test('f08/us05/fr01/e51, e57: bootstrap-prd procedure routes the glossary '
      'move in the one singular_doc_missing row and copies no step', () {
    const file = 'specstone-bootstrap-prd/references/procedure.md';
    final pointers = _findingRows(file)
        .where((line) => line.contains('`singular_doc_missing`'))
        .toList();
    expect(pointers, hasLength(1));
    expect(
      pointers.single,
      allOf(
        contains('`goal-move.md`'),
        contains("PROJECT's goals or glossary section |"),
        contains('`glossary-move.md`'),
        contains('`prds/GLOSSARY.md`'),
      ),
    );
    final text = _pluginText(file);
    for (final step in ['new glossary', 'glossary:glossary']) {
      expect(text, isNot(contains(step)), reason: step);
    }
  });

  test('f08/us05/fr01/e52, e54, e56: glossary-move.md states the commands in '
      'step order and names no item ID or doc link', () {
    final text = _oneLine(_pluginText(_glossaryMove));
    var previous = -1;
    for (final command in _glossaryMoveCommands) {
      final at = text.indexOf(command);
      expect(at, greaterThan(previous), reason: command);
      previous = at;
    }
    expect(RegExp(r'\bE\d\d\b').hasMatch(text), isFalse);
    expect(RegExp(r'\]\([^)]*\b(?:prds|specs)/').hasMatch(text), isFalse);
  });

  test('f08/us05/fr01/e51, e52, e53, e55, e56: glossary-move.md asks the '
      'Owner nothing, writes held entries first, keeps a held term, and '
      'states each link rule', () {
    final text = _oneLine(_pluginText(_glossaryMove));
    for (final rule in [
      'Ask the Owner nothing.',
      'its leading `**…**` span, trimmed, compared with case ignored',
      'An item with no leading bold span has no term and always moves.',
      'whose term the glossary doc already holds',
      'stays in PROJECT, never renamed',
      'List it once under open questions.',
      'first the entries it already held, verbatim and in place,',
      "then the moved ones in PROJECT's order",
      'never shortened',
      '`item_over_limit`',
      'gains `PROJECT.md` as its path, its anchor unchanged',
      'links to `GLOSSARY.md` with no anchor',
      'A link with a path keeps it.',
      'also point each `#domain-glossary` link PROJECT keeps at `GLOSSARY.md`',
      'A glossary doc already there takes the same retitle',
      'stop there: its `terms` section stays empty, and no entry moves.',
      'and the glossary section once no entry stays in it',
      'While an entry stays in the section, each link to it stays',
      'a link to another heading of PROJECT,',
      'or to PROJECT with no anchor, stays',
      "Write a spec doc's link in the code target its DocPath names.",
      'Leave the link of an untyped file',
    ]) {
      expect(text, contains(rule), reason: rule);
    }
    expect(text, contains('When the batch also runs the goal move, finish'));
    expect(
      text.indexOf('also point each `#domain-glossary` link PROJECT keeps'),
      lessThan(text.indexOf('run `specstone set --batch')),
    );
  });

  test("f08/us05/fr01/e39: goal-move.md's other-DocPath step leaves "
      'prds/GLOSSARY.md to glossary-move.md', () {
    final step = _oneLine(
      _sectionOf(_pluginText(_goalMove), '1. A missing singular doc'),
    );
    expect(
      step,
      contains('- **`prds/GLOSSARY.md`:** `glossary-move.md` takes it.'),
    );
    expect(step, contains('- **Any other DocPath**, such as the features'));
  });

  test('f08/us05/fr01/e19, e58, e59: bootstrap-prd SKILL.md names the goal '
      'and glossary docs among the skeletons and stops a round on a glossary '
      'section a move kept an entry in', () {
    final text = _pluginText('specstone-bootstrap-prd/SKILL.md');
    final handOff = _oneLine(_sectionOf(text, '2. Hand off in batches'));
    expect(
      handOff,
      contains('names the project, goal, glossary, features, and gnfr docs'),
    );
    expect(handOff, contains('its glossary section asks the Owner nothing.'));
    final after = _sectionOf(text, '3. After the reports');
    final item = _oneLine(
      after.substring(after.indexOf('\n5. '), after.indexOf('\n6. ')),
    );
    final goals = item.indexOf(
      "the `section_undeclared` on PROJECT's goals section after a goal move "
      'kept a goal there,',
    );
    expect(goals, isNonNegative);
    final glossary = item.indexOf(
      'the one on its glossary section after a glossary move kept an entry '
      'there,',
    );
    expect(glossary, greaterThan(goals));
    expect(glossary, lessThan(item.indexOf('or it waits on')));
    expect(
      item,
      contains(
        'no batch holds that goals finding, no batch holds that glossary '
        'finding, and no question',
      ),
    );
    final answers = _oneLine(
      after.substring(after.indexOf('\n3. '), after.indexOf('\n4. ')),
    );
    expect(
      answers,
      contains(
        'a goal that a goal move kept in PROJECT, or an entry that a glossary '
        'move kept there, without asking it',
      ),
    );
  });

  test('f08/us05/fr01/e41, e59: bootstrap-prd procedure step 6 titles the '
      'goal and glossary docs per their guides whenever the title differs', () {
    final step = _oneLine(
      _sectionOf(
        _pluginText('specstone-bootstrap-prd/references/procedure.md'),
        '6. Fill the skeletons, then ask for approval',
      ),
    );
    expect(
      step,
      contains(
        "Set a goal or glossary doc's title to its guide's with `--title` "
        'when it differs.',
      ),
    );
  });

  test(
    "glossary-move.md points a carried entry's link to a goal the batch's "
    'goal move moved, or to the goals section it dropped, at the goal doc',
    () {
      final move = _oneLine(
        _sectionOf(_pluginText(_glossaryMove), '2. Move each entry'),
      );
      const moved =
          "one to a goal the batch's goal move moved (`#pg-…`) links to "
          '`GOAL.md#pg-…`, its anchor unchanged';
      const dropped =
          'one to the goals section that move dropped links to `GOAL.md` with '
          'no anchor';
      final at = move.indexOf(moved);
      expect(at, isNonNegative);
      expect(move.indexOf(dropped, at), isNonNegative);
      expect(
        move,
        contains('gains `PROJECT.md` as its path, its anchor unchanged'),
      );
      expect(move, contains('A link with a path keeps it.'));
    },
  );
}

const _runPlanSkill = 'agent_plugin/plan_approved_stories/run_plan_skill';
const _writePlan = 'agent_plugin/plan_approved_stories/write_grounded_plan';

/// The plan skill and the plan agent, under the plugin folder.
const _planSkill = 'specstone-plan-sdd/SKILL.md';
const _planAgent = 'specstone-plan-engineer.md';

/// [_planAgent] by the path the plan skill's runner reads it from.
const _planAgentPath = '../../agents/specstone-plan-engineer.md';

/// The lead and source 1 of the plan agent's `## Ground`, as the plan-sdd
/// design's ground ruling words them, cut at line width.
const _groundLead =
    'Read sources in this order; read a later source only for what the '
    'earlier ones leave out.';
const _groundSpecstone =
    '1. Specstone, always first: `specstone context <story> --for implement '
    '--out` for each story the plan builds. The bundle holds the story, its '
    'FRs, NFR overrides, and specs (ARCHITECTURE, API, DOMAIN, TECH_STACK). '
    'Never open a doc file by path.';

/// The line between sources 1 and 2: the plan-sdd design's line for a target
/// that is no story, opening with a capital where the design's colon let it
/// open on a lowercase word.
const _groundNonStoryTarget =
    'For a target that is no story, an NFR or a spec doc, `specstone context '
    '<target> --for implement --out` on that doc itself. An FR target grounds '
    "through its story's step-1 call, so "
    'a task citing a story and its FRs grounds once.';

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
      'specstone-plan-engineer as the dispatch file gives, with a report: file '
      'under the reports folder, shows the Report: line, follows the agent '
      "file itself, follows the Owner's pick, and names no plan mode", () {
    final text = _oneLine(_pluginText(_planSkill));
    for (final point in [
      '`specstone-plan-engineer`',
      '`../specstone-expert-sdd/references/dispatch.md`',
      '`report:`',
      '`<folder>/reports/plan-engineer.plan.<XXXXXX>.md`',
      '`Report:`',
      '`$_planAgentPath`',
      "follow it and hand it the plan's path",
    ]) {
      expect(text, contains(point), reason: point);
    }
    expect(text, isNot(contains('mode: plan')));
    expect(text, isNot(contains('`Agent` tool')));
    expect(text, isNot(contains('`Skill`')));
    expect(text, isNot(contains('rung')));
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
      '`specstone-sync-sdd`',
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
      'plan-engineer name only the context and check commands it runs and '
      'the set command a tests-line step gives the implementer', () {
    final agent = _pluginText(_planAgent);
    final sections =
        '${_sectionOf(agent, 'Ground')}\n${_sectionOf(agent, 'Workflow')}';
    expect(cliCommands(sections).toSet(), {'context', 'check', 'set'});
    expect(cliCommands(_sectionOf(agent, 'Ground')).toSet(), {
      'context',
    }, reason: 'the Ground section names no write command');
    final testsLine = RegExp(
      r'^ +- \*\*Tests line\*\*.*(?:\n {5}.*)*',
      multiLine: true,
    ).firstMatch(sections)?[0];
    expect(testsLine, isNotNull);
    expect(cliCommands(testsLine!).toSet(), {'set'});
    expect(cliCommands(sections.replaceFirst(testsLine, '')).toSet(), {
      'context',
      'check',
    }, reason: 'only the tests-line step names set');
  });

  test('plan-engineer has each task that adds or moves a '
      "test for an FR write a step that sets that FR's tests line", () {
    expect(
      _oneLine(_sectionOf(_pluginText(_planAgent), 'Workflow')),
      contains(
        '- **Tests line**: a task that adds or moves a test for an FR writes '
        "out a step that sets that FR's `tests` line in its target's record: "
        '`specstone set implementation:<feature> --field tests`, with '
        '`--target <code target>` when one is given. The sync writes no new '
        '`tests` line.',
      ),
    );
  });

  test('the last task of a plan runs the specstone-sync-sdd skill with '
      'no path list and carries no read line', () {
    final workflow = _oneLine(_sectionOf(_pluginText(_planAgent), 'Workflow'));
    expect(
      workflow,
      contains(
        "The plan's last task runs the `specstone-sync-sdd` skill with no path "
        'list; it builds no doc, so it carries no read line.',
      ),
    );
    expect(workflow, isNot(contains('paths the plan changed')));
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

  test('$_runPlanSkill E17, S4: plan-sdd runs the '
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
        '**Code target:** when the list '
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

  test('$_writePlan E29: plan-engineer takes the '
      'code target as an input and carries it as --target on every Ground '
      "call and each task's read line, none when no target is given", () {
    final agent = _pluginText(_planAgent);
    expect(
      _oneLine(_sectionOf(agent, 'Input Contract')),
      contains(
        "**`code target`** (optional): `specstone-plan-sdd`'s answer, given "
        'when the project has two or more code targets',
      ),
    );
    expect(
      _oneLine(_sectionOf(agent, 'Ground')).trimRight(),
      endsWith(
        '**Code target:** with one given, '
        "every Ground `context` call and each task's read line adds "
        "`--target <code target>`, and the plan holds that target's tasks "
        'alone. With none given, add no `--target`.',
      ),
    );
    expect(
      _oneLine(_sectionOf(agent, 'Workflow')),
      contains(
        'with `--target <code target>` before `--out` when one is given, the '
        "FR's story as `<target>` for an FR",
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

  group('the ticket tools of plan-sdd', () {
    const ticketsFile = 'specstone-plan-sdd/references/tickets.md';
    String tickets() => _oneLine(_pluginText(ticketsFile));

    test('step 5 points at the tickets file once', () {
      final skill = _oneLine(_pluginText(_planSkill));
      final step = skill.substring(skill.indexOf('## 5. Ask how to run'));
      expect(step, contains('`references/tickets.md`'));
      expect(
        '`references/tickets.md`'.allMatches(skill),
        hasLength(1),
        reason: 'one pointer, no copy of the rule in the skill file',
      );
    });

    test('it finds ticket tools by their descriptions and names them to the '
        'Owner beside the run question, naming none when none qualifies', () {
      final text = tickets();
      expect(text, contains('description says it breaks work into tickets'));
      expect(text, contains('beside the run question'));
      expect(text, contains('never by a name'));
      expect(text, contains('Specstone makes no ticket'));
    });

    test('it writes a ref through set --field tasks, several refs on one item '
        'included', () {
      final text = tickets();
      expect(text, contains('specstone set <type>:<name> --field tasks'));
      expect(text, contains('`bases.fields.tasks`'));
      expect(text, contains('`<item>:<task>`'));
      expect(text, contains('`<task>` alone for the whole doc'));
      expect(text, contains('One item takes several refs'));
      expect(text, contains('Write the whole list as YAML `- <entry>` lines'));
      expect(text, contains('Quote an entry YAML reads as a comment'));
      expect(text, contains('`- "#123"`'));
    });

    test('it has the work commits name the task id and the finishing commit '
        'close it as Closes <task>', () {
      final text = tickets();
      expect(text, contains('Name the task id in the message of each commit'));
      expect(text, contains('`Closes <task>`'));
      expect(text, contains('finishes'));
    });

    test('it names the CLI commands the shipped CLI has, no other plugin, '
        'and stays within 1,500 est. tokens', () {
      bool ofThisFile(String problem) => problem.startsWith('$ticketsFile:');
      expect(oversizedSkillFiles(contentFiles()).where(ofThisFile), isEmpty);
      expect(
        unknownCliNames(
          contentFiles(),
          SpecstoneCommandRunner(),
        ).where(ofThisFile),
        isEmpty,
      );
      expect(
        cliCommands(_pluginText(ticketsFile)),
        containsAll(['get', 'set']),
      );
      expect(
        _shippedOtherPluginSkills().where(
          (problem) => problem.startsWith('specstone-plan-sdd/'),
        ),
        isEmpty,
      );
    });
  });

  test('$_runPlanSkill, $_writePlan: neither plan-sdd nor plan-engineer names '
      "another plugin's skill", () {
    for (final file in [_planSkill, _planAgent]) {
      final shipped = File.fromUri(agentAssetsRoot().uri.resolve(file));
      expect(shipped.existsSync(), isTrue, reason: '$file is missing');
    }
    expect(
      _shippedOtherPluginSkills().where(
        (problem) =>
            problem.startsWith('specstone-plan-sdd/') ||
            problem.startsWith('$_planAgent:'),
      ),
      isEmpty,
    );
  });
}

ContentFile _file(
  String path,
  String body, {
  String? frontmatter,
  bool isSkillFile = false,
}) => (
  path: path,
  body: body,
  frontmatter: frontmatter,
  isSkillFile: isSkillFile,
);

String _skillHead(String name, String description) =>
    '---\nname: $name\ndescription: $description\n---\n';

String _unresolved(String file, String span) =>
    '$file: $span names no rendered file';

AgentAsset _asset(String path, String text) => (path: path, text: text);

List<ContentFile> _rendersOf(List<AgentAsset> assets) =>
    renderedContentFiles(renderHostFilesOf(assets));

const _agentHead =
    '---\nname: specstone-a\ndescription: An agent.\ntools: Read, Grep\n---\n';

void _hostRenderTests() {
  group('host-tied text', () {
    test('a CLAUDE_ variable in a body fails naming it', () {
      expect(
        hostTiedText([
          _file(
            'specstone-x/SKILL.md',
            r'Read ${CLAUDE_PLUGIN_ROOT}/skills/a/references/b.md.',
            isSkillFile: true,
          ),
        ]),
        [r'specstone-x/SKILL.md: ${CLAUDE_PLUGIN_ROOT}'],
      );
    });

    test('a backticked host tool name in a body fails, any of the five', () {
      for (final tool in ['Skill', 'Agent', 'Write', 'Edit', 'Read']) {
        expect(
          hostTiedText([_file('specstone-a.md', 'Change it with `$tool`.')]),
          ['specstone-a.md: `$tool`'],
          reason: tool,
        );
      }
    });

    test('the tool names Grep, Glob, and Bash, a sentence opening on Read, '
        'and a fenced line pass', () {
      expect(
        hostTiedText([
          _file(
            'specstone-a.md',
            'Read the file.\nSearch it with `Grep`, `Glob`, or `Bash`.\n'
                '```\nEdit\n```\n',
          ),
        ]),
        isEmpty,
      );
    });

    test('a tools list in a Claude Code frontmatter passes', () {
      final files = _rendersOf([
        _asset('specstone-a.md', '${_agentHead}Follow the steps.\n'),
      ]);
      expect(
        files.map((file) => file.frontmatter),
        contains(contains('tools: Read, Grep')),
        reason: 'the Claude Code render keeps the tools',
      );
      expect(hostTiedText(files), isEmpty);
    });

    test('a path of the Claude Code skills folder passes in a .claude/ render '
        'and fails in every other file', () {
      final files = [
        ..._rendersOf([
          _asset(
            'specstone-a.md',
            '${_agentHead}Read `.agents/skills/specstone-x/SKILL.md`.\n',
          ),
        ]),
        _file('specstone-b.md', 'Read `.claude/skills/specstone-x/SKILL.md`.'),
        _file(
          '.codex/agents/specstone-b.toml',
          'Read `.claude/skills/specstone-x/SKILL.md`.',
        ),
        _file(
          '.claude/agents/specstone-b.md',
          'Read `.claude/skills/specstone-x/SKILL.md`.',
        ),
      ];
      expect(hostTiedText(files), [
        '.codex/agents/specstone-b.toml: .claude/skills/',
        'specstone-b.md: .claude/skills/',
      ]);
    });

    test('a render that fails names its own path while the others pass', () {
      final files = _rendersOf([
        _asset(
          'specstone-a.md',
          '${_agentHead}Read `.claude/skills/specstone-x/SKILL.md`.\n',
        ),
      ]);
      expect(hostTiedText(files), [
        '.agents/agents/specstone-a.md: .claude/skills/',
        '.codex/agents/specstone-a.toml: .claude/skills/',
        '.cursor/agents/specstone-a.md: .claude/skills/',
      ]);
      expect(
        hostTiedText([
          _file(
            '.cursor/agents/specstone-a.md',
            r'Read ${CLAUDE_PLUGIN_ROOT}/skills/x/SKILL.md.',
          ),
        ]),
        [r'.cursor/agents/specstone-a.md: ${CLAUDE_PLUGIN_ROOT}'],
      );
    });

    test('a Codex file holds its developer_instructions value unescaped, as '
        'the Cursor file holds the body', () {
      const body = 'Quote "a" and \\b, then `specstone check`.\n\ttab\n';
      final files = _rendersOf([_asset('specstone-a.md', '$_agentHead$body')]);
      ContentFile at(String path) =>
          files.singleWhere((file) => file.path == path);

      expect(at('.codex/agents/specstone-a.toml').body, body);
      expect(at('.cursor/agents/specstone-a.md').body, body);
      expect(at('.codex/agents/specstone-a.toml').frontmatter, isNotNull);
    });
  });

  group('skill head', () {
    test('a name other than its folder fails naming the SKILL.md', () {
      expect(
        skillHeadProblems([
          _file(
            'specstone-read-sdd/SKILL.md',
            'Body.',
            frontmatter: _skillHead('read-sdd', 'Reads.'),
            isSkillFile: true,
          ),
        ]),
        ['specstone-read-sdd/SKILL.md: name read-sdd is not specstone-read-sdd'],
      );
    });

    test('a description of 1,100 characters fails and 1,024 passes', () {
      List<String> problemsOf(int length) => skillHeadProblems([
        _file(
          'specstone-x/SKILL.md',
          'Body.',
          frontmatter: _skillHead('specstone-x', 'a' * length),
          isSkillFile: true,
        ),
      ]);

      expect(problemsOf(1100), [
        'specstone-x/SKILL.md: description is 1100 characters, over 1024',
      ]);
      expect(problemsOf(1024), isEmpty);
    });

    test('a SKILL.md with no frontmatter fails, and a reference file and an '
        'agent file are not read', () {
      expect(
        skillHeadProblems([
          _file('specstone-x/SKILL.md', 'Body.', isSkillFile: true),
          _file('specstone-x/references/a.md', 'Body.', isSkillFile: true),
          _file('specstone-a.md', 'Body.'),
        ]),
        ['specstone-x/SKILL.md: no name'],
      );
    });
  });

  group('relative paths', () {
    final assets = [
      _asset('specstone-x/SKILL.md', _skillHead('specstone-x', 'Skill.')),
      _asset('specstone-y/SKILL.md', _skillHead('specstone-y', 'Skill.')),
      _asset('specstone-y/references/y.md', 'Reference.\n'),
      _asset('specstone-a.md', '${_agentHead}Agent.\n'),
    ];

    List<String> problemsOf(Map<String, String> changed) => unresolvedPaths(
      _rendersOf([
        for (final asset in assets)
          _asset(asset.path, changed[asset.path] ?? asset.text),
      ]),
    );

    test('a reference file that names a sibling skill from the wrong depth '
        'fails in each skill folder, and the right depth passes', () {
      final withReference = [
        ...assets,
        _asset('specstone-x/references/x.md', 'See `../specstone-y/SKILL.md`.'),
      ];
      expect(unresolvedPaths(_rendersOf(withReference)), [
        _unresolved(
          '.agents/skills/specstone-x/references/x.md',
          '../specstone-y/SKILL.md',
        ),
        _unresolved(
          '.claude/skills/specstone-x/references/x.md',
          '../specstone-y/SKILL.md',
        ),
      ]);
      expect(
        unresolvedPaths(
          _rendersOf([
            ...assets,
            _asset(
              'specstone-x/references/x.md',
              'See `../../specstone-y/references/y.md`.',
            ),
          ]),
        ),
        isEmpty,
      );
    });

    test(
      'a skill names an agent file by the path both agent folders share',
      () {
        expect(
          problemsOf({
            'specstone-x/SKILL.md':
                '${_skillHead('specstone-x', 'Skill.')}Follow '
                '`../../agents/specstone-a.md`.',
          }),
          isEmpty,
        );
        expect(
          problemsOf({
            'specstone-x/SKILL.md':
                '${_skillHead('specstone-x', 'Skill.')}Follow '
                '`../../agents/specstone-b.md`.',
          }),
          [
            _unresolved(
              '.agents/skills/specstone-x/SKILL.md',
              '../../agents/specstone-b.md',
            ),
            _unresolved(
              '.claude/skills/specstone-x/SKILL.md',
              '../../agents/specstone-b.md',
            ),
          ],
        );
      },
    );

    test('an agent joins a project-root path to the root of its render', () {
      expect(
        problemsOf({
          'specstone-a.md':
              '${_agentHead}Read `.agents/skills/specstone-y/SKILL.md`.\n',
        }),
        isEmpty,
      );
      expect(
        problemsOf({
          'specstone-a.md':
              '${_agentHead}Read `.agents/skills/specstone-z/SKILL.md`.\n',
        }),
        [
          _unresolved(
            '.agents/agents/specstone-a.md',
            '.agents/skills/specstone-z/SKILL.md',
          ),
          _unresolved(
            '.claude/agents/specstone-a.md',
            '.claude/skills/specstone-z/SKILL.md',
          ),
          _unresolved(
            '.codex/agents/specstone-a.toml',
            '.agents/skills/specstone-z/SKILL.md',
          ),
          _unresolved(
            '.cursor/agents/specstone-a.md',
            '.agents/skills/specstone-z/SKILL.md',
          ),
        ],
      );
    });

    test('a project doc path is not read, whatever its first folder', () {
      expect(
        problemsOf({
          'specstone-x/SKILL.md':
              '${_skillHead('specstone-x', 'Skill.')}See `specs/x/y.md` and '
              '`docs/a/b.md`.',
        }),
        isEmpty,
      );
    });

    test('a placeholder, a name with no folder, and a path that climbs out of '
        'the root are read as written', () {
      expect(
        problemsOf({
          'specstone-a.md':
              '${_agentHead}Write `<folder>/reports/a.<XXXXXX>.md`, then '
              '`CLAUDE.md`, not `docs/x y.md`.\n',
        }),
        isEmpty,
      );
      expect(
        problemsOf({'specstone-a.md': '${_agentHead}Read `../../x/a.md`.\n'}),
        hasLength(4),
      );
    });
  });

  group('shipped files', () {
    test('the sources and every host render are read', () {
      final paths = contentFiles().map((file) => file.path);
      expect(
        paths,
        containsAll([
          'specstone-read-sdd/SKILL.md',
          'specstone-sdd-reader.md',
          '.claude/skills/specstone-read-sdd/SKILL.md',
          '.agents/skills/specstone-read-sdd/SKILL.md',
          '.claude/agents/specstone-sdd-reader.md',
          '.cursor/agents/specstone-sdd-reader.md',
          '.codex/agents/specstone-sdd-reader.toml',
          '.agents/agents/specstone-sdd-reader.md',
        ]),
      );
    });

    test('a Codex file holds the body its Cursor file holds', () {
      final files = {for (final file in contentFiles()) file.path: file};
      for (final path in files.keys.where((p) => p.endsWith('.toml'))) {
        final cursor = path
            .replaceFirst('.codex/', '.cursor/')
            .replaceFirst('.toml', '.md');
        expect(files[path]!.body, files[cursor]!.body, reason: path);
      }
    });

    test('each SKILL.md names its folder and holds a description within 1,024 '
        'characters', () {
      expect(skillHeadProblems(contentFiles()), isEmpty);
    });
  });
}

const _dispatchReference = 'specstone-expert-sdd/references/dispatch.md';

/// The `specstone-expert-sdd` files, in the source and in each skill render.
List<ContentFile> _expertSddFiles() => [
  for (final file in contentFiles())
    if (file.path.contains('specstone-expert-sdd/')) file,
];

void _dispatchReferenceTests() {
  group('the dispatch rungs', () {
    test('dispatch.md sits in the source and in both skill renders', () {
      final paths = _expertSddFiles().map((file) => file.path);
      expect(
        paths,
        containsAll([
          _dispatchReference,
          '.claude/skills/$_dispatchReference',
          '.agents/skills/$_dispatchReference',
        ]),
      );
    });

    test('dispatch.md holds the named rung, the generic rung, and the '
        'main-session rung, in that order', () {
      final text = _pluginText(_dispatchReference);
      final rungs = [
        for (final heading in [
          '## Named agent',
          '## Generic subagent',
          '## Main session',
        ])
          text.indexOf('\n$heading\n'),
      ];
      expect(rungs, everyElement(isNonNegative));
      expect([...rungs]..sort(), rungs);
    });

    test('the rungs name the host lists no such agent, no subagent, the '
        'agent file from the skill, the failed dispatch, and the audit that '
        "is no fresh reader's", () {
      final text = _oneLine(_pluginText(_dispatchReference));
      for (final point in [
        '`specstone-sdd-engineer`',
        '`specstone-sdd-reader`',
        '`specstone-plan-engineer`',
        'the host lists no such agent',
        'no subagent',
        '`../../agents/specstone-<agent>.md`',
        'a dispatch that fails',
        "not a fresh reader's",
        '`Report:` line',
      ]) {
        expect(text, contains(point), reason: point);
      }
    });

    test('the specstone-expert-sdd files name no host tool, no CLAUDE_ '
        "variable, no other host's skills folder, no specstone:<name> skill, "
        'and every relative path resolves', () {
      final files = _expertSddFiles();
      expect(hostTiedText(files), isEmpty);
      expect(otherPluginSkillNames(files, shippedDocTypes()), isEmpty);
      expect(
        unresolvedPaths(contentFiles())
            .where((problem) => problem.contains('specstone-expert-sdd/')),
        isEmpty,
      );
    });
  });
}

const _groundInitUpdateFiles = [
  'specstone-read-sdd/',
  'specstone-sdd-reader.',
  'specstone-init/',
  'specstone-update-sdd/',
];

/// The grounding, reader, init, and update files, in the source and in each
/// host's render.
List<ContentFile> _groundInitUpdateContent() => [
  for (final file in contentFiles())
    if (_groundInitUpdateFiles.any(file.path.contains)) file,
];

void _groundInitUpdateTests() {
  group('the grounding, init, and update files', () {
    test('each of the four reaches the source and every host render', () {
      final paths = _groundInitUpdateContent().map((file) => file.path);
      expect(paths, hasLength(3 + 5 + 3 + 3));
    });

    test("they name no host tool, no CLAUDE_ variable, no other host's skills "
        'folder, no specstone:<name> skill, and every relative path '
        'resolves', () {
      final files = _groundInitUpdateContent();
      expect(hostTiedText(files), isEmpty);
      expect(otherPluginSkillNames(files, shippedDocTypes()), isEmpty);
      expect(
        unresolvedPaths(contentFiles())
            .where((problem) => _groundInitUpdateFiles.any(problem.contains)),
        isEmpty,
      );
    });

    test('read-sdd takes the dispatch rungs from expert-sdd and names the '
        'reader', () {
      final skill = _oneLine(_pluginText('specstone-read-sdd/SKILL.md'));
      expect(skill, contains('`specstone-sdd-reader`'));
      expect(
        skill,
        contains('`../specstone-expert-sdd/references/dispatch.md`'),
      );
      expect(skill, isNot(contains('`Agent` tool')));
      expect(skill, isNot(contains('rung')));
    });

    test(
      'sdd-reader runs no specstone folder and takes the saved-file paths as '
      'given',
      () {
        final reader = _oneLine(_pluginText('specstone-sdd-reader.md'));
        expect(reader, isNot(contains('specstone folder')));
        expect(reader, contains('Use them as given; join no folder to them.'));
        expect(reader, contains('and no other command.'));
      },
    );

    test("sdd-reader reads through the host's file read and stays read-only "
        'by its own text', () {
      final reader = _oneLine(_pluginText('specstone-sdd-reader.md'));
      expect(reader, contains("read them with the host's file read"));
      expect(
        _sectionOf(_pluginText('specstone-sdd-reader.md'), 'Scope Boundaries'),
        contains(
          "- Write or edit any file, by the host's file write or a shell "
          'redirect;',
        ),
      );
    });

    test('init and update-sdd hand over by following the next skill', () {
      final init = _oneLine(_pluginText('specstone-init/SKILL.md'));
      final update = _oneLine(_pluginText('specstone-update-sdd/SKILL.md'));
      expect(init, contains('follow the `specstone-expert-sdd` skill'));
      expect(init, contains('follow the `specstone-brainstorming-sdd` skill'));
      expect(update, contains('Follow the `specstone-expert-sdd` skill'));
      expect(update, contains('follow the `specstone-sync-sdd` skill instead'));
      expect(
        update,
        contains('follow the `specstone-brainstorming-sdd` skill instead'),
      );
    });

    test('each of the four skill files stays within 1,500 est. tokens', () {
      expect(oversizedSkillFiles(_groundInitUpdateContent()), isEmpty);
    });
  });
}

const _brainstormFiles = [
  'specstone-brainstorming-sdd/',
  'specstone-sdd-engineer.',
];

/// The brainstorm skill, its six references, and the engineer, in the source
/// and in each host's render.
List<ContentFile> _brainstormContent() => [
  for (final file in contentFiles())
    if (_brainstormFiles.any(file.path.contains)) file,
];

void _brainstormTests() {
  group('the brainstorm skill family and the engineer', () {
    test('each of the seven reaches the source and every host render', () {
      final paths = _brainstormContent().map((file) => file.path);
      expect(paths, hasLength(8 + 7 + 7 + 4));
    });

    test("they name no host tool, no CLAUDE_ variable, no other host's skills "
        'folder, no specstone:<name> skill, and every relative path '
        'resolves', () {
      final files = _brainstormContent();
      expect(hostTiedText(files), isEmpty);
      expect(otherPluginSkillNames(files, shippedDocTypes()), isEmpty);
      expect(
        unresolvedPaths(contentFiles())
            .where((problem) => _brainstormFiles.any(problem.contains)),
        isEmpty,
      );
    });

    test('the skill takes the dispatch rungs from expert-sdd and names each '
        "mode's procedure", () {
      final skill = _oneLine(
        _pluginText('specstone-brainstorming-sdd/SKILL.md'),
      );
      expect(
        skill,
        contains('`../specstone-expert-sdd/references/dispatch.md`'),
      );
      expect(skill, isNot(contains('`Agent` tool')));
      expect(skill, isNot(contains('rung')));
      for (final mode in ['author', 'design', 'audit']) {
        expect(skill, contains('`references/$mode.md`'), reason: mode);
      }
    });

    test('the skill hands the approved drafts over by following the plan '
        'skill', () {
      final skill = _oneLine(
        _pluginText('specstone-brainstorming-sdd/SKILL.md'),
      );
      expect(skill, contains('follow the `specstone-plan-sdd` skill'));
      expect(skill, isNot(contains('through `Skill`')));
    });

    test(
      'the references reach their siblings by paths from their own folder',
      () {
        expect(
          _pluginText('specstone-brainstorming-sdd/references/design.md'),
          contains('`source.md`'),
        );
        expect(
          _pluginText('specstone-brainstorming-sdd/references/rounds.md'),
          contains('`design.md`'),
        );
        expect(
          _pluginText('specstone-brainstorming-sdd/SKILL.md'),
          contains('`references/source.md`'),
        );
      },
    );

    test('the engineer has no skills key and follows expert-sdd by one body '
        'line at its path under .agents/skills', () {
      final text = _pluginText('specstone-sdd-engineer.md');
      final head = text.substring(0, text.indexOf('\n---\n', 4));
      expect(head, isNot(contains('\nskills:')));
      expect(
        _oneLine(_sectionOf(text, 'Bootstrap')),
        contains(
          'follow the `specstone-expert-sdd` skill, at '
          '`.agents/skills/specstone-expert-sdd/SKILL.md`',
        ),
      );
      for (final name in [
        'sync-sdd/references/procedure.md',
        'bootstrap-prd/references/procedure.md',
        'bootstrap-spec/references/procedure.md',
        'expert-sdd/references/size-fix.md',
        'expert-sdd/references/repeats.md',
        'brainstorming-sdd/references/author.md',
        'brainstorming-sdd/references/audit.md',
      ]) {
        expect(
          text,
          contains('`.agents/skills/specstone-$name`'),
          reason: name,
        );
      }
    });

    test('the skill picks a brainstorm skill by the files that carry the '
        "project's instructions", () {
      final skill = _oneLine(
        _pluginText('specstone-brainstorming-sdd/SKILL.md'),
      );
      expect(
        skill,
        contains(
          "the project's instruction file (`CLAUDE.md`, `AGENTS.md`) names",
        ),
      );
    });

    test('each of the six skill files stays within 1,500 est. tokens', () {
      expect(oversizedSkillFiles(_brainstormContent()), isEmpty);
    });
  });
}

/// The skill and agent files that do design work with a saved bundle: the
/// design brief's runner, its readers, and the audit.
const _designWorkFiles = [
  'specstone-read-sdd/SKILL.md',
  'specstone-brainstorming-sdd/SKILL.md',
  'specstone-brainstorming-sdd/references/audit.md',
  'specstone-brainstorming-sdd/references/source.md',
  'specstone-brainstorming-sdd/references/rounds.md',
  'specstone-sdd-engineer.md',
];

void _designBriefTests() {
  group('the design document the runner writes', () {
    String skillStep(String heading) => _oneLine(
      _sectionOf(_pluginText('specstone-brainstorming-sdd/SKILL.md'), heading),
    );
    String design() => _oneLine(
      _pluginText('specstone-brainstorming-sdd/references/design.md'),
    );
    String designSection(String heading) => _oneLine(
      _sectionOf(
        _pluginText('specstone-brainstorming-sdd/references/design.md'),
        heading,
      ),
    );
    String rounds() => _oneLine(
      _pluginText('specstone-brainstorming-sdd/references/rounds.md'),
    );

    test('step 3 has the runner write the one design document from its saved '
        "files and the Owner's answers, with no dispatch and no brief", () {
      final step = skillStep('3. Write the document');

      expect(step, contains('Write the one design document yourself'));
      expect(step, contains('`references/design.md`'));
      expect(
        step,
        contains("from step 1's saved files and the Owner's answers"),
      );
      expect(step, contains(_designPath));
      expect(step, contains('Dispatch nothing for it.'));
      expect(step, isNot(contains('mode: design')));
      expect(step.toLowerCase(), isNot(contains('brief')));
      expect(step, isNot(contains('rerun')));
      expect(step, isNot(contains('line range')));
    });

    test('step 3 names a refused design path as an open question written at '
        "the Owner's new path", () {
      expect(
        skillStep('3. Write the document'),
        contains(
          "A refused path is an open question; write at the Owner's new path.",
        ),
      );
    });

    test('step 4 names the report folder once and runs no context call and '
        'writes no brief before a dispatch', () {
      final step = skillStep('4. Write the drafts, then audit them');

      expect(
        step,
        contains(
          'take `<folder>` the path `specstone folder` prints, run once',
        ),
      );
      expect(
        step,
        contains('passes `report:` `<folder>/reports/sdd-engineer.<mode>'),
      );
      expect(
        step,
        contains(
          'Write no brief and run no `context` call again on a target already '
          'grounded before a dispatch; a claim your saved files do not ground '
          'is an open question of the document.',
        ),
      );
    });

    test('no step of the skill dispatches design mode or writes a brief', () {
      final skill = _oneLine(
        _pluginText('specstone-brainstorming-sdd/SKILL.md'),
      );

      expect(skill, isNot(contains('mode: design')));
      expect(skill, isNot(contains('design.brief')));
      expect(skill, isNot(contains('design mode')));
    });

    test('design.md takes the Owner answers and the saved files as its '
        'inputs', () {
      final inputs = designSection('1. Check the inputs');

      expect(
        inputs,
        contains(
          "the Owner's approved answers in the conversation (decisions in the "
          "Owner's words, rulings, the approach picked, open questions)",
        ),
      );
      expect(
        inputs,
        contains('also follow `## Map the source` in `source.md`'),
      );
      expect(
        inputs,
        contains(
          'the saved bundle files of your `context --for design --out` calls',
        ),
      );
      expect(design(), isNot(contains('the brief')));
    });

    test('design.md runs no get, search, or refs, and no context', () {
      expect(
        designSection('2. Ground each claim'),
        contains('Run no `get`, no `search`, and no `refs` for a doc'),
      );
      expect(
        _contextCalls(
          _pluginText('specstone-brainstorming-sdd/references/design.md'),
        ),
        isEmpty,
      );
    });

    test('design.md has a claim neither the saved files nor an answer grounds '
        'become an open question', () {
      expect(
        designSection('2. Ground each claim'),
        contains('A claim neither grounds is an open question.'),
      );
    });

    test('design.md has the runner write at the Owner new path in place of a '
        'refused one', () {
      expect(
        designSection('2. Ground each claim'),
        contains(
          'write nothing; the path is an open question, and you write at the '
          "Owner's new path in its place",
        ),
      );
    });

    test('design.md lists each open question and each claim or code name it '
        'could not find', () {
      final tell = designSection('5. Tell the Owner');

      expect(tell, contains('each open question'));
      expect(tell, contains('each claim its saved files could not ground'));
      expect(tell, contains('each code path or symbol not found'));
    });

    test('design.md keeps the engineer report out of the design document', () {
      expect(design(), isNot(contains('`report:`')));
      expect(design(), isNot(contains("agent's")));
    });

    test('rounds.md has the runner write and amend the document itself', () {
      final text = rounds();

      expect(
        text,
        contains(
          "write the document at the Owner's new path in place of the refused "
          'one',
        ),
      );
      expect(text, isNot(contains('mode: design')));
      expect(text, isNot(contains('the brief')));
      expect(text, isNot(contains('design report')));
      expect(text, isNot(contains('rerun')));
      expect(text, isNot(contains('line range')));
    });

    test('the engineer runs author, sync, bootstrap, and audit, and loads no '
        'design reference', () {
      final agent = _pluginText('specstone-sdd-engineer.md');
      final description = RegExp(
        r'^description:(.*)$',
        multiLine: true,
      ).firstMatch(agent)!.group(1)!;

      expect(
        _oneLine(_sectionOf(agent, 'Input Contract')),
        contains('`author`, `sync`, `bootstrap`, or `audit`'),
      );
      expect(description, contains('`author`'));
      expect(description, contains('`audit`'));
      expect(description, isNot(contains('`design`')));
      expect(
        _sectionOf(agent, 'On-Demand Loads'),
        isNot(contains('references/design.md')),
      );
    });

    test('a design mode dispatch gets the unknown-mode stop naming the '
        'runner skill', () {
      final stop = _designStop();

      expect(stop, contains('`design`'));
      expect(stop, contains('`specstone-brainstorming-sdd`'));
      expect(stop, contains('`specstone-plan-sdd`'));
    });

    test('the engineer file names design mode only in its unknown-mode '
        'stop', () {
      final text = _pluginText('specstone-sdd-engineer.md');
      final rest = text.replaceFirst(_designStopBullet(), '');

      expect(rest, isNot(contains('mode: design')));
      for (final stale in [
        '`design`',
        'design mode',
        'design-mode',
        'design dispatch',
        'In design',
      ]) {
        expect(rest, isNot(contains(stale)), reason: stale);
      }
    });

    test('no plugin file names a design brief file', () {
      for (final file in agentSourceFiles(agentAssetsRoot())) {
        expect(
          file.readAsStringSync(),
          isNot(contains('sdd-engineer.design.brief')),
          reason: shippedPathOf(file),
        );
      }
      expect(
        _agentFileSpan.hasMatch(
          '<folder>/reports/sdd-engineer.design.brief.<XXXXXX>.md',
        ),
        isFalse,
      );
      expect(
        _agentFileSpan.hasMatch(
          '<folder>/reports/sdd-engineer.design.source.<XXXXXX>.md',
        ),
        isTrue,
      );
    });

    test('the audit sends a behavior line to the runner design amend', () {
      final audit = _oneLine(
        _pluginText('specstone-brainstorming-sdd/references/audit.md'),
      );

      expect(
        audit,
        contains("a `[behavior]` line goes to the runner's design amend."),
      );
      expect(audit, isNot(contains('design-mode')));
    });

    test('the Intent section stays in a few lines', () {
      final design = _oneLine(
        _pluginText('specstone-brainstorming-sdd/references/design.md'),
      );

      expect(design, contains('it advances, in a few lines.'));
    });

    test('with no brainstorm skill the skill runs the dialogue file', () {
      final skill = _oneLine(
        _pluginText('specstone-brainstorming-sdd/SKILL.md'),
      );
      final dialogue = _oneLine(
        _pluginText('specstone-brainstorming-sdd/references/dialogue.md'),
      );

      expect(skill, contains('run `references/dialogue.md`'));
      expect(skill, isNot(contains('Offer two or three approaches')));
      expect(dialogue, contains('Ask the Owner one question per message'));
      expect(
        dialogue,
        contains('Offer two or three approaches with trade-offs'),
      );
    });

    test('design grounds a newly reached doc with context --for design, '
        'never get', () {
      for (final file in _designWorkFiles) {
        expect(
          _oneLine(_pluginText(file)),
          matches(
            RegExp(
              '`(?:specstone )?context <doc> --for design --out`, '
              'never `get`',
            ),
          ),
          reason: file,
        );
      }
    });
  });
}

const _syncBootstrapFiles = [
  'specstone-sync-sdd/',
  'specstone-bootstrap-prd/',
  'specstone-bootstrap-spec/',
];

/// The sync and the two bootstrap skills, each a skill file and its
/// references, in the source and in each host's render.
List<ContentFile> _syncBootstrapContent() => [
  for (final file in contentFiles())
    if (_syncBootstrapFiles.any(file.path.contains)) file,
];

void _syncBootstrapTests() {
  group('the sync and bootstrap skills', () {
    const bootstraps = ['bootstrap-prd', 'bootstrap-spec'];

    test('each of the nine reaches the source and every host render', () {
      final paths = _syncBootstrapContent().map((file) => file.path);
      expect(paths, hasLength(9 + 9 + 9));
    });

    test("they name no host tool, no CLAUDE_ variable, no other host's skills "
        'folder, no specstone:<name> skill, and every relative path '
        'resolves', () {
      final files = _syncBootstrapContent();
      expect(hostTiedText(files), isEmpty);
      expect(otherPluginSkillNames(files, shippedDocTypes()), isEmpty);
      expect(skillHeadProblems(files), isEmpty);
      expect(
        unresolvedPaths(contentFiles())
            .where((problem) => _syncBootstrapFiles.any(problem.contains)),
        isEmpty,
      );
    });

    test('each skill takes the dispatch steps from expert-sdd and names its '
        'procedure', () {
      for (final skill in ['sync-sdd', ...bootstraps]) {
        final text = _oneLine(_pluginText('specstone-$skill/SKILL.md'));
        expect(
          text,
          contains('`../specstone-expert-sdd/references/dispatch.md`'),
          reason: skill,
        );
        expect(text, contains('`specstone-sdd-engineer`'), reason: skill);
        expect(text, contains('`references/procedure.md`'), reason: skill);
        expect(text, isNot(contains('`Agent` tool')), reason: skill);
        expect(text, isNot(contains('rung')), reason: skill);
      }
    });

    test('each bootstrap skill splits the main-session step in one line: one '
        'batch after a failed dispatch, no batch with no subagent', () {
      for (final skill in bootstraps) {
        final text = _oneLine(_pluginText('specstone-$skill/SKILL.md'));
        expect(
          text,
          contains(
            'with no subagent at all, over every finding this skill takes; '
            "after a failed dispatch, over that dispatch's one batch",
          ),
          reason: skill,
        );
      }
    });

    test('the bootstrap skills reach the size and repeats files of expert-sdd '
        'by a path from their own folder', () {
      for (final skill in bootstraps) {
        final text = _pluginText('specstone-$skill/SKILL.md');
        final procedure = _pluginText(
          'specstone-$skill/references/procedure.md',
        );
        for (final file in ['size-fix', 'repeats']) {
          expect(
            text,
            contains('../specstone-expert-sdd/references/$file.md'),
            reason: '$skill, $file',
          );
          expect(
            procedure,
            contains('../../specstone-expert-sdd/references/$file.md'),
            reason: '$skill procedure, $file',
          );
        }
      }
    });

    test('the spec bootstrap reaches the sync procedure by a path from its '
        'own folder', () {
      expect(
        _pluginText('specstone-bootstrap-spec/references/procedure.md'),
        contains('`../../specstone-sync-sdd/references/procedure.md`'),
      );
    });

    test('each of the nine skill files stays within 1,500 est. tokens', () {
      expect(oversizedSkillFiles(_syncBootstrapContent()), isEmpty);
    });

    group('the task refs file of the sync skill', () {
      String refs() =>
          _oneLine(_pluginText('specstone-sync-sdd/references/task-refs.md'));

      test('step 4.2 of the procedure points at it, and the report lists the '
          'removed tasks', () {
        final text = _pluginText('specstone-sync-sdd/references/procedure.md');
        final procedure = _oneLine(text);
        final step = procedure.substring(
          procedure.indexOf('2. Write by outcome'),
          procedure.indexOf('3. Fix each record'),
        );
        expect(step, contains('`task-refs.md`'));
        expect(
          _oneLine(_sectionOf(text, 'Report to the Owner')),
          contains('each task removed'),
        );
      });

      test('it takes the candidates from the bundle and the messages from '
          'git log, with and without a base', () {
        final text = refs();
        expect(text, contains('`context --code` bundle'));
        expect(text, contains('git log --format=%B <base>..HEAD --'));
        expect(text, contains('With none, read the messages of every commit'));
      });

      test('a mismatch and a planned entry without its behavior take no '
          'removal', () {
        expect(refs(), contains('take no removal: every ref stays'));
      });

      test('it names every closing word, both forms, and the mention rule', () {
        final text = refs();
        for (final word in [
          'close',
          'closes',
          'closed',
          'fix',
          'fixes',
          'fixed',
          'resolve',
          'resolves',
          'resolved',
        ]) {
          expect(text, contains('`$word`'), reason: word);
        }
        expect(text, contains('Keyword form'));
        expect(text, contains('Command form'));
        expect(text, contains('`done`'));
        expect(text, contains('a mention and closes nothing'));
        expect(text, contains('`Refs ENG-42`'));
      });

      test('it runs one set --remove-task, with --target for two or more '
          'targets, and waits under a pending draft', () {
        final text = refs();
        expect(text, contains('specstone set --remove-task <task>'));
        expect(text, contains('run once'));
        expect(text, contains('when the project has 2 or more code targets'));
        expect(text, contains('waiting pointer'));
        expect(text, contains('pending draft'));
        expect(text, contains('in your report to the Owner'));
      });

      test('the skill runs each waiting removal once its draft is approved, '
          'and the procedure report names its tasks and code target', () {
        final skill = _oneLine(_pluginText('specstone-sync-sdd/SKILL.md'));
        expect(
          skill,
          contains(
            'For each waiting removal, once its draft is approved, run '
            '`specstone set --remove-task <task> ...`',
          ),
        );
        expect(skill, contains('then name the removed tasks to the Owner'));
        final report = _oneLine(
          _sectionOf(
            _pluginText('specstone-sync-sdd/references/procedure.md'),
            'Report to the Owner',
          ),
        );
        expect(
          report,
          contains('its code target, and its doc and code path, or its tasks'),
        );
      });

      test('the sdd-engineer sync report names the removed tasks', () {
        final sync = _oneLine(
          _sectionOf(_pluginText('specstone-sdd-engineer.md'), 'Output Format'),
        );
        expect(sync, contains('each task whose refs the sync removed'));
      });
    });
  });
}

const _planFiles = ['specstone-plan-sdd/', 'specstone-plan-engineer.'];

/// The plan skill and the plan agent, in the source and in each host's render.
List<ContentFile> _planContent() => [
  for (final file in contentFiles())
    if (_planFiles.any(file.path.contains)) file,
];

void _planFilesTests() {
  group('the plan skill and the plan engineer', () {
    test('each of the two reaches the source and every host render', () {
      final paths = _planContent().map((file) => file.path);
      expect(
        paths,
        hasLength(3 + 4 + 4),
        reason:
            '3 source files: engineer, skill, tickets.md; 4 skill renders, '
            'the skill and tickets.md in each of 2 hosts; 4 engineer renders',
      );
    });

    test("they name no host tool, no CLAUDE_ variable, no other host's skills "
        'folder, no specstone:<name> skill, and every relative path '
        'resolves', () {
      final files = _planContent();
      expect(hostTiedText(files), isEmpty);
      expect(otherPluginSkillNames(files, shippedDocTypes()), isEmpty);
      expect(skillHeadProblems(files), isEmpty);
      expect(
        unresolvedPaths(contentFiles())
            .where((problem) => _planFiles.any(problem.contains)),
        isEmpty,
      );
    });

    test('the skill takes the dispatch steps from expert-sdd and reaches the '
        'agent file by its path from the skill', () {
      final skill = _oneLine(_pluginText(_planSkill));
      expect(
        skill,
        contains('`../specstone-expert-sdd/references/dispatch.md`'),
      );
      expect(skill, contains('`../../agents/specstone-plan-engineer.md`'));
    });

    test('the agent reads and writes files through the host and names the '
        "project's instruction file by both of its names", () {
      final agent = _oneLine(_pluginText(_planAgent));
      expect(agent, contains("with the host's file read"));
      expect(agent, contains("with the host's file write"));
      expect(
        agent,
        contains(
          "the one the project's instruction file (`CLAUDE.md`, `AGENTS.md`) "
          'names',
        ),
      );
      expect(agent, isNot(contains("the project's CLAUDE.md")));
    });

    test('the plan skill file stays within 1,500 est. tokens', () {
      expect(oversizedSkillFiles(_planContent()), isEmpty);
    });

    test('each bootstrap procedure hands its writes over by following the '
        'expert skill', () {
      for (final skill in ['bootstrap-prd', 'bootstrap-spec']) {
        expect(
          _oneLine(_pluginText('specstone-$skill/references/procedure.md')),
          contains('Follow the `specstone-expert-sdd` skill for every write'),
          reason: skill,
        );
      }
    });
  });
}

void _shippedTreeTests() {
  group('every shipped source and render', () {
    test("they name no host tool, no CLAUDE_ variable, no other host's skills "
        'folder, no specstone:<name> skill, and every skill head and '
        'relative path holds', () {
      final files = contentFiles();
      expect(hostTiedText(files), isEmpty);
      expect(otherPluginSkillNames(files, shippedDocTypes()), isEmpty);
      expect(skillHeadProblems(files), isEmpty);
      expect(unresolvedPaths(files), isEmpty);
    });
  });
}

/// A `specstone get` call whose output a shell redirect writes to a file.
final _getRedirect = RegExp(r'specstone get [^`]*\s>>?\s');

void _outAndReplaceTests() {
  test('the sdd-engineer makes its batch file with get --out and runs no get '
      'shell redirect', () {
    final text = _oneLine(_pluginText('specstone-sdd-engineer.md'));

    expect(text, contains('made by `specstone get … --out "<file>"`'));
    expect(text, isNot(matches(_getRedirect)));
  });

  test('the author procedure saves long output with --out and edits a passage '
      'with set --replace', () {
    final text = _oneLine(
      _pluginText('specstone-brainstorming-sdd/references/author.md'),
    );

    expect(text, contains('`specstone get <names> --out "<file>"`'));
    expect(text, isNot(matches(_getRedirect)));
    expect(
      text,
      contains('long `check`, `guide`, or `get` output with `--out`'),
    );
    expect(text, contains('`==> old <==`, the passage, `==> new <==`'));
    expect(
      text,
      contains('`specstone set <type>:<name>#<key> --base <hash> --replace`'),
    );
  });

  test('the read skill names --out for long output and set --replace for a '
      'passage', () {
    final text = _oneLine(_pluginText('specstone-read-sdd/SKILL.md'));

    expect(text, contains('long `check`, `guide`, or `get` output'));
    expect(text, contains('bare `--out`'));
    expect(text, contains('Change one passage with `set --replace`'));
    expect(
      text,
      contains(
        'Write no file by shell redirect, `sed -i`, `perl -pi`, or `tee`; '
        'hand edit no doc file.',
      ),
    );
  });
}

void _docLevelPointTests() {
  test('the sdd-engineer stops on a message that names no mode and writes only '
      'its report', () {
    final text = _oneLine(_pluginText('specstone-sdd-engineer.md'));

    expect(
      text,
      contains('a message that names no `mode`, a later round included'),
    );
    expect(text, contains('write only `OPEN QUESTIONS:` naming the missing'));
    expect(text, contains('asking for a fresh dispatch with it'));
    expect(
      text,
      contains('as the report and its relay block; overwrite no other file'),
    );
  });

  test('rounds dispatches every re-audit anew in audit mode with its '
      'targets', () {
    final text = _oneLine(
      _pluginText('specstone-brainstorming-sdd/references/rounds.md'),
    );

    expect(
      text,
      contains(
        "Dispatch a fresh `mode: audit` with the document's path and, as its "
        'targets',
      ),
    );
    expect(
      text,
      contains(
        'Send every re-audit so, never as a follow-up message to the agent of '
        'an earlier audit',
      ),
    );
  });

  test('design sends no design with an open doc-level point to the author and '
      'leaves code-level points to the builder', () {
    final text = _oneLine(
      _pluginText('specstone-brainstorming-sdd/references/design.md'),
    );

    expect(text, contains('such as a refusal or a name rule'));
    expect(text, contains('naming the one owner item its rule takes'));
    expect(
      text,
      contains('a design holding such a point open goes to no author'),
    );
    expect(text, contains('such as a class name, to the builder'));
    expect(text, contains('with no decision and no open question'));
  });

  test('audit checks each draft against its decision and each repoint', () {
    final text = _oneLine(
      _pluginText('specstone-brainstorming-sdd/references/audit.md'),
    );

    expect(text, contains('a draft that departs from its decision'));
    expect(text, contains("naming the draft (or the design's owner doc)"));
    expect(text, contains('a citer a size-fix move repointed or kept'));
    expect(text, contains('name the citer and the item it should link'));
  });

  test('size-fix.md gives a moved item or scenario a ready move and keeps '
      'refs repoints for keyed items and a split-off ID', () {
    final text = _oneLine(_sectionOf(_pluginText(_sizeFix), 'The order'));

    expect(
      text,
      contains(
        'An item of a `prefix_id` section or a scenario to another doc: one '
        'ready `specstone move <doc>#<ID> … --under <doc>` or '
        '`specstone move <story>#S<N> … --under <story>`, which rewrites each '
        'citer',
      ),
    );
    expect(
      text,
      contains('a keyed item, or a new ID split off inside one doc'),
    );
    expect(text, contains("`specstone refs <old item's doc>`"));
    expect(text, contains('repoint each citer that cites the moved part'));
    expect(text, contains('keep each other citer'));
  });

  test("size-fix.md's split proposal lists move feature and the scenario "
      'move in run order', () {
    final text = _oneLine(
      _sectionOf(_pluginText(_sizeFix), 'The split proposal'),
    );
    final newFeature = text.indexOf(
      'specstone new feature --parent <feature> --slug <slug>',
    );
    final moveStory = text.indexOf(
      'specstone move <story> … --under <sub-feature>',
    );
    final moveFeature = text.indexOf(
      'specstone move feature:<x> … --under <feature>',
    );
    final moveScenario = text.indexOf(
      'specstone move <story>#S<N> … --under <story>',
    );
    expect(newFeature, isNonNegative);
    expect(moveStory, greaterThan(newFeature));
    expect(moveFeature, greaterThan(moveStory));
    expect(moveScenario, greaterThan(moveFeature));
    expect(text, contains('for a feature that exists'));
    expect(text, contains('for a story past its scenario cap'));
  });
}
