import 'dart:io';

import 'package:specstone/src/command_runner.dart';
import 'package:specstone_core/src/setup_migration/host_render.dart';
import 'package:specstone_core/src/setup_migration/models/agent_asset.dart';
import 'package:specstone_core/src/setup_migration/models/rendered_file.dart';
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
  group('approve step', _approveStepTests);
  group('trim reference', _trimReferenceTests);
  group('brainstorm rounds', _brainstormRoundTests);
  group('glossary move', _glossaryMoveTests);
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

const _agentNames = [
  'plan-engineer',
  'sdd-auditor',
  'sdd-engineer',
  'sdd-reader',
  'sdd-sweeper',
];

const _procedures = <String>[
  'specstone-sync-sdd/references/procedure.md',
  'specstone-sync-sdd/references/routes.md',
  'specstone-sync-sdd/references/helpers.md',
  'specstone-sync-sdd/references/task-refs.md',
  'specstone-sync-sdd/references/matrix-rows.md',
  'specstone-bootstrap-prd/references/procedure.md',
  'specstone-bootstrap-spec/references/procedure.md',
  _trimRound,
  _goalMove,
  'specstone-brainstorming-sdd/references/author.md',
  'specstone-brainstorming-sdd/references/author-report.md',
  'specstone-brainstorming-sdd/references/design.md',
  'specstone-brainstorming-sdd/references/audit.md',
  'specstone-brainstorming-sdd/references/design-check.md',
  'specstone-brainstorming-sdd/references/sweep.md',
  'specstone-brainstorming-sdd/references/removal.md',
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
  'specstone-brainstorming-sdd/SKILL.md': [
    'sdd-engineer.author.<XXXXXX>.md',
    'sdd-auditor.audit.<XXXXXX>.md',
    'sdd-sweeper.sweep.<XXXXXX>.md',
  ],
  'specstone-brainstorming-sdd/references/author.md': [
    'sdd-engineer.author.batch.<XXXXXX>.txt',
  ],
  'specstone-brainstorming-sdd/references/source.md': [
    'sdd-engineer.design.source.<XXXXXX>.md',
  ],
  'specstone-brainstorming-sdd/references/rounds.md': [
    'sdd-auditor.audit.snapshot.<XXXXXX>.md',
  ],
  'specstone-plan-sdd/SKILL.md': ['plan-engineer.plan.<XXXXXX>.md'],
  'specstone-sync-sdd/SKILL.md': ['sdd-engineer.sync.<XXXXXX>.md'],
  'specstone-expert-sdd/references/trim-round.md': [
    'sdd-auditor.audit.<XXXXXX>.md',
  ],
  'specstone-sdd-sweeper.md': ['sdd-sweeper.sweep.<XXXXXX>.md'],
  'specstone-sdd-auditor.md': ['sdd-auditor.audit.<XXXXXX>.md'],
};

const _reportsFolder = '<folder>/reports/';

final _agentFilePath =
    '<folder>/reports/(?:(?:sdd-engineer|sdd-sweeper|sdd-auditor|'
    r'plan-engineer)\.(?:<mode>|[a-z]+)\.'
    r'(?:(?:batch|source|snapshot)\.)?<XXXXXX>\.(?:md|txt)|check\.'
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

