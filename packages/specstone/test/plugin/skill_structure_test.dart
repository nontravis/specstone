// Test names stay one literal so `specstone check` finds them by exact text.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:convert';
import 'dart:io';

import 'package:specstone/src/command_runner.dart';
import 'package:specstone_core/specstone_core.dart'
    show FormatKey, KeyShape, docTypeFileFormat, packFileFormat;
import 'package:specstone_core/src/setup_migration/host_render.dart';
import 'package:specstone_core/src/setup_migration/models/agent_asset.dart';
import 'package:specstone_core/src/setup_migration/models/rendered_file.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import '../helpers/package_root.dart';
import '../helpers/plugin_content.dart';
import '../helpers/read_fixture.dart';
import '../helpers/temp_tree.dart';
import '../helpers/write_runner.dart';

void main() {
  group('frontmatter', _frontmatterTests);
  group('token budget', _tokenBudgetTests);
  group('references resolve', _referencesResolveTests);
  group('pack doc type', _packDocTypeTests);
  group('cli calls exist', _cliCallsExistTests);
  group('host renders match source', _hostRendersMatchSourceTests);
  group('runs on every host', _runsOnEveryHostTests);
  group('approve step', _approveStepTests);
  group('trim reference', _trimReferenceTests);
  group('brainstorm rounds', _brainstormRoundTests);
  group('brainstorm flow', _brainstormFlowTests);
  group('re-review', _reReviewTests);
  group('fix loop', _fixLoopTests);
  group('author mode', _authorModeTests);
  group('small edit', _smallEditTests);
  group('grounding', _groundingTests);
  group('customize doc types', _customizeDocTypesTests);
  group('plan flow', _planFlowTests);
  group('sync routes', _syncRouteTests);
  group('sync procedure', _syncProcedureTests);
  group('sync engineer', _syncEngineerTests);
  group('bootstrap routing', _bootstrapRoutingTests);
  group('json paths', _jsonPathsTests);
}

// MARK: - Fixtures and readers

const _skillNames = [
  'bootstrap-prd',
  'bootstrap-spec',
  'brainstorming-sdd',
  'customize-doc-types',
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
];

/// The reference files the shipped skills name, each of which must exist.
const _requiredReferences = <String>[
  _syncEntry,
  'specstone-sync-sdd/references/routes.md',
  _syncDecided,
  'specstone-bootstrap-prd/references/procedure.md',
  'specstone-bootstrap-spec/references/procedure.md',
  _trimRound,
  _goalMove,
  'specstone-brainstorming-sdd/references/author.md',
  'specstone-brainstorming-sdd/references/design.md',
  'specstone-brainstorming-sdd/references/audit.md',
  'specstone-brainstorming-sdd/references/trim-audit.md',
  _noDispatchReference,
  _reReviewReference,
  _buildFirstAuditReference,
  _fixLoopReference,
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
    'plan-engineer.part.<XXXXXX>.md',
    'check.plan.<XXXXXX>.txt',
    '<agent>.sync.<XXXXXX>.md',
  ],
  'specstone-sdd-engineer.md': [
    'sdd-engineer.<mode>.<XXXXXX>.md',
    'sdd-engineer.<mode>.batch.<XXXXXX>.txt',
    'sdd-engineer.<mode>.plan.<XXXXXX>.txt',
  ],
  'specstone-bootstrap-prd/SKILL.md': ['sdd-engineer.bootstrap.<XXXXXX>.md'],
  _goalMove: ['sdd-engineer.bootstrap.batch.<XXXXXX>.txt'],
  _glossaryMove: ['sdd-engineer.bootstrap.batch.<XXXXXX>.txt'],
  'specstone-bootstrap-spec/SKILL.md': ['sdd-engineer.bootstrap.<XXXXXX>.md'],
  'specstone-brainstorming-sdd/SKILL.md': [
    'sdd-engineer.author.<XXXXXX>.md',
    'sdd-auditor.audit.<XXXXXX>.md',
  ],
  'specstone-brainstorming-sdd/references/author.md': [
    'sdd-engineer.author.batch.<XXXXXX>.txt',
    'sdd-engineer.author.plan.<XXXXXX>.txt',
  ],
  'specstone-brainstorming-sdd/references/source.md': [
    'sdd-engineer.design.source.<XXXXXX>.md',
  ],
  'specstone-plan-sdd/SKILL.md': ['plan-engineer.plan.<XXXXXX>.md'],
  _planGroups: [
    'plan-engineer.plan.<XXXXXX>.md',
    'plan-engineer.part.<XXXXXX>.md',
  ],
  'specstone-sync-sdd/SKILL.md': [
    'sdd-engineer.sync.<XXXXXX>.md',
    '<agent>.sync.<XXXXXX>.md',
  ],
  'specstone-expert-sdd/references/approve.md': [
    'sdd-auditor.audit.queued.<XXXXXX>.md',
  ],
  'specstone-expert-sdd/references/trim-round.md': [
    'sdd-auditor.audit.<XXXXXX>.md',
  ],
  _fixLoopReference: ['sdd-auditor.audit.<XXXXXX>.md'],
  'specstone-sdd-auditor.md': ['sdd-auditor.audit.<XXXXXX>.md'],
};

const _reportsFolder = '<folder>/reports/';

final _agentFilePath =
    '<folder>/reports/(?:(?:sdd-engineer|sdd-auditor|'
    r'plan-engineer)\.(?:<mode>|[a-z]+)\.'
    r'(?:(?:batch|source|queued|plan)\.)?<XXXXXX>\.(?:md|txt)|'
    r'<agent>\.sync\.<XXXXXX>\.md|check\.'
    '(?:${checkRoles.join('|')}|<role>)'
    r'\.<XXXXXX>\.txt|guide\.<XXXXXX>\.(?:txt|json))';

