import 'dart:io';

import 'package:specstone/src/command_runner.dart';
import 'package:specstone_core/src/setup_migration/agent_assets.dart';
import 'package:specstone_core/src/setup_migration/host_render.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import '../helpers/package_root.dart';
import '../helpers/plugin_content.dart';
import '../helpers/temp_tree.dart';

void main() {
  group('frontmatter', _frontmatterTests);
  group('token budget', _tokenBudgetTests);
  group('references resolve', _referencesResolveTests);
  group('cli calls exist', _cliCallsExistTests);
  group('host renders match source', _hostRendersMatchSourceTests);
  group('runs on every host', _runsOnEveryHostTests);
}

// MARK: - Fixtures and readers

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

const _procedures = <String>[
  'specstone-sync-sdd/references/procedure.md',
  'specstone-sync-sdd/references/routes.md',
  'specstone-sync-sdd/references/helpers.md',
  'specstone-sync-sdd/references/task-refs.md',
  'specstone-sync-sdd/references/path-fixes.md',
  'specstone-sync-sdd/references/matrix-rows.md',
  'specstone-sync-sdd/references/spec-drafts.md',
  'specstone-bootstrap-prd/references/procedure.md',
  'specstone-bootstrap-spec/references/procedure.md',
  _goalMove,
  'specstone-brainstorming-sdd/references/author.md',
  'specstone-brainstorming-sdd/references/design.md',
  'specstone-brainstorming-sdd/references/audit.md',
  'specstone-brainstorming-sdd/references/design-check.md',
  'specstone-brainstorming-sdd/references/removal.md',
  'specstone-brainstorming-sdd/references/refused-batch.md',
  'specstone-brainstorming-sdd/references/repoint.md',
];

/// The goal-move reference of bootstrap-prd, under the plugin folder.
const _goalMove = 'specstone-bootstrap-prd/references/goal-move.md';

/// The glossary-move reference of bootstrap-prd, under the plugin folder.
const _glossaryMove = 'specstone-bootstrap-prd/references/glossary-move.md';

const _planAgent = 'specstone-plan-engineer.md';