/// The entries of the frontmatter block list `skills:` in [frontmatter];
/// null when it has none.
List<String>? _skillsOf(String frontmatter) {
  final block = RegExp(
    r'^skills:\n((?:  - .+\n?)+)',
    multiLine: true,
  ).firstMatch(frontmatter)?.group(1);
  return block
      ?.split('\n')
      .where((line) => line.isNotEmpty)
      .map((line) => line.replaceFirst('  - ', '').trim())
      .toList();
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

AgentAsset _asset(String path, String text) =>
    AgentAsset(path: path, text: text);

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
    final skills = _skillsOf(head);
    expect(skills, ['specstone-expert-sdd', 'specstone-read-sdd']);
    expect(_toolsOf(text, 'tools'), ['Bash', 'Read', 'Grep', 'Write', 'Edit']);
  });

  test('the sweeper preloads read-sdd alone and writes its report', () {
    final text = _pluginText(_sweeper);
    final head = text.substring(0, text.indexOf('\n---\n', 4));
    expect(_skillsOf(head), ['specstone-read-sdd']);
    expect(_toolsOf(text, 'tools'), ['Bash', 'Read', 'Grep', 'Write']);
  });

  test('the sweeper reads sweep.md and design-check section 1 alone', () {
    final text = _pluginText(_sweeper);
    expect(text, contains('references/sweep.md'));
    expect(text, contains('references/design-check.md'));
    expect(
      _hasSentenceWith(_sectionOf(text, '## Bootstrap'), [
        'section 1',
        'references/design-check.md',
      ]),
      isTrue,
    );
    for (final other in [
      'references/author.md',
      'references/audit.md',
      'references/rounds.md',
      'specstone-sync-sdd/references/procedure.md',
      'specstone-bootstrap-prd/references/procedure.md',
      'specstone-bootstrap-spec/references/procedure.md',
    ]) {
      expect(text, isNot(contains(other)), reason: other);
    }
    expect(
      _hasSentenceWith(_sectionOf(text, '## Input Contract'), [
        '`since`',
        '`amend`',
        'OPEN QUESTIONS:',
      ]),
      isTrue,
    );
  });

  test("sweep.md orders the sweeper's Sweep, Ignored, Swept, Rows", () {
    final text = _pluginText(_sweepReference);
    final start = text.indexOf(_sweeperReportHeading);
    expect(start, isNonNegative);
    final section = text.substring(start);
    final block = _fencedBlock.firstMatch(section)!.group(1)!;
    final indices = [
      for (final line in ['Sweep: ', 'Ignored: ', 'Swept: ', 'Rows:'])
        block.indexOf(line),
    ];
    expect(indices.first, isNonNegative);
    expect(indices, [...indices]..sort());
    expect(indices.toSet(), hasLength(indices.length));
    expect(section, contains('Rows: none'));
  });

  test('the auditor preloads expert-sdd and read-sdd', () {
    final text = _pluginText(_auditor);
    final head = text.substring(0, text.indexOf('\n---\n', 4));
    expect(_skillsOf(head), ['specstone-expert-sdd', 'specstone-read-sdd']);
    expect(_toolsOf(text, 'tools'), ['Bash', 'Read', 'Grep', 'Write']);
  });

  test('the auditor sends an engineer mode to specstone-sdd-engineer', () {
    final contract = _sectionOf(_pluginText(_auditor), '## Input Contract');
    for (final words in [
      [
        '`author`',
        '`sync`',
        '`bootstrap`',
        'OPEN QUESTIONS:',
        '`specstone-sdd-engineer`',
      ],
      ['OPEN QUESTIONS:', '`mode`', '`audit`'],
    ]) {
      expect(
        _hasSentenceWith(contract, words),
        isTrue,
        reason: words.join(', '),
      );
    }
  });

  test('the engineer sends mode: audit to specstone-sdd-auditor', () {
    final text = _pluginText(_engineer);
    final contract = _sectionOf(text, '## Input Contract');
    expect(contract, contains('`author`, `sync`, or `bootstrap`'));
    expect(
      _hasSentenceWith(contract, [
        '`mode: audit`',
        'OPEN QUESTIONS:',
        '`specstone-sdd-auditor`',
      ]),
      isTrue,
    );
    expect(
      text,
      isNot(
        contains(
          '.agents/skills/specstone-brainstorming-sdd/references/audit.md',
        ),
      ),
    );
  });

  test('the auditor runs approve only as a dry run, the sweeper never', () {
    final spans = _approveSpans(_pluginText(_auditor));
    expect(spans, isNotEmpty);
    for (final span in spans) {
      expect(span, contains('--dry-run'), reason: span);
    }
    expect(_approveSpans(_pluginText(_sweeper)), isEmpty);
  });

  test('audit.md and design-check.md name the auditor as runner', () {
    for (final file in [_auditReference, _designCheckReference]) {
      final text = _pluginText(file);
      expect(
        text.split('\n').first,
        contains('`specstone-sdd-auditor`'),
        reason: file,
      );
      expect(text, isNot(contains('`specstone-sdd-engineer`')), reason: file);
    }
  });
}

const _sweeper = 'specstone-sdd-sweeper.md';

const _auditor = 'specstone-sdd-auditor.md';

const _designCheckReference =
    'specstone-brainstorming-sdd/references/design-check.md';

/// Each `specstone approve` code span of [markdown], a span wrapped over lines
/// read whole.
List<String> _approveSpans(String markdown) => [
  for (final span in _inlineSpans(markdown))
    if (span.contains('specstone approve')) span,
];

const _sweepReference = 'specstone-brainstorming-sdd/references/sweep.md';