/// A code span naming an agent file by its AgentFileName under
/// [_reportsFolder], bare or as the quoted `--out` of a `specstone check` or
/// `specstone guide`; the file is group 1 or 2.
final _agentFileSpan = RegExp(
  '^(?:($_agentFilePath)|'
  'specstone (?:check|guide|move)(?: [^\\s"]+)* --out "($_agentFilePath)")\$',
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
  return unknownCliNames(
    contentFilesOf(root),
    SpecstoneCommandRunner(console: FakeConsole()),
  );
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
}) => ContentFile(
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

  test('the engineer source preloads expert-sdd alone and lists no '
      'Skill tool', () {
    final text = _pluginText('specstone-sdd-engineer.md');
    final head = text.substring(0, text.indexOf('\n---\n', 4));
    final skills = _skillsOf(head);
    expect(skills, ['specstone-expert-sdd']);
    expect(_toolsOf(text, 'tools'), ['Bash', 'Read', 'Grep', 'Write', 'Edit']);
  });

  test('the auditor preloads expert-sdd and read-sdd', () {
    final text = _pluginText(_auditor);
    final head = text.substring(0, text.indexOf('\n---\n', 4));
    expect(_skillsOf(head), ['specstone-expert-sdd', 'specstone-read-sdd']);
    expect(_toolsOf(text, 'tools'), ['Bash', 'Read', 'Grep', 'Write']);
  });

  test('the auditor runs approve only as a dry run', () {
    final spans = _approveSpans(_pluginText(_auditor));
    expect(spans, isNotEmpty);
    for (final span in spans) {
      expect(span, contains('--dry-run'), reason: span);
    }
  });

  test('audit.md and trim-audit.md name the auditor as runner', () {
    for (final file in [_auditReference, _trimAuditReference]) {
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

const _auditor = 'specstone-sdd-auditor.md';

/// Each `specstone approve` code span of [markdown], a span wrapped over lines
/// read whole.
List<String> _approveSpans(String markdown) => [
  for (final span in _inlineSpans(markdown))
    if (span.contains('specstone approve')) span,
];

// MARK: - sync routes

const _syncSkill = 'specstone-sync-sdd/SKILL.md';

const _syncRoutes = 'specstone-sync-sdd/references/routes.md';

const _syncFirstStep = '## 1. The first call';

const _syncRouteStep = '## 2. Route each group';

const _routesHeading = '## Routes';

/// Whether [call], the words after `specstone context`, asks for the sync
/// mode.
bool _isSyncCall(List<String> call) {
  final mode = call.indexOf('--for');
  return mode >= 0 && mode + 1 < call.length && call[mode + 1] == 'sync';
}

void _syncRouteTests() {
  test('sync starts with one context --for sync --out call and no check', () {
    final skill = _pluginText(_syncSkill);
    final first = _sectionOf(skill, _syncFirstStep);
    expect(first, contains('`specstone context --for sync --out`'));
    expect(cliCommands(first).first, 'context');
    expect(cliCommands(skill), isNot(contains('check')));
  });

  test('a sync dispatch passes its scope and its group file path', () {
    final skill = _pluginText(_syncSkill);
    final dispatch = _sentencesOf(_sectionOf(skill, _syncRouteStep))
        .where((line) => line.contains('dispatch `specstone-sdd-engineer`'));
    expect(dispatch, hasLength(1));
    expect(
      dispatch.single,
      allOf(
        contains('`mode: sync`'),
        contains('`scope: feature:<name>`'),
        contains('`group file:`'),
      ),
    );
    expect(skill, isNot(contains('`check:`')));
  });

  test('sync routes run every group at once, with no uncovered group last', () {
    final rows = _tableRowsOf(_pluginText(_syncRoutes), _routesHeading);
    String rowOf(String word) =>
        rows.singleWhere((row) => row.startsWith('| `$word` |'));
    expect(rows.where((row) => row.startsWith('| `')), hasLength(2));
    expect(rowOf('small'), contains('`specstone set --sync`'));
    expect(rowOf('engineer'), contains('at once'));
    expect(_pluginText(_syncSkill), isNot(contains('`last`')));
  });

  // D1
  test(
    'at a last sync the decided engineer runs before every engineer group',
    () {
      final routes = _pluginText(_syncRoutes);
      expect(
        _hasSentenceWith(_sectionOf(routes, '## Order'), [
          'decided engineer',
          'before',
        ]),
        isTrue,
      );
      final small = _sectionOf(routes, '## Small group');
      final decidedLine = _sentencesOf(small)
          .where((sentence) => sentence.contains('decided behavior'));
      expect(decidedLine, isNotEmpty);
      for (final sentence in decidedLine) {
        expect(sentence, isNot(contains('drafts')));
      }
    },
  );

  // D1
  test('an empty work list stops unless a change note sent the decided '
      'engineer', () {
    final skill = _pluginText(_syncSkill);
    final first = _sectionOf(skill, _syncFirstStep);
    expect(
      _hasSentenceWith(first, [
        'no code changed',
        'stop',
        'no dispatch',
        'unless',
        '`change note`',
      ]),
      isTrue,
    );
    final noSubagent = skill
        .split('\n')
        .singleWhere((line) => line.startsWith('- No subagent:'));
    expect(
      noSubagent,
      allOf(
        contains('`change note`'),
        contains('Decided-only run'),
        isNot(contains("main's own")),
      ),
    );
  });

  // D1
  test('one decided engineer takes every decided decision before the group '
      'wave', () {
    final skill = _pluginText(_syncSkill);
    final first = _sectionOf(skill, _syncFirstStep);
    final dispatch = _sentencesOf(first).where(
      (sentence) => [
        '`decided:`',
        '`change note:`',
        'every',
        '(decided)',
      ].every(sentence.contains),
    );
    expect(dispatch, hasLength(1));
    expect(dispatch.single, isNot(contains('`scope: feature:<name>`')));
    expect(_hasSentenceWith(first, ['report', '`engineer`', 'once']), isTrue);
    final after = _sectionOf(skill, '## 3. After the report');
    expect(after, isNot(contains('`decided:`')));
    expect(after, isNot(contains('Not landed: D')));
  });

  test('no later sync step runs a second context --for sync call', () {
    final files = [
      _syncSkill,
      ..._requiredReferences.where(
        (file) => file.startsWith('specstone-sync-sdd/'),
      ),
    ];
    final syncCalls = [
      for (final file in files)
        for (final call in _contextCalls(_pluginText(file)))
          if (_isSyncCall(call)) '$file: ${call.join(' ')}',
    ];
    final firstStepCalls = _contextCalls(
      _sectionOf(_pluginText(_syncSkill), _syncFirstStep),
    ).where(_isSyncCall);
    expect(firstStepCalls, isNotEmpty);
    expect(syncCalls, hasLength(firstStepCalls.length));
  });
}

// MARK: - sync procedure

/// The decided-line steps of a sync engineer given a change note.
const _syncDecided = 'specstone-sync-sdd/references/decided.md';

void _syncProcedureTests() {
  test(
    'sync procedure judges a group file and writes it by one set --sync',
    () {
      final procedure = _pluginText(_syncEntry);
      expect(procedure, contains('`==> verdicts <==`'));
      expect(
        '`specstone set --sync <group file>`'.allMatches(procedure),
        hasLength(1),
      );
      expect('context --code'.allMatches(procedure), hasLength(1));
      expect('specstone check'.allMatches(procedure), hasLength(1));
      for (final file in [_syncSkill, _syncEntry]) {
        expect(_pluginText(file), isNot(contains('--stamp')), reason: file);
      }
    },
  );

  test(
    'sync procedure lists a covers path outside entry and never repoints it',
    () {
      final procedure = _pluginText(_syncEntry);
      final judging = _sectionOf(
        procedure,
        '## 2. Judge each line',
      ).split('\n');
      expect(
        judging.any(
          (line) =>
              line.contains('`covers_path_outside`') &&
              line.contains('<doc>: covers path outside: <entry>') &&
              line.contains('repoint'),
        ),
        isTrue,
      );
      expect(
        _sectionOf(procedure, '## Report'),
        contains("step 2's `covers` report lines"),
      );
    },
  );

  test('sync procedure shows a repoint line with an optional new symbol', () {
    final judging = _sectionOf(
      _pluginText(_syncEntry),
      '## 2. Judge each line',
    );
    expect(
      judging,
      contains('repoint <doc> <entry> <new path>[:<new symbol>]'),
    );
  });

  test(
    'sync names an unstated behavior point and routes it to a PRD change',
    () {
      final judging = _sectionOf(
        _pluginText(_syncEntry),
        '## 2. Judge each line',
      ).split('\n');
      expect(
        judging.any(
          (line) =>
              line.contains('`unstated behavior`') &&
              line.contains('`specstone context --code ') &&
              line.contains(' --for implement --out`') &&
              line.contains('`specstone context <story> --for implement'),
        ),
        isTrue,
        reason:
            'the PRD docs of the path and the FR text of each story it '
            'lists are read before the point',
      );
      expect(
        _hasSentenceWith(
          _sectionOf(_pluginText(_syncSkill), '## 3. After the report'),
          ['unstated behavior', 'PRD'],
        ),
        isTrue,
      );
    },
  );

  test(
    'matrix rows write row lines, each stamped by a following match line',
    () {
      final rows = _sectionOf(_pluginText(_syncEntry), '## Matrix rows');
      expect(rows, contains('`row <record> <item>[ <edge case>]: '));
      expect(rows, isNot(contains('--replace')));
      expect(rows, isNot(contains('specstone get')));
      expect(rows, isNot(contains('specstone check')));
    },
  );

  test('no sync file names uncovered code, its scope, or a helper test', () {
    final files = [
      _syncSkill,
      ..._requiredReferences.where(
        (file) => file.startsWith('specstone-sync-sdd/'),
      ),
      _engineer,
    ];
    final removed = [
      RegExp('`code_uncovered`'),
      RegExp('Uncovered:'),
      RegExp(r'`(scope:\s+)?uncovered`'),
      RegExp(r'uncovered`?\s+scope'),
      RegExp(r'write(-|\s+)a(-|\s+)spec'),
      RegExp(r'helpers\.md'),
    ];
    for (final file in files) {
      final text = _pluginText(file);
      for (final pattern in removed) {
        expect(text, isNot(contains(pattern)), reason: '$file: $pattern');
      }
    }
  });

  test('no sync file runs a set --remove-task left waiting for main', () {
    final files = [
      _syncSkill,
      ..._requiredReferences.where(
        (file) => file.startsWith('specstone-sync-sdd/'),
      ),
    ];
    for (final file in files) {
      expect(_pluginText(file), isNot(contains('--remove-task')), reason: file);
    }
  });
}

// MARK: - sync engineer

void _syncEngineerTests() {
  test('the engineer file names one entry file per mode and holds no '
      'mode steps', () {
    final text = _pluginText(_engineer);
    final loads = _sectionOf(text, '## On-Demand Loads').split('\n');
    for (final (cue, file) in [
      ('`mode: author`', _authorEntry),
      ('`mode: sync`', _syncEntry),
      ('`procedure: bootstrap-prd`', _bootstrapEntries[0]),
      ('`procedure: bootstrap-spec`', _bootstrapEntries[1]),
    ]) {
      expect(
        loads.any(
          (line) => line.contains(cue) && line.contains('.agents/skills/$file'),
        ),
        isTrue,
        reason: cue,
      );
    }
  });

  test('each bootstrap entry file names its mode files', () {
    for (final (entry, modeFiles) in [
      (_bootstrapEntries[0], ['`goal-move.md`', '`glossary-move.md`']),
      (_bootstrapEntries[1], ['`merge-untyped.md`']),
    ]) {
      final text = _pluginText(entry);
      for (final name in [
        '`procedure.md`',
        ...modeFiles,
        '`../../specstone-expert-sdd/references/size-fix.md`',
        '`../../specstone-expert-sdd/references/repeats.md`',
        '`../../specstone-expert-sdd/references/trim.md`',
      ]) {
        expect(text, contains(name), reason: '$entry: $name');
      }
    }
  });

  test('the sync entry file holds its numbered steps and its matrix rows', () {
    final lines = _pluginText(_syncEntry).split('\n');
    expect(
      lines,
      containsAll([
        '## 1. Read the group file',
        '## 5. Spec drafts',
        '## Matrix rows',
        '## Report',
      ]),
    );
  });

  test(
    'the engineer hands a change-the-PRD pick on and writes no doc for it',
    () {
      final picks = _sectionOf(_pluginText(_engineer), '## Input Contract')
          .split(RegExp(r'(?= - \*\*`)'))
          .singleWhere((bullet) => bullet.contains('**`picks`**'));
      expect(
        picks,
        matches(
          RegExp(
            r'change-the-PRD\s+pick[\s\S]*handed\s+behavior'
            r'[\s\S]*writes?\s+no\s+doc',
          ),
        ),
      );
    },
  );

  test('the sync engineer takes decided ids in place of a group file', () {
    final bullets = _sectionOf(
      _pluginText(_engineer),
      '## Input Contract',
    ).split(RegExp(r'(?= - \*\*`)'));
    final decided = bullets.singleWhere(
      (bullet) => bullet.contains('**`decided`**'),
    );
    final groupFile = bullets.singleWhere(
      (bullet) => bullet.contains('**`group file`**'),
    );
    // D1
    expect(
      decided,
      allOf(
        contains('`change note`'),
        contains('`group file`'),
        contains('every'),
        contains('before'),
      ),
    );
    expect(groupFile, contains('`decided`'));
  });

  test('a group sync engineer judges its links against the decided lines and '
      'drafts none', () {
    // D1
    final section = _sectionOf(
      _pluginText(_syncDecided),
      '## 1. Judge against the decided lines',
    );
    expect(section, allOf(contains('match'), contains('Mismatches:')));
    for (final word in [
      'specstone set',
      'specstone new',
      'Decision:',
      'Not landed:',
    ]) {
      expect(section, isNot(contains(word)), reason: word);
    }
    final outputFormat = _sectionOf(_pluginText(_engineer), '## Output Format');
    final bullet = outputFormat
        .split(RegExp(r'(?= - \*\*)'))
        .singleWhere((b) => b.contains('**Sync with a change note**'));
    expect(bullet, isNot(contains("group's work holds")));
    final report = _sectionOf(_pluginText(_syncEntry), '## Report')
        .split(RegExp('(?= - )'))
        .singleWhere(
          (b) => b.contains('A group engineer with a `change note`'),
        );
    expect(report, allOf(contains('decided engineer'), contains('decided.md')));
  });

  test('the decided engineer drafts or names the carrying section of every '
      'decided id', () {
    // D1
    final text = _pluginText(_syncDecided);
    final section = _sectionOf(text, '## Decided-only run');
    expect(
      section,
      allOf(
        contains('## 2. Find the readers'),
        contains('--for design'),
        contains('Decision:'),
        contains('carr'),
        contains('Not landed:'),
      ),
    );
    final lines = text.split('\n');
    expect(lines, isNot(contains('## 2. Find the readers')));
    expect(lines, isNot(contains('## 3. Draft')));
  });

  test('a decided-only sync engineer drafts and writes no pointer or '
      'fingerprint', () {
    final section = _sectionOf(
      _pluginText(_syncDecided),
      '## Decided-only run',
    );
    expect(section, isNotEmpty);
    expect(section, allOf(contains('Decision:'), contains('Not landed:')));
    expect(section, isNot(contains('set --sync')));
    expect(_hasSentenceWith(section, ['pointer', 'fingerprint']), isTrue);
    expect(
      _hasSentenceWith(section, ['`specstone context', '--for design']),
      isTrue,
    );
    expect(
      _hasSentenceWith(_pluginText(_syncEntry), [
        'decided-only run has no group file',
        'no gate',
        'no `Check:` line',
      ]),
      isTrue,
    );
    expect(
      _pluginText(_syncEntry),
      allOf(contains('`decided`'), contains('## Decided-only run')),
    );
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

  test('every shipped skill file but the merged references stays within '
      '1,500 est. tokens', () {
    final files = contentFiles();
    expect(files.where((file) => file.isSkillFile), isNotEmpty);
    expect(files.map((file) => file.path), contains(_reReviewReference));
    expect(
      oversizedSkillFiles([
        for (final file in files)
          if (!_mergedReferenceTokens.keys.any(
            (path) => file.path == path || file.path.endsWith('/$path'),
          ))
            file,
      ]),
      isEmpty,
    );
  });

  test('each bootstrap procedure and merged reference stays within its '
      'est. tokens', () {
    final paths = contentFiles().map((file) => file.path);
    for (final MapEntry(key: file, value: tokens) in {
      ..._bootstrapProcedureTokens,
      ..._mergedReferenceTokens,
    }.entries) {
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

/// Each reference that took in its split family as one file, by the Owner's
/// ruling, and its est. tokens: at most 10,000 characters.
const _mergedReferenceTokens = <String, int>{
  _authorReference: 2500,
  _syncEntry: 2500,
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
      expect(
        seen.where((path) => path.endsWith('/SKILL.md')),
        hasLength(_skillNames.length),
      );
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

  test('the ten skills and four agents are all there', () {
    expect(
      _skillFolders().map(_baseNameOf),
      unorderedEquals([for (final name in _skillNames) 'specstone-$name']),
    );
    expect(
      _agentFiles().map(_baseNameOf),
      unorderedEquals([for (final name in _agentNames) 'specstone-$name']),
    );
  });

  for (final reference in _requiredReferences) {
    test('$reference exists', () {
      final file = File.fromUri(agentAssetsRoot().uri.resolve(reference));
      expect(file.existsSync(), isTrue, reason: '$reference is missing');
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

  test('a skill file naming superpowers:writing-plans fails naming the file and the span', () async {
    final cases = [
      (
        reason: 'another plugin skill in a skill file',
        files: {
          'specstone-x/SKILL.md': 'Then run `superpowers:writing-plans`.',
        },
        problems: [
          "specstone-x/SKILL.md: superpowers:writing-plans is another plugin's skill",
        ],
      ),
      (
        reason: 'path:line in an agent file',
        files: {'specstone-a.md': 'Cite each hit as `path:line`.'},
        problems: ["specstone-a.md: path:line is another plugin's skill"],
      ),
      (
        reason: 'specstone:<name> in a skill file and an agent file',
        files: {
          'specstone-x/SKILL.md': 'Follow `specstone:read-sdd`.',
          'specstone-a.md':
              'Follow `specstone:read-sdd`, not `specstone-read-sdd`.',
        },
        problems: [
          "specstone-a.md: specstone:read-sdd is another plugin's skill",
          "specstone-x/SKILL.md: specstone:read-sdd is another plugin's skill",
        ],
      ),
    ];
    for (final c in cases) {
      final root = await writeTree(c.files);
      expect(
        otherPluginSkillNames(contentFilesOf(root), shippedDocTypes()),
        c.problems,
        reason: c.reason,
      );
    }
  });

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
    expect(
      unknownCliNames(files, SpecstoneCommandRunner(console: FakeConsole())),
      isEmpty,
    );
    expect(hostTiedText(files), isEmpty);
    expect(skillHeadProblems(files), isEmpty);
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

// MARK: - pack doc type

void _packDocTypeTests() {
  Future<List<String>> namesIn(String text) async {
    final root = await writeTree({'specstone-x/SKILL.md': text});
    return packDocTypeNames(
      contentFilesOf(root),
      PackDocTypes.shipped(),
      cliWords: cliWordsOf(SpecstoneCommandRunner(console: FakeConsole())),
    );
  }

  test(
    'a file naming architecture:login fails naming its file and architecture',
    () async {
      for (final (text, type) in [
        ('Open `architecture:login` first.', 'architecture'),
        ('Open domain:login first.', 'domain'),
      ]) {
        expect(await namesIn(text), [
          'specstone-x/SKILL.md: $type',
        ], reason: text);
      }
    },
  );

  test('a file naming ARCHITECTURE.md fails naming the architecture type', () {
    expect(
      namesIn('Read ARCHITECTURE.md first.'),
      completion(['specstone-x/SKILL.md: architecture']),
    );
  });

  test('retired doc types hold with no pack migration read', () {
    expect(PackDocTypes.fromPackFiles(const {}).fileNameById, {
      'error': 'ERROR.md',
      'project_error': 'ERROR.md',
      'domain': 'DOMAIN.md',
      'project_domain': 'DOMAIN.md',
      'project_integration': 'INTEGRATION.md',
      'auth': 'AUTH.md',
      'project_auth': 'AUTH.md',
      'topic': null,
    });
  });

  test('a bare id, a stem, or prose such as the architecture doc passes', () {
    expect(
      namesIn(
        'Read the architecture doc, the ARCHITECTURE stem, and security.',
      ),
      completion(isEmpty),
    );
  });

  // D4
  test('a code span naming a pack type id or a section key only such a type '
      'defines fails naming the type', () {
    expect(
      namesIn('Read `api` and `fr_trace` first.'),
      completion([
        'specstone-x/SKILL.md: api',
        'specstone-x/SKILL.md: fr_trace of api, project_api',
      ]),
    );
  });

  // D4
  test('a fenced line, prose, and a span that is a CLI command or flag '
      'pass', () {
    expect(
      namesIn(
        '```\n`api`\n```\n'
        'The api and fr_trace words are prose.\n'
        'Run `context`, `audit`, and `plan`.\n',
      ),
      completion(isEmpty),
    );
  });

  test('a prd-core address such as fr:login/x passes', () {
    expect(
      namesIn('Open fr:login/x and user_story:login.'),
      completion(isEmpty),
    );
  });

  test('shipped skill, reference, and agent files hold no non-prd-core pack '
      'type', () {
    final files = contentFiles();
    expect(files, isNotEmpty);
    expect(
      packDocTypeNames(
        files,
        PackDocTypes.shipped(),
        cliWords: cliWordsOf(SpecstoneCommandRunner(console: FakeConsole())),
      ),
      isEmpty,
    );
  });

  test('merge-untyped.md and trim.md name no pack type id, no pack type doc, '
      'and no `## <section>` span', () {
    final ids = PackDocTypes.shipped().fileNameById.keys.map(RegExp.escape);
    final idSpan = RegExp('`(${ids.join('|')})`');
    final idDoc = RegExp('\\b(${ids.join('|')}) doc\\b');
    final sectionSpan = RegExp('`## [^`]+`');
    final problems = <String>[];
    for (final file in [_mergeUntyped, _trimReference]) {
      final text = _pluginText(file);
      for (final pattern in [idSpan, idDoc, sectionSpan]) {
        for (final match in pattern.allMatches(text)) {
          problems.add('$file: ${match.group(0)}');
        }
      }
    }
    expect(problems, isEmpty);
  });
}

// MARK: - cli calls exist

void _cliCallsExistTests() {
  test(
    'a skill naming specstone check --fix fails naming its file and --fix',
    () async {
      for (final file in ['specstone-x/SKILL.md', 'specstone-a.md']) {
        expect(await _problemsOf({file: 'Run `specstone check --fix`.'}), [
          '$file: specstone check has no --fix',
        ], reason: file);
      }
    },
  );

  test('a command the CLI lacks fails naming it', () async {
    expect(
      await _problemsOf({'specstone-x/SKILL.md': 'Run `specstone lint docs`.'}),
      ['specstone-x/SKILL.md: specstone has no command lint'],
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
    expect([
      for (final leg in matrix['leg'] as YamlList) (leg as YamlMap)['suite'],
    ], contains('cli'));
    final cliRuns = [
      for (final step in job['steps'] as YamlList)
        if (step is YamlMap &&
            step['working-directory'] == 'packages/specstone' &&
            '${step['if']}'.contains("matrix.leg.suite == 'cli'") &&
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
    expect(
      unknownCliNames(files, SpecstoneCommandRunner(console: FakeConsole())),
      isEmpty,
    );
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
        ], reason: render.path);
      }
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

  test(
    'a backticked host tool name in a body fails, any of the quoted set',
    () {
      for (final tool in [
        'Skill',
        'Agent',
        'Write',
        'Edit',
        'Read',
        'Grep',
        'Glob',
        'Bash',
        'Task',
        'WebFetch',
        'WebSearch',
        'AskUserQuestion',
        'TodoWrite',
        'MultiEdit',
        'NotebookEdit',
      ]) {
        expect(
          hostTiedText([_file('specstone-a.md', 'Change it with `$tool`.')]),
          ['specstone-a.md: `$tool`'],
          reason: tool,
        );
      }
    },
  );

  test(
    'a backticked host tool call in a body fails, as Grep(x) or Bash(x)',
    () {
      for (final call in ['Grep(pattern)', 'Bash(git:*)', 'Read(file)']) {
        expect(hostTiedText([_file('specstone-a.md', 'Call `$call` on it.')]), [
          'specstone-a.md: `$call`',
        ], reason: call);
      }
      expect(
        hostTiedText([_file('specstone-a.md', 'Call `Readme(x)` on it.')]),
        isEmpty,
      );
    },
  );

  test('a bare or backticked Grep, Glob, or Bash in a body fails', () {
    expect(
      hostTiedText([
        _file('specstone-a.md', 'Search it with Grep.\nRun it with `Bash`.\n'),
      ]),
      ['specstone-a.md: Grep', 'specstone-a.md: `Bash`'],
    );
    for (final tool in [
      'Grep',
      'Glob',
      'Bash',
      'WebFetch',
      'WebSearch',
      'AskUserQuestion',
      'TodoWrite',
      'MultiEdit',
      'NotebookEdit',
    ]) {
      expect(
        hostTiedText([_file('specstone-a.md', 'Find it through $tool, then.')]),
        ['specstone-a.md: $tool'],
        reason: tool,
      );
    }
  });

  test('Read opening a sentence, a bare Edit, and a lowercase grep pass', () {
    expect(
      hostTiedText([
        _file(
          'specstone-a.md',
          'Read the file.\nEdit it.\nSearch it with `grep -n -E`.\n'
              'Run grep on it, then bash.\n```\nGrep\n```\n',
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

  test('dispatch.md names the four dispatchable agents and no other', () {
    final named = RegExp('`(specstone-(?:sdd-[a-z]+|plan-engineer))`')
        .allMatches(_pluginText(_dispatchReference))
        .map((m) => m.group(1))
        .toSet();
    expect(named, {
      'specstone-sdd-engineer',
      'specstone-sdd-auditor',
      'specstone-sdd-reader',
      'specstone-plan-engineer',
    });
  });

  test('dispatch.md tries the named, generic, and main-session rungs in '
      'order with no resume rung', () {
    final text = _pluginText(_dispatchReference);
    final headings = text.split('\n').where((l) => l.startsWith('## '));
    expect(headings, [
      '## Named agent',
      '## Generic subagent',
      '## Main session',
    ]);
  });
}

/// The rungs every dispatching skill points to.
const _dispatchReference = 'specstone-expert-sdd/references/dispatch.md';

// MARK: - approve step

const _expertSdd = 'specstone-expert-sdd/SKILL.md';

const _approveHeading = '## Get the drafts approved';

/// The reference file that holds the approval steps.
const _approveRef = 'specstone-expert-sdd/references/approve.md';

/// The path a runner skill names the approval reference file by.
const _approvePath = '../$_approveRef';

/// The opening words of the approval step that runs the `--auto` call.
const _approveCallStep =
    'Run one `specstone approve <type>:<name> … --auto --json`';

/// The report flags each runner skill's approval names, by skill file.
const _runnerFlags = {
  'specstone-brainstorming-sdd/SKILL.md': ['--audit', '--author'],
  'specstone-update-sdd/SKILL.md': ['--no-audit'],
  'specstone-sync-sdd/SKILL.md': ['--audit', '--no-audit'],
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

/// Words of the approval steps that no runner restates.
const _approveStepWords = [
  '--auto',
  '--dry-run',
  '`doc`, `path`,',
  '`asked`',
  '`Why:`',
  'approve-mode',
];

/// One problem per way runner skill [file] fails to point to expert-sdd's
/// approval reference file with exactly its [flags], holding no copy of it.
List<String> _runnerPointerProblems(String file, List<String> flags) {
  final text = _pluginText(file);
  final body = _oneLine(
    text.split('\n').where((line) => !line.startsWith('#')).join('\n'),
  );
  final title = _approveHeading.substring('## '.length);
  bool isPointer(String span) => span.contains(_approvePath);
  final pointers = body
      .split(RegExp(r'(?<=[.;])\s'))
      .where(isPointer)
      .join(' ');
  final redFlagRows = text
      .split('\n')
      .skipWhile((line) => line != '## Red flags')
      .where((line) => line.startsWith('|') && line.contains(_approvePath));
  return [
    if (pointers.isEmpty) '$file: no pointer to $_approvePath',
    if (body.contains(title)) '$file: names "$title"',
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
  test('expert-sdd holds the auto approve step once, in its approval reference '
      'file', () {
    final lines = _pluginText(_expertSdd).split('\n');
    expect(lines.where((line) => line == _approveHeading), hasLength(1));
    expect(
      lines.indexOf(_approveHeading),
      lessThan(lines.indexOf('## Owner confirmation')),
    );
    expect(
      _sectionOf(_pluginText(_expertSdd), _approveHeading),
      contains('references/approve.md'),
    );
    final section = _approveText();
    for (final word in [
      'specstone approve',
      '--auto',
      '--json',
      '--audit',
      '--author',
      '--no-audit',
      '`approved`',
      '`doc`, `path`,',
      '`asked`',
      'Exit 75',
      'waitsFor',
      'Queued:',
      'refs',
      'sdd-auditor.audit.queued.<XXXXXX>.md',
    ]) {
      expect(section, contains(word), reason: word);
    }
    expect(
      [
        for (final file in _skillAndAgentFiles())
          if (_oneLine(_pluginText(file)).contains(_approveCallStep)) file,
      ],
      [_approveRef],
    );
  });

  // D8
  test('a Build-first approval takes the decided engineer report as its one '
      'author', () {
    // D7
    // D1
    final approve = _approveText();
    expect(approve, isNot(contains('once per sync engineer report')));
    expect(approve, contains("the decided engineer's report"));
    expect(
      approve,
      matches(RegExp("decided engineer's report[^;]*`--author <path>`")),
    );
    final audit = _oneLine(_pluginText(_buildFirstAuditReference));
    expect(audit, isNot(contains('each sync engineer report')));
    final ground = audit.substring(audit.indexOf('1. **Hashes and ground**'));
    expect(
      ground.substring(0, ground.indexOf('2. **Read**')),
      allOf(contains('`Decision:`'), contains('carr')),
    );
  });

  // D8
  test('a sync approves every draft it wrote in one step after its last '
      'rerun', () {
    // D2
    final sentences = _sentencesOf(
      _sectionOf(_pluginText(_syncSkill), '## 3. After the report'),
    );
    final pointers = [
      for (final (index, sentence) in sentences.indexed)
        if (sentence.contains(_approvePath)) index,
    ];
    expect(pointers, hasLength(1));
    final specFix = sentences.indexWhere((s) => s.contains('A spec fix'));
    expect(specFix, isNonNegative);
    expect(pointers.single, greaterThan(specFix));
    expect(
      sentences[pointers.single],
      allOf(contains('--audit'), contains('--no-audit')),
    );
    expect(
      _hasSentenceWith(sentences.join(' '), [
        'build-first-audit',
        'every draft',
      ]),
      isTrue,
    );
  });

  test('expert-sdd sends behavior no PRD doc states to the Owner, never to a spec draft', () {
    final text = _pluginText(_expertSdd);
    final flat = _oneLine(text);
    final start = flat.indexOf('1. **Docs lead.**');
    final rule = flat.substring(start, flat.indexOf(' 2. ', start));
    expect(
      rule,
      matches(RegExp(r'requirement\s+change.*Owner\s+decides.*PRD\s+first')),
    );
    expect(rule, isNot(contains('spec draft')));
    expect(
      rule,
      matches(
        RegExp(
          r'one\s+exception.*decided\s+line.*until\s+the\s+plan.s\s+last\s+task',
        ),
      ),
    );
    final description = text
        .split('\n')
        .firstWhere((line) => line.startsWith('description:'));
    expect(description, isNot(contains('no spec states')));
  });

  test('gated-plan names the delete and migrate plan commands and Owner '
      'confirmation points to it twice', () {
    final plan = _pluginText('specstone-expert-sdd/references/gated-plan.md');
    for (final command in [
      '`specstone delete <path> … --yes --plan <hash>`',
      '`specstone migrate --yes --plan <hash>`',
    ]) {
      expect(plan, contains(command), reason: command);
    }
    expect(plan, isNot(contains('specstone init')));
    final lines = _pluginText(_expertSdd).split('\n');
    final section = lines.skipWhile((l) => l != '## Owner confirmation');
    expect(
      'references/gated-plan.md'.allMatches(section.join('\n')),
      hasLength(2),
    );
  });

  test('the five runners point to expert-sdd and hold no gated plan copy', () {
    const runners = [
      'specstone-bootstrap-prd/',
      'specstone-bootstrap-spec/',
      'specstone-init/',
      'specstone-sync-sdd/',
      'specstone-update-sdd/',
    ];
    final files = _skillAndAgentFiles();
    for (final runner in runners) {
      expect(
        files.any((file) => file.startsWith(runner)),
        isTrue,
        reason: runner,
      );
    }
    final copies = [
      for (final file in files)
        if (runners.any(file.startsWith) &&
            _pluginText(file)
                .replaceAll(RegExp(r'\s+'), ' ')
                .contains(_gatedPlanFlags))
          file,
    ];
    expect(copies, isEmpty);
  });

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

  test("each runner points to the approval reference file with its flow's "
      'report flags', () {
    final problems = [
      for (final MapEntry(key: file, value: flags) in _runnerFlags.entries)
        ..._runnerPointerProblems(file, flags),
    ];
    expect(problems, isEmpty);
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

/// The text of the approval reference file, headings left out.
String _approveText() => _oneLine(
  _pluginText(_approveRef)
      .split('\n')
      .where((line) => !line.startsWith('#'))
      .join('\n'),
);

/// The heading of the bootstrap skills' after-the-reports step.
const _bootstrapAfterReports = '## 3. After the reports';

/// The runner's steps for a bootstrap round with a trim batch.
const _trimRound = 'specstone-expert-sdd/references/trim-round.md';

// MARK: - trim reference

const _trimReference = 'specstone-expert-sdd/references/trim.md';

const _mergeUntyped = 'specstone-bootstrap-spec/references/merge-untyped.md';

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

const _authorEntry = 'specstone-brainstorming-sdd/references/author.md';

const _syncEntry = 'specstone-sync-sdd/references/engineer.md';

const _bootstrapEntries = [
  'specstone-bootstrap-prd/references/engineer.md',
  'specstone-bootstrap-spec/references/engineer.md',
];

const _auditReference = 'specstone-brainstorming-sdd/references/audit.md';

const _trimAuditReference =
    'specstone-brainstorming-sdd/references/trim-audit.md';

const _reReviewReference =
    'specstone-brainstorming-sdd/references/re-review.md';

const _reReviewHeading = '## Re-review';

const _buildFirstAuditReference =
    'specstone-brainstorming-sdd/references/build-first-audit.md';

/// The one fix loop main runs after a builder check or a trim audit.
const _fixLoopReference = 'specstone-expert-sdd/references/fix-loop.md';

const _builderCheckHeading = '## Builder check';

const _trimAuditHeading = '## Trim audit';

/// The flag pair of a gated plan command; no runner skill may copy it.
const _gatedPlanFlags = '--yes --plan';

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
      '`overrides`',
      '`Citers outside:`',
    ]) {
      expect(text, contains(word), reason: word);
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
    for (final splitStep in ['**Split.**', '`new fr --parent']) {
      expect(
        trimLine,
        lessThan(lines.indexWhere((line) => line.contains(splitStep))),
        reason: splitStep,
      );
    }
  });

  test('size-fix folds top features on a feature map size finding', () {
    final text = _pluginText(_sizeFix);
    final fold = _sectionOf(text, '## The fold proposal');
    expect(fold, contains('new feature --slug'));
    expect(fold, contains('feature:<x> -> feature:<parent>'));
    expect(
      fold.indexOf('new feature --slug'),
      lessThan(fold.indexOf('feature:<x> -> feature:<parent>')),
    );
  });

  test('size fix split proposal names a plan file and no command list', () {
    final text = _pluginText(_sizeFix);
    expect(text, isNot(contains('```')));
    expect(text, isNot(contains('--under')));
    expect(
      _hasSentenceWith(_sectionOf(text, '## The order'), [
        '`<doc>#<ID> -> <doc>`',
        '`<story>#S<N> -> <story>`',
        "applied as the split's plan is",
      ]),
      isTrue,
    );
    for (final heading in [
      '## The split proposal',
      '## The fold proposal',
      '## A finding that names items to move',
      '## A bundle over its limit',
    ]) {
      final section = _sectionOf(text, heading);
      expect(section, isNotEmpty, reason: heading);
      expect(section, isNot(contains('specstone new')), reason: heading);
      expect(section, isNot(contains('specstone move <')), reason: heading);
    }
    final split = _sectionOf(text, '## The split proposal');
    for (final words in [
      ['move plan file', 'move --plan-out', "run's reports folder"],
      ['`<story> -> <sub-feature>`'],
      ['`new feature --parent <feature> --slug <slug>`'],
      ['`new <spec type> --parent <sub-feature>`'],
      ["`<doc>#<ID or section/key> -> <sub-feature's spec doc>`"],
      ['Put each `new` line above every line that names its doc'],
      [
        'Owner',
        'one `specstone move --plan-file "<file>"`',
        'dispatched agent',
      ],
    ]) {
      expect(_hasSentenceWith(split, words), isTrue, reason: words.join(', '));
    }
    expect(
      _hasSentenceWith(
        _pluginText('specstone-expert-sdd/references/size-fix-story.md'),
        ['plan file', '`<story>#S<N> -> <new story>`'],
      ),
      isTrue,
    );
    expect(text, contains('`size-fix-story.md`'));
    expect(
      _hasSentenceWith(
        _sectionOf(text, '## A finding that names items to move'),
        ['`<fr>#<edge case ID> -> <new fr>`'],
      ),
      isTrue,
    );
  });

  test('the builder check ranks its five labels in one list', () {
    final check = _sectionOf(
      _pluginText(_auditReference),
      _builderCheckHeading,
    );
    final labels = [
      'Guess',
      'Contradiction',
      'Stale reader',
      'Not carried',
      'Misplaced',
    ];
    for (final label in labels) {
      expect(check, contains('- $label: <docs>: <point>'), reason: label);
    }
  });

  test('the builder check flags a member rule added to a shared FR', () {
    final check = _sectionOf(
      _pluginText(_auditReference),
      _builderCheckHeading,
    );
    expect(check, contains('- Misplaced: <docs>: <point>'));
  });

  test(
    'a Misplaced item sends an internal code-level spec fact to the plan',
    () {
      final text = _pluginText(_auditReference);
      expect(
        _bulletOf(text, '   - `Misplaced`'),
        allOf(
          contains('code-level'),
          contains('`code_detail_home`'),
          contains('`library_code_detail_home`'),
          contains('plan'),
        ),
      );
      expect(_bulletOf(text, '   - `Guess`'), contains('code-level'));
    },
  );

  // D3
  test('a Misplaced item with a member FR leads with both FRs', () {
    final misplaced = _bulletOf(
      _pluginText(_auditReference),
      '   - `Misplaced`',
    );
    expect(
      misplaced,
      allOf(
        contains(
          '<shared FR>#<key>, <member FR>: <rule> belongs in <member FR>',
        ),
        contains('belongs in a new FR for <member>'),
        isNot(
          contains(
            '`- Misplaced: <shared FR>#<key>: <rule> belongs in <member FR>`',
          ),
        ),
      ),
    );
  });

  test('a feature pattern item neither covered nor skipped is one Not carried '
      'line', () {
    final check = _sectionOf(
      _pluginText(_auditReference),
      _builderCheckHeading,
    );
    expect(
      check,
      contains(
        '- Not carried: <type>:<name>#out_of_scope: <pattern>/<item> '
        'neither covered nor skipped',
      ),
    );
  });
}

// MARK: - brainstorm rounds

const _brainstormSkill = 'specstone-brainstorming-sdd/SKILL.md';

const _roundsReference = 'specstone-brainstorming-sdd/references/rounds.md';

const _designReference = 'specstone-brainstorming-sdd/references/design.md';

/// The brainstorm runner's steps with no subagent, under the plugin folder.
const _noDispatchReference =
    'specstone-brainstorming-sdd/references/no-dispatch.md';

/// The heading of the change note step of the design reference.
const _changeNoteHeading = '## 3. Write the change note';

/// The heading of the brainstorm skill's grounding step.
const _brainstormGround = '## 1. Ground: the first call';

/// The heading of the brainstorm skill's dialogue step.
const _brainstormApproach = '## 2. Dialogue until the Owner picks an approach';

/// The heading of the brainstorm skill's change note step.
const _brainstormNote = '## 3. Write the change note';

/// The heading of the brainstorm skill's writers-and-check step.
const _brainstormDrafts = '## 4. Write the drafts, check them once';

/// The heading of the brainstorm skill's approval step.
const _brainstormApproval = '## 5. Get the drafts approved';

/// The heading of the brainstorm skill's plan hand-off step.
const _brainstormPlan = '## 6. Hand off to the plan skill';

/// The heading of the brainstorm skill's no-subagent section.
const _brainstormNoDispatch = '## Without a dispatch';

void _brainstormRoundTests() {
  group('rounds.md', _roundsReferenceTests);
  test(
    'design.md writes the change note sections in order and no old table',
    () {
      final step = _sectionOf(
        _pluginText(_designReference),
        _changeNoteHeading,
      );
      final names = [
        'Intent',
        'Goals',
        'Non-goals',
        'Anti-goals',
        'Constraints',
        'Approaches',
        'Decisions',
        'Reach',
        'Left to the builder',
        'Open questions',
        'Calls made',
      ];
      final at = [for (final name in names) step.indexOf('**$name**')];
      expect(at, everyElement(isNonNegative), reason: '$at');
      expect(at, orderedEquals([...at]..sort()), reason: 'section order');
    },
  );

  test('each brainstorm dispatch follows dispatch.md by its report path', () {
    final text = _pluginText(_brainstormSkill);
    for (final words in [
      [
        '../specstone-expert-sdd/references/dispatch.md',
        'sdd-engineer.author',
        'sdd-auditor.audit',
      ],
    ]) {
      expect(_hasSentenceWith(text, words), isTrue, reason: words.join(', '));
    }
  });

  test('every brainstorm audit dispatch names specstone-sdd-auditor with its '
      'job', () {
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
    expect(_pluginText(_brainstormSkill), contains('`job: builder-check`'));
  });
}

// MARK: - rounds reference

/// The heading of the rounds reference's moves-and-deletes section.
const _roundsMoves = "## 1. Run the writers' deletes and moves";

/// The heading of the rounds reference's question-round section.
const _roundsSort = '## 2. Sort the builder check and ask once';

/// The heading of the rounds reference's Owner-change section.
const _roundsChange = '## 4. Take an Owner change after the check';

void _roundsReferenceTests() {
  test('the three sections come in the order of the flow', () {
    final headings = _pluginText(_roundsReference)
        .split('\n')
        .where((line) => line.startsWith('## '));
    expect(headings, [_roundsMoves, _roundsSort, _roundsChange]);
  });
}

void _brainstormFlowTests() {
  String step(String heading) =>
      _sectionOf(_pluginText(_brainstormSkill), heading);

  test('the steps run from the grounding to the plan hand-off', () {
    final headings = _pluginText(_brainstormSkill)
        .split('\n')
        .where((line) => line.startsWith('## '));
    expect(headings, [
      _brainstormGround,
      _brainstormApproach,
      _brainstormNote,
      _brainstormDrafts,
      _brainstormApproval,
      _brainstormPlan,
      _brainstormNoDispatch,
    ]);
  });

  test('the writers run first, then the moves and deletes, one builder check, '
      'the one question round, and the fixes with no check after', () {
    final text = step(_brainstormDrafts);
    final order = [
      for (final word in [
        '`specstone-sdd-engineer`',
        '`references/rounds.md` section 1',
        '`job: builder-check`',
        '`references/rounds.md` section 2',
        '`../specstone-expert-sdd/references/fix-loop.md`',
      ])
        text.indexOf(word),
    ];
    expect(order, everyElement(isNonNegative), reason: '$order');
    expect(order, orderedEquals([...order]..sort()), reason: 'order');
  });

  // D5
  test('a change the plan check sends back Docs-first goes on to the drafts '
      'step with its note', () {
    expect(
      _hasSentenceWith(step(_brainstormNote), [
        'plan check',
        'Docs-first',
        'keeps its note',
        'step 4',
      ]),
      isTrue,
    );
  });

  test('the plan skill and the plan engineer take the input `change note` and '
      'no `design document`', () {
    for (final (file, inputLine) in [
      ('specstone-plan-sdd/SKILL.md', '- `change note:` its path'),
      (_planAgent, '- **`change note`** (optional): a path'),
    ]) {
      final text = _pluginText(file);
      expect(
        text.split('\n').any((line) => line.startsWith(inputLine)),
        isTrue,
        reason: file,
      );
    }
  });

  // D7
  test('the class test runs Doc-only before Build-first, keeps code-level change Internal, and sends doubt Docs-first', () {
    final text = _pluginText(_classReference);
    final questions = text.substring(0, text.indexOf('| Class |'));
    final docOnly = questions.indexOf('Doc-only');
    expect(docOnly, isNonNegative);
    expect(docOnly, lessThan(questions.indexOf('Build-first')));
    expect(
      _oneLine(text),
      contains(
        RegExp(
          r'\| Internal \| no observable behavior changes\.'
          r' An internal code-level change\b[^|]*\bis Internal\b',
        ),
      ),
    );
    final closing = text.substring(
      text.indexOf('A change not shown Build-first'),
    );
    expect(
      closing,
      startsWith('A change not shown Build-first is Docs-first:\n'),
    );
    expect(closing, contains('- its class is in doubt'));
    expect(closing, contains('neither `(decided)` nor `(plan)`'));
    expect(closing, contains('have no `Owner ok:` line in the note'));
  });
}

const _classReference = 'specstone-brainstorming-sdd/references/class.md';

const _authorReference = 'specstone-brainstorming-sdd/references/author.md';

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

// MARK: - re-review

void _reReviewTests() {
  test('the builder check files every point under Findings and observations under Notes', () {
    final check = _sectionOf(
      _pluginText(_auditReference),
      _builderCheckHeading,
    );
    expect(check, contains('Notes: - <observation>'));
  });

  test(
    'the trim audit opens each outside item with the docs that hold its fix',
    () {
      final audit = _sectionOf(
        _pluginText(_trimAuditReference),
        _trimAuditHeading,
      );
      expect(audit, contains('Notes: - <observation>'));
      expect(audit, contains('- <docs whose fix it is>:'));
    },
  );

  // D8
  test(
    'each audit reference opens its items with a comma-joined docs list',
    () {
      final audit = _pluginText(_auditReference);
      final decided = _pluginText(_buildFirstAuditReference);
      final reReview = _pluginText(_reReviewReference);
      final trim = _pluginText(_trimAuditReference);
      final jobs = {
        _auditReference: _sectionOf(audit, _builderCheckHeading),
        _buildFirstAuditReference: _sectionOf(decided, '## Build-first audit'),
        _reReviewReference: _sectionOf(reReview, _reReviewHeading),
      };
      for (final MapEntry(:key, :value) in jobs.entries) {
        expect(value, contains(': <docs>: <point>'), reason: key);
        expect(value, isNot(contains('<doc>#<key>: <point>')), reason: key);
      }
      expect(_oneLine(audit), contains('`<docs>`'));
      expect(_oneLine(audit), contains('joined by `, `'));
      for (final text in [decided, reReview, trim]) {
        expect(_oneLine(text), contains('`audit.md` gives `<docs>`'));
      }
      for (final text in [reReview, trim]) {
        final flat = _oneLine(text);
        expect(flat, contains('- <docs whose fix it is>:'));
        expect(flat, isNot(contains('- <doc whose fix it is>:')));
      }
      for (final text in [audit, decided, reReview, trim]) {
        expect(
          _oneLine(text),
          isNot(contains('the name of the doc where its fix lies')),
        );
      }
    },
  );

  // D8
  test(
    'each audit writes its Audited lines from the dry run doc and base keys',
    () {
      final texts = {
        _auditReference: _pluginText(_auditReference),
        _buildFirstAuditReference: _pluginText(_buildFirstAuditReference),
        _reReviewReference: _pluginText(_reReviewReference),
        _trimAuditReference: _pluginText(_trimAuditReference),
      };
      for (final MapEntry(:key, :value) in texts.entries) {
        final flat = _oneLine(value);
        expect(flat, contains('Audited: <doc>@<hash>'), reason: key);
        expect(
          flat,
          isNot(contains('Audited: <type>:<name>@<hash>')),
          reason: key,
        );
      }
      for (final entry in {
        _auditReference: _builderCheckHeading,
        _reReviewReference: _reReviewHeading,
        _trimAuditReference: _trimAuditHeading,
      }.entries) {
        final step = _sectionOf(texts[entry.key]!, entry.value);
        expect(step, contains('`doc`'), reason: entry.key);
      }
    },
  );

  test('the trim lens restores no removed code-level fact', () {
    final audit = _sectionOf(
      _pluginText(_trimAuditReference),
      _trimAuditHeading,
    );
    expect(_hasSentenceWith(audit, ['code-level', 'restore']), isTrue);
  });

  // D8
  test('the auditor names a Notes section for each of its five jobs', () {
    for (final file in [
      _auditReference,
      _reReviewReference,
      _trimAuditReference,
      _buildFirstAuditReference,
      _planCheck,
    ]) {
      expect(_oneLine(_pluginText(file)), contains('`Notes:`'), reason: file);
    }
  });

  test('the auditor report shape opens each item with its fix docs after any '
      'label', () {
    final text = _pluginText(_auditor);
    final lead = _bulletOf(text, '- **Lead names**');
    expect(lead, contains('plan check'));
    expect(lead, contains('after any label'));
    expect(lead, contains('`, `'));
    final trim = _bulletOf(
      _pluginText(_trimAuditReference),
      '- Each item under `Outside the drafts:`',
    );
    expect(trim, contains('every doc its fix lies in'));
    expect(trim, contains('never a draft of the round'));
    expect(trim, isNot(contains('the doc where its fix lies')));
  });

  // D16
  // D8
  test("the auditor links each job's report shape and restates none", () {
    final text = _pluginText(_auditor);
    final from = text.indexOf('\n## Output Format\n');
    final output = text.substring(from, text.indexOf('\n## ', from + 4));
    final lines = output.split('\n');
    for (final lead in [
      '- **Builder check**',
      '- **Re-review**',
      '- **Trim audit**',
      '- **Build-first audit**',
      '- **Plan check**',
    ]) {
      expect(lines.any((line) => line.startsWith(lead)), isFalse, reason: lead);
    }
    final shape = _bulletOf(output, '- **Report shape**');
    expect(shape, contains('On-Demand'));
    expect(shape, contains('`## 6. Report`'));
  });

  test('the auditor takes findings, and no sections or citers', () {
    final text = _sectionOf(_pluginText(_auditor), '## Input Contract');
    expect(text, contains('**`findings`**'));
    for (final input in ['**`sections`**', '**`citers`**']) {
      expect(text, isNot(contains(input)), reason: input);
    }
  });

  // D8
  test('the auditor takes five jobs and names the plan check and its load', () {
    final text = _pluginText(_auditor);
    final drafts = _bulletOf(text, '- **Drafts**');
    for (final word in ['`re-review`', '`changedSections`']) {
      expect(drafts, contains(word), reason: word);
    }
    final loads = _sectionOf(text, '## On-Demand Loads');
    for (final job in ['re-review', 'build-first-audit']) {
      expect(
        loads,
        contains(
          '| `job: $job` | '
          '`.agents/skills/specstone-brainstorming-sdd/references/$job.md` |',
        ),
        reason: job,
      );
    }
    expect(
      loads,
      contains(
        '| `job: plan-check` | '
        '`.agents/skills/specstone-plan-sdd/references/plan-check.md` |',
      ),
    );
    final head = text.substring(0, text.indexOf('\n---\n', 4));
    for (final job in [
      '`job: re-review`',
      '`job: build-first-audit`',
      '`job: plan-check`',
    ]) {
      expect(head, contains(job), reason: job);
    }
    final decided = _sectionOf(
      _pluginText(_buildFirstAuditReference),
      '## Build-first audit',
    );
    for (final words in [
      '`Contradiction`, `Stale reader`, and `Not carried`',
      '`Fix:` lines',
      '`Audited:`',
    ]) {
      expect(decided, contains(words), reason: words);
    }
    final report = _sectionOf(
      _pluginText(_reReviewReference),
      _reReviewHeading,
    );
    for (final line in [
      '`Findings:`',
      '`Verdicts:`',
      '`Outside the round:`',
      '`Audited:`',
    ]) {
      expect(report, contains(line), reason: line);
    }
    expect(
      _sectionOf(_pluginText(_auditReference), _builderCheckHeading),
      contains('`Fix:` lines'),
    );
    for (final file in [
      _auditor,
      _auditReference,
      _trimAuditReference,
      _reReviewReference,
      _buildFirstAuditReference,
    ]) {
      final words = _oneLine(_pluginText(file)).toLowerCase();
      for (final gone in ['fix-read', 'fix read']) {
        expect(words, isNot(contains(gone)), reason: '$file: $gone');
      }
    }
    expect(
      contentFiles().map((file) => file.path),
      isNot(contains('specstone-brainstorming-sdd/references/fix-read.md')),
    );
  });

  // D8
  test('the Build-first audit reference names its agent and job value on its '
      'first line', () {
    final text = _pluginText(_buildFirstAuditReference);
    final first = text.split('\n').first;
    for (final word in [
      '`specstone-sdd-auditor`',
      '`job: build-first-audit`',
    ]) {
      expect(first, contains(word), reason: word);
    }
  });

  // D8
  test('no shipped file keeps the old audit name or job value', () {
    final files = contentFiles();
    for (final file in files) {
      for (final old in ['decided-audit', 'Decided audit']) {
        expect(file.body, isNot(contains(old)), reason: '${file.path}: $old');
        expect(
          file.frontmatter ?? '',
          isNot(contains(old)),
          reason: '${file.path} frontmatter: $old',
        );
      }
    }
    final paths = files.map((file) => file.path);
    expect(paths, contains(_buildFirstAuditReference));
    expect(
      paths.where((path) => path.endsWith('references/decided-audit.md')),
      isEmpty,
    );
  });

  // D7
  test('no shipped skill or agent file names a lane by its old word', () {
    final oldLane = RegExp(r'\b(?:Undecided|Decided)\b(?!-only)');
    final files = contentFiles();
    for (final file in files) {
      expect(oldLane.hasMatch(file.body), isFalse, reason: '${file.path} body');
      expect(
        oldLane.hasMatch(file.frontmatter ?? ''),
        isFalse,
        reason: '${file.path} frontmatter',
      );
    }
    final text = files.singleWhere((file) => file.path == _classReference).body;
    expect(text, allOf(contains('Build-first'), contains('Docs-first')));
  });

  // D9
  test(
    'the lane ask puts Build-first forward and leaves the pick to the Owner',
    () {
      final ask = _sectionOf(
        _pluginText(_designReference),
        '## 4. Tell the Owner',
      );
      expect(
        _hasSentenceWith(ask, ['In that ask', 'recommend', 'Build-first']),
        isTrue,
      );
      expect(
        _hasSentenceWith(ask, [
          'Docs-first',
          'fresh reader',
          'before any work',
        ]),
        isTrue,
      );
      expect(_hasSentenceWith(ask, ['The Owner picks the lane']), isTrue);
      expect(_hasSentenceWith(ask, ['Docs-first', 'no reason asked']), isTrue);
    },
  );

  // D8
  test('the auditor lists the renamed job and so stops on the old one', () {
    final text = _pluginText(_auditor);
    final job = _bulletOf(text, '- **`job`**');
    expect(job, contains('`build-first-audit`'));
    expect(job, isNot(contains('`decided-audit`')));
    final missing = _bulletOf(text, '- **Missing input**');
    expect(missing, contains('`build-first-audit`'));
    expect(missing, contains('its five values'));
    expect(
      _sectionOf(text, '## On-Demand Loads'),
      contains(
        '| `job: build-first-audit` | '
        '`.agents/skills/specstone-brainstorming-sdd/references/'
        'build-first-audit.md` |',
      ),
    );
  });

  test('the builder check writes fix lines under a finding it can settle', () {
    final check = _sectionOf(
      _pluginText(_auditReference),
      _builderCheckHeading,
    );
    expect(
      check,
      contains('- Guess: <docs>: <point> Fix: <type>:<name>#<key>'),
    );
  });

  test(
    'the re-review grounds once in review mode and reads only changed sections',
    () {
      final read = _sectionOf(
        _pluginText(_reReviewReference),
        _reReviewHeading,
      );
      expect(_contextCalls(read), [
        ['<draft>', '<draft>', '--for', 'review', '--out'],
      ]);
    },
  );

  test('the re-review reports audited lines, one verdict per open finding, '
      'and new gaps', () {
    final read = _sectionOf(_pluginText(_reReviewReference), _reReviewHeading);
    final findings = read.indexOf('Findings: - <Label>: <docs>: <point>');
    final verdicts = read.indexOf(
      'Verdicts: - ADDRESSED: <item> - NOT ADDRESSED: <item>',
    );
    final outside = read.indexOf(
      'Outside the round: - <docs whose fix it is>: <gap>',
    );
    final notes = read.indexOf('Notes: - <observation>');
    final audited = read.indexOf('Audited: <doc>@<hash>');
    expect(findings, isNonNegative);
    expect(verdicts, greaterThan(findings));
    expect(outside, greaterThan(verdicts));
    expect(notes, greaterThan(outside));
    expect(audited, greaterThan(notes));
  });

  test('the re-review runs no check and changes no file but its report', () {
    final text = _pluginText(_reReviewReference);
    final head = text.split('\n').first;
    expect(head, contains('`specstone-sdd-auditor`'));
    expect(head, contains('`job: re-review`'));
    expect(text, isNot(contains('`specstone-sdd-engineer`')));
    final spans = _approveSpans(text);
    expect(spans, isNotEmpty);
    for (final span in spans) {
      expect(span, contains('--dry-run'), reason: span);
    }
  });
}

// MARK: - fix loop

/// The path an agent file names the fix loop reference file by.
const _fixLoopAgentPath = '.agents/skills/$_fixLoopReference';

/// The path a reference of another skill names the fix loop file by.
const _fixLoopRelativePath = '../../$_fixLoopReference';

void _fixLoopTests() {
  test(
    'expert-sdd points to fix-loop.md once and its pointers hold no loop rule',
    () {
      final expert = _pluginText(_expertSdd);
      expect('references/fix-loop.md'.allMatches(expert), hasLength(1));
      final pointers = [
        (_engineer, _fixLoopAgentPath),
        (_auditor, _fixLoopAgentPath),
        (_trimAuditReference, _fixLoopRelativePath),
        (_roundsReference, _fixLoopRelativePath),
        for (final entry in _bootstrapEntries) (entry, _fixLoopRelativePath),
      ];
      for (final (file, path) in pointers) {
        expect(_pluginText(file), contains('`$path`'), reason: file);
      }
    },
  );
}

void _authorModeTests() {
  test('the engineer names each author line and no old line', () {
    final output = _sectionOf(_pluginText(_engineer), '## Output Format');
    expect(
      _hasSentenceWith(output, [
        '`Decision:`',
        '`Not landed:`',
        '`Readers:`',
        '`Elsewhere:`',
        '`Move:`',
        '`Rename:`',
        '`Delete:`',
        '`Open questions:`',
        '`Check:`',
        '`Findings:`',
      ]),
      isTrue,
    );
    for (final gone in ['`Design:`', '`Guide:`', '`Sections:`', 'fix file']) {
      expect(output, isNot(contains(gone)), reason: gone);
    }
  });

  test('the author report template holds one line per Output row in order', () {
    final report = _pluginText(_authorReference);
    final open = report.indexOf('```');
    final template = report.substring(open, report.indexOf('```', open + 3));
    var last = -1;
    for (final label in [
      "Drafts for the Owner's specstone approve",
      'Decision: D<n> -> <type>:<name>#<key>, …',
      'Not landed: D<n>:',
      'Readers: <type>:<name>#<key> changed|linked|unaffected: <why>',
      'Elsewhere: <type>:<name>#<key>: <why>',
      'Move: <plan file path>',
      'Rename: specstone rename <doc> --to <slug>',
      'Delete:',
      'Open questions:',
      'Check: <path>',
      'Counts:',
      'Findings:',
    ]) {
      final at = template.indexOf(label);
      expect(at, greaterThan(last), reason: label);
      last = at;
    }
    for (final gone in ['Design:', 'Guide:', 'Sections:', '| Decision']) {
      expect(template, isNot(contains(gone)), reason: gone);
    }
  });

  test('the reader step runs per decision before the first write', () {
    final text = _pluginText(_authorReference);
    const readers = '## 2. Find the readers';
    expect(text.indexOf(readers), isNonNegative);
    expect(text.indexOf(readers), lessThan(text.indexOf('## 3. Write')));
  });

  // D12
  test(
    'the reader step reads a narrowed rule and searches its old wording',
    () {
      final steps = _sectionOf(
        _pluginText(_authorReference),
        '## 2. Find the readers',
      );
      expect(
        _hasSentenceWith(steps, [
          'current text',
          'never by `get`',
          'saved bundle files',
          'else',
          '`specstone context <doc> --for design --out`',
        ]),
        isTrue,
      );
      expect(
        _hasSentenceWith(steps, ['`specstone search', 'noun phrase']),
        isTrue,
      );
      expect(_hasSentenceWith(steps, ['hit', 'reader']), isTrue);
      expect(steps, contains('`specstone refs`'));
      expect(steps, contains('once per decision before your first write'));
    },
  );

  test('the author reads by name list and writes one batch', () {
    final step = _sectionOf(_pluginText(_authorReference), '## 3. Write');
    for (final phrase in [
      'one `specstone get <list> --out "<file>"`',
      'one `specstone set --batch "<file>"`',
      'sdd-engineer.author.batch.<XXXXXX>.txt',
      '`<type>:<name>#<key>`',
      '`input_output`',
      '`section_not_found`',
      'its own `get … --out` and its own `set --batch`',
    ]) {
      expect(step, contains(phrase), reason: phrase);
    }
  });

  test('the author recovers a refused batch fault by fault', () {
    final step = _sectionOf(
      _pluginText(_authorReference),
      '## 4. Recover a refused batch',
    );
    for (final fault in [
      '`output_not_writable`',
      'Stale block',
      'Gone block',
      'rerun the batch',
    ]) {
      expect(step, contains(fault), reason: fault);
    }
  });

  test('author report names its plan file in place of commands', () {
    final report = _pluginText(_authorReference);
    final open = report.indexOf('```');
    final template = report.substring(open, report.indexOf('```', open + 3));
    expect(template, contains('Move: <plan file path>'));
    expect(template, isNot(contains('specstone move')));
  });

  // D11
  test('an engineer splits an FR past its edge-case cap inside its story', () {
    final steps = _sectionOf(_pluginText(_authorReference), _authorSplit);
    const order = [
      'specstone new fr --parent <story>',
      'specstone move --plan-out <fr>',
      'specstone move --plan-file',
    ];
    for (final words in [
      [order[0]],
      ['Save one plan file', order[1]],
      [order[2]],
      ['new FR', 'section 3', '`<mode>`'],
      ['author mode', "section 5's later-write bare check"],
      ['sync mode', 'specstone check <doc> --out', 'per FR'],
      ['old and the new FR', 'drafts list'],
      ['`Move:`', '`Findings:`', 'draft line'],
      ['Owner', 'story or feature'],
    ]) {
      expect(_hasSentenceWith(steps, words), isTrue, reason: words.join(', '));
    }
    final at = [for (final command in order) steps.indexOf(command)];
    expect(at, orderedEquals([...at]..sort()));
    expect(steps, isNot(contains('run no `new` or `move`')));
    final engineer = _pluginText(_engineer);
    expect(
      _sectionOf(engineer, '## Workflow'),
      contains('$_authorEntryPath` `$_authorSplit`'),
    );
    final scope = _sectionOf(engineer, '## Scope Boundaries');
    for (final words in [
      [
        'the main session applies it',
        'bar the in-story split',
        '$_authorEntryPath` `## 7`',
      ],
      ['exception', 'move --plan-file', '$_authorEntryPath` `## 7`'],
    ]) {
      expect(_hasSentenceWith(scope, words), isTrue, reason: words.join(', '));
    }
    expect(
      scope,
      isNot(contains(' `author.md`')),
      reason: 'the engineer names a skill file by its full path',
    );
    expect(
      _sectionOf(
        _pluginText(_sizeFix),
        '## A finding that names items to move',
      ),
      contains('references/author.md` `$_authorSplit`'),
    );
  });
}

/// The author entry file as the engineer names it, from the project root.
const _authorEntryPath = '.agents/skills/$_authorEntry';

/// The author entry file's edge-case cap step, which sync mode runs too.
const _authorSplit = '## 7. Split an FR past its edge-case cap';

// MARK: - small edit

const _updateSkill = 'specstone-update-sdd/SKILL.md';

void _smallEditTests() {
  test('update-sdd writes through set with the base hash as a draft', () {
    final write = _sectionOf(_pluginText(_updateSkill), '## 3. Write the edit');
    expect(
      write,
      contains('specstone set <type>:<name>#<section key> --base <hash>'),
    );
    expect(
      write,
      contains('specstone set <type>:<name> --field <id> --base <hash>'),
    );
    expect(_hasSentenceWith(write, ['`draft: true`']), isTrue);
  });

  test('update-sdd merges a base_mismatch into the current text', () {
    final write = _sectionOf(_pluginText(_updateSkill), '## 3. Write the edit');
    expect(_hasSentenceWith(write, ['`base_mismatch`']), isTrue);
  });
}

// MARK: - grounding

void _groundingTests() {
  test('each skill and agent that gates on a project names specstone init on '
      'project_not_found and no old format', () {
    for (final file in [
      'specstone-read-sdd/SKILL.md',
      'specstone-sdd-reader.md',
      _auditor,
      'specstone-expert-sdd/SKILL.md',
      'specstone-update-sdd/SKILL.md',
      _syncSkill,
      'specstone-bootstrap-prd/SKILL.md',
      'specstone-bootstrap-spec/SKILL.md',
      'specstone-brainstorming-sdd/SKILL.md',
      'specstone-plan-sdd/SKILL.md',
      _planAgent,
      _customizeSkill,
    ]) {
      final text = _pluginText(file);
      final lines = text.split('\n');
      final hits = [
        for (var i = 0; i < lines.length - 1; i++)
          if (lines[i].contains('project_not_found')) i,
      ];
      expect(hits, isNotEmpty, reason: file);
      for (final at in hits) {
        final reply = '${lines[at]} ${lines[at + 1]}'.replaceAll(
          RegExp(r'\*\*.*?\*\*'),
          '',
        );
        expect(reply, contains('`specstone init`'), reason: '$file:${at + 1}');
      }
      expect(
        RegExp(
          r'old[\s-]+format|old\s+skills',
          caseSensitive: false,
        ).hasMatch(text),
        isFalse,
        reason: file,
      );
    }
  });
}

// MARK: - customize doc types

const _customizeFolder = 'specstone-customize-doc-types';

const _customizeSkill = '$_customizeFolder/SKILL.md';

/// The title of the customize skill's step that drafts and asks the Owner.
const _customizeAsk = '3. Draft the layer file and ask the Owner';

/// The format keys the customize skill's steps name; every other key comes
/// from the `guide --file-format` printout alone.
const _customizeKeys = {'name', 'version', 'extends'};

/// Each file of the customize skill, relative to the assets folder.
List<String> _customizeFiles() => [
  for (final file in _skillAndAgentFiles())
    if (file.startsWith('$_customizeFolder/')) file,
];

/// The text of [markdown] after its frontmatter block.
String _bodyOf(String markdown) => markdown.replaceFirst(_frontmatterBlock, '');

/// Each `## ` step of [markdown]'s body, its title first, every whitespace
/// run as one space, in order.
List<String> _stepsOf(String markdown) =>
    _bodyOf(markdown)
        .split(RegExp('^## ', multiLine: true))
        .skip(1)
        .map(_oneLine)
        .toList();

/// A pattern matching [words] as whole words, any whitespace run between them.
RegExp _wordsPattern(String words) =>
    RegExp('\\b${words.split(' ').map(RegExp.escape).join(r'\s+')}\\b');

/// The text after the `**<label>:**` bullet mark of a one-line [step], up to
/// the next bullet mark, or null when [step] holds no such bullet.
String? _markedClauseOf(String step, String label) =>
    RegExp('\\*\\*${RegExp.escape(label)}:\\*\\*(.*?)(?: - \\*\\*|\$)')
        .firstMatch(step)
        ?.group(1);

/// A word of a fenced line that may name a format key: a YAML key, group 1,
/// or a dotted word, group 2.
final _fencedKeyWord = RegExp(
  r'^\s*(?:-\s+)?([a-z_][a-z0-9_]*)\s*:|\b([a-z_][a-z0-9_]*(?:\.[a-z_][a-z0-9_]*)+)\b',
  multiLine: true,
);

/// Every dotted key of [table] under [parent], each variant's keys and each
/// `add`/`remove` change key included.
Set<String> _dottedKeysOf(List<FormatKey> table, [String parent = '']) => {
  for (final key in table) ...{
    '$parent${key.name}',
    ..._dottedKeysOf([
      ...key.children,
      for (final variant in key.variants) ...variant.children,
    ], '$parent${key.name}.'),
    if (key.shape == KeyShape.entriesOrChange ||
        key.shape == KeyShape.valuesOrChange) ...[
      '$parent${key.name}.add',
      '$parent${key.name}.remove',
    ],
  },
};

void _customizeDocTypesTests() {
  test('customize-doc-types takes a doc type change and leaves doc content and upgrade findings', () {
    final frontmatter = _frontmatterBlock
        .firstMatch(_pluginText(_customizeSkill))
        ?.group(1);
    final head = loadYaml(frontmatter ?? '') as YamlMap;
    final description = _oneLine(head['description'] as String);
    final needs =
        RegExp(r"\bneeds\s+(.+?)\s+that\s+the\s+project's")
            .firstMatch(description)
            ?.group(1) ??
        '';
    for (final part in [
      'doc type',
      'section',
      'field',
      'lint value',
      'list entry',
    ]) {
      expect(needs, matches(_wordsPattern(part)), reason: part);
    }
    for (final part in [
      "project's merged doc types",
      'lack or hold otherwise',
      "writing a doc's content",
    ]) {
      expect(description, matches(_wordsPattern(part)), reason: part);
    }
    expect(
      description,
      matches(
        RegExp(
          r'migration\s+or\s+a\s+pack\s+upgrade\s+with\s+no\s+layer\s+file\s+'
          'change[^.]*`specstone-bootstrap-prd`[^.]*`specstone-bootstrap-spec`',
        ),
      ),
    );
  });

  test('customize-doc-types runs the file format guide first', () {
    // The gate names `specstone init` as the way out; the skill never runs it.
    final calls = _inlineSpans(_bodyOf(_pluginText(_customizeSkill))).where(
      (span) => span.startsWith('specstone ') && span != 'specstone init',
    );
    expect(calls.take(3), [
      'specstone folder',
      'specstone guide --file-format --out',
      'specstone guide <type> --out',
    ]);
    final files = _customizeFiles();
    expect(files, contains(_customizeSkill));
    final folderCalls = files.fold(
      0,
      (count, file) =>
          count + 'specstone folder'.allMatches(_pluginText(file)).length,
    );
    expect(folderCalls, 1);
    final gate = _pluginText(_customizeSkill)
        .split('\n')
        .where((line) => line.contains('project_not_found'))
        .single;
    expect(gate, contains('**78, `project_not_found`:**'));
  });

  test(
    "customize-doc-types shows a new pack's pack.yaml and pin in the same ask",
    () {
      final steps = _stepsOf(_pluginText(_customizeSkill));
      final ask = steps.indexWhere((step) => step.startsWith(_customizeAsk));
      expect(ask, isNonNegative);
      expect(
        [
          for (final (at, step) in steps.indexed)
            if (step.contains('`pack.yaml`')) at,
        ],
        [ask],
      );
      expect(
        _hasSentenceWith(steps[ask], [
          '`pack.yaml`',
          '`name`',
          '`version`',
          '`extends`',
          '`packs:`',
        ]),
        isTrue,
      );
    },
  );

  test('customize-doc-types caps its fix loop', () {
    final fix = _stepsOf(_pluginText(_customizeSkill))
        .where((step) => step.startsWith(RegExp(r'\d+\. On exit 78\b')))
        .single;
    for (final word in [
      _wordsPattern('fix'),
      _wordsPattern('rerun'),
      RegExp('`specstone guide '),
      _wordsPattern('two'),
      RegExp(r'\bstops?\b'),
      _wordsPattern('Owner'),
    ]) {
      expect(fix, contains(word), reason: word.pattern);
    }
    expect(fix, contains(_wordsPattern('as step 4 does')));
    expect(_hasSentenceWith(fix, ['did not write', 'Owner', 'stop']), isTrue);
    final notWritten = fix.indexOf('did not write');
    expect(notWritten, isNonNegative);
    expect(notWritten, lessThan(fix.indexOf('the file step 4 wrote')));
  });

  test('customize-doc-types confirms each saved guide shows the drafted '
      'entries', () {
    final write = _stepsOf(_pluginText(_customizeSkill))
        .where((step) => step.contains("the host's file write"))
        .single;
    final landed = _markedClauseOf(write, '0');
    expect(landed, isNotNull);
    for (final phrase in ['saved guide', 'Owner', 'the file written', 'stop']) {
      expect(landed, contains(_wordsPattern(phrase)), reason: phrase);
    }
    final sentences = _sentencesOf(landed ?? '');
    final confirm = sentences
        .where((sentence) => sentence.contains('saved guide'))
        .single;
    expect(confirm, contains(_wordsPattern('every drafted doc-type entry')));
    expect(confirm, isNot(contains('pack')));
    expect(
      _hasSentenceWith(landed ?? '', ['pack file', 'pin', 'exit 0']),
      isTrue,
    );
  });

  test('customize-doc-types names only the format keys its steps use', () {
    final formatKeys = {
      ..._dottedKeysOf(docTypeFileFormat),
      ..._dottedKeysOf(packFileFormat),
    };
    final leafKeys = {for (final key in formatKeys) key.split('.').last};
    final files = _customizeFiles();
    expect(files, contains(_customizeSkill));
    expect(formatKeys, containsAll(_customizeKeys));
    for (final file in files) {
      final text = _pluginText(file);
      final fenced = [
        for (final block in _fencedBlock.allMatches(text))
          for (final word in _fencedKeyWord.allMatches(block.group(1) ?? ''))
            word.group(1) ?? word.group(2) ?? '',
      ];
      bool isKey(String word) =>
          formatKeys.contains(word) || leafKeys.contains(word);
      final named = [
        ..._inlineSpans(text).where(isKey),
        ...fenced.where(isKey),
      ];
      expect(_customizeKeys, containsAll(named), reason: file);
    }
  });

  test('customize-doc-types routes check findings to the bootstrap skills', () {
    final body = _bodyOf(_pluginText(_customizeSkill));
    final lines = body.split('\n');
    final prdRoute = lines.where((line) => line.contains('`prds/`')).single;
    expect(prdRoute, contains('`measurements/`'));
    expect(prdRoute, contains('`specstone-bootstrap-prd`'));
    final specRoute = lines.where((line) => line.contains('`specs/`')).single;
    expect(specRoute, contains('`specstone-bootstrap-spec`'));
    final route = _stepsOf(_pluginText(_customizeSkill))
        .where((step) => step.contains('`specs/`'))
        .single;
    final opening = route.substring(0, route.indexOf('`specstone check'));
    expect(
      opening,
      contains(_wordsPattern('shows every drafted doc-type entry')),
    );
    const elsewhereMark = '**Findings outside the folders below:**';
    final elsewhere = _markedClauseOf(
      route,
      'Findings outside the folders below',
    );
    expect(elsewhere, isNotNull);
    for (final phrase in [
      'Owner',
      'check file',
      'stop',
      'before following any skill below',
    ]) {
      expect(elsewhere, contains(_wordsPattern(phrase)), reason: phrase);
    }
    expect(route.indexOf(elsewhereMark), lessThan(route.indexOf('`prds/`')));
    expect(
      _markedClauseOf(route, 'None'),
      contains(_wordsPattern('report the change done')),
    );
    final checks = _inlineSpans(body)
        .where((span) => span.startsWith('specstone check'));
    expect(checks, isNotEmpty);
    expect(
      checks,
      everyElement(
        'specstone check --out "<folder>/reports/check.done.<XXXXXX>.txt"',
      ),
    );
  });

  test('customize-doc-types asks the Owner before any file write', () {
    final steps = _stepsOf(_pluginText(_customizeSkill));
    final ask = steps.indexWhere((step) => step.startsWith(_customizeAsk));
    expect(ask, isNonNegative);
    expect(steps[ask], contains("Owner's ok"));
    final writes = [
      for (final (at, step) in steps.indexed)
        if (step.contains("the host's file write")) at,
    ];
    expect(writes, isNotEmpty);
    expect(writes, everyElement(greaterThan(ask)));
  });

  test('customize-doc-types enters its fix loop only from the post-write '
      'guide', () {
    final steps = _stepsOf(_pluginText(_customizeSkill));
    final ask = steps.indexWhere((step) => step.startsWith(_customizeAsk));
    final fix = steps.indexWhere(
      (step) => step.startsWith(RegExp(r'\d+\. On exit 78\b')),
    );
    expect(ask, isNonNegative);
    expect(fix, greaterThan(ask));
    final toFix = _wordsPattern(
      'step ${RegExp(r'^\d+').stringMatch(steps[fix])}',
    );
    final routes = [
      for (final (at, step) in steps.indexed)
        if (step.contains(toFix)) at,
    ];
    expect(routes, isNotEmpty);
    expect(routes, everyElement(allOf(greaterThan(ask), lessThan(fix))));
    final read = steps
        .take(ask)
        .where((step) => step.contains('`specstone guide '))
        .single;
    final fault = _markedClauseOf(read, '78');
    expect(fault, isNotNull);
    for (final phrase in ['Owner', "the fault's file, key, and code", 'stop']) {
      expect(fault, contains(_wordsPattern(phrase)), reason: phrase);
    }
  });

  test('customize-doc-types writes each file at the full path its ask '
      'names', () {
    final text = _pluginText(_customizeSkill);
    final spans = _inlineSpans(_bodyOf(text));
    expect(
      spans,
      containsAll([
        '<folder>/templates/<doc_type>.yaml',
        '~/.specstone/packs/<pack>/<doc_type>.yaml',
        '<folder>/config.yaml',
      ]),
    );
    expect(spans.where((span) => span.startsWith('.specstone/')), isEmpty);
    final write = _stepsOf(text)
        .where((step) => step.contains("the host's file write"))
        .single;
    expect(write, contains(_wordsPattern('at the paths the ask named')));
  });
}

// MARK: - plan flow

const _planSkill = 'specstone-plan-sdd/SKILL.md';

/// The plan skill's group and merge dispatch steps, read on a
/// `Plan: none (groups)` reply alone.
const _planGroups = 'specstone-plan-sdd/references/groups.md';

/// The plan skill's test for the main session writing the plan itself, read
/// at the hand-off step alone.
const _planMainWriter = 'specstone-plan-sdd/references/main-writer.md';

/// The auditor's plan-check procedure, loaded for `job: plan-check`.
const _planCheck = 'specstone-plan-sdd/references/plan-check.md';

/// The plan skill's fresh plan check, run before the Owner sees a written plan.
const _planFreshRead = 'specstone-plan-sdd/references/fresh-read.md';

/// The heading of the plan check's report shape.
const _planCheckReport = '## 6. Report';

/// The first fenced block of the plan check's report section, its lines kept;
/// empty when the section holds none.
String _planCheckReportBlock() {
  final text = _pluginText(_planCheck);
  final start = text.indexOf('\n$_planCheckReport\n');
  if (start < 0) return '';
  return _fencedBlock.firstMatch(text.substring(start))?.group(1) ?? '';
}

void _planFlowTests() {
  test('plan-sdd keeps its skill file and groups reference within the size '
      'cap', () {
    final files = contentFiles();
    expect(
      files.map((file) => file.path),
      containsAll([
        _planSkill,
        _planGroups,
        _planMainWriter,
        _planFreshRead,
        _planCheck,
      ]),
    );
    expect(
      oversizedSkillFiles(files)
          .where((problem) => problem.contains('specstone-plan-sdd/')),
      isEmpty,
    );
  });

  test('plan-engineer grounds docs, code, instructions, then library docs', () {
    final ground = _sectionOf(_pluginText(_planAgent), '## Ground');
    final order = [
      '`specstone context',
      '`implements` and `covers`',
      '`CLAUDE.md`',
      'Library docs',
    ].map(ground.indexOf).toList();
    expect(order, everyElement(isNonNegative));
    expect(order, orderedEquals([...order]..sort()));
    expect(ground, contains('**Code target:**'));
  });

  test('plan-engineer lists a spec gap as a PRD change for the Owner', () {
    final ground = _sectionOf(_pluginText(_planAgent), '## Ground');
    expect(_hasSentenceWith(ground, ['spec gap', 'PRD']), isTrue);
  });

  test('plan-engineer ends each task but the last with its own sync step', () {
    final workflow = _sectionOf(_pluginText(_planAgent), '## Workflow');
    expect(workflow, contains('`specstone context --for sync --out`'));
  });

  test('plan-engineer writes a code-level seed into each task', () {
    final workflow = _sectionOf(_pluginText(_planAgent), '## Workflow');
    expect(workflow, contains('**Seed**'));
    expect(workflow, contains('code-level'));
  });

  test('plan-engineer writes tests lines before row lines', () {
    final text = _pluginText(_planAgent);
    final workflow = _sectionOf(text, '## Workflow');
    final testsLine = workflow.indexOf('`tests <record> <item>: +<test file>`');
    final rowLine = workflow.indexOf('`row <record> <item>: +<literal>`');
    expect(testsLine, isNonNegative);
    expect(rowLine, greaterThan(testsLine));
    expect(text, isNot(contains('--field tests')));
    expect(text, isNot(contains('#verification_matrix')));
  });

  test('plan-engineer stops at a grouping pass when its Ground call gives two '
      'or more work groups', () {
    final text = _pluginText(_planAgent);
    expect(
      _sectionOf(text, '## Ground'),
      contains('--for implement --out --groups`'),
    );
  });

  // D1
  test(
    'an okayed note has the plan check rank a decided line clash as Critical',
    () {
      final text = _pluginText(_planCheck);
      expect(
        _hasSentenceWith(text, ['`Owner ok:`', 'Critical', '`D<n>`']),
        isTrue,
      );
      expect(
        text,
        contains('`../../specstone-brainstorming-sdd/references/audit.md`'),
      );
      expect(text, contains('`Contradiction`'));
      expect(
        _planCheckReportBlock(),
        contains('- Critical: D<n> <change note path>:<line>'),
      );
      expect(
        _hasSentenceWith(_sectionOf(text, _planCheckReport), [
          'Critical',
          '`Fix:`',
          'no `Fix:`',
        ]),
        isTrue,
      );
      expect(
        _bulletOf(_pluginText(_auditor), '- **Plan check**'),
        anyOf(isEmpty, contains('change note')),
      );
    },
  );

  // D2
  test(
    'a decided line with no outcome for a covered state is one Important item',
    () {
      final text = _pluginText(_planCheck);
      expect(
        _hasSentenceWith(text, ['Important', '`D<n>`', 'no `Fix:`']),
        isTrue,
      );
      expect(_planCheckReportBlock(), contains('- Important: D<n>'));
    },
  );

  // D3
  test('the plan check greps every refs file once for its decided lines', () {
    final text = _pluginText(_planCheck);
    expect(
      _hasSentenceWith(text, [
        '`grep -n -E`',
        'refs file',
        'decided line',
        'every group',
      ]),
      isTrue,
    );
    // D1 D2
    expect(
      _hasSentenceWith(text, ['hit', '`Critical`', '`Important`']),
      isTrue,
    );
    expect(
      _hasSentenceWith(text, [
        'evidence',
        '`<doc>#<key>`',
        '`==> `',
        'never',
        '`<path>:<line>`',
      ]),
      isTrue,
    );
    expect(_planCheckReportBlock(), isNot(contains('<refs path>')));
    expect(
      text,
      contains(
        '`../../specstone-brainstorming-sdd/references/build-first-audit.md`',
      ),
    );
    expect(
      _bulletOf(_pluginText(_auditor), '- In a plan check'),
      contains('`grep -n -E`'),
    );
  });

  // D6
  test('without an Owner ok line the plan check clears every decided line as before', () {
    final text = _pluginText(_planCheck);
    final read = _sectionOf(text, '## 2. Read the plan');
    expect(
      _bulletOf(text, '3. When a `change note` is given'),
      allOf(isNotEmpty, isNot(contains('no change note'))),
    );
    expect(
      _hasSentenceWith(read, [
        '`Owner ok:`',
        'decided line',
        'lacks',
        'no change note',
      ]),
      isTrue,
    );
  });

  // D4
  test('a decided-line finding goes to the Owner before any planner round', () {
    final act = _sectionOf(
      _pluginText(_planFreshRead),
      '## 2. Act on the check',
    );
    expect(
      act.indexOf('decided-line finding'),
      allOf(
        isNonNegative,
        lessThan(act.indexOf('Then send every finding once')),
      ),
    );
    expect(_hasSentenceWith(act, ['decided-line tests', 'design.md']), isTrue);
    expect(
      _hasSentenceWith(act, [
        'ask the Owner once',
        'in one message',
        'every decided-line finding',
      ]),
      isTrue,
    );
    expect(
      _hasSentenceWith(act, [
        "replace the note's `Owner ok:` line with `Owner ok: <YYYY-MM-DD>`",
        "the date of the Owner's answer",
      ]),
      isTrue,
    );
    expect(
      _hasSentenceWith(act, ['names there the doc it supersedes']),
      isTrue,
    );
  });

  // D5
  test(
    'an unsettled decided-line finding takes the whole change Docs-first',
    () {
      final act = _sectionOf(
        _pluginText(_planFreshRead),
        '## 2. Act on the check',
      );
      expect(_hasSentenceWith(act, ['Docs-first', '`Owner ok:`']), isTrue);
      expect(
        _hasSentenceWith(act, [
          'some settled and some not included',
          'fails a decided-line test',
        ]),
        isTrue,
      );
      expect(
        _hasSentenceWith(act, [
          'leave the plan skill',
          'no item of step 3',
          "no step 4 of the plan skill's `SKILL.md`",
        ]),
        isTrue,
      );
      expect(act, contains('`../../specstone-brainstorming-sdd/SKILL.md`'));
      expect(_hasSentenceWith(act, ['step 4', 'same change note']), isTrue);
    },
  );

  // D4
  test('a decided-line finding goes to the group planner whose part cites its '
      'D<n>', () {
    final answers = _sectionOf(
      _pluginText(_planGroups),
      '## 2. Answers after the merge',
    );
    expect(
      _hasSentenceWith(answers, [
        'decided-line finding',
        'each group whose part cites that `D<n>`',
        'group 1',
        'changes no story',
      ]),
      isTrue,
    );
    expect(
      _hasSentenceWith(answers, [
        "Any other finding on no part's line",
        'merge planner',
      ]),
      isTrue,
    );
  });

  test("plan-engineer as a group planner writes its group's tasks to its part "
      'file alone', () {
    final text = _pluginText(_planAgent);
    expect(
      _sectionOf(text, '## Input Contract'),
      contains('**`group`, `bundles`, `check`, `part`**'),
    );
  });

  test('plan-engineer as the merge planner writes one plan from the parts, '
      'ordered by their Waits on lines', () {
    final text = _pluginText(_planAgent);
    expect(
      _sectionOf(text, '## Input Contract'),
      contains('**`parts`** (the merge planner'),
    );
  });
}

// MARK: - Bootstrap routing

const _prdProcedure = 'specstone-bootstrap-prd/references/procedure.md';
const _specProcedure = 'specstone-bootstrap-spec/references/procedure.md';
const _prdMergeUntyped = 'specstone-bootstrap-prd/references/merge-untyped.md';

const List<String> _bootstrapSpecFiles = [
  'specstone-bootstrap-spec/SKILL.md',
  _specProcedure,
  'specstone-bootstrap-spec/references/merge-untyped.md',
  'specstone-bootstrap-spec/references/engineer.md',
];

const List<String> _bootstrapPrdFiles = [
  'specstone-bootstrap-prd/SKILL.md',
  _prdProcedure,
  _prdMergeUntyped,
  'specstone-bootstrap-prd/references/engineer.md',
];

void _bootstrapRoutingTests() {
  test('both bootstrap skills point to the fix loop from their trim round', () {
    for (final skill in _bootstrapSkills) {
      final text = _pluginText(skill);
      final pointer = _sentencesOf(_sectionOf(text, _bootstrapAfterReports))
          .where((sentence) => sentence.contains('trim-round.md'));
      expect(
        pointer.single,
        contains('`../$_fixLoopReference`'),
        reason: skill,
      );
      expect('fix-loop.md'.allMatches(text), hasLength(1), reason: skill);
    }
  });

  test('bootstrap-spec names no finding kind the CLI lacks and no spec type '
      'file name', () {
    for (final file in _bootstrapSpecFiles) {
      final text = _pluginText(file);
      expect(text, isNot(contains('architecture_missing')), reason: file);
      expect(text, isNot(contains('TECH_STACK.md')), reason: file);
    }
  });

  test('no bootstrap file writes a record at a typed address of its own', () {
    for (final file in [..._bootstrapSpecFiles, ..._bootstrapPrdFiles]) {
      expect(
        _pluginText(file),
        isNot(contains('implementation:<')),
        reason: file,
      );
    }
  });

  test('no bootstrap or init file takes code_uncovered, an Uncovered file, or a picks input', () {
    for (final file in [..._bootstrapSpecFiles, ..._bootstrapPrdFiles]) {
      final text = _pluginText(file);
      expect(text, isNot(contains('code_uncovered')), reason: file);
      expect(text, isNot(contains('`Uncovered:`')), reason: file);
      expect(text, isNot(contains('`picks`')), reason: file);
      expect(text, isNot(contains('`picks:`')), reason: file);
    }
    expect(
      _pluginText('specstone-init/SKILL.md'),
      isNot(matches(RegExp(r'uncovered\s+code'))),
    );
    final picks = _sectionOf(_pluginText(_engineer), '## Input Contract')
        .split(RegExp(r'(?= - \*\*`)'))
        .singleWhere((bullet) => bullet.contains('**`picks`**'));
    expect(picks, contains('sync'));
    expect(picks, isNot(contains('bootstrap')));
  });
}

// MARK: - json paths

/// The fixture docs whose `get --json` reply a span may resolve in: the
/// architecture doc holds `tasks` and `overrides`, the FR doc `confirmed`.
const _jsonPathDocs = [
  'specs/f01_login/ARCHITECTURE.md',
  'prds/features/f01_login/us01_email_login/fr01_validate_credentials.md',
];

final _jsonPathStep = RegExp(r'^([^\[\]]+)(?:\[(\d+)\])?$');

/// Whether the dotted [path] resolves in [json]; a `<placeholder>` step
/// matches any key of the object it meets.
bool _resolvesIn(Object? json, String path) =>
    _resolvesSteps(json, path.split('.'));

bool _resolvesSteps(Object? node, List<String> steps) {
  if (steps.isEmpty) return true;
  final match = _jsonPathStep.firstMatch(steps.first);
  if (match == null || node is! Map<String, Object?>) return false;
  final key = match.group(1)!;
  final isPlaceholder = key.startsWith('<') && key.endsWith('>');
  final values = isPlaceholder
      ? node.values
      : [if (node.containsKey(key)) node[key]];
  final index = match.group(2);
  final rest = steps.sublist(1);
  return values.any((value) {
    if (index == null) return _resolvesSteps(value, rest);
    final at = int.parse(index);
    return value is List<Object?> &&
        at < value.length &&
        _resolvesSteps(value[at], rest);
  });
}

void _jsonPathsTests() {
  // D17: a skill names the JSON path under `docs[<i>]`, never a bare `bases.`.
  test('each code span starting with docs[ or bases. in an agent source file resolves in the get --json reply', () async {
    final (:runner, :out, :err) = readRunner(await writeReadProject());
    final replies = <Object?>[];
    for (final doc in _jsonPathDocs) {
      out.clear();
      expect(await runner.run(['get', doc, '--json']), 0, reason: '$err');
      replies.add(jsonDecode(out.toString()));
    }
    final problems = <String>[];
    for (final file in agentSourceFiles(agentAssetsRoot())) {
      final text = file.readAsStringSync().replaceAll('\r\n', '\n');
      for (final span in _inlineSpans(text)) {
        if (!span.startsWith('docs[') && !span.startsWith('bases.')) continue;
        if (!replies.any((reply) => _resolvesIn(reply, span))) {
          problems.add('${shippedPathOf(file)}: $span');
        }
      }
    }
    expect(problems, isEmpty);
  });
}