/// Each plugin file that names a file for an agent's run, and the
/// AgentFileName forms it names under `<folder>/reports/`.
const _agentFileNames = <String, List<String>>{
  'specstone-plan-engineer.md': [
    'plan-engineer.plan.<XXXXXX>.md',
    'check.plan.<XXXXXX>.txt',
  ],
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

final _agentFilePath =
    r'<folder>/reports/(?:(?:sdd|plan)-engineer\.(?:<mode>|[a-z]+)\.'
    r'(?:(?:batch|source)\.)?<XXXXXX>\.(?:md|txt)|check\.'
    '(?:${checkRoles.join('|')}|<role>)'
    r'\.<XXXXXX>\.txt|guide\.<XXXXXX>\.(?:txt|json))';

/// A code span naming an agent file by its AgentFileName under
/// [_reportsFolder], bare or as the quoted `--out` of a `specstone check` or
/// `specstone guide`; the file is group 1 or 2.
final _agentFileSpan = RegExp(
  '^(?:($_agentFilePath)|'
  'specstone (?:check|guide)(?: [^\\s"]+)* --out "($_agentFilePath)")\$',
);

/// A code line run in a shell: a `specstone` call or a redirect.
final _shellLine = RegExp(r'^\s*specstone |\s>>?\s');

/// An agent file placeholder, `<file>` or a `<folder>` path, with no `"`
/// before it.
final _unquotedAgentFile = RegExp('(?<!")<(?:file|folder)>');

final _codeSpan = RegExp(r'`([^`\n]+)`');

final _fencedBlock = RegExp(r'^ *```[^\n]*\n([\s\S]*?)^ *```', multiLine: true);

final _frontmatterName = RegExp(r'^---\r?\n(?:.*\r?\n)*?name:\s*(\S+)');

final _frontmatterBlock = RegExp(r'^---\r?\n((?:.*\r?\n)*?)---\r?\n');

final _contextCall = RegExp(r'specstone context\b(.*?)(?=specstone |$)');

/// [text] with every run of whitespace, a wrapped line end included, as one
/// space.
String _oneLine(String text) => text.replaceAll(RegExp(r'\s+'), ' ');

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

/// Each inline code span of [markdown] outside its fenced blocks, a span
/// wrapped over lines read whole.
List<String> _inlineSpans(String markdown) {
  final blanked = markdown
      .replaceAllMapped(_fencedBlock, (block) => ' ' * block[0]!.length)
      .replaceAll('\n', ' ');
  return [for (final span in _codeSpan.allMatches(blanked)) span.group(1)!];
}

/// The text of plugin [file] with `\n` line ends, as a Windows checkout's
/// `\r\n` would otherwise fail every multi-line match.
String _pluginText(String file) =>
    File.fromUri(agentAssetsRoot().uri.resolve(file))
        .readAsStringSync()
        .replaceAll('\r\n', '\n');

/// Each `.md` file of the skill and agent sources, relative to the assets
/// folder with `/` separators, sorted.
List<String> _skillAndAgentFiles() => [
  for (final file in agentSourceFiles(agentAssetsRoot()))
    if (file.path.endsWith('.md')) shippedPathOf(file),
];

/// The comma-separated tools of the frontmatter line `<key>:` in [agent];
/// null when the frontmatter has no such line.
List<String>? _toolsOf(String agent, String key) {
  final frontmatter = _frontmatterBlock.firstMatch(agent)?.group(1) ?? '';
  final line = RegExp('^$key:(.*)\$', multiLine: true).firstMatch(frontmatter);
  return line?.group(1)?.split(',').map((tool) => tool.trim()).toList();
}

/// The base name of [entity]'s path, its `.md` ending cut.
String _baseNameOf(FileSystemEntity entity) {
  final segments = entity.uri.pathSegments.where((s) => s.isNotEmpty);
  return segments.last.replaceFirst(RegExp(r'\.md$'), '');
}

List<Directory> _skillFolders() =>
    {
          for (final file in agentSourceFiles(agentAssetsRoot()))
            if (isSkillSourcePath(shippedPathOf(file)))
              shippedPathOf(file).split('/').first,
        }
        .map(
          (name) => Directory.fromUri(agentAssetsRoot().uri.resolve('$name/')),
        )
        .toList();

List<File> _agentFiles() =>
    agentSourceFiles(agentAssetsRoot())
        .where((file) => !isSkillSourcePath(shippedPathOf(file)))
        .toList();

Future<List<String>> _problemsOf(Map<String, String> files) async {
  final root = await writeTree(files);
  return unknownCliNames(contentFilesOf(root), SpecstoneCommandRunner());
}

Future<List<String>> _skillProblemsOf(String markdown) async {
  final root = await writeTree({'specstone-x/SKILL.md': markdown});
  return otherPluginSkillNames(contentFilesOf(root), shippedDocTypes());
}

const _otherSkill = "specstone-x/SKILL.md: a:b is another plugin's skill";

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

// MARK: - frontmatter

void _frontmatterTests() {
  test('each specstone-<name> folder holds a SKILL.md named as the folder', () {
    final skillFolders = _skillFolders();
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
    final agentFiles = _agentFiles();
    expect(agentFiles, isNotEmpty);
    for (final file in agentFiles) {
      expect(
        _frontmatterName.firstMatch(file.readAsStringSync())?.group(1),
        _baseNameOf(file),
      );
    }
  });

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

  test('each SKILL.md names its folder and holds a description within 1,024 '
      'characters', () {
    final files = contentFiles();
    expect(files.where((file) => file.path.endsWith('/SKILL.md')), isNotEmpty);
    expect(skillHeadProblems(files), isEmpty);
  });

  test(
    'the sdd-engineer holds Write and Edit for its report and batch files',
    () {
      expect(
        _toolsOf(_pluginText('specstone-sdd-engineer.md'), 'tools'),
        containsAll(['Write', 'Edit']),
      );
    },
  );

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

  test('the engineer source preloads expert-sdd and read-sdd and lists no '
      'Skill tool', () {
    final text = _pluginText('specstone-sdd-engineer.md');
    final head = text.substring(0, text.indexOf('\n---\n', 4));
    final skills = RegExp(r'^skills:\n((?:  - .+\n?)+)', multiLine: true)
        .firstMatch(head)
        ?.group(1)
        ?.split('\n')
        .where((line) => line.isNotEmpty)
        .map((line) => line.replaceFirst('  - ', '').trim())
        .toList();
    expect(skills, ['specstone-expert-sdd', 'specstone-read-sdd']);
    expect(_toolsOf(text, 'tools'), isNot(contains('Skill')));
  });
}

// MARK: - token budget

void _tokenBudgetTests() {
  test('a reference file of 1,620 est. tokens fails alone naming it', () async {
    final root = await writeTree({
      'specstone-x/SKILL.md': 'a' * 4000,
      'specstone-x/reference.md': 'b' * 6480,
    });
    expect(oversizedSkillFiles(contentFilesOf(root)), [
      'specstone-x/reference.md: 1620 est. tokens, over 1500',
    ]);
  });

  test('files of one skill that sum past 1,500 est. tokens pass when each '
      'stays within it', () async {
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

  test('oversized skill files list sorted, nested and non-md files are sized, '
      'exactly-limit files pass', () async {
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

  test('every shipped skill file stays within 1,500 est. tokens', () {
    final files = contentFiles();
    expect(files.where((file) => file.isSkillFile), isNotEmpty);
    expect(oversizedSkillFiles(files), isEmpty);
  });

  test('each bootstrap procedure stays within its est. tokens', () {
    final paths = contentFiles().map((file) => file.path);
    for (final MapEntry(key: file, value: tokens)
        in _bootstrapProcedureTokens.entries) {
      expect(paths, contains(file), reason: file);
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

/// Each bootstrap procedure and its est. tokens once the write block moved to
/// writes.md, which its one guide call per batch leaves no higher.
const _bootstrapProcedureTokens = {
  'specstone-bootstrap-prd/references/procedure.md': 1494,
  'specstone-bootstrap-spec/references/procedure.md': 1416,
};

// MARK: - references resolve

/// The spans that carry no skill-name form, or a doc type prefix.
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

void _referencesResolveTests() {
  test('the plugin folder holds no skills folder and no agents folder', () {
    final shipped = agentSourceFiles(agentAssetsRoot()).map(shippedPathOf);
    expect(shipped, isNotEmpty);
    for (final folder in const ['skills', 'agents']) {
      expect(
        shipped.where((path) => path.startsWith('$folder/')),
        isEmpty,
        reason: '$folder/ is shipped',
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
      _skillFolders().map(_baseNameOf),
      unorderedEquals([for (final name in _skillNames) 'specstone-$name']),
    );
    expect(
      _agentFiles().map(_baseNameOf),
      unorderedEquals([for (final name in _agentNames) 'specstone-$name']),
    );
  });

  for (final procedure in _procedures) {
    test('$procedure exists', () {
      final file = File.fromUri(agentAssetsRoot().uri.resolve(procedure));
      expect(file.existsSync(), isTrue, reason: '$procedure is missing');
    });
  }

  test('each agent file a plugin file names starts from the specstone folder '
      'output, by its AgentFileName', () {
    final named = <String, List<String>>{};
    final problems = <String>[];
    final files = _skillAndAgentFiles();
    expect(files, isNotEmpty);
    for (final file in files) {
      for (final code in _inlineSpans(_pluginText(file))) {
        if (!code.contains('reports/')) continue;
        final match = _agentFileSpan.firstMatch(code);
        if (match != null) {
          final path = (match.group(1) ?? match.group(2))!;
          named
              .putIfAbsent(file, () => [])
              .add(path.substring(_reportsFolder.length));
        } else {
          problems.add('$file: $code');
        }
      }
    }
    expect(problems, isEmpty);
    for (final MapEntry(key: file, value: names) in _agentFileNames.entries) {
      expect(named[file], containsAll(names), reason: file);
    }
  });

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

  test('every relative path of every shipped source and render resolves', () {
    final files = contentFiles();
    expect(files.where((file) => file.path.startsWith('.claude/')), isNotEmpty);
    expect(unresolvedPaths(files), isEmpty);
  });

  test('a skill file naming superpowers:writing-plans fails naming the file '
      'and the span', () async {
    final root = await writeTree({
      'specstone-x/SKILL.md': 'Then run `superpowers:writing-plans`.',
    });
    expect(otherPluginSkillNames(contentFilesOf(root), shippedDocTypes()), [
      "specstone-x/SKILL.md: superpowers:writing-plans is another plugin's skill",
    ]);
  });

  test(
    'an agent file holding path:line fails naming the file and the span',
    () async {
      final root = await writeTree({
        'specstone-a.md': 'Cite each hit as `path:line`.',
      });
      expect(otherPluginSkillNames(contentFilesOf(root), shippedDocTypes()), [
        "specstone-a.md: path:line is another plugin's skill",
      ]);
    },
  );

  test('a doc citation, a placeholder, a doc-type prefix, and a hyphenated '
      'specstone skill name pass', () async {
    final root = await writeTree({
      'specstone-x/SKILL.md': 'Cite ${_docCitations.join(', ')}.',
      'specstone-a.md': 'Cite ${_docCitations.join(', ')}.',
    });
    expect(
      otherPluginSkillNames(contentFilesOf(root), shippedDocTypes()),
      isEmpty,
    );
  });

  test(
    'a span holding a slash, an underscore, a hash, or an angle bracket '
    'never has the skill-name form, and a markdown-link cite passes',
    () async {
      final root = await writeTree({
        'specstone-x/SKILL.md':
            'Cite `shop/cart:add_item`, `a_b:c`, `a:b#c`, `a:<b>`, and '
            '[domain:document_writing](../../specs/f02_document_writing/DOMAIN.md#invariants).',
      });
      expect(
        otherPluginSkillNames(contentFilesOf(root), shippedDocTypes()),
        isEmpty,
      );
    },
  );

  test('a file naming another plugin in prose, with no backticked span, '
      'passes the content test', () async {
    final root = await writeTree({
      'specstone-x/SKILL.md':
          "${_skillHead('specstone-x', 'Skill.')}Then follow superpowers' "
          'writing-plans skill.\n',
    });
    final files = contentFilesOf(root);
    expect(otherPluginSkillNames(files, shippedDocTypes()), isEmpty);
    expect(unknownCliNames(files, SpecstoneCommandRunner()), isEmpty);
    expect(hostTiedText(files), isEmpty);
    expect(skillHeadProblems(files), isEmpty);
  });

  test('a backticked specstone:<name> fails in a skill file and an agent '
      'file, and the hyphenated name passes', () async {
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

  test('shippedDocTypes holds the doc types the packs define, project, '
      'features, and gnfr among them', () {
    expect(
      shippedDocTypes(),
      containsAll(['project', 'features', 'gnfr', 'fr', 'tech_stack']),
    );
  });

  test('a fenced line and a span holding a space never have the form, and a '
      'repeated span lists once', () async {
    final root = await writeTree({
      'specstone-x/SKILL.md':
          '```\nsuperpowers:writing-plans\n```\n'
          '`superpowers:writing-plans now` `a:b` `a:b`\n',
    });
    expect(otherPluginSkillNames(contentFilesOf(root), shippedDocTypes()), [
      "specstone-x/SKILL.md: a:b is another plugin's skill",
    ]);
  });

  test("no shipped plugin file names another plugin's skill", () {
    final files = contentFiles();
    expect(files, isNotEmpty);
    expect(otherPluginSkillNames(files, shippedDocTypes()), isEmpty);
  });
}

// MARK: - cli calls exist

void _cliCallsExistTests() {
  test(
    'a skill naming specstone check --fix fails naming its file and --fix',
    () async {
      expect(
        await _problemsOf({
          'specstone-x/SKILL.md': 'Run `specstone check --fix`.',
        }),
        ['specstone-x/SKILL.md: specstone check has no --fix'],
      );
    },
  );

  test('a command the CLI lacks fails naming it', () async {
    expect(
      await _problemsOf({'specstone-x/SKILL.md': 'Run `specstone lint docs`.'}),
      ['specstone-x/SKILL.md: specstone has no command lint'],
    );
  });

  test('an agent file naming a flag the CLI lacks fails naming the file and '
      'the flag', () async {
    expect(
      await _problemsOf({'specstone-a.md': 'Run `specstone check --fix`.'}),
      ['specstone-a.md: specstone check has no --fix'],
    );
  });

  test('the CLI package tests run on ubuntu, macos, and windows in CI, with '
      'the plugin content test left in', () {
    final workflow = loadYaml(
      File.fromUri(packageRoot().uri.resolve('../../.github/workflows/ci.yaml'))
          .readAsStringSync(),
    ) as YamlMap;
    final job = (workflow['jobs'] as YamlMap)['test'] as YamlMap;
    final matrix = (job['strategy'] as YamlMap)['matrix'] as YamlMap;
    expect(
      matrix['os'],
      unorderedEquals(['ubuntu-latest', 'macos-latest', 'windows-latest']),
    );
    expect(matrix['suite'], contains('cli'));
    final cliRuns = [
      for (final step in job['steps'] as YamlList)
        if (step is YamlMap &&
            step['working-directory'] == 'packages/specstone' &&
            '${step['if']}'.contains("matrix.suite == 'cli'") &&
            '${step['run']}'.startsWith('dart test'))
          '${step['run']}',
    ];
    expect(cliRuns, isNotEmpty);
    for (final run in cliRuns) {
      expect(run, isNot(contains('plugin')), reason: run);
    }
    final covered = {
      for (final step in job['steps'] as YamlList)
        if (step is YamlMap && cliRuns.contains('${step['run']}'))
          for (final os in ['ubuntu', 'macos', 'windows'])
            if ('${step['if']}'.contains(os)) os,
    };
    expect(covered, {'ubuntu', 'macos', 'windows'});
  });

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

  test(
    'a flag a subcommand lacks fails naming the full command path',
    () async {
      expect(
        await _problemsOf({
          'specstone-x/SKILL.md': 'Run `specstone hook post-edit --x`.',
        }),
        ['specstone-x/SKILL.md: specstone hook post-edit has no --x'],
      );
    },
  );

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

  test('a span wrapped over two lines is read whole, and the span after it is '
      'still read', () async {
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

  test('a ~~~ fence is a code block, so its text is no inline span and its '
      'lines are checked', () async {
    expect(await _skillProblemsOf('~~~\n`a:b`\n~~~\n'), isEmpty);
    expect(
      await _problemsOf({
        'specstone-x/SKILL.md': '~~~sh\nspecstone nope\n~~~\n',
      }),
      ['specstone-x/SKILL.md: specstone has no command nope'],
    );
  });

  test('a fence inside a list item or a quote is a code block', () async {
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
  });

  test('a four-backtick fence holding a three-backtick line stays one code '
      'block', () async {
    expect(await _skillProblemsOf('````\n```\n`a:b`\n```\n````\n'), isEmpty);
    expect(await _skillProblemsOf('````\n```\n````\n`a:b`\n'), [_otherSkill]);
  });

  test('an unclosed fence runs to the end of the file', () async {
    expect(await _skillProblemsOf('`a:b`\n```\n`c:d`\n'), [_otherSkill]);
    expect(
      await _problemsOf({
        'specstone-x/SKILL.md': '- ```sh\n  specstone nope\n',
      }),
      ['specstone-x/SKILL.md: specstone has no command nope'],
    );
  });

  test('a context call holding --out and --budget is read, also when its span '
      'wraps over two lines', () {
    expect(
      _contextCalls('Run `specstone context a --for query\n--out --budget 9`.'),
      [
        ['a', '--for', 'query', '--out', '--budget', '9'],
      ],
    );
  });

  test('no shipped context call holds both --out and --budget', () {
    final problems = <String>[];
    var calls = 0;
    for (final file in _skillAndAgentFiles()) {
      for (final call in _contextCalls(_pluginText(file))) {
        calls++;
        if (call.contains('--out') &&
            call.any((token) => token.startsWith('--budget'))) {
          problems.add('$file: specstone context ${call.join(' ')}');
        }
      }
    }
    expect(calls, greaterThan(0));
    expect(problems, isEmpty);
  });

  test('every shipped skill and agent names only commands and flags the CLI '
      'has', () {
    final files = contentFiles();
    expect([for (final file in files) ...cliCommands(file.body)], isNotEmpty);
    expect(unknownCliNames(files, SpecstoneCommandRunner()), isEmpty);
  });

  test('every shipped check call saves to a check role file under reports', () {
    final files = contentFilesOf(agentAssetsRoot());
    expect(checkCalls(files), isNotEmpty);
    expect(checkCallsWithoutSavedFile(files), isEmpty);
  });

  test('a skill naming a bare specstone check fails naming its file and '
      'call', () async {
    const skill = 'specstone-a/SKILL.md';
    const reference = 'specstone-a/references/b.md';
    const saved = '<folder>/reports/check.sync.<XXXXXX>.txt';
    final root = await writeTree({
      skill:
          '---\ndescription: Run `specstone check` first.\n---\n'
          'Run `specstone check <doc>` now.\n\n'
          '```\nspecstone check --json\n```\n\n'
          '~~~\nspecstone check --out "<folder>/reports/check.sync.txt"\n~~~\n\n'
          'Wrapped `specstone check\n--out $saved\n--repeats` is fine, and so '
          'is `specstone check --out "$saved"`.\n',
      reference:
          'Run `specstone check <doc> --out <folder>/reports/check.<role>.<XXXXXX>.txt`, '
          '`specstone check --out "$saved"`, not '
          '`specstone check --out "<folder>/reports/check.sync.<XXXXXX>.md"` '
          'nor `specstone check --out "<folder>/reports/check.audit.<XXXXXX>.txt` '
          'nor `specstone check --out <folder>/reports/check.other.<XXXXXX>.txt`.\n',
    });

    expect(checkCallsWithoutSavedFile(contentFilesOf(root)), [
      '$skill: specstone check --json',
      '$skill: specstone check --out "<folder>/reports/check.sync.txt"',
      '$skill: specstone check <doc>',
      '$reference: specstone check --out "<folder>/reports/check.audit.<XXXXXX>.txt',
      '$reference: specstone check --out "<folder>/reports/check.sync.<XXXXXX>.md"',
      '$reference: specstone check --out <folder>/reports/check.other.<XXXXXX>.txt',
    ]);
  });
}

// MARK: - host renders match source

void _hostRendersMatchSourceTests() {
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

  test('each host render holds the text or body of its source file', () {
    final sources = {
      for (final file in contentFilesOf(agentAssetsRoot())) file.path: file,
    };
    final renders = renderedContentFiles(renderHostFiles());
    expect(sources, isNotEmpty);
    expect(renders, isNotEmpty);

    final rendered = <String>{};
    for (final render in renders) {
      final sourcePath = _sourcePathOf(render.path);
      final source = sources[sourcePath];
      expect(source, isNotNull, reason: '${render.path} has no source');
      rendered.add(sourcePath);
      final isClaudeAgent = render.path.startsWith('.claude/agents/');
      final body = isClaudeAgent
          ? source!.body.replaceAll('.agents/skills/', '.claude/skills/')
          : source!.body;
      expect(render.body, body, reason: render.path);
      if (render.isSkillFile) {
        expect(render.frontmatter, source.frontmatter, reason: render.path);
      }
    }
    expect(rendered, sources.keys.toSet(), reason: 'a source has no render');
  });

  test('a Codex file holds the body its Cursor file holds', () {
    final files = {for (final file in contentFiles()) file.path: file};
    final codex = files.keys.where((p) => p.endsWith('.toml'));
    expect(codex, isNotEmpty);
    for (final path in codex) {
      final cursor = path
          .replaceFirst('.codex/', '.cursor/')
          .replaceFirst('.toml', '.md');
      expect(files[path]!.body, files[cursor]!.body, reason: path);
    }
  });

  test('a Codex file holds its developer_instructions value unescaped, as the '
      'Cursor file holds the body', () {
    const body = 'Quote "a" and \\b, then `specstone check`.\n\ttab\n';
    final files = _rendersOf([_asset('specstone-a.md', '$_agentHead$body')]);
    ContentFile at(String path) =>
        files.singleWhere((file) => file.path == path);

    expect(at('.codex/agents/specstone-a.toml').body, body);
    expect(at('.cursor/agents/specstone-a.md').body, body);
    expect(at('.codex/agents/specstone-a.toml').frontmatter, isNotNull);
  });
}

/// The source path of the render at [renderPath]: the host folder cut, a Codex
/// `.toml` back to `.md`.
String _sourcePathOf(String renderPath) {
  final folder = AgentFolder.values.singleWhere(
    (folder) => renderPath.startsWith('${folder.path}/'),
  );
  return renderPath
      .substring(folder.path.length + 1)
      .replaceFirst(RegExp(r'\.toml$'), '.md');
}

// MARK: - runs on every host

void _runsOnEveryHostTests() {
  test('no skill file names a hook or the settings file that holds one', () {
    final problems = [
      for (final file in contentFilesOf(agentAssetsRoot()))
        if (file.isSkillFile &&
            RegExp(
              r'hook|settings\.json|PostToolUse',
              caseSensitive: false,
            ).hasMatch(file.body))
          file.path,
    ];
    expect(problems, isEmpty);
  });

  test('no skill and no agent share a name', () {
    final skills = _skillFolders().map(_baseNameOf).toSet();
    final agents = _agentFiles().map(_baseNameOf).toSet();
    expect(skills, isNotEmpty);
    expect(agents, isNotEmpty);
    expect(skills.intersection(agents), isEmpty);
  });

  test('a hand-over to the next skill reads "follow the `specstone-<name>` '
      'skill" and names a skill the plugin ships', () {
    final shipped = _skillFolders().map(_baseNameOf).toSet();
    final handOver = RegExp('follow the `(specstone-[a-z-]+)` skill');
    final bannedHandOver = RegExp(
      '(?:invoke|load) (?:it|the `specstone-[a-z-]+` skill) '
      '(?:through|with|via)',
    );
    final named = <String>{};
    for (final file in contentFiles()) {
      final text = _oneLine(file.body);
      for (final match in handOver.allMatches(text)) {
        named.add(match.group(1)!);
      }
      expect(bannedHandOver.hasMatch(text), isFalse, reason: file.path);
    }
    expect(named, isNotEmpty);
    expect(shipped, containsAll(named));
  });

  test('each render of the sdd-engineer holds one line telling it to follow '
      'specstone-expert-sdd, and a skills preload only in the Claude Code '
      'render', () {
    final renders = contentFiles()
        .where((file) => file.path.contains('specstone-sdd-engineer.'))
        .toList();
    expect(renders, hasLength(greaterThanOrEqualTo(5)));
    for (final render in renders) {
      expect(
        'follow the `specstone-expert-sdd` skill'.allMatches(
          _oneLine(render.body),
        ),
        hasLength(1),
        reason: render.path,
      );
      expect(
        'specstone-read-sdd/SKILL.md'.allMatches(render.body),
        hasLength(1),
        reason: render.path,
      );
      expect(
        (render.frontmatter ?? '').contains('\nskills:'),
        !render.path.contains('/') || render.path.contains('.claude/agents/'),
        reason: render.path,
      );
    }
  });

  test('a mention of the project instruction file names CLAUDE.md beside '
      'AGENTS.md in every shipped file', () {
    var mentions = 0;
    for (final file in contentFiles()) {
      final text = _oneLine(file.body);
      for (final match in '`CLAUDE.md`'.allMatches(text)) {
        mentions++;
        expect(
          text.substring(match.end),
          startsWith(', `AGENTS.md`'),
          reason: file.path,
        );
      }
      expect(
        text,
        isNot(contains("the project's `CLAUDE.md`")),
        reason: file.path,
      );
    }
    expect(mentions, greaterThan(0));
    expect(
      _oneLine(_pluginText('specstone-brainstorming-sdd/SKILL.md')),
      contains("the project's instruction file (`CLAUDE.md`, `AGENTS.md`)"),
    );
  });

  test('the shipped files word a file action, a dispatch, and the next skill '
      'by the forms table', () {
    final sources = _oneLine(
      [for (final file in contentFilesOf(agentAssetsRoot())) file.body]
          .join(' '),
    );
    for (final form in [
      "the host's file read",
      "the host's file write",
      'dispatch `specstone-sdd-engineer`',
      'the host lists no such agent',
      'no subagent',
      'follow the `specstone-',
    ]) {
      expect(sources, contains(form));
    }
    final never = RegExp(
      'the `?(?:Agent|Skill|Read|Write|Edit)`? tool|'
      'through `Skill`|with `Skill`',
    );
    for (final file in contentFiles()) {
      expect(never.hasMatch(_oneLine(file.body)), isFalse, reason: file.path);
    }
  });

  test('a step that picks another plugin skill by its description names no '
      'skill', () {
    final skillNameSpan = RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)+$');
    for (final (file, marker) in [
      (
        'specstone-brainstorming-sdd/SKILL.md',
        'whose description, never its name,',
      ),
      ('specstone-plan-sdd/SKILL.md', 'Judge by that description alone'),
    ]) {
      final steps = [
        for (final paragraph in _pluginText(file).split('\n\n'))
          if (_oneLine(paragraph).contains(marker)) paragraph,
      ];
      expect(steps, hasLength(1), reason: file);
      expect(
        _inlineSpans(steps.single).where(skillNameSpan.hasMatch),
        isEmpty,
        reason: file,
      );
    }
  });

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

  test('the tool names Grep, Glob, and Bash, a sentence opening on Read, and a '
      'fenced line pass', () {
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

  test('every shipped source and render names no host tool, no CLAUDE_ '
      "variable, and no other host's skills folder", () {
    final files = contentFiles();
    expect(files, isNotEmpty);
    expect(hostTiedText(files), isEmpty);
  });

  test('no plugin file names mktemp', () {
    final files = agentSourceFiles(agentAssetsRoot());
    expect(files, isNotEmpty);
    final problems = [
      for (final file in files)
        if (file.readAsStringSync().contains('mktemp')) shippedPathOf(file),
    ];
    expect(problems, isEmpty);
  });

  test('each shell line quotes the agent file it names, an absolute path that '
      'may hold a space', () {
    final problems = <String>[];
    final files = _skillAndAgentFiles();
    expect(files, isNotEmpty);
    for (final file in files) {
      final text = _pluginText(file);
      final codes = [
        for (final block in _fencedBlock.allMatches(text))
          ...block.group(1)!.split('\n'),
        ..._inlineSpans(text),
      ];
      for (final code in codes) {
        if (!_shellLine.hasMatch(code)) continue;
        if (_unquotedAgentFile.hasMatch(code)) problems.add('$file: $code');
      }
    }
    expect(problems, isEmpty);
  });

  test('a line with a letter outside the Latin script fails naming its file '
      'and line; accents, emoji, and symbols pass', () async {
    final root = await writeTree({
      'specstone-x/SKILL.md': 'Old text, café.\nMark it `เดิม:`.\n📜 ⊆ … —\n',
      'hooks/h.sh': '# 日本\n',
    });

    expect(nonLatinLetterLines(root), [
      'hooks/h.sh:1',
      'specstone-x/SKILL.md:2',
    ]);
  });

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

  test("no shipped file presumes the Owner's language with a letter outside "
      'the Latin script', () {
    expect(trackedFiles(agentAssetsRoot()), isNotEmpty);
    expect(nonLatinLetterLines(agentAssetsRoot()), isEmpty);
  });
}
