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
  _procedureTests();
  _handOffTests();
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

final _frontmatterName = RegExp(r'^---\r?\n(?:.*\r?\n)*?name:\s*(\S+)');

const _procedures = <String>[
  'specstone-sync-sdd/references/procedure.md',
  'specstone-sync-sdd/references/task-refs.md',
  'specstone-bootstrap-prd/references/procedure.md',
  'specstone-bootstrap-spec/references/procedure.md',
  _goalMove,
  'specstone-brainstorming-sdd/references/author.md',
  'specstone-brainstorming-sdd/references/design.md',
  'specstone-brainstorming-sdd/references/audit.md',
];

void _procedureTests() {
  for (final procedure in _procedures) {
    test('$procedure exists', () {
      final file = File.fromUri(agentAssetsRoot().uri.resolve(procedure));
      expect(file.existsSync(), isTrue, reason: '$procedure is missing');
    });
  }
}

/// [text] with every run of whitespace, a wrapped line end included, as one
/// space.
String _oneLine(String text) => text.replaceAll(RegExp(r'\s+'), ' ');

/// The text of plugin [file] with `\n` line ends, as a Windows checkout's
/// `\r\n` would otherwise fail every multi-line match.
String _pluginText(String file) =>
    File.fromUri(agentAssetsRoot().uri.resolve(file))
        .readAsStringSync()
        .replaceAll('\r\n', '\n');