const _sweeperReportHeading = "## 5. The sweeper's report";

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
/// the expert-sdd skill, which its one guide call per batch leaves no higher.
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
    'the source walk sees the fourteen sources and leaves AGENT.md out',
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

  test('the nine skills and five agents are all there', () {
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
      final isSource = !render.path.contains('/');
      final isClaudeCodeRender = render.path.contains('.claude/agents/');
      final frontmatter = render.frontmatter ?? '';
      expect(
        frontmatter.contains('\nskills:'),
        isSource || isClaudeCodeRender,
        reason: render.path,
      );
      if (isClaudeCodeRender) {
        expect(_skillsOf(frontmatter), [
          'specstone-expert-sdd',
          'specstone-read-sdd',
        ], reason: render.path);
      }
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

  test('dispatch.md names five agents and gives a sweep no main rung', () {
    final text = _pluginText(_dispatchReference);
    for (final agent in [
      '`specstone-sdd-engineer`',
      '`specstone-sdd-sweeper`',
      '`specstone-sdd-auditor`',
      '`specstone-sdd-reader`',
      '`specstone-plan-engineer`',
    ]) {
      expect(text, contains(agent), reason: agent);
    }
    expect(
      _hasSentenceWith(_sectionOf(text, '## Main session'), [
        'sweep',
        'no main-session rung',
      ]),
      isTrue,
    );
  });
}

/// The rungs every dispatching skill points to.
const _dispatchReference = 'specstone-expert-sdd/references/dispatch.md';

// MARK: - approve step

const _expertSdd = 'specstone-expert-sdd/SKILL.md';

const _approveHeading = '## Get the drafts approved';

/// The report flags each runner skill's approval names, by skill file.
const _runnerFlags = {
  'specstone-brainstorming-sdd/SKILL.md': ['--audit', '--author'],
  'specstone-update-sdd/SKILL.md': ['--no-audit'],
  'specstone-sync-sdd/SKILL.md': ['--no-audit'],
  'specstone-bootstrap-prd/SKILL.md': ['--audit', '--no-audit'],
  'specstone-bootstrap-spec/SKILL.md': ['--audit', '--no-audit'],
  'specstone-init/SKILL.md': ['--no-audit'],
};

const _reportFlags = ['--audit', '--author', '--no-audit'];

/// The runner skills whose red flags hold an approve row.
const _runnersWithApproveRedFlag = {
  'specstone-update-sdd/SKILL.md',
  'specstone-init/SKILL.md',
};

/// Words of the auto approve section's steps that no runner restates.
const _approveStepWords = [
  '--auto',
  '--dry-run',
  '`docPath`',
  '`asked`',
  '`Why:`',
  'approve-mode',
];

/// One problem per way runner skill [file] fails to point to expert-sdd's
/// auto approve section with exactly its [flags], holding no copy of it.
List<String> _runnerPointerProblems(String file, List<String> flags) {
  final text = _pluginText(file);
  final body = _oneLine(
    text.split('\n').where((line) => !line.startsWith('#')).join('\n'),
  );
  final title = _approveHeading.substring('## '.length);
  bool isPointer(String span) =>
      span.contains(title) && span.contains('specstone-expert-sdd');
  final pointers = body
      .split(RegExp(r'(?<=[.;])\s'))
      .where(isPointer)
      .join(' ');
  final redFlagRows = text
      .split('\n')
      .skipWhile((line) => line != '## Red flags')
      .where((line) => line.startsWith('|') && line.contains(title));
  return [
    if (pointers.isEmpty) '$file: no pointer to "$title"',
    for (final flag in _reportFlags)
      if (flags.contains(flag) && !pointers.contains(flag))
        '$file: pointer lacks $flag'
      else if (!flags.contains(flag) && body.contains(flag))
        '$file: names $flag',
    if (_runnersWithApproveRedFlag.contains(file) &&
        !redFlagRows.any((row) => isPointer(row) && flags.every(row.contains)))
      '$file: red flag lacks the pointer',
    for (final word in _approveStepWords)
      if (text.contains(word)) '$file: copies $word',
  ];
}

/// The text of [heading]'s section in [markdown], up to the next `## `
/// heading, every whitespace run as one space; empty when no line is
/// [heading].
String _sectionOf(String markdown, String heading) {
  final lines = markdown.split('\n');
  final start = lines.indexOf(heading);
  if (start < 0) return '';
  final rest = lines.skip(start + 1).takeWhile((l) => !l.startsWith('## '));
  return _oneLine(rest.join('\n'));
}

void _approveStepTests() {
  test(
    'expert-sdd holds one auto approve section ahead of Owner confirmation',
    () {
      final lines = _pluginText(_expertSdd).split('\n');
      expect(lines.where((line) => line == _approveHeading), hasLength(1));
      expect(
        lines.indexOf(_approveHeading),
        lessThan(lines.indexOf('## Owner confirmation')),
      );
      final section = _sectionOf(_pluginText(_expertSdd), _approveHeading);
      for (final word in [
        'specstone approve',
        '--auto',
        '--json',
        '--audit',
        '--author',
        '--no-audit',
        '`approved`',
        '`docPath`',
        '`asked`',
        'Exit 75',
      ]) {
        expect(section, contains(word), reason: word);
      }
    },
  );

  test('no skill file names the approve-mode reference', () {
    final files = contentFiles();
    expect(files, isNotEmpty);
    final problems = [
      for (final file in files)
        if (file.path.endsWith('approve-mode.md') ||
            '${file.frontmatter ?? ''}${file.body}'.contains('approve-mode.md'))
          file.path,
    ];
    expect(problems, isEmpty);
  });

  test('expert-sdd tells a subagent to run approve only as a dry run', () {
    final section = _sectionOf(_pluginText(_expertSdd), _approveHeading);
    final sentences = section.split(RegExp(r'(?<=[.;:])\s'));
    expect(
      sentences.where(
        (sentence) =>
            sentence.toLowerCase().contains('subagent') &&
            sentence.contains('`approve`') &&
            sentence.contains('only with `--dry-run`'),
      ),
      isNotEmpty,
    );
    expect(
      sentences.where(
        (sentence) =>
            sentence.contains('Only the main session') &&
            sentence.contains('`--auto`'),
      ),
      isNotEmpty,
    );
  });

  test("each runner points to the auto approve section with its flow's report "
      'flags', () {
    final problems = [
      for (final MapEntry(key: file, value: flags) in _runnerFlags.entries)
        ..._runnerPointerProblems(file, flags),
    ];
    expect(problems, isEmpty);
  });

  test(
    'both bootstrap skills join a retrim mark to its feature folder batch',
    () {
      for (final skill in _bootstrapSkills) {
        expect(
          _hasSentenceWith(_pluginText(skill), [
            '`retrim_due`',
            'feature folder batch',
          ]),
          isTrue,
          reason: skill,
        );
      }
    },
  );

  test('a trim round dispatches a fresh audit with the round reports as '
      'trims, then fix batches and re-audits, one round at most', () {
    final sentences = _sentencesOf(_pluginText(_trimRound));
    int indexWith(List<String> words) =>
        sentences.indexWhere((sentence) => words.every(sentence.contains));
    final dispatch = indexWith([
      'fresh',
      '`specstone-sdd-auditor`',
      '`trims:`',
      'bootstrap reports',
    ]);
    final fixBatch = indexWith(['fix batch', '`batch:`', 'finding lines']);
    final reaudit = indexWith(['fresh audit', 'hash changed']);
    final cap = indexWith(['one such round']);
    expect(dispatch, isNonNegative, reason: 'audit dispatch');
    expect(fixBatch, greaterThan(dispatch), reason: 'fix batch');
    expect(reaudit, greaterThan(fixBatch), reason: 're-audit');
    expect(cap, greaterThan(reaudit), reason: 'one round');
  });

  test('a bootstrap round with a trim batch approves with one audit flag per '
      'audit report, not no-audit', () {
    final approve = _sentencesOf(
      _sectionOf(_pluginText(_expertSdd), _approveHeading),
    );
    final trimRound = approve.indexWhere(
      (sentence) => [
        'bootstrap round',
        'trim batch',
        'fix batch',
        '`--audit <path>` per audit report of the round',
        'oldest first',
      ].every(sentence.contains),
    );
    expect(trimRound, isNonNegative);
    expect(
      approve.indexWhere((sentence) => sentence.contains('else `--no-audit`')),
      greaterThan(trimRound),
    );
    expect(
      _hasSentenceWith(_pluginText(_trimRound), [
        '"Get the drafts approved"',
        '`--audit` per audit report of the round',
        'in place of `--no-audit`',
      ]),
      isTrue,
    );
    for (final skill in _bootstrapSkills) {
      expect(
        _hasSentenceWith(_pluginText(skill), [
          '"Get the drafts approved"',
          '`--no-audit`',
          'trim batch',
          '`--audit`',
          'per audit report',
        ]),
        isTrue,
        reason: skill,
      );
    }
  });

  test('handed citer and spec move lines start the next round, and a trim run '
      'ends with sync', () {
    final text = _pluginText(_trimRound);
    for (final words in [
      ['`Citers outside:`', '`Spec moves:`', 'starts another round'],
      ['`specstone-sync-sdd`', 'trim', '`verification_coverage`'],
    ]) {
      expect(_hasSentenceWith(text, words), isTrue, reason: words.join(', '));
    }
    for (final MapEntry(key: skill, value: sentences) in {
      'specstone-bootstrap-prd/SKILL.md': [
        [
          '`Citers outside:`',
          'starts a round too when this skill takes its doc',
        ],
        ['`Spec moves:`', 'waits on `specstone-bootstrap-spec`'],
      ],
      'specstone-bootstrap-spec/SKILL.md': [
        [
          '`Spec moves:`',
          '`Citers outside:` line on a doc this skill takes',
          'starts a round too',
        ],
      ],
    }.entries) {
      for (final words in sentences) {
        expect(
          _hasSentenceWith(_pluginText(skill), words),
          isTrue,
          reason: '$skill: ${words.join(', ')}',
        );
      }
    }
  });

  test('a spec move goes to its feature folder spec batch, and a line left '
      'for the other bootstrap skill is listed before the stop', () {
    final trimRound = _pluginText(_trimRound);
    for (final (section, words) in [
      (
        '## Handed lines',
        ['`Spec moves:`', 'feature folder, not a doc', 'spec batch'],
      ),
      ('## Handed lines', ['`Citers outside:`', 'else the rest batch']),
      (
        '## Before you stop',
        [
          '`Waits on specstone-bootstrap-spec:`',
          '`Waits on specstone-bootstrap-prd:`',
          'the report that names it',
        ],
      ),
      ('## Before you stop', ['next round', 'Handed lines']),
    ]) {
      expect(
        _hasSentenceWith(_sectionOf(trimRound, section), words),
        isTrue,
        reason: '$section: ${words.join(', ')}',
      );
    }
    expect(
      _hasSentenceWith(
        _sectionOf(
          _pluginText('specstone-bootstrap-prd/SKILL.md'),
          _bootstrapAfterReports,
        ),
        ['`../$_trimRound`', 'waits and sync before you stop'],
      ),
      isTrue,
    );
    expect(
      _hasSentenceWith(_pluginText('specstone-bootstrap-spec/SKILL.md'), [
        '`batch:`',
        'each line handed to it, by either skill',
      ]),
      isTrue,
    );
  });

  test('both bootstrap skills point to trim-round.md once, in a round with a '
      'trim batch, and it points to no trim.md', () {
    for (final skill in _bootstrapSkills) {
      final sentences = _sentencesOf(
        _sectionOf(_pluginText(skill), _bootstrapAfterReports),
      ).where((sentence) => sentence.contains('trim-round.md'));
      expect(sentences, hasLength(1), reason: skill);
      expect(
        sentences.single,
        allOf(contains('`../$_trimRound`'), contains('trim batch')),
        reason: skill,
      );
    }
    expect(_pluginText(_trimRound), isNot(contains('trim.md')));
  });
}

/// The heading of the bootstrap skills' after-the-reports step.
const _bootstrapAfterReports = '## 3. After the reports';

/// The runner's steps for a bootstrap round with a trim batch.
const _trimRound = 'specstone-expert-sdd/references/trim-round.md';

// MARK: - trim reference

const _trimReference = 'specstone-expert-sdd/references/trim.md';

const _trimStepsHeading = "## A skill's or agent's steps";

const _trimMapHeading = '## The guide lines per section';

/// The table rows under [heading] of [markdown], up to the next `## ` heading.
List<String> _tableRowsOf(String markdown, String heading) {
  final lines = markdown.split('\n');
  final start = lines.indexOf(heading);
  if (start < 0) return [];
  return lines
      .skip(start + 1)
      .takeWhile((line) => !line.startsWith('## '))
      .where((line) => line.startsWith('|'))
      .toList();
}

const _bootstrapProcedures = [
  'specstone-bootstrap-prd/references/procedure.md',
  'specstone-bootstrap-spec/references/procedure.md',
];

const _sizeFix = 'specstone-expert-sdd/references/size-fix.md';

const _engineer = 'specstone-sdd-engineer.md';

const _auditReference = 'specstone-brainstorming-sdd/references/audit.md';

const _bootstrapSkills = [
  'specstone-bootstrap-prd/SKILL.md',
  'specstone-bootstrap-spec/SKILL.md',
];

/// The sentences of [markdown], every whitespace run as one space.
List<String> _sentencesOf(String markdown) =>
    _oneLine(markdown).split(RegExp(r'(?<=[.;])\s'));

/// Whether some sentence of [markdown] holds every one of [words].
bool _hasSentenceWith(String markdown, List<String> words) =>
    _sentencesOf(markdown).any((sentence) => words.every(sentence.contains));

void _trimReferenceTests() {
  test('trim.md names the four outcomes, the cite rewrite through refs, and '
      'the report lines', () {
    final text = _pluginText(_trimReference);
    for (final word in [
      '| keep |',
      '| cut |',
      '| move |',
      '| delete |',
      '`specstone refs <doc>`',
      '`specstone guide <type>`',
      'a range link',
      'a matrix row',
      '`overrides`',
      '`Citers outside:`',
      '`Spec moves:`',
      '`kept: top ID`',
    ]) {
      expect(text, contains(word), reason: word);
    }
  });

  test('trim.md cuts steps, keeps component roles, and prunes diagrams to '
      'contract', () {
    final text = _pluginText(_trimReference);
    final cutRow = text.split('\n').singleWhere((l) => l.startsWith('| cut |'));
    expect(cutRow, contains("a skill's or agent's steps"));
    final section = _sectionOf(text, _trimStepsHeading);
    for (final words in [
      [
        'Outside a Components row and a diagram',
        'move them nowhere',
        "skill's or agent's own files",
      ],
      ['Delete an item', 'only steps', 'unless the IDs section keeps it'],
      [
        'Components row',
        'Responsibility',
        "component's role",
        'never delete the row',
      ],
      ['Behavior diagram', 'contract nodes', 'contract part'],
      ['in-edges', 'out-edges', 'labels', 'decision node'],
      [
        'Interaction sequence diagram',
        'contract messages',
        'a question to the Owner',
        "a dispatch's inputs",
        'a report',
        'a CLI write call with its flags',
        'a limit',
      ],
      ['CLI read call', 'unless', '`--budget`'],
      ["plugin's own parts", 'step order'],
      ['no node or message', 'optional section'],
    ]) {
      expect(
        _hasSentenceWith(section, words),
        isTrue,
        reason: words.join(', '),
      );
    }
  });

  test('trim.md maps each marked section to its guide lines', () {
    final rows = _tableRowsOf(_pluginText(_trimReference), _trimMapHeading);
    for (final words in [
      [
        '`fr` Input / Output and Behavior',
        'item shape line',
        'skill and agent sentences',
        '`behavior`',
      ],
      ['`fr` Edge cases', 'four edge-case lines'],
      ['`fr` Verification', '`verification`'],
      [
        '`architecture` Components, Component details, and Interaction',
        '`architecture` description line',
        "section's own lines",
      ],
      ['`domain` and `project_domain` Invariants', '`invariants`'],
      ['Value objects', '`value_objects`'],
    ]) {
      expect(
        rows.where((row) => words.every(row.contains)),
        hasLength(1),
        reason: words.join(', '),
      );
    }
    expect(
      _hasSentenceWith(
        _sectionOf(_pluginText(_trimReference), _trimMapHeading),
        ['delete each item', 'except a Components row'],
      ),
      isTrue,
    );
  });

  test('trim.md keeps IDs and the top ID, and removes every copy of the '
      'mark', () {
    final text = _pluginText(_trimReference);
    for (final words in [
      ['Renumber no item'],
      ['highest ID', '`kept: top ID`'],
      ['every copy', '`retrim`'],
      ['no id left', 'drop the field'],
      ['`field_value_mismatch`', '`retrim`'],
    ]) {
      expect(_hasSentenceWith(text, words), isTrue, reason: words.join(', '));
    }
  });

  test('a PRD batch trim writes no spec doc and names its moves for the spec '
      'batch', () {
    final section = _sectionOf(_pluginText(_trimReference), '## A PRD batch');
    for (final words in [
      ['writes no spec doc'],
      ['`known_limits`', '`Spec moves:`', 'spec batch'],
      ['Mechanism text', 'never move it'],
      ['Only a spec batch', 'ARCHITECTURE', '`known_limits`'],
    ]) {
      expect(
        _hasSentenceWith(section, words),
        isTrue,
        reason: words.join(', '),
      );
    }
  });

  test('both bootstrap procedures point to trim.md by one line', () {
    for (final procedure in _bootstrapProcedures) {
      final lines = _pluginText(procedure)
          .split('\n')
          .where((line) => line.contains('trim.md'))
          .toList();
      expect(lines, hasLength(1), reason: procedure);
      for (final word in [
        '`../../$_trimReference`',
        '`retrim_due`',
        '`field_value_mismatch` on `retrim`',
      ]) {
        expect(lines.single, contains(word), reason: '$procedure: $word');
      }
    }
  });

  test('size-fix trims an FR past a cap before it proposes a split', () {
    final text = _pluginText(_sizeFix);
    final lines = text.split('\n');
    final trimLines = lines.where((line) => line.contains('`trim.md`'));
    expect(trimLines, hasLength(1));
    final trimLine = lines.indexOf(trimLines.single);
    for (final splitStep in ['**Split.**', '`specstone new fr']) {
      expect(
        trimLine,
        lessThan(lines.indexWhere((line) => line.contains(splitStep))),
        reason: splitStep,
      );
    }
    expect(
      _hasSentenceWith(text, [
        '`item_count_out_of_range`',
        '`chars_over_limit` on an FR',
        '`trim.md`',
      ]),
      isTrue,
    );
    expect(text, isNot(contains('Drop or merge no edge case')));
  });

  test("the auditor takes trims, the engineer an audit's fix batch", () {
    for (final (file, words) in [
      (_auditor, ['`trims`', 'audit', 'bootstrap reports']),
      (_engineer, ['fix batch', '`Findings:` lines', 'trim round']),
    ]) {
      expect(
        _hasSentenceWith(
          _sectionOf(_pluginText(file), '## Input Contract'),
          words,
        ),
        isTrue,
        reason: '$file: ${words.join(', ')}',
      );
    }
  });

  test('the engineer takes handed citer and spec move lines in a bootstrap '
      'batch and applies them by trim.md', () {
    final text = _pluginText(_engineer);
    expect(
      _hasSentenceWith(_sectionOf(text, '## Input Contract'), [
        'each line a trim round handed',
        '`Citers outside:`',
        '`Spec moves:`',
      ]),
      isTrue,
    );
    expect(
      _hasSentenceWith(_sectionOf(text, '## Workflow'), [
        'apply each handed',
        '`Citers outside:`',
        '`Spec moves:`',
        'trim.md',
      ]),
      isTrue,
    );
    expect(
      _hasSentenceWith(_pluginText(_trimReference), [
        'handed a `Citers outside:` line',
        'rewritten cite',
      ]),
      isTrue,
    );
  });

  test('the engineer reports each trimmed item with its guide line and the '
      'trim report lines', () {
    final text = _pluginText(_engineer);
    expect(
      _hasSentenceWith(_sectionOf(text, '## Workflow'), [
        '`retrim_due`',
        'trim.md',
      ]),
      isTrue,
    );
    expect(
      _hasSentenceWith(_sectionOf(text, '## Output Format'), [
        'deleted, moved, and cut item',
        'guide line',
        'rewritten cite',
        '`kept: top ID`',
        '`Citers outside:`',
        '`Spec moves:`',
      ]),
      isTrue,
    );
  });

  test('the audit reads each trimmed item against the guide line its trims '
      'report names', () {
    final compare = _sectionOf(_pluginText(_auditReference), '## 2. Compare');
    for (final words in [
      [
        '**Trim:**',
        '`trims:`',
        'deleted, moved, and cut item',
        'guide line',
        'rewritten cite',
        '`../../$_trimReference`',
      ],
      ['removed item', 'no other doc states', 'restor'],
    ]) {
      expect(
        _hasSentenceWith(compare, words),
        isTrue,
        reason: words.join(', '),
      );
    }
  });

  test('the audit trim lens restores contract parts and no removed step', () {
    final lines = _pluginText(_auditReference).split('\n');
    final start = lines.indexWhere((line) => line.startsWith('- **Trim:**'));
    expect(start, isNonNegative);
    final lens = lines
        .skip(start + 1)
        .takeWhile((line) => line.startsWith('  '))
        .fold(lines[start], (bullet, line) => '$bullet\n$line');
    expect(
      _hasSentenceWith(lens, ['a removed step, per trim.md,', 'is none']),
      isTrue,
    );
    final steps = _sectionOf(_pluginText(_trimReference), _trimStepsHeading);
    for (final words in [
      [
        "`fr` guide's item shape line",
        'contract',
        'when it asks',
        'what it takes',
        'what it reports',
        'its limits',
        'what it may write',
      ],
      ['audit restores a removed contract part', 'never a removed step'],
    ]) {
      expect(_hasSentenceWith(steps, words), isTrue, reason: words.join(', '));
    }
  });

  test('both bootstrap skills join an unmarked FR past a cap only when the '
      'Owner named its kind', () {
    for (final skill in _bootstrapSkills) {
      expect(
        _hasSentenceWith(_pluginText(skill), [
          '`item_over_limit`',
          '`item_count_out_of_range`',
          '`chars_over_limit`',
          'no `retrim_due`',
          'joins its doc',
          'Owner named its kind',
        ]),
        isTrue,
        reason: skill,
      );
    }
  });
}

// MARK: - brainstorm rounds

const _brainstormSkill = 'specstone-brainstorming-sdd/SKILL.md';

const _roundsReference = 'specstone-brainstorming-sdd/references/rounds.md';

const _designReference = 'specstone-brainstorming-sdd/references/design.md';

/// The heading of the rounds reference's Owner-decision section.
const _roundsDecisions = '## 1. Route each Owner decision';

void _brainstormRoundTests() {
  test('the runner sweeps before each design check, then snapshots', () {
    final sentences = _sentencesOf(
      _sectionOf(_pluginText(_roundsReference), _roundsDecisions),
    );
    int indexWith(String word) =>
        sentences.indexWhere((sentence) => sentence.contains(word));
    final sweep = indexWith('`specstone-sdd-sweeper`');
    final rows = indexWith('Rows:');
    final snapshot = indexWith('sdd-auditor.audit.snapshot');
    expect(sweep, isNonNegative, reason: 'sweep');
    expect(rows, greaterThan(sweep), reason: 'rows');
    expect(snapshot, greaterThan(rows), reason: 'snapshot');
  });

  test('a design-check scope takes one delta check at most', () {
    final text = _oneLine(_pluginText(_roundsReference));
    expect(text, contains('one delta check'));
    for (final word in [
      'third delta check',
      'Third delta check',
      'next delta check',
    ]) {
      expect(text, isNot(contains(word)), reason: word);
    }
  });

  test('no subagent or a failed sweep adds no rows', () {
    expect(
      _hasSentenceWith(
        _sectionOf(_pluginText(_roundsReference), _roundsDecisions),
        ['no subagent', 'failed', 'sweep', 'no rows'],
      ),
      isTrue,
    );
  });

  test("design.md takes readers from the sweeper's Rows lines", () {
    final text = _oneLine(_pluginText(_designReference));
    expect(text, contains('`Rows:`'));
    expect(text, isNot(contains('the design check sweeps every reader')));
  });

  test('each brainstorm dispatch follows dispatch.md by its report', () {
    final text = _pluginText(_brainstormSkill);
    for (final words in [
      [
        '../specstone-expert-sdd/references/dispatch.md',
        'sdd-engineer.author',
        'sdd-auditor.audit',
        'sdd-sweeper.sweep',
      ],
      ['`Report:`', 'word for word'],
    ]) {
      expect(_hasSentenceWith(text, words), isTrue, reason: words.join(', '));
    }
  });
  test('the drafts audit takes one fix round or amend pass', () {
    final text = _pluginText(_roundsReference);
    expect(_sectionOf(text, '## 2. Run the fix round'), contains('one round'));
    for (final word in [
      'two rounds',
      'both rounds',
      'after the second',
      'third round',
    ]) {
      expect(_oneLine(text), isNot(contains(word)), reason: word);
    }
  });

  test('an amend past the spent round takes one author pass', () {
    expect(
      _hasSentenceWith(_pluginText(_roundsReference), [
        'round is spent',
        'amend',
        'one author pass',
      ]),
      isTrue,
    );
  });

  test('every brainstorm audit dispatch names specstone-sdd-auditor', () {
    for (final file in [_brainstormSkill, _roundsReference]) {
      expect(
        _inlineSpans(_pluginText(file)),
        isNot(contains('mode: audit')),
        reason: file,
      );
    }
    for (final file in [_brainstormSkill, _roundsReference]) {
      expect(
        _pluginText(file),
        contains('`specstone-sdd-auditor`'),
        reason: file,
      );
    }
  });

  test("the design check tags a decision's removal [behavior]", () {
    expect(
      _hasSentenceWith(
        _sectionOf(_pluginText(_designCheckReference), '## 4. Report'),
        ['`[behavior]`', 'removes a decision'],
      ),
      isTrue,
    );
  });

  test('the Reader missed lens takes gap hits alone', () {
    final lens = _bulletOf(
      _pluginText(_designCheckReference),
      '- **Reader missed:**',
    );
    expect(lens, contains('`gap` hit'));
    expect(_hasSentenceWith(lens, ['`held` hit', 'none']), isTrue);
  });

  test('the sweep marks each hit by three marks and the check prints a Held '
      'line', () {
    final sweep = _pluginText(_sweepReference);
    final marks = _sectionOf(sweep, '## 3. Sweep each decision');
    expect(marks, contains('covered|gap|held: <why>'));
    for (final words in [
      ['`covered` only', 'Decisions cell', '`whole`', 'bare key'],
      ['stay true', '`held: <why>`'],
      ['with no covering row', '(`gap` and `held`)'],
    ]) {
      expect(_hasSentenceWith(marks, words), isTrue, reason: words.join(', '));
    }
    expect(
      sweep,
      contains(
        'Swept: D<n>: <term>, <term>; <n> items hit, <m> with no row, <h> held',
      ),
    );
    expect(
      _hasSentenceWith(_sectionOf(sweep, '## 2. Ground'), [
        "A story's",
        "an FR's",
        '`--summary`',
        '`context project`',
        'several-target bundle',
        'stands in for none',
      ]),
      isTrue,
    );
  });

  test('the design check prints its Held line after the Swept lines', () {
    final check = _pluginText(_designCheckReference);
    final block = _fencedBlock
        .firstMatch(check.substring(check.indexOf('## 4. Report')))!
        .group(1)!;
    expect(block.indexOf('Swept: '), isNonNegative);
    expect(block.indexOf('Held: '), greaterThan(block.indexOf('Swept: ')));
  });

  test('the design check and auditor relays copy Held after Swept', () {
    for (final (file, heading) in [
      (_designCheckReference, '## 4. Report'),
      (_auditor, '## Output Format'),
    ]) {
      final relay = _sentencesOf(_sectionOf(_pluginText(file), heading))
          .firstWhere(
            (sentence) =>
                sentence.contains('`Swept:`') && sentence.contains('`Held:`'),
            orElse: () => '',
          );
      expect(
        relay.indexOf('`Held:`'),
        greaterThan(relay.indexOf('`Swept:`')),
        reason: file,
      );
    }
  });

  test("the sweeper's Rows lines take no row for a held hit", () {
    final rows = _bulletOf(_pluginText(_sweepReference), '- **`Rows:`**');
    expect(_hasSentenceWith(rows, ['a `held` hit takes none']), isTrue);
  });

  test('design.md gives each Docs to change row form', () {
    final text = _pluginText(_designReference);
    final step = _bulletOf(text, '6. **Docs to change**');
    for (final (form, words) in [
      (
        'changed section',
        [
          'by its `get` key',
          'item list in parentheses',
          '`new E19` if added',
          '`E24: <note>`',
        ],
      ),
      (
        'item in the list',
        [
          "item IDs, a row's first cell, a node ID,",
          'a scenario number, quoted words',
        ],
      ),
      ('section rewritten whole', ['`<key> whole` for one rewritten whole']),
      (
        'new doc or every section',
        ['`whole` for a new doc or a rewrite of every section'],
      ),
      ('bare key', ['A key with neither: a design-check line']),
      ("amend's rows", ["Each amend's rows form an `Amend <N> rows` table"]),
    ]) {
      for (final word in words) {
        expect(step, contains(word), reason: '$form: $word');
      }
    }
  });

  test("design.md sends a removed decision's stub rows to removal.md", () {
    expect(
      _hasSentenceWith(
        _sectionOf(_pluginText(_designReference), '## 3. Write the document'),
        ['removes a decision', '`removal.md`', 'stub rows'],
      ),
      isTrue,
    );
  });

  test('removal.md writes a stub row by key with its item list or whole', () {
    final bullet = _bulletOf(_pluginText(_removalReference), '- **Stub rows**');
    for (final word in [
      '`take out the D<n> text: <sections>` in Sections',
      'each with its item list or `whole`',
      '`design.md`',
      'never `all`',
      '`D<n> (Amend <N>, removed)` in Decisions',
    ]) {
      expect(bullet, contains(word), reason: word);
    }
  });

  test('author.md names each section a stub row cell lists', () {
    final list = _bulletOf(_pluginText(_authorReference), '- **Several docs**');
    for (final (form, phrase) in [
      ('row cell with items', '`<key> (<items>)`'),
      ('key whole', '`<key> whole`'),
      ('whole or new doc', '`whole` or a new doc: its bare name'),
      (
        'stub row cell',
        'a stub row cell `take out the D<n> text: <sections>`: each '
            'section it names',
      ),
      ('audit or check line', 'a bare `<key>`: that key'),
      ('anchor', '`#input--output` as `input_output`'),
      ('item or note', "a finding's key with an item or note: the key"),
      ('doc with no key', 'a finding naming a doc with no key: its bare name'),
      ('key no template defines', "`section_not_found`: rerun with its doc's"),
      ('key the doc lacks', 'key the doc lacks: its naming line'),
    ]) {
      expect(list, contains(phrase), reason: form);
    }
  });
}

const _authorReference = 'specstone-brainstorming-sdd/references/author.md';

const _removalReference = 'specstone-brainstorming-sdd/references/removal.md';

/// The text of the bullet of [markdown] whose first line starts with [lead],
/// with its indented lines, every whitespace run as one space; empty when no
/// line starts with [lead].
String _bulletOf(String markdown, String lead) {
  final lines = markdown.split('\n');
  final start = lines.indexWhere((line) => line.startsWith(lead));
  if (start < 0) return '';
  final rest = lines.skip(start + 1).takeWhile((line) => line.startsWith('  '));
  return _oneLine([lines[start], ...rest].join('\n'));
}

// MARK: - glossary move

void _glossaryMoveTests() {
  test('the Moved bullet names `term_bullet_form` and its wait', () {
    final bullet = _bulletOf(_pluginText(_glossaryMove), '- **Moved:**');
    expect(
      _hasSentenceWith(bullet, [
        '`pattern_banned`',
        '`term_bullet_form`',
        'waits for the agent until a later fill round of `bootstrap-prd`',
      ]),
      isTrue,
    );
  });
}