void _handOffTests() {
  test('the sdd-engineer reply names the Report line, the Findings line, and '
      'the relay block of each mode but plan', () {
    final output = _sectionOf(
      _pluginText('specstone-sdd-engineer.md'),
      'Output Format',
    );
    expect(output, contains('`Report: <path>`'));
    expect(output, contains('`Findings:`'));
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
  });

  test('the audit report splits Findings, Waits on the Owner, and Outside the '
      'drafts', () {
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
  });

  test('each plugin reader of what waits for the Owner reads waitsFor or its '
      'tag', () {
    for (final (file, section) in _ownerFindingReaders) {
      final text = _oneLine(_sectionOf(_pluginText(file), section));
      expect(
        text,
        anyOf(contains('`waitsFor`'), contains('`(waits for the Owner)`')),
        reason: '$file#$section',
      );
    }
  });

  test('the author report holds the ready move command', () {
    final report = _sectionOf(
      _pluginText('specstone-brainstorming-sdd/references/author.md'),
      '5. Report',
    );
    expect(report, contains('\nMove: specstone move feature:<name> … --top\n'));
  });

  test("the author report's Drafts line and Counts line keep their form", () {
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

    test('every pointing skill holds no auto copy', () {
      for (final skill in [
        'bootstrap-prd',
        'bootstrap-spec',
        'init',
        'sync-sdd',
        'update-sdd',
      ]) {
        expect(
          _pluginText('specstone-$skill/SKILL.md'),
          isNot(contains('approveMode')),
          reason: skill,
        );
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

  test(
    'the sdd-engineer holds Write and Edit for its report and batch files',
    () {
      expect(
        _toolsOf(_pluginText('specstone-sdd-engineer.md'), 'tools'),
        containsAll(['Write', 'Edit']),
      );
    },
  );

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

  test('the sdd-engineer holds Grep for the search of its saved files', () {
    expect(
      _toolsOf(_pluginText('specstone-sdd-engineer.md'), 'tools'),
      contains('Grep'),
    );
  });

  test('plan-engineer denies none of the Grep, Bash, and Read tools its read '
      'path runs', () {
    expect(
      _toolsOf(_pluginText(_planAgent), 'disallowedTools'),
      isNot(anyOf(contains('Grep'), contains('Bash'), contains('Read'))),
    );
  });

  test('sdd-reader holds Read and Grep and never Write or Edit', () {
    final tools = _toolsOf(_pluginText('specstone-sdd-reader.md'), 'tools');
    expect(tools, containsAll(['Read', 'Grep']));
    expect(tools, isNot(anyOf(contains('Write'), contains('Edit'))));
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

  test('the design reference runs no refs or search and names check', () {
    final design = cliCommands(
      _pluginText('specstone-brainstorming-sdd/references/design.md'),
    );
    expect(design, isNot(contains('refs')));
    expect(design, isNot(contains('search')));
    expect(design, contains('check'));
  });

  test('the sync procedure keeps each command code span on one line', () {
    for (final line in _pluginText(
      'specstone-sync-sdd/references/procedure.md',
    ).split('\n')) {
      expect('`'.allMatches(line).length.isEven, isTrue, reason: line);
    }
  });

  test('design.md and audit.md hold the Audited and Findings line form and '
      'restate nothing the rules own', () {
    final design = _pluginText(
      'specstone-brainstorming-sdd/references/design.md',
    );
    final audit = _pluginText(
      'specstone-brainstorming-sdd/references/audit.md',
    );
    expect(
      _sectionOf(audit, '3. Report'),
      contains('\nAudited: <type>:<name>@<hash>\nFindings:\n'),
    );
    for (final restated in _ownedElsewhere) {
      expect(
        _oneLine('$design\n$audit'),
        isNot(contains(restated)),
        reason: restated,
      );
    }
  });

  test('rounds.md restates nothing audit.md or design.md owns and names no '
      'bare step', () {
    final rounds = _oneLine(_pluginText(_rounds));
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
  });

  test('author.md restates no text of the batch fault table', () {
    final author = _pluginText(_author);
    for (final restated in _batchTableText) {
      expect(author, isNot(contains(restated)), reason: restated);
    }
  });
}

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

/// Text of `write_a_batch`'s fault table, which author.md handles through
/// E11's points and never restates.
const _batchTableText = ['exit status', '`75`', 'argument_invalid'];

/// The one home of the size-fix rule, under the plugin folder.
const _sizeFix = 'specstone-expert-sdd/references/size-fix.md';

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

const _bootstrapProcedures = [
  'specstone-bootstrap-prd/references/procedure.md',
  'specstone-bootstrap-spec/references/procedure.md',
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
  test('no bootstrap procedure restates the readability rewrite', () {
    for (final file in _bootstrapProcedures) {
      final text = _oneLine(_pluginText(file));
      for (final point in _readabilityRewritePoints) {
        expect(text, isNot(contains(point)), reason: '$file: $point');
      }
    }
  });

  test('only the two bootstrap procedures name readability-fix.md', () {
    final namers = [
      for (final file in agentSourceFiles(agentAssetsRoot()))
        if (file.readAsStringSync().contains('readability-fix.md'))
          shippedPathOf(file),
    ];
    expect(namers, unorderedEquals(_bootstrapProcedures));
  });

  test('only the two bootstrap procedures name writes.md, and hold no write '
      'detail of it', () {
    final namers = [
      for (final file in agentSourceFiles(agentAssetsRoot()))
        if (file.readAsStringSync().contains('writes.md')) shippedPathOf(file),
    ];
    expect(namers, unorderedEquals(_bootstrapProcedures));
    for (final file in _bootstrapProcedures) {
      final text = _pluginText(file);
      for (final held in ['base_mismatch', '#quot;', '#_lead']) {
        expect(text, isNot(contains(held)), reason: '$file: $held');
      }
    }
  });
}

void _sizeFixTests() {
  test('the bootstrap skills and the engineer restate no item rewrite of '
      'size-fix.md', () {
    for (final file in [
      'specstone-bootstrap-prd/SKILL.md',
      'specstone-bootstrap-spec/SKILL.md',
      'specstone-sdd-engineer.md',
    ]) {
      final text = _oneLine(_pluginText(file));
      for (final point in _itemRewritePoints) {
        expect(text, isNot(contains(point)), reason: '$file: $point');
      }
    }
  });

  test('no file but size-fix.md restates its new feature --parent command', () {
    for (final file in agentSourceFiles(agentAssetsRoot())) {
      if (file.uri.path.endsWith(_sizeFix)) continue;
      expect(
        _oneLine(file.readAsStringSync()),
        isNot(contains('new feature --parent')),
        reason: file.path,
      );
    }
  });
}

/// Each bootstrap procedure and its est. tokens once the write block moved to
/// writes.md, which its one guide call per batch leaves no higher.
const _bootstrapProcedureTokens = {
  'specstone-bootstrap-prd/references/procedure.md': 1402,
  'specstone-bootstrap-spec/references/procedure.md': 1416,
};

void _batchGuideTests() {
  test('each bootstrap procedure stays within its est. tokens', () {
    for (final MapEntry(key: file, value: tokens)
        in _bootstrapProcedureTokens.entries) {
      expect(
        oversizedSkillFiles(
          contentFiles(),
          limit: tokens,
        ).where((problem) => problem.startsWith('$file:')),
        isEmpty,
        reason: file,
      );
    }
  });
}

/// How the repeats batch's agent merges one group or keeps it.
const _repeatMergePoints = [
  'Per group, judge whether its items state one rule.',
  "keep the item in the doc that owns the rule's subject",
  'replace each other copy in a doc your skill takes with a link to that item',
  "name the owner in each draft's reason.",
  'keep each item and report the group as kept.',
];

void _repeatsBatchTests() {
  for (final skill in ['bootstrap-prd', 'bootstrap-spec']) {
    test('the $skill procedure copies no step of the repeats batch', () {
      final text = _oneLine(
        _pluginText('specstone-$skill/references/procedure.md'),
      );
      for (final point in _repeatMergePoints) {
        expect(text, isNot(contains(point)), reason: point);
      }
    });
  }
}

/// The goal-move reference of bootstrap-prd, under the plugin folder.
const _goalMove = 'specstone-bootstrap-prd/references/goal-move.md';

void _goalMoveTests() {
  test('the bootstrap-prd procedure copies no step of the goal move', () {
    final text = _pluginText('specstone-bootstrap-prd/references/procedure.md');
    for (final step in ['new goal', 'set --batch', 'refs project']) {
      expect(text, isNot(contains(step)), reason: step);
    }
  });

  test('goal-move.md names no item ID and links no prds or specs doc', () {
    final text = _oneLine(_pluginText(_goalMove));
    expect(RegExp(r'\bE\d\d\b').hasMatch(text), isFalse);
    expect(RegExp(r'\]\([^)]*\b(?:prds|specs)/').hasMatch(text), isFalse);
  });
}

/// The glossary-move reference of bootstrap-prd, under the plugin folder.
const _glossaryMove = 'specstone-bootstrap-prd/references/glossary-move.md';

void _glossaryMoveTests() {
  test('the bootstrap-prd procedure copies no step of the glossary move', () {
    final text = _pluginText('specstone-bootstrap-prd/references/procedure.md');
    for (final step in ['new glossary', 'glossary:glossary']) {
      expect(text, isNot(contains(step)), reason: step);
    }
  });

  test('glossary-move.md names no item ID and links no prds or specs doc', () {
    final text = _oneLine(_pluginText(_glossaryMove));
    expect(RegExp(r'\bE\d\d\b').hasMatch(text), isFalse);
    expect(RegExp(r'\]\([^)]*\b(?:prds|specs)/').hasMatch(text), isFalse);
  });
}

const _runPlanSkill = 'agent_plugin/plan_approved_stories/run_plan_skill';
const _writePlan = 'agent_plugin/plan_approved_stories/write_grounded_plan';

/// The plan skill and the plan agent, under the plugin folder.
const _planSkill = 'specstone-plan-sdd/SKILL.md';
const _planAgent = 'specstone-plan-engineer.md';

final _frontmatterBlock = RegExp(r'^---\r?\n((?:.*\r?\n)*?)---\r?\n');

/// The comma-separated tools of the frontmatter line `<key>:` in [agent];
/// null when the frontmatter has no such line.
List<String>? _toolsOf(String agent, String key) {
  final frontmatter = _frontmatterBlock.firstMatch(agent)?.group(1) ?? '';
  final line = RegExp('^$key:(.*)\$', multiLine: true).firstMatch(frontmatter);
  return line?.group(1)?.split(',').map((tool) => tool.trim()).toList();
}

void _planTests() {
  test('$_writePlan: plan-engineer names the Report, Plan, and Findings reply '
      'lines', () {
    final agent = _oneLine(_pluginText(_planAgent));
    for (final line in ['Report: <path>', 'Plan:', 'Findings:']) {
      expect(agent, contains(line), reason: line);
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

  test('$_writePlan: plan-engineer lists no tools line and denies only Agent '
      'and NotebookEdit', () {
    final agent = _pluginText(_planAgent);
    expect(_toolsOf(agent, 'tools'), isNull);
    final denied = _toolsOf(agent, 'disallowedTools');
    expect(denied?.toSet(), {'Agent', 'NotebookEdit'});
    expect(
      denied!.toSet().intersection({'Write', 'Edit', 'Skill', 'Bash', 'Read'}),
      isEmpty,
    );
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

    test('the engineer has no skills key', () {
      final text = _pluginText('specstone-sdd-engineer.md');
      final head = text.substring(0, text.indexOf('\n---\n', 4));
      expect(head, isNot(contains('\nskills:')));
    });

    test('each of the six skill files stays within 1,500 est. tokens', () {
      expect(oversizedSkillFiles(_brainstormContent()), isEmpty);
    });
  });
}

void _designBriefTests() {
  test('an agent file span accepts the design source file and rejects a '
      'design brief file', () {
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

    test('each of the nine skill files stays within 1,500 est. tokens', () {
      expect(oversizedSkillFiles(_syncBootstrapContent()), isEmpty);
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

    test('the plan skill file stays within 1,500 est. tokens', () {
      expect(oversizedSkillFiles(_planContent()), isEmpty);
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
