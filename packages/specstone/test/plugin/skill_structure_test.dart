// Test names stay one literal so `specstone check` finds them by exact text.
// ignore_for_file: lines_longer_than_80_chars

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
  group('glossary move', _glossaryMoveTests);
  group('re-review', _reReviewTests);
  group('fix loop', _fixLoopTests);
  group('author mode', _authorModeTests);
  group('small edit', _smallEditTests);
  group('moved parts', _movedPartsTests);
  group('grounding', _groundingTests);
  group('plan flow', _planFlowTests);
  group('sync routes', _syncRouteTests);
  group('sync procedure', _syncProcedureTests);
  group('sync engineer', _syncEngineerTests);
  group('bootstrap routing', _bootstrapRoutingTests);
  group('boundary rule', _boundaryRuleTests);
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
];

const _procedures = <String>[
  'specstone-sync-sdd/references/procedure.md',
  'specstone-sync-sdd/references/routes.md',
  'specstone-sync-sdd/references/helpers.md',
  'specstone-sync-sdd/references/task-refs.md',
  'specstone-sync-sdd/references/matrix-rows.md',
  _syncDecided,
  'specstone-bootstrap-prd/references/procedure.md',
  'specstone-bootstrap-spec/references/procedure.md',
  _trimRound,
  _goalMove,
  'specstone-brainstorming-sdd/references/author.md',
  'specstone-brainstorming-sdd/references/author-report.md',
  'specstone-brainstorming-sdd/references/author-recovery.md',
  'specstone-brainstorming-sdd/references/author-size.md',
  'specstone-brainstorming-sdd/references/design.md',
  'specstone-brainstorming-sdd/references/audit.md',
  'specstone-brainstorming-sdd/references/trim-audit.md',
  _noDispatchReference,
  _reReviewReference,
  _decidedAuditReference,
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
  ],
  'specstone-brainstorming-sdd/references/author-report.md': [
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

  test('the auditor stops with OPEN QUESTIONS on a missing or other job', () {
    final contract = _sectionOf(_pluginText(_auditor), '## Input Contract');
    expect(
      _hasSentenceWith(contract, [
        '**`job`**',
        '`builder-check`',
        '`trim-audit`',
        '`plan-check`',
        'OPEN QUESTIONS:',
        'no other file written',
      ]),
      isTrue,
    );
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
    expect(skill, isNot(contains('gate file')));
    expect(skill, isNot(contains('check.gate')));
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

  test("sync writes a deferring plan's lines before its first call", () {
    final first = _sectionOf(_pluginText(_syncSkill), _syncFirstStep);
    expect(
      _hasSentenceWith(first, [
        'deferred its record writes',
        'every `tests` line',
        'then every `row` line',
        '`<folder>/reports/<agent>.sync.<XXXXXX>.md`',
        '`specstone folder`',
      ]),
      isTrue,
    );
    expect(first, contains('one `specstone set --sync <sync file>`'));
    expect(
      _hasSentenceWith(first, [
        'then make the first call',
        "pre-fills each new row's `match` line",
      ]),
      isTrue,
    );
  });

  test('sync routes run a no-feature doc beside features, uncovered last', () {
    final rows = _tableRowsOf(_pluginText(_syncRoutes), _routesHeading);
    String rowOf(String word) =>
        rows.singleWhere((row) => row.startsWith('| `$word` |'));
    expect(rows.where((row) => row.startsWith('| `')), hasLength(3));
    expect(
      rowOf('engineer'),
      allOf(contains('doc under no feature'), contains('at once')),
    );
    expect(rowOf('engineer'), isNot(contains('uncovered')));
    expect(
      rowOf('last'),
      allOf(contains('`uncovered`'), contains('after every other group')),
    );
    expect(rowOf('small'), contains('`specstone set --sync`'));
  });

  test("sync routes name a record's covers in the small route and group "
      'a record with its top feature', () {
    final routes = _pluginText(_syncRoutes);
    final small = _tableRowsOf(
      routes,
      _routesHeading,
    ).singleWhere((row) => row.startsWith('| `small` |'));
    expect(small, allOf(contains('`covers` entries'), contains("record's")));
    expect(
      _hasSentenceWith(routes, ['A record', "top feature's group"]),
      isTrue,
    );
    expect(
      _hasSentenceWith(routes, ["record's `implements` entry", 'never small']),
      isTrue,
    );
    expect(routes, isNot(contains('`architecture')));
  });

  test('no later sync step runs a second context --for sync call', () {
    final files = [
      _syncSkill,
      ..._procedures.where((file) => file.startsWith('specstone-sync-sdd/')),
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
    expect(
      _oneLine(_pluginText(_syncRoutes)),
      contains("the first call's group file"),
    );
  });

  test("sync passes the change note to each engineer of a plan's last sync "
      'and its reruns', () {
    final route = _sectionOf(_pluginText(_syncSkill), _syncRouteStep);
    expect(
      _hasSentenceWith(route, [
        "plan's last sync and each of its reruns",
        'each engineer dispatch',
        '`change note:`',
        "plan's last task names",
      ]),
      isTrue,
    );
    expect(
      _hasSentenceWith(route, [
        'No subagent',
        '`references/decided.md`',
        '`change note`',
      ]),
      isTrue,
    );
  });

  test('a small group with decided work routes to its engineer', () {
    final small = _sectionOf(_pluginText(_syncRoutes), '## Small group');
    expect(
      _hasSentenceWith(small, [
        "plan's last sync",
        'decided behavior no spec states',
        'whole group to an engineer of its route',
      ]),
      isTrue,
    );
  });

  test('sync runs one Decided audit and approves its drafts before the '
      'branch lands', () {
    final after = _sectionOf(_pluginText(_syncSkill), _syncAfterReport);
    expect(
      _hasSentenceWith(after, [
        "a Decided change's drafts",
        'last rerun',
        'one fresh `specstone-sdd-auditor`',
        '`job: decided-audit`',
      ]),
      isTrue,
    );
    expect(
      _hasSentenceWith(after, [
        '`../specstone-expert-sdd/references/approve.md`',
        "the audit's report its one `--audit`",
        'before the branch lands',
      ]),
      isTrue,
    );
    expect(
      _hasSentenceWith(after, [
        'write no PRD doc',
        "but a decided line's drafts",
      ]),
      isTrue,
    );
  });

  test(
    "sync runs the Decided audit after the Mismatches picks' spec fixes",
    () {
      final after = _sectionOf(_pluginText(_syncSkill), _syncAfterReport);
      expect(
        _hasSentenceWith(after, [
          "item 3's spec fixes",
          'one fresh `specstone-sdd-auditor`',
          "a decided-line point's fix-the-spec drafts",
        ]),
        isTrue,
      );
      expect(
        after.indexOf('`job: decided-audit`'),
        greaterThan(after.indexOf('per `Mismatches:` point')),
      );
    },
  );
}

// MARK: - sync procedure

const _syncProcedure = 'specstone-sync-sdd/references/procedure.md';

const _syncMatrixRows = 'specstone-sync-sdd/references/matrix-rows.md';

const _syncHelpers = 'specstone-sync-sdd/references/helpers.md';

/// The decided-line steps of a sync engineer given a change note.
const _syncDecided = 'specstone-sync-sdd/references/decided.md';

const _syncTaskRefs = 'specstone-sync-sdd/references/task-refs.md';

const _syncWrite = '## 4. Write the group in one call';

const _syncRefused = '## 5. Answer each refused line';

const _syncAfterReport = '## 3. After the report';

void _syncProcedureTests() {
  test(
    'sync procedure judges a group file and writes it by one set --sync',
    () {
      final procedure = _pluginText(_syncProcedure);
      expect(procedure, contains('`==> verdicts <==`'));
      expect(_hasSentenceWith(procedure, ['verdict part', 'in place']), isTrue);
      expect(
        '`specstone set --sync <group file>`'.allMatches(procedure),
        hasLength(1),
      );
      expect(
        _hasSentenceWith(_sectionOf(procedure, _syncWrite), [
          '`specstone set --sync <group file>`',
          '`--target <name>`',
        ]),
        isTrue,
      );
      expect(procedure, isNot(contains('context --code')));
      expect(procedure, isNot(contains('gate file')));
      expect('specstone check'.allMatches(procedure), hasLength(1));
      for (final file in [_syncSkill, _syncProcedure, _syncMatrixRows]) {
        expect(_pluginText(file), isNot(contains('--stamp')), reason: file);
      }
    },
  );

  test(
    'sync refusals: rejudge stale, repoint unresolved, two reruns at most',
    () {
      final refused = _sectionOf(_pluginText(_syncProcedure), _syncRefused);
      for (final words in [
        [
          '`stamp_stale`',
          'judge',
          '`match` or `planned`',
          "row's `suspect` finding",
          'specstone check',
        ],
        ['`stamp_entry_unresolved`', '`repoint`', '`root: project`'],
        ['`verdict_unjudged`', '`stamp_entry_unknown`', '`doc_not_found`'],
        ['`argument_invalid`', 'at most twice'],
      ]) {
        expect(_hasSentenceWith(refused, words), isTrue, reason: words.join());
      }
      final after = _sectionOf(_pluginText(_syncSkill), _syncAfterReport);
      expect(
        _hasSentenceWith(after, ['`specstone set --sync`', 'same group file']),
        isTrue,
      );
      expect(
        _hasSentenceWith(after, ['refuses', 'leave it out', 'the rest']),
        isTrue,
      );
    },
  );

  test('matrix rows copy each plus literal from the test file', () {
    expect(
      _hasSentenceWith(_pluginText(_syncMatrixRows), [
        'copied from the test file as it stands',
        'its first literal when the name is split',
        'interpolations kept',
      ]),
      isTrue,
    );
  });

  test(
    'matrix rows write row lines, each stamped by a following match line',
    () {
      final rows = _pluginText(_syncMatrixRows);
      expect(rows, contains('`row <record> <item>[ <edge case>]: '));
      expect(
        _hasSentenceWith(rows, ['`match` line', 'after', '`row` line']),
        isTrue,
      );
      expect(_hasSentenceWith(rows, ['`<literal>` in one code span']), isTrue);
      expect(rows, isNot(contains('--replace')));
      expect(rows, isNot(contains('specstone get')));
      expect(rows, isNot(contains('specstone check')));
    },
  );

  test('a helper joins covers by set --field covers with no fingerprint', () {
    final helpers = _pluginText(_syncHelpers);
    expect(
      _hasSentenceWith(helpers, ['--field covers', 'no fingerprint']),
      isTrue,
    );
    expect(_hasSentenceWith(helpers, ['no `match` line']), isTrue);
    expect(helpers, isNot(contains('--stamp')));
    expect(helpers, isNot(contains('specstone check')));
  });

  test("a helper joins its feature's record covers and names no other doc "
      'type', () {
    final helpers = _pluginText(_syncHelpers);
    expect(
      _hasSentenceWith(helpers, ["feature's record", '`covers`', 'add']),
      isTrue,
    );
    expect(helpers, isNot(contains('`architecture')));
    expect(helpers, isNot(contains('topic')));
    expect(helpers, isNot(contains("spec doc's `covers`")));
  });

  test('a code_uncovered file a decided line states takes its drafts or a '
      'Mismatches point, never Uncovered', () {
    expect(
      _hasSentenceWith(_pluginText(_syncHelpers), [
        '`change note`',
        'decided line',
        '`decided.md`',
        '`Mismatches:` point',
        'never `Uncovered:`',
      ]),
      isTrue,
    );
    final decided = _pluginText(_syncDecided);
    expect(
      _hasSentenceWith(decided, [
        '`code_uncovered` file',
        'does what a decided line states',
        'no Owner pick',
      ]),
      isTrue,
    );
    expect(
      _hasSentenceWith(decided, [
        '`code_uncovered` file',
        'no pointer',
        '`Pointers:`',
        'approval',
      ]),
      isTrue,
    );
  });

  test(
    'task refs keep each pre-filled remove-task line in the group set --sync',
    () {
      final taskRefs = _pluginText(_syncTaskRefs);
      expect(
        _hasSentenceWith(taskRefs, [
          'pre-filled `remove-task`',
          "group's own `specstone set --sync`",
        ]),
        isTrue,
      );
      expect(_hasSentenceWith(taskRefs, ['delete none', 'write none']), isTrue);
      expect(_hasSentenceWith(taskRefs, ['`Kept:`']), isTrue);
      expect(
        _hasSentenceWith(_sectionOf(taskRefs, '## Report'), [
          'lists no removed task',
          '`remove-task` lines',
          '`Waiting:`',
          '`Kept:`',
          'no refs',
        ]),
        isTrue,
      );
      expect(taskRefs, isNot(contains('git log')));
      expect(taskRefs, isNot(contains('`resolves`')));
      expect(RegExp(r'step \d').hasMatch(taskRefs), isFalse);
      expect(
        _hasSentenceWith(_pluginText(_syncProcedure), [
          '`remove-task`',
          '`task-refs.md`',
        ]),
        isTrue,
      );
    },
  );

  test('a fix-the-spec draft turns its mismatch lines into a match', () {
    final drafts = _sectionOf(_pluginText(_syncProcedure), '## 6. Spec drafts');
    expect(
      _hasSentenceWith(drafts, [
        'fix-the-spec draft',
        "link's `mismatch` lines",
        'one `match` line',
        '`fingerprint` line',
        '`specstone set --sync` again',
        '`Waiting:`',
      ]),
      isTrue,
    );
  });

  test('sync procedure judges each line by the doc printed for its link', () {
    final procedure = _pluginText(_syncProcedure);
    expect(
      _sectionOf(procedure, '## 1. Read the group file'),
      contains("each judged link's doc"),
    );
    expect(
      _hasSentenceWith(_sectionOf(procedure, '## 2. Judge each line'), [
        '**`match`:**',
        'printed for its link',
      ]),
      isTrue,
    );
    expect(procedure, isNot(contains('every covering doc')));
    expect(procedure, isNot(contains("covering doc's contract text")));
  });

  test("main writes a new spec's waiting pointer once approved", () {
    final after = _sectionOf(_pluginText(_syncSkill), _syncAfterReport);
    expect(
      _hasSentenceWith(after, [
        "new spec's waiting pointer",
        '`--field covers`',
        '`--field implements`',
        'no fingerprint',
      ]),
      isTrue,
    );
  });

  test('no sync file runs a set --remove-task left waiting for main', () {
    final files = [
      _syncSkill,
      ..._procedures.where((file) => file.startsWith('specstone-sync-sdd/')),
    ];
    for (final file in files) {
      expect(_pluginText(file), isNot(contains('--remove-task')), reason: file);
    }
    final after = _sectionOf(_pluginText(_syncSkill), _syncAfterReport);
    expect(
      _hasSentenceWith(after, [
        '`specstone set --sync`',
        'same group file',
        'waiting `remove-task`',
      ]),
      isTrue,
    );
    expect('waiting `remove-task`'.allMatches(after), hasLength(1));
  });
}

// MARK: - sync engineer

void _syncEngineerTests() {
  test('the sync engineer takes a group file and no check input', () {
    final contract = _sectionOf(_pluginText(_engineer), '## Input Contract');
    expect(
      _hasSentenceWith(contract, [
        '**`group file`** (sync, required)',
        '`group file: <path>`',
        'first call',
      ]),
      isTrue,
    );
    expect(contract, contains('**`check`** (bootstrap, optional)'));
    expect(contract, isNot(contains('`check:` file')));
  });

  test('the sync engineer writes the verdict part of its group file', () {
    final boundaries = _sectionOf(
      _pluginText(_engineer),
      '## Scope Boundaries',
    );
    expect(
      _hasSentenceWith(boundaries, [
        '`mode: sync`',
        'verdict part',
        'group file',
        'reports folder',
      ]),
      isTrue,
    );
  });

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
    expect(text, contains('A failed load: report it and stop; never search.'));
    final workflow = _sectionOf(text, '## Workflow');
    expect(
      _hasSentenceWith(workflow, [
        '**Bootstrap**',
        'from its step 2',
        'through its report',
      ]),
      isTrue,
      reason: 'a bootstrap run reaches the gate once, at Workflow step 1',
    );
    for (final entry in _bootstrapEntries) {
      expect(
        _pluginText(entry),
        isNot(contains('else first run')),
        reason: entry,
      );
    }
    for (final moved in ['from its step 1', 'retrim_due', 'check.done']) {
      expect(workflow, isNot(contains(moved)), reason: moved);
    }
    final output = _sectionOf(text, '## Output Format');
    for (final moved in ['**Sync**', '**Bootstrap**']) {
      expect(output, isNot(contains(moved)), reason: moved);
    }
  });

  test('each mode entry file names its mode files', () {
    final sync = _pluginText(_syncEntry);
    for (final name in [
      '`procedure.md`',
      '`helpers.md`',
      '`task-refs.md`',
      '`matrix-rows.md`',
    ]) {
      expect(sync, contains(name), reason: name);
    }
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

  test('each sync and bootstrap path reaches the draft line wording', () {
    expect(
      _hasSentenceWith(_sectionOf(_pluginText(_engineer), '## Output Format'), [
        'sync and bootstrap mode',
        '`<type>:<name>`',
        'never their text',
      ]),
      isTrue,
    );
    for (final entry in [_syncEntry, ..._bootstrapEntries]) {
      expect(
        _hasSentenceWith(_pluginText(entry), [
          'draft lines',
          'Output Format gives for sync and bootstrap mode',
        ]),
        isTrue,
        reason: entry,
      );
    }
  });

  test('the sync engineer runs one set --sync, no gate, and no stamp', () {
    final text = _pluginText(_engineer);
    final entry = _pluginText(_syncEntry);
    for (final words in [
      ['**Gate**', 'sync mode', 'run none'],
      ['**Sync**', 'one `specstone set --sync`', 'only your scope'],
      [
        '**Check and report**',
        'sync mode',
        'no gate or done `check`',
        'step 5',
      ],
    ]) {
      expect(_hasSentenceWith(entry, words), isTrue, reason: words.join());
    }
    expect(text, isNot(contains('--stamp')));
    expect(text, isNot(contains('check.sync')));
    expect(entry, isNot(contains('--stamp')));
    expect(entry, isNot(contains('check.sync')));
    expect(
      _hasSentenceWith(entry, [
        '`Findings:`, each line still refused',
        'step 5 reruns',
      ]),
      isTrue,
    );
    expect(
      _hasSentenceWith(_sectionOf(text, '## Scope Boundaries'), [
        'group file belongs to on `specstone set --sync`',
      ]),
      isTrue,
    );
  });

  test("a named feature's work list takes its record's covers links", () {
    final entry = _pluginText(_syncEntry);
    expect(
      _hasSentenceWith(entry, [
        '`feature: <name>`',
        "its record's `covers:` links",
      ]),
      isTrue,
    );
    expect(entry, isNot(contains('`architecture')));
  });

  test('the sync engineer points at the procedure steps by number', () {
    final procedure = _pluginText(_syncProcedure).split('\n');
    expect(
      procedure,
      containsAll(['## 1. Read the group file', '## 6. Spec drafts']),
    );
    final entry = _pluginText(_syncEntry);
    expect(_hasSentenceWith(entry, ['**Sync**', 'from its step 1']), isTrue);
    expect(_hasSentenceWith(entry, ['`picks`', 'by its step 6']), isTrue);
  });

  test('the sync engineer takes a change note and drafts each decided line '
      'with no pick', () {
    final text = _pluginText(_engineer);
    expect(
      _hasSentenceWith(_sectionOf(text, '## Input Contract'), [
        '**`change note`** (sync, optional)',
        "plan's last sync",
        '`(decided)`',
      ]),
      isTrue,
    );
    expect(
      _hasSentenceWith(_pluginText(_syncEntry), [
        'With a `change note`',
        '`decided.md`',
      ]),
      isTrue,
    );
    final decided = _pluginText(_syncDecided);
    expect(
      _hasSentenceWith(decided, [
        "each decided line's PRD and spec drafts",
        'no Owner pick',
        '`specstone new <type>`',
        'story or FR no doc holds yet',
      ]),
      isTrue,
    );
    expect(
      _hasSentenceWith(decided, [
        'no decided behavior',
        '`specstone-brainstorming-sdd`',
      ]),
      isTrue,
    );
    expect(
      _hasSentenceWith(_sectionOf(text, '## Output Format'), [
        '**Sync with a change note**',
        '`Decision:` line per decided line',
        '`Not landed:` line',
      ]),
      isTrue,
    );
  });

  test(
    'the sync engineer finds the readers of each decided line it drafts',
    () {
      final decided = _pluginText(_syncDecided);
      expect(
        _oneLine(decided),
        contains(
          '`../../specstone-brainstorming-sdd/references/author.md` '
          '`## 2. Find the readers`',
        ),
      );
      expect(
        _hasSentenceWith(decided, [
          'Before your first write',
          'reader step',
          'author.md`',
        ]),
        isTrue,
      );
      expect(
        _hasSentenceWith(decided, [
          'Find the readers`',
          'each decided line you draft',
          '`Readers:` line',
        ]),
        isTrue,
      );
      for (final copied in ['specstone search', 'specstone refs']) {
        expect(decided, isNot(contains(copied)), reason: copied);
      }
      expect(
        _hasSentenceWith(
          _sectionOf(_pluginText(_engineer), '## Output Format'),
          ['**Sync with a change note**', "each decided draft's `Readers:`"],
        ),
        isTrue,
      );
    },
  );

  test('the sync engineer reports a decided-line departure as a Mismatches '
      'point naming its D-number', () {
    expect(
      _hasSentenceWith(_pluginText(_syncDecided), [
        'departs from its decided line',
        '`Mismatches:` point',
        "the line's `D<n>`",
        "until the Owner's pick",
      ]),
      isTrue,
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

  test('every shipped skill file stays within 1,500 est. tokens', () {
    final files = contentFiles();
    expect(files.where((file) => file.isSkillFile), isNotEmpty);
    expect(files.map((file) => file.path), contains(_reReviewReference));
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
    'the source walk sees the thirteen sources and leaves AGENT.md out',
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

  test('the nine skills and four agents are all there', () {
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
    expect(
      unknownCliNames(files, SpecstoneCommandRunner(console: FakeConsole())),
      isEmpty,
    );
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

// MARK: - pack doc type

void _packDocTypeTests() {
  Future<List<String>> namesIn(String text) async {
    final root = await writeTree({'specstone-x/SKILL.md': text});
    return packDocTypeNames(contentFilesOf(root), PackDocTypes.shipped());
  }

  test('a file naming architecture:login fails naming its file and '
      'architecture', () async {
    expect(await namesIn('Open `architecture:login` first.'), [
      'specstone-x/SKILL.md: architecture',
    ]);
  });

  test('a file naming ARCHITECTURE.md fails naming the architecture type', () {
    expect(
      namesIn('Read ARCHITECTURE.md first.'),
      completion(['specstone-x/SKILL.md: architecture']),
    );
  });

  test('a file naming a dropped type address such as domain:login fails', () {
    expect(
      namesIn('Open domain:login first.'),
      completion(['specstone-x/SKILL.md: domain']),
    );
  });

  test('a bare id, a stem, or prose such as the architecture doc passes', () {
    expect(
      namesIn(
        'Read the architecture doc, the ARCHITECTURE stem, and security.',
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
    expect(packDocTypeNames(files, PackDocTypes.shipped()), isEmpty);
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

  test('merge-untyped.md sends an event schema, data shape, and rollout note '
      'to the section whose guide takes it, else deletes it', () {
    final text = _pluginText(_mergeUntyped);
    expect(
      _hasSentenceWith(text, [
        'an event or message schema',
        'the section whose guide takes it',
        'deleted as code holds it',
      ]),
      isTrue,
    );
    expect(
      _hasSentenceWith(text, [
        'a migration or rollout note',
        'the section whose guide takes it',
      ]),
      isTrue,
    );
  });

  test('trim.md sends FR mechanism text to the home its guide line names, '
      'never cuts it as banned text, and names no API operation', () {
    final text = _pluginText(_trimReference);
    expect(text, isNot(contains('never move it')));
    expect(
      _hasSentenceWith(text, [
        'Mechanism text in an FR',
        'home its guide line names',
      ]),
      isTrue,
    );
    expect(text, contains('delete it when no line names one'));
    final cutRows = text
        .split('\n')
        .where((line) => line.startsWith('| cut |'));
    expect(cutRows, hasLength(1));
    expect(cutRows.single, isNot(contains('mechanism')));
    expect(text, isNot(contains('API operation')));
  });

  test('specstone-init names no pack doc type', () {
    final text = _pluginText('specstone-init/SKILL.md');
    expect(text, isNot(contains('tech stack')));
    expect(
      _hasSentenceWith(text, ['in the order', '`specstone init`', 'printed']),
      isTrue,
    );
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

  test('no shipped skill or agent file names docPath, bases.doc, or a dry-run hash key', () {
    for (final file in _skillAndAgentFiles()) {
      final text = _pluginText(file);
      expect(text, isNot(contains('`docPath`')), reason: file);
      expect(text, isNot(contains('bases.doc')), reason: file);
      expect(
        _hasSentenceWith(text, ['--dry-run --json', '`hash`']),
        isFalse,
        reason: file,
      );
    }
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
        ], reason: render.path);
      }
      expect(
        _hasSentenceWith(_sectionOf(render.body, '## Bootstrap'), [
          'specstone-read-sdd',
          'no `bundles`',
          'already in context',
        ]),
        isTrue,
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
    expect(text.toLowerCase(), isNot(contains('resum')));
    expect(text, isNot(contains('sweep')));
  });

  test('dispatch.md generic rung dispatches anyway and reads the agent file '
      'by its path', () {
    final section = _sectionOf(
      _pluginText(_dispatchReference),
      '## Generic subagent',
    );
    for (final words in [
      ['host forbids handing skill reading to a subagent', 'Dispatch anyway'],
      ['`../../agents/specstone-<agent>.md`', "dispatching skill's folder"],
    ]) {
      expect(_hasSentenceWith(section, words), isTrue, reason: words.join());
    }
  });

  test('dispatch.md main-session rung runs on no subagent or a failed '
      'dispatch', () {
    final section = _sectionOf(
      _pluginText(_dispatchReference),
      '## Main session',
    );
    expect(
      _hasSentenceWith(section, [
        'With no subagent',
        'failed dispatch',
        'follow it yourself',
      ]),
      isTrue,
    );
  });

  test('dispatch.md main-session rung tells the Owner a check it runs is no '
      "fresh reader's", () {
    final section = _sectionOf(
      _pluginText(_dispatchReference),
      '## Main session',
    );
    expect(
      _hasSentenceWith(section, [
        'builder check',
        'trim audit',
        "not a fresh reader's",
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

  test("expert-sdd writes one Queued file before a bootstrap round's auto "
      'call', () {
    final sentences = _approveSentences();
    final queued = _indexWith(sentences, [
      'Queued:',
      'Citers outside:',
      '--audit',
    ]);
    expect(queued, isNonNegative);
    expect(
      _indexWith(sentences, ['Run one', '--auto --json']),
      greaterThan(queued),
    );
  });

  test('expert-sdd sends brainstorm audit asks, added drafts, and named drafts '
      'to one re-review, and Owner-only or ruled asks to the Owner', () {
    final sentences = _approveSentences();
    final reReview = _indexWith(sentences, [
      '`waitsFor` `audit`',
      '`no audit report names it`',
      '`named in Findings of` an audit report for an item with a `Fix:` line',
      'one fresh `specstone-sdd-auditor`',
      '`job: re-review`',
      '`findings:` each audit item still open that names those drafts',
      'those drafts, verbatim, or `none`',
      'no `fix report:`',
      '`audits:` every first-call audit report path',
      'the `Queued:` file aside, oldest first',
      "change note's path",
      "Owner's answers",
    ]);
    expect(reReview, isNonNegative);
    expect(
      sentences[reReview],
      startsWith('Send every `asked` entry of the first call '),
    );
    expect(
      sentences.elementAtOrNull(reReview + 1),
      allOf(
        contains('no `Fix:` line that only the Owner settles'),
        contains("fix loop's breaker decided"),
        contains('goes to the Owner, not to the re-review'),
      ),
    );
    final none = _indexWith(sentences, ['no such entry', 'no re-review runs']);
    expect(none, greaterThan(reReview));
    expect(_secondCallIndex(sentences), greaterThan(none));
    expect(
      sentences.where((sentence) => sentence.contains('`job: re-review`')),
      hasLength(1),
    );
    for (final gone in [
      'fix-read',
      'fix read',
      'trim-audit',
      '`trims:`',
      'changedSections',
    ]) {
      expect(_approveText(), isNot(contains(gone)), reason: gone);
    }
  });

  test('expert-sdd adds each listed citer of a bootstrap draft to its '
      're-review', () {
    final sentences = _approveSentences();
    final reReview = _indexWith(sentences, ['`job: re-review`']);
    final citers = _indexWith(sentences, [
      'In a bootstrap round',
      '`drafts:` adds each listed draft awaiting approval',
      '`Inbound` lines of `refs <draft>`',
      'citing one',
      'marked `citer of <type>:<name>`',
    ]);
    expect(reReview, isNonNegative);
    expect(citers, greaterThan(reReview));
    expect(_secondCallIndex(sentences), greaterThan(citers));
    expect(
      _hasSentenceWith(_pluginText(_reReviewReference), [
        'marked `citer of <type>:<name>`',
        'citing items alone',
        '`grep -n -E`',
        'whatever step 1 lists for it',
      ]),
      isTrue,
    );
  });

  test('expert-sdd passes each loop re-review report to the first auto call '
      'oldest first', () {
    final sentences = _approveSentences();
    final first = _indexWith(sentences, ['Run one', '--auto --json']);
    for (final words in [
      [
        'In `specstone-brainstorming-sdd`',
        '`--audit <path>` per audit report of the run',
        'the builder check, then each loop re-review, oldest first',
      ],
      [
        'in a bootstrap round',
        '`--audit <path>` per audit report of the round',
        'the trim audit, then each loop re-review, oldest first',
      ],
    ]) {
      expect(
        _indexWith(sentences, words),
        allOf(greaterThan(first), lessThan(_secondCallIndex(sentences))),
        reason: words.join(', '),
      );
    }
    expect(_approveText(), isNot(contains('per builder check report')));
  });

  test("expert-sdd applies the re-review's fix blocks before one second auto "
      'call', () {
    final sentences = _approveSentences();
    final blocks = _indexWith(sentences, [
      "each `Fix:` block of the re-review's report",
      '`specstone set`',
      "that section's whole text",
      'unchanged',
    ]);
    final secondCall = _secondCallIndex(sentences);
    expect(blocks, isNonNegative);
    expect(secondCall, greaterThan(blocks));
    expect(sentences[secondCall], startsWith('After the re-review and its '));
    expect(
      sentences.where(
        (sentence) =>
            sentence.contains('second') && sentence.contains('--auto'),
      ),
      hasLength(1),
    );
  });

  test('expert-sdd names every draft sent to the re-review and no citer in '
      'the second auto call', () {
    final sentences = _approveSentences();
    final second = sentences[_secondCallIndex(sentences)];
    expect(second, contains('naming each draft sent to it, no citer,'));
    expect(second, isNot(contains('`Fix:` block changed')));
    expect(_approveText(), isNot(contains('only the drafts it read')));
  });

  test('expert-sdd passes one author report per writer, the same files in the '
      'second call', () {
    final sentences = _approveSentences();
    final first = _indexWith(sentences, [
      '`--author <path>` once per writer',
      'its one report file',
      'every round of that writer',
    ]);
    expect(first, isNonNegative);
    expect(
      sentences[_secondCallIndex(sentences)],
      contains('the same `--author` paths'),
    );
    expect(
      sentences.where((sentence) => sentence.contains('--author')),
      hasLength(3),
    );
    expect(_approveText(), isNot(contains('per writer report')));
  });

  test("expert-sdd approves a Decided change's drafts in one auto call with "
      'the Decided audit and each sync engineer report', () {
    final sentences = _approveSentences();
    final first = _indexWith(sentences, ['Run one', '--auto --json']);
    final blocks = _indexWith(sentences, [
      "a Decided change's drafts",
      '`Fix:` block of the Decided audit',
      'doc outside the drafts',
      '`specstone set`',
      'unchanged',
      'joins the call',
    ]);
    expect(blocks, allOf(isNonNegative, lessThan(first)));
    final call = _indexWith(sentences, [
      "a Decided change's drafts",
      "the Decided audit's report as the one `--audit <path>`",
      '`--author <path>` once per sync engineer report',
      'before the branch lands',
    ]);
    expect(
      call,
      allOf(greaterThan(first), lessThan(_secondCallIndex(sentences))),
    );
    final reReview = _indexWith(sentences, ['`job: re-review`']);
    expect(sentences[reReview], contains("bar a Decided change's drafts"));
    expect(
      _indexWith(sentences, [
        "A Decided change's drafts take no re-review and no other call",
        'Owner confirmation',
        'each other Decided audit item',
        'its `Fix:` lines',
      ]),
      isNonNegative,
    );
  });

  test('the writer writes each fix block verbatim as its section', () {
    expect(
      _hasSentenceWith(_pluginText(_engineer), [
        '`Fix:` block',
        "that section's whole text",
        'unchanged',
        'never reworded',
      ]),
      isTrue,
    );
  });

  test('expert-sdd asks the Owner once after the second call', () {
    final sentences = _approveSentences();
    final ask = _indexWith(sentences, [
      'one message',
      '`Why:`',
      'change made after the audit',
    ]);
    expect(ask, greaterThan(_secondCallIndex(sentences)));
    expect(sentences[ask], startsWith('Ask them in one message'));
    expect(sentences[ask - 1], contains("first call's `owner` entries"));
    expect(
      sentences.elementAtOrNull(ask + 1),
      allOf(contains("fix loop's breaker"), contains('`Why:`')),
    );
  });

  test(
    'expert-sdd sends the drafts to the Owner when no re-review can run',
    () {
      final sentences = _approveSentences();
      final fallback = _indexWith(sentences, [
        'no subagent',
        'failed dispatch',
        'no re-review runs',
        'Owner confirmation',
        'change made after the audit',
      ]);
      expect(fallback, isNonNegative);
      expect(
        _indexWith(sentences, ['never read your own fixes']),
        greaterThanOrEqualTo(fallback),
      );
    },
  );

  test('expert-sdd shows each carried finding beside its approved draft', () {
    expect(
      _indexWith(_approveSentences(), [
        '`approved` entry',
        'with no wait',
        'each finding of its `carried` key',
        'beside it',
      ]),
      isNonNegative,
    );
  });

  test('expert-sdd shows a brainstorm change note Decisions with the approved '
      'list, also when no draft is asked', () {
    expect(
      _approveSentences().any(
        (sentence) => [
          'In a brainstorm',
          'change note',
          'Decisions',
          'approved list',
          'also when no draft is asked',
        ].every(sentence.contains),
      ),
      isTrue,
    );
  });

  test("a bootstrap round's Owner confirmation starts after the second auto "
      'call', () {
    final sentences = _approveSentences();
    final secondCall = _secondCallIndex(sentences);
    expect(secondCall, isNonNegative);
    expect(
      sentences.indexWhere(
        (sentence) =>
            sentence.contains('Owner confirmation') &&
            sentence.contains('second'),
        secondCall + 1,
      ),
      isNonNegative,
    );
  });

  test('expert-sdd names each Owner question under both modes', () {
    expect(
      _hasSentenceWith(_pluginText(_expertSdd), [
        'both modes',
        'approach pick',
        'builder check',
        'mid-flow',
        'open question',
        'split proposal',
        'sync pick',
        '`delete`',
        '`migrate`',
        '`init`',
        '`--plan`',
      ]),
      isTrue,
    );
  });

  test('gated-plan names the three plan commands and Owner confirmation points '
      'to it twice', () {
    final plan = _pluginText('specstone-expert-sdd/references/gated-plan.md');
    for (final command in [
      '`specstone delete <path> … --yes --plan <hash>`',
      '`specstone migrate --yes --plan <hash>`',
      '`specstone init --yes --plan <hash>`',
    ]) {
      expect(plan, contains(command), reason: command);
    }
    final lines = _pluginText(_expertSdd).split('\n');
    final section = lines.skipWhile((l) => l != '## Owner confirmation');
    expect(
      'references/gated-plan.md'.allMatches(section.join('\n')),
      hasLength(2),
    );
  });

  test('the five runners point to expert-sdd and hold no gated plan copy', () {
    for (final skill in _bootstrapSkills) {
      final procedure = skill.replaceFirst(
        'SKILL.md',
        'references/procedure.md',
      );
      expect(
        _hasSentenceWith(_pluginText(procedure), [
          '`specstone-expert-sdd`',
          'Owner confirmation',
        ]),
        isTrue,
        reason: procedure,
      );
    }
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

  test('Owner confirmation shows each item in full, fixes through set, '
      'shows it again on exit 75, and writes each hash literally', () {
    final text = _sectionOf(_pluginText(_expertSdd), '## Owner confirmation');
    for (final words in [
      ['Show each item in full', 'one per message'],
      ['Fix what the Owner names', '`set`', 'show it again', 'until `ok`'],
      ['exit 75', 'show it again'],
      [
        'Write each `@<hash>`',
        'path',
        '`--plan <hash>`',
        'literally',
        'never from a file, variable, or command substitution',
      ],
      [
        '`--auto` asks',
        'the literal `Why:`',
        "chat's language",
        '--dry-run` text verbatim',
      ],
    ]) {
      expect(_hasSentenceWith(text, words), isTrue, reason: words.join(', '));
    }
    expect(
      _hasSentenceWith(
        _pluginText('specstone-expert-sdd/references/gated-plan.md'),
        ['why each file goes'],
      ),
      isTrue,
    );
  });

  test('Owner confirmation leaves `specstone trust` to the Owner even when '
      'told otherwise', () {
    final text = _sectionOf(_pluginText(_expertSdd), '## Owner confirmation');
    for (final words in [
      ['Never run `specstone trust`', 'answer its prompt', 'even if told to'],
      [
        '`run specstone trust at a terminal`',
        'ask the Owner to run it',
        'then retry',
      ],
    ]) {
      expect(_hasSentenceWith(text, words), isTrue, reason: words.join(', '));
    }
  });

  test('approve runs only with a dry run, auto, or yes, and an auto-approved '
      'draft is listed with no wait', () {
    for (final (text, words) in [
      (
        _sectionOf(_pluginText(_expertSdd), _approveHeading),
        ['Run `approve` only with', '`--dry-run`', '`--auto`', '`--yes`'],
      ),
      (_approveText(), ['each `approved` entry', 'with no wait']),
    ]) {
      expect(_hasSentenceWith(text, words), isTrue, reason: words.join(', '));
    }
  });

  test('the exit 75 rerun covers each auto call', () {
    final sentences = _approveSentences();
    expect(
      _indexWith(sentences, ['Exit 75', 'first', 'second']),
      isNonNegative,
    );
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

  test('expert-sdd tells each subagent to run approve only as a dry run', () {
    final text = _pluginText(_expertSdd);
    final section = _sectionOf(text, _approveHeading);
    final sentences = section.split(RegExp(r'(?<=[.;:])\s'));
    expect(
      sentences.where(
        (sentence) => [
          '`specstone-sdd-engineer`',
          '`specstone-sdd-auditor`',
          '`specstone-plan-engineer`',
          '`specstone-sdd-reader`',
          '`approve`',
          'only with `--dry-run`',
        ].every(sentence.contains),
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
    expect(text, isNot(contains('sweeper')));
  });

  test("each runner points to the approval reference file with its flow's "
      'report flags', () {
    final problems = [
      for (final MapEntry(key: file, value: flags) in _runnerFlags.entries)
        ..._runnerPointerProblems(file, flags),
    ];
    expect(problems, isEmpty);
  });

  test('each trim route of a bootstrap skill names the code block finding', () {
    for (final route in [
      'specstone-bootstrap-prd/references/procedure.md',
      'specstone-bootstrap-spec/references/procedure.md',
      'specstone-bootstrap-prd/references/engineer.md',
      'specstone-bootstrap-spec/references/engineer.md',
    ]) {
      expect(
        _hasSentenceWith(_pluginText(route), [
          '`retrim_due`',
          '`code_blocks_over_limit`',
        ]),
        isTrue,
        reason: route,
      );
    }
  });

  test('both bootstrap skills make a code block finding a trim batch', () {
    for (final skill in _bootstrapSkills) {
      expect(
        _hasSentenceWith(_pluginText(skill), [
          '`code_blocks_over_limit`',
          'trim batch',
        ]),
        isTrue,
        reason: skill,
      );
    }
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

  test('trim-round sends its audit findings to the fix loop and names no '
      'second round', () {
    final text = _pluginText(_trimRound);
    final sentences = _sentencesOf(text);
    final dispatch = _indexWith(sentences, [
      'fresh',
      '`specstone-sdd-auditor`',
      '`trims:`',
      'bootstrap reports',
    ]);
    final loop = _indexWith(sentences, [
      "the audit's `Findings:` items",
      'the fix loop of `fix-loop.md`',
      'bootstrap engineer of the batch that wrote the draft it names',
    ]);
    final approve = _indexWith(sentences, [
      'Once the fix loop ends',
      '`approve.md`',
    ]);
    expect(dispatch, isNonNegative, reason: 'audit dispatch');
    expect(loop, greaterThan(dispatch), reason: 'fix loop');
    expect(approve, greaterThan(loop), reason: 'approve');
    for (final step in [
      'Fix and audit again',
      'fix batch',
      'fresh audit',
      're-audit',
      'one such round',
    ]) {
      expect(text, isNot(contains(step)), reason: step);
    }
    expect(text, isNot(contains('oldest first')), reason: 'audit order');
  });

  test("a trim audit's outside item goes to the next round as a citer outside "
      'line that a Queued line names', () {
    expect(
      _hasSentenceWith(_sectionOf(_pluginText(_trimRound), '## Handed lines'), [
        'Each `Outside the drafts:` item of the trim audit',
        'goes to the next round as a `Citers outside:` line',
        '`approve.md` names its lead name on a `Queued:` line',
      ]),
      isTrue,
    );
  });

  test('a bootstrap round with a trim batch approves with one audit flag per '
      'audit report, not no-audit', () {
    final approve = _approveSentences();
    final trimRound = approve.indexWhere(
      (sentence) => [
        'bootstrap round',
        'trim batch',
        'fix loop',
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
        '`approve.md`',
        '`--audit` per audit report of the round',
        'in place of `--no-audit`',
      ]),
      isTrue,
    );
    expect(_pluginText(_trimRound), isNot(contains('Get the drafts approved')));
    for (final skill in _bootstrapSkills) {
      expect(
        _hasSentenceWith(_pluginText(skill), [
          _approvePath,
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
      ['`Citers outside:`', 'starts another round'],
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
        ['`Citers outside:`', 'waits on `specstone-bootstrap-spec`'],
      ],
      'specstone-bootstrap-spec/SKILL.md': [
        [
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

  test('a line left for the other bootstrap skill is listed before the stop, '
      'and the round hands no Spec moves line', () {
    final trimRound = _pluginText(_trimRound);
    expect(trimRound, isNot(contains('Spec moves:')));
    for (final (section, words) in [
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

/// The text of the approval reference file, headings left out.
String _approveText() => _oneLine(
  _pluginText(_approveRef)
      .split('\n')
      .where((line) => !line.startsWith('#'))
      .join('\n'),
);

/// The sentences of the approval reference file.
List<String> _approveSentences() => _sentencesOf(_approveText());

/// The index of the first of [sentences] holding every one of [words], or -1.
int _indexWith(List<String> sentences, List<String> words) =>
    sentences.indexWhere((sentence) => words.every(sentence.contains));

/// The index of the approval steps' second `--auto` call sentence.
int _secondCallIndex(List<String> sentences) => _indexWith(sentences, [
  'second',
  '--auto',
  'no citer',
  '`--audit` path',
  'new report',
]);

/// The heading of the bootstrap skills' after-the-reports step.
const _bootstrapAfterReports = '## 3. After the reports';

/// The runner's steps for a bootstrap round with a trim batch.
const _trimRound = 'specstone-expert-sdd/references/trim-round.md';

// MARK: - trim reference

const _trimReference = 'specstone-expert-sdd/references/trim.md';

const _trimStepsHeading = "## A skill's or agent's steps";

const _mergeUntyped = 'specstone-bootstrap-spec/references/merge-untyped.md';

const _bootstrapSpecProcedure =
    'specstone-bootstrap-spec/references/procedure.md';

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

const _decidedAuditReference =
    'specstone-brainstorming-sdd/references/decided-audit.md';

const _decidedAuditHeading = '## Decided audit';

/// The one fix loop main runs after a builder check or a trim audit.
const _fixLoopReference = 'specstone-expert-sdd/references/fix-loop.md';

/// The fence a fix line's body sits in, as the clean draft judge reads it.
const _fixFence =
    'in a bare fence of three or more backticks, longer than any backtick run '
    'at a line start in the body';

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
      'a range link',
      'a matrix row',
      '`overrides`',
      '`Citers outside:`',
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
      ['Delete an item', 'only steps'],
      [
        'Components row',
        'Responsibility',
        "component's role",
        'never delete the row',
      ],
      ['Behavior diagram', 'contract nodes', 'contract part'],
      ['in-edges', 'out-edges', 'labels', 'decision node'],
      [
        'Technical diagram sequence view',
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
    expect(section, isNot(contains('IDs section')));
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
        'Components and Technical diagram',
        "type's description line",
        "section's own lines",
      ],
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

  test('trim.md deletes an excluded item whatever its ID, leaves a gap to the '
      'keep plan, and removes every copy of the mark', () {
    final text = _pluginText(_trimReference);
    expect(text, isNot(contains('`kept: top ID`')));
    expect(text, isNot(contains('highest ID')));
    for (final words in [
      ['Renumber no item', 'gap', 'keep plan'],
      ['`retired_ids`', 'CLI'],
      ['every copy', '`retrim`'],
      ['no id left', 'drop the field'],
      ['`field_value_mismatch`', '`retrim`'],
    ]) {
      expect(_hasSentenceWith(text, words), isTrue, reason: words.join(', '));
    }
    expect(
      _hasSentenceWith(_sectionOf(text, '## The cites'), [
        '`Citers outside:`',
        'number',
        'keep plan',
      ]),
      isTrue,
    );
  });

  test('trim.md writes a moved statement into its guide-named home in the '
      'same batch', () {
    final section = _sectionOf(
      _pluginText(_trimReference),
      '## A moved statement',
    );
    for (final words in [
      ['each moved statement', 'home', 'guide line names', 'same batch'],
      ['before it leaves the FR'],
      ['no designed response', 'Out-of-scope', 'not planned'],
      ['Mechanism text', 'home its guide line names'],
    ]) {
      expect(
        _hasSentenceWith(section, words),
        isTrue,
        reason: words.join(', '),
      );
    }
  });

  test(
    'trim.md names no spec home of its own and hands no Spec moves line',
    () {
      final text = _pluginText(_trimReference);
      expect(text, isNot(contains('Spec moves:')));
      expect(text, isNot(contains('known_limits')));
      expect(text, isNot(contains('## A wire fact')));
    },
  );

  test('trim.md maps an FR Input / Output and the API error sections to '
      'their own guide lines', () {
    final rows = _tableRowsOf(_pluginText(_trimReference), _trimMapHeading);
    for (final words in [
      [
        '`fr` Input / Output, also',
        '`input_output` section lines',
        'product words',
        'wire attributes',
      ],
      ['Errors and Error model', "section's own lines"],
    ]) {
      expect(
        rows.where((row) => words.every(row.contains)),
        hasLength(1),
        reason: words.join(', '),
      );
    }
  });

  test('the bootstrap-prd procedure names no wire fact or API operation as a '
      'spec write of a PRD batch', () {
    final text = _pluginText(_prdProcedure);
    expect(text, isNot(contains('wire fact')));
    expect(text, isNot(contains('API operation')));
    expect(
      _hasSentenceWith(text, ['`specstone-bootstrap-spec`', 'go to']),
      isTrue,
    );
  });

  test('no bootstrap file hands or waits on a Spec moves line', () {
    for (final file in [
      ..._bootstrapSkills,
      ..._bootstrapEntries,
      ..._bootstrapProcedures,
    ]) {
      expect(_pluginText(file), isNot(contains('Spec moves')), reason: file);
    }
  });

  test('the bootstrap entries send a moved statement to its guide-named home '
      'in the same batch', () {
    for (final entry in _bootstrapEntries) {
      expect(
        _hasSentenceWith(_pluginText(entry), [
          'moved statement',
          'trim.md',
          'same batch',
        ]),
        isTrue,
        reason: entry,
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
    for (final splitStep in ['**Split.**', '`new fr --parent']) {
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

  test(
    'trim.md takes a code block finding and cuts its examples to the cap',
    () {
      final text = _pluginText(_trimReference);
      expect(
        _hasSentenceWith(text, [
          '`code_blocks_over_limit`',
          'examples',
          'to the cap',
        ]),
        isTrue,
      );
      expect(
        _hasSentenceWith(text, [
          '`retrim_due`',
          '`code_blocks_over_limit`',
          'one draft',
        ]),
        isTrue,
      );
    },
  );

  test('size-fix sends a code block finding to the trim, never a split', () {
    final text = _pluginText(_sizeFix);
    expect(
      _hasSentenceWith(text, [
        '`code_blocks_over_limit`',
        "section's examples",
        'same trim',
        'no split',
      ]),
      isTrue,
    );
  });

  test('size-fix folds top features on a feature map size finding', () {
    final text = _pluginText(_sizeFix);
    final fold = _sectionOf(text, '## The fold proposal');
    expect(
      _hasSentenceWith(text, [
        '`chars_over_limit` or `lines_over_limit`',
        'feature map',
        'fold',
      ]),
      isTrue,
    );
    expect(fold, contains('new feature --slug'));
    expect(fold, contains('feature:<x> -> feature:<parent>'));
    expect(
      fold.indexOf('new feature --slug'),
      lessThan(fold.indexOf('feature:<x> -> feature:<parent>')),
    );
    expect(fold, contains('cut no text'));
    expect(_hasSentenceWith(fold, ['`max_depth`', 'Never fold']), isTrue);
    expect(
      _hasSentenceWith(fold, ['no fold fits', 'Owner', 'project']),
      isTrue,
    );
    final topDocLine = _sectionOf(text, '## No split applies');
    expect(topDocLine, contains('a top doc'));
    expect(topDocLine, contains('but the feature map'));
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

  test('trim gap report names a keep plan', () {
    for (final entry in _bootstrapEntries) {
      expect(
        _hasSentenceWith(_sectionOf(_pluginText(entry), '## Report'), [
          'gap',
          'edge case numbers',
          'keep plan file',
          "run's reports folder",
        ]),
        isTrue,
        reason: entry,
      );
      expect(
        _hasSentenceWith(_sectionOf(_pluginText(entry), '## Report'), [
          'one `specstone move --plan-file "<file>"`',
          'no Owner ok',
        ]),
        isTrue,
        reason: entry,
      );
    }
    expect(
      _hasSentenceWith(
        _sectionOf(_pluginText(_trimRound), '## Audit the round'),
        [
          'keep plan file a report names',
          'one `specstone move --plan-file "<file>"`',
          'no Owner ok',
          'before the audit',
        ],
      ),
      isTrue,
    );
  });

  test("the auditor takes trims, the engineer an audit's fix batch", () {
    for (final (file, words) in [
      (_auditor, ['`trims`', 'audit', 'bootstrap reports']),
      (_engineer, ['in a fix round', "the round's open findings", 'verbatim']),
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

  test('a fix round writer writes only its open findings sections and their '
      'readers, with no author pass', () {
    for (final (text, words) in [
      (
        _sectionOf(_pluginText(_engineer), '## Input Contract'),
        [
          'only the sections your open findings name',
          'each reader of a term a fix changes',
          'no author pass',
        ],
      ),
      (
        _pluginText(_fixLoopReference),
        [
          'only the sections its open findings name',
          'each reader of a term a fix changes',
          'no author pass',
        ],
      ),
    ]) {
      expect(_hasSentenceWith(text, words), isTrue, reason: words.join(', '));
    }
  });

  test(
    'the author procedure holds a fix-round branch the engineer points at',
    () {
      final text = _pluginText(_authorReference);
      final head = text.substring(0, text.indexOf('## 1. Read'));
      final branch = _oneLine(head);
      for (final part in [
        'In a fix round',
        "section 1's `--target` rule and its guide save",
        'the save only without a saved guide for the types of the findings and their readers',
        'section 2 for terms a fix changes alone',
        "section 3 for the findings' sections and their readers alone",
        'then sections 4 to 6',
      ]) {
        expect(branch, contains(part));
      }
      expect(
        _hasSentenceWith(_pluginText(_engineer), [
          'a fix round takes the fix-round branch of that file',
        ]),
        isTrue,
      );
    },
  );

  test('a citer gap goes outside Findings, a theirs change enters the fix '
      'loop, and the auditor takes its audits', () {
    expect(
      _hasSentenceWith(_pluginText(_reReviewReference), [
        'citer of <type>:<name>',
        '`Outside the round:` too, never `Findings:`',
      ]),
      isTrue,
    );
    expect(
      _hasSentenceWith(_pluginText(_roundsReference), [
        'given in an answer to the theirs pile',
        'enters `../../specstone-expert-sdd/references/fix-loop.md`',
      ]),
      isTrue,
    );
    expect(
      _hasSentenceWith(_sectionOf(_pluginText(_auditor), '## Input Contract'), [
        '`audits`',
        're-review',
        'earlier audit reports',
      ]),
      isTrue,
    );
  });

  test('the engineer takes handed citer and spec move lines in a bootstrap '
      'batch and applies them by trim.md', () {
    final text = _pluginText(_engineer);
    expect(
      _hasSentenceWith(_sectionOf(text, '## Input Contract'), [
        'each line a trim round handed',
        '`Citers outside:`',
      ]),
      isTrue,
    );
    for (final entry in _bootstrapEntries) {
      expect(
        _hasSentenceWith(_pluginText(entry), [
          'apply each handed',
          '`Citers outside:`',
          'trim.md',
        ]),
        isTrue,
        reason: entry,
      );
    }
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
    for (final entry in _bootstrapEntries) {
      final text = _pluginText(entry);
      expect(
        _hasSentenceWith(text, ['`retrim_due`', 'trim.md']),
        isTrue,
        reason: entry,
      );
      expect(
        _hasSentenceWith(text, [
          'deleted, moved, and cut item',
          'guide line',
          'rewritten cite',
          '`Citers outside:`',
        ]),
        isTrue,
        reason: entry,
      );
      expect(text, isNot(contains('`kept: top ID`')), reason: entry);
    }
  });

  test('the audit reads each trimmed item against the guide line its trims '
      'report names', () {
    final audit = _sectionOf(
      _pluginText(_trimAuditReference),
      _trimAuditHeading,
    );
    for (final words in [
      [
        '`trims`',
        'deleted, moved, and cut item',
        'guide line',
        'rewritten cite',
        '`../../$_trimReference`',
      ],
      ['removed item', 'no other doc states', 'restor'],
    ]) {
      expect(_hasSentenceWith(audit, words), isTrue, reason: words.join(', '));
    }
  });

  test('the audit trim lens restores contract parts and no removed step', () {
    final audit = _sectionOf(
      _pluginText(_trimAuditReference),
      _trimAuditHeading,
    );
    expect(
      _hasSentenceWith(audit, ['a removed step, per trim.md,', 'is none']),
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

  test('the trim audit takes job, targets, and trims, and writes '
      'each report line of its job', () {
    final audit = _sectionOf(
      _pluginText(_trimAuditReference),
      _trimAuditHeading,
    );
    for (final words in [
      ['`job: trim-audit`', '`targets`', '`trims`'],
      ['one `specstone context <draft> <draft> --for design --out`'],
      ['each target read whole'],
      ['`Findings:`', 'wrong citer or trimmed item'],
      ['`Outside the drafts:`', 'fix lies in no draft'],
      ['`Audited:`', 'per target'],
      ['`none`'],
    ]) {
      expect(_hasSentenceWith(audit, words), isTrue, reason: words.join(', '));
    }
  });

  test('a trim round sends the trim-audit job to the auditor', () {
    expect(
      _hasSentenceWith(_pluginText(_trimRound), [
        '`specstone-sdd-auditor`',
        '`job: trim-audit`',
        '`targets:`',
      ]),
      isTrue,
    );
  });

  test("a fix loop's handed line starts the next bootstrap round as a citer "
      'outside line', () {
    expect(
      _hasSentenceWith(_sectionOf(_pluginText(_trimRound), '## Handed lines'), [
        'each item the fix loop hands on',
        '`Outside the round:`',
        'as a `Citers outside:` line',
        'trim batch',
        'own trim audit and loop',
      ]),
      isTrue,
    );
  });

  test('the builder check runs once on the drafts and writes Findings then '
      'Audited', () {
    final check = _sectionOf(
      _pluginText(_auditReference),
      _builderCheckHeading,
    );
    for (final words in [
      ['`job: builder-check`'],
      ['one `specstone approve <drafts> --dry-run --json`', '`base`'],
      ['`doc_not_found`', 'drop each name', 'again on the rest'],
      ['A dropped name', 'no report line', 'no `Audited:` line'],
      ['whole-doc `base`', '`specstone get <doc> --json`'],
      ['Ground again', 'predate the writers'],
      ['the change note', 'the review read-first file'],
      ['`nothing important left`'],
      ['`Audited:`', 'doc of the drafts list alone'],
      ['no `check`', 'no `check --repeats`', 'no lens walk', 'second check'],
    ]) {
      expect(_hasSentenceWith(check, words), isTrue, reason: words.join(', '));
    }
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
      expect(check, contains('- $label: <doc>#<key>: <point>'), reason: label);
    }
    expect(
      _hasSentenceWith(check, ['ranked by importance', 'across the labels']),
      isTrue,
    );
    for (final words in [
      ['wording or shape', '`check` owns', 'no line'],
      ['a rule another doc owns', 'owner doc', 'item link'],
      ['each hit', 'its own line'],
    ]) {
      expect(_hasSentenceWith(check, words), isTrue, reason: words.join(', '));
    }
  });

  test('the builder check flags a member rule added to a shared FR', () {
    final check = _sectionOf(
      _pluginText(_auditReference),
      _builderCheckHeading,
    );
    expect(check, contains('- Misplaced: <doc>#<key>: <point>'));
    for (final words in [
      ['a shared FR', 'only one member', 'holds'],
      ['belongs in <member FR>', 'belongs in a new FR for <member>'],
      ['no draft adds or changes', 'two or more members', 'no `Misplaced`'],
    ]) {
      expect(_hasSentenceWith(check, words), isTrue, reason: words.join(', '));
    }
  });

  test('the builder check labels a moved citer a Contradiction', () {
    final check = _sectionOf(
      _pluginText(_auditReference),
      _builderCheckHeading,
    );
    final start = check.indexOf('- `Contradiction`: ');
    final end = check.indexOf('- `Stale reader`: ', start);
    expect([start, end], everyElement(isNonNegative), reason: '$start $end');
    expect(
      _hasSentenceWith(check.substring(start, end), [
        'a citer',
        'size-fix move',
        'name the citer and the item it should link',
      ]),
      isTrue,
    );
  });

  test('the builder check reads the writer reports and only its read set', () {
    final check = _sectionOf(
      _pluginText(_auditReference),
      _builderCheckHeading,
    );
    for (final words in [
      ['`Decision:`', '`Readers:`', 'open question lines', 'writer report'],
      [
        'the review read-first file',
        'by its read plan',
        'changed, removed, citer, summary, and pattern parts',
      ],
      ['A doc the Owner names', 'read whole'],
    ]) {
      expect(_hasSentenceWith(check, words), isTrue, reason: words.join(', '));
    }
    expect(check, isNot(contains('never the read-first file whole')));
  });

  test('the builder check grounds with one context --for review and one grep '
      'of its refs file', () {
    final check = _sectionOf(
      _pluginText(_auditReference),
      _builderCheckHeading,
    );
    for (final words in [
      [
        'one `specstone context <draft> <draft> --for review --out`',
        'every draft step 1 keeps',
      ],
      ['one `grep -n -E`', 'refs file'],
      ['no other doc read', '`search`', '`refs`', '`context` call'],
      [
        'A feature or doc the Owner names',
        '`specstone context <it> --for design --out`',
      ],
    ]) {
      expect(_hasSentenceWith(check, words), isTrue, reason: words.join(', '));
    }
    final designSentences = _sentencesOf(check)
        .where((sentence) => sentence.contains('--for design'));
    expect(designSentences, everyElement(contains('the Owner names')));
    final boundaries = _sectionOf(_pluginText(_auditor), '## Scope Boundaries');
    expect(
      _hasSentenceWith(boundaries, [
        'builder check of drafts',
        'one `context <drafts> --for review --out`',
        'one `grep -n -E` of its refs file',
        'no other `search`, `refs`, or `context` call',
      ]),
      isTrue,
    );
  });

  test("the builder check joins each point's sibling search into the one refs "
      'grep', () {
    final check = _sectionOf(
      _pluginText(_auditReference),
      _builderCheckHeading,
    );
    final start = check.indexOf('6. **Siblings**');
    final end = check.indexOf('A point of wording or shape', start);
    expect([start, end], everyElement(isNonNegative), reason: '$start $end');
    final siblings = check.substring(start, end);
    for (final words in [
      [
        'after judging',
        'one `grep -n -E` over the refs file',
        "every point's wording",
        'the rule or term it breaks',
      ],
      ['each hit', 'its own line'],
      ['in summary', 'out of reach'],
    ]) {
      expect(
        _hasSentenceWith(siblings, words),
        isTrue,
        reason: words.join(', '),
      );
    }
    expect(check, isNot(contains('for each point, search')));
  });

  test("the feature pattern search runs in the builder check's one refs "
      'grep', () {
    final check = _sectionOf(
      _pluginText(_auditReference),
      _builderCheckHeading,
    );
    final start = check.indexOf('5. **Feature pattern**');
    final end = check.indexOf('6. **Siblings**', start);
    expect([start, end], everyElement(isNonNegative), reason: '$start $end');
    expect(
      _hasSentenceWith(check.substring(start, end), [
        "step 6's one `grep -n -E`",
        'the doc that lists the pattern',
        'the spec folder of its feature',
      ]),
      isTrue,
    );
    expect(
      _hasSentenceWith(check.substring(end), ['grep', "step 5's search"]),
      isTrue,
    );
    final savedFileSearches = _sentencesOf(
      check,
    ).where((sentence) => sentence.toLowerCase().contains('search the saved'));
    expect(savedFileSearches, everyElement(contains('the Owner names')));
  });

  test("a check of drafts learns each pattern item from the read-first file's "
      'pattern parts and types its doc as the part names it', () {
    final check = _sectionOf(
      _pluginText(_auditReference),
      _builderCheckHeading,
    );
    final start = check.indexOf('5. **Feature pattern**');
    final end = check.indexOf('6. **Siblings**', start);
    expect([start, end], everyElement(isNonNegative), reason: '$start $end');
    final pattern = check.substring(start, end);
    for (final words in [
      [
        'In a check of drafts',
        "the read-first file's `pattern` parts",
        '`<type>:<name>`',
        "step 6's one `grep -n -E`",
      ],
      ['no `pattern` part', 'ancestor feature', 'no line'],
      ['typed as the `pattern` part names it'],
    ]) {
      expect(
        _hasSentenceWith(pattern, words),
        isTrue,
        reason: words.join(', '),
      );
    }
  });

  test("a check of drafts keeps step 1's hash calls beside its review call "
      'and its grep', () {
    expect(
      _hasSentenceWith(
        _sectionOf(_pluginText(_auditReference), _builderCheckHeading),
        ['In a check of drafts', "besides step 1's calls", 'no other doc read'],
      ),
      isTrue,
    );
  });

  test('read-sdd prints the refs header alone in implement and review', () {
    expect(
      _hasSentenceWith(
        _sectionOf(_pluginText(_readSdd), '## Ground in one call'),
        [
          'In `implement` and `review`',
          'the refs file prints its header alone',
        ],
      ),
      isTrue,
    );
  });

  test('the Owner-named check still searches the saved files', () {
    final check = _sectionOf(
      _pluginText(_auditReference),
      _builderCheckHeading,
    );
    final patternStart = check.indexOf('5. **Feature pattern**');
    final siblingsStart = check.indexOf('6. **Siblings**', patternStart);
    final end = check.indexOf('A point of wording or shape', siblingsStart);
    expect(
      [patternStart, siblingsStart, end],
      everyElement(isNonNegative),
      reason: '$patternStart $siblingsStart $end',
    );
    expect(
      _hasSentenceWith(check.substring(patternStart, siblingsStart), [
        'the Owner names',
        'search the saved files',
      ]),
      isTrue,
    );
    expect(
      _hasSentenceWith(check.substring(siblingsStart, end), [
        'the Owner names',
        'search the saved files',
        "each point's wording",
      ]),
      isTrue,
    );
    expect(
      _hasSentenceWith(check, ['In a check of drafts', 'no other doc read']),
      isTrue,
    );
  });

  test(
    'the builder check names a wrong citer and a decision no draft carries',
    () {
      final check = _sectionOf(
        _pluginText(_auditReference),
        _builderCheckHeading,
      );
      for (final words in [
        [
          'citer',
          'size-fix move',
          'name the citer and the item it should link',
        ],
        [
          'a decision of the change note no draft carries',
          'one line in each doc',
        ],
      ]) {
        expect(
          _hasSentenceWith(check, words),
          isTrue,
          reason: words.join(', '),
        );
      }
    },
  );

  test('read-sdd has the builder check read review files by plan and grep', () {
    final ground = _sectionOf(
      _pluginText('specstone-read-sdd/SKILL.md'),
      '## Ground in one call',
    );
    expect(
      _hasSentenceWith(ground, [
        '`review`',
        'read the read-first file whole',
        'every range the plan line names',
      ]),
      isTrue,
    );
    final greps = _sentencesOf(ground)
        .where((sentence) => sentence.contains('greps its refs file once'));
    expect(greps, isNotEmpty);
    expect(greps, everyElement(contains('a `review` check')));
    expect(greps, everyElement(isNot(contains('builder-check'))));
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
    for (final words in [
      ['skip line', '`out_of_scope`', 'covered'],
      ['a non-target feature', 'no line'],
    ]) {
      expect(_hasSentenceWith(check, words), isTrue, reason: words.join(', '));
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

  test('merge-untyped.md sends an event schema to the section whose guide takes it', () {
    final text = _pluginText(_mergeUntyped);
    expect(
      _hasSentenceWith(text, [
        'an event or message schema',
        'the section whose guide takes it',
        'deleted as code holds it',
      ]),
      isTrue,
    );
    expect(text, isNot(contains('Component details')));
    expect(text, isNot(contains('its topic')));
    expect(text, isNot(contains('topic doc')));
    expect(text.toLowerCase(), isNot(contains('interaction')));
  });

  test('the bootstrap-spec procedure holds no section home of a pack', () {
    final rows = _pluginText(_bootstrapSpecProcedure)
        .split('\n')
        .where((line) => line.startsWith('| `section_undeclared`'));
    expect(rows, hasLength(1));
    expect(rows.single.toLowerCase(), isNot(contains('interaction')));
  });

  test("the bootstrap-spec procedure sends a helper to its feature's record "
      'covers by helpers.md and names no removed finding', () {
    final text = _pluginText(_bootstrapSpecProcedure);
    expect(
      _hasSentenceWith(text, [
        '`../../specstone-sync-sdd/references/helpers.md`',
        'a helper joins',
        "feature's record `covers`",
      ]),
      isTrue,
    );
    expect(text, isNot(contains('architecture_missing')));
    expect(text, isNot(contains('Component details')));
    expect(text, isNot(contains('architecture or topic doc')));
    expect(
      _hasSentenceWith(text, [
        'write-a-spec pick',
        "add the file or its folder to `covers` of its feature's record",
      ]),
      isTrue,
    );
    expect(text, isNot(contains('new topic')));
  });

  test('trim.md names the technical diagram in its components row and no interaction section', () {
    final text = _pluginText(_trimReference);
    final rows = _tableRowsOf(text, _trimMapHeading);
    expect(
      rows.where((row) => row.contains('Components and Technical diagram')),
      hasLength(1),
    );
    expect(text.toLowerCase(), isNot(contains('interaction')));
  });

  test('trim.md keeps contract nodes in every flowchart view and keeps the section when a view empties', () {
    final section = _sectionOf(_pluginText(_trimReference), _trimStepsHeading);
    for (final words in [
      [
        'any `flowchart` view of a Technical diagram',
        'a deployment or a data flow view',
        'contract nodes',
      ],
      [
        'emptied Technical diagram view',
        'leaves the section',
        'keeps its component diagram',
      ],
    ]) {
      expect(
        _hasSentenceWith(section, words),
        isTrue,
        reason: words.join(', '),
      );
    }
  });

  test('trim.md names no dropped Component details, zoom-in, or domain '
      'invariants row', () {
    final text = _pluginText(_trimReference);
    for (final dropped in ['Component details', 'zoom-in', '`domain`']) {
      expect(text, isNot(contains(dropped)), reason: dropped);
    }
  });
}

// MARK: - brainstorm rounds

const _brainstormSkill = 'specstone-brainstorming-sdd/SKILL.md';

const _roundsReference = 'specstone-brainstorming-sdd/references/rounds.md';

const _designReference = 'specstone-brainstorming-sdd/references/design.md';

const _sourceReference = 'specstone-brainstorming-sdd/references/source.md';

/// The class test the runner gives a change once its change note is written.
const _classReference = 'specstone-brainstorming-sdd/references/class.md';

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
      expect(
        _hasSentenceWith(step, [
          'no Docs to change table',
          'no input table',
          'no amend number',
          'no snapshot',
        ]),
        isTrue,
      );
    },
  );

  test('design.md judges the note path by the saved headers and writes none '
      'inside the checked folders', () {
    final step = _sectionOf(_pluginText(_designReference), _changeNoteHeading);
    for (final words in [
      ['`==> ` headers', 'first folder', 'right under the docs folder'],
      ['a deeper folder of that name', 'outside'],
      ['write nothing', 'open question', "Owner's new path"],
      ['write nothing', 'PRD or spec doc'],
    ]) {
      expect(_hasSentenceWith(step, words), isTrue, reason: words.join(', '));
    }
  });

  test('design.md edits an existing note at each superseded place with the '
      "host's file write", () {
    final step = _sectionOf(_pluginText(_designReference), _changeNoteHeading);
    expect(
      _hasSentenceWith(step, [
        'already at the path',
        "host's file write",
        'every place stating text an Owner decision supersedes',
      ]),
      isTrue,
    );
  });

  test("design.md lists the writer's start docs in Reach with their code "
      'target', () {
    final step = _sectionOf(_pluginText(_designReference), _changeNoteHeading);
    for (final words in [
      ['**Reach**', 'docs the writer starts from'],
      ['per-target spec doc', 'code target', 'open question'],
      ["writer's one `context` call", 'names these docs'],
    ]) {
      expect(_hasSentenceWith(step, words), isTrue, reason: words.join(', '));
    }
  });

  test('design.md grounds each claim in a saved file, an answer, or a run and '
      'asks the rest', () {
    final step = _sectionOf(
      _pluginText(_designReference),
      '## 2. Ground each claim',
    );
    for (final words in [
      ['Open each code path and symbol', 'cannot find', 'open question'],
      [
        'A claim nothing grounds',
        'open question',
        'no `get`, `search`, or `refs`',
      ],
      [
        'library, parser, or tool',
        'only by a run of your own',
        'read-only command',
        'scratch folder outside the docs',
        '`Run:` line',
      ],
      ['saved files ground a claim about the Specstone CLI'],
    ]) {
      expect(_hasSentenceWith(step, words), isTrue, reason: words.join(', '));
    }
  });

  test('design.md decides a doc point, leaves a code point to the builder, and '
      'writes no draft while a question is open', () {
    final step = _sectionOf(_pluginText(_designReference), _changeNoteHeading);
    for (final words in [
      [
        '**Left to the builder**',
        'class name',
        'no decision',
        'no open question',
      ],
      ['Decide', 'a PRD or spec doc must state', 'answers leave open'],
      ['No draft is written while', 'one is open'],
      ['Write only the change note', 'no PRD or spec doc'],
    ]) {
      expect(_hasSentenceWith(step, words), isTrue, reason: words.join(', '));
    }
  });

  test('design.md marks a run-order decision with the plan mark', () {
    final step = _sectionOf(_pluginText(_designReference), _changeNoteHeading);
    for (final words in [
      ['only the plan holds', 'run order', '`D<n> (plan): <text>`'],
      ['PRD or spec doc must hold every other decision'],
    ]) {
      expect(_hasSentenceWith(step, words), isTrue, reason: words.join(', '));
    }
  });

  test('design.md names no retired stage', () {
    final text = _oneLine(_pluginText(_designReference));
    for (final word in ['sweep', 'design check', 'removal.md', 'rounds.md']) {
      expect(text, isNot(contains(word)), reason: word);
    }
  });

  test('source.md maps each source item in the change note', () {
    final text = _pluginText(_sourceReference);
    final step = _sectionOf(text, '## Map the source');
    for (final words in [
      ['write and edit of the change note'],
      ['Re-read file whole', 'never record it as the source'],
      [
        'one row per source item',
        '0 left out',
        'doc and section it lands in',
        '"not taken" and why',
      ],
      ['ticket list, task list, or plan', '"not taken"', 'task management'],
      ['no shape or Owner answer places', 'open question', 'before any draft'],
      ['A change with no source', 'no Source map'],
      ['opening with the Source line', 'one row per source item'],
      ['Write only the copy and the change note'],
    ]) {
      expect(_hasSentenceWith(step, words), isTrue, reason: words.join(', '));
    }
    for (final word in ['design document', 'Docs to change', 'snapshot']) {
      expect(_oneLine(text), isNot(contains(word)), reason: word);
    }
  });

  test('source.md names the copy folder once and keeps a re-read copy in '
      'use', () {
    final step = _sectionOf(
      _pluginText(_sourceReference),
      '## Take in the source',
    );
    for (final words in [
      ['`<folder>` the path `specstone folder` prints', 'once per run'],
      ['re-read keeps the copy in use'],
      ['Keep two lines for the change note write'],
      ['The change note names no source'],
    ]) {
      expect(_hasSentenceWith(step, words), isTrue, reason: words.join(', '));
    }
  });

  test('each brainstorm dispatch follows dispatch.md by its report path', () {
    final text = _pluginText(_brainstormSkill);
    for (final words in [
      [
        '../specstone-expert-sdd/references/dispatch.md',
        'sdd-engineer.author',
        'sdd-auditor.audit',
      ],
      ['six `a-z0-9` characters', 'picked again while that file exists'],
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
  String section(String heading) =>
      _sectionOf(_pluginText(_roundsReference), heading);

  void expectSentences(String heading, List<List<String>> sentences) {
    final text = section(heading);
    for (final words in sentences) {
      expect(_hasSentenceWith(text, words), isTrue, reason: words.join(', '));
    }
  }

  test('the three sections come in the order of the flow', () {
    final headings = _pluginText(_roundsReference)
        .split('\n')
        .where((line) => line.startsWith('## '));
    expect(headings, [_roundsMoves, _roundsSort, _roundsChange]);
  });

  test('deletes and moves run before the builder check, a refused delete '
      'first sends its citers to the writers', () {
    final text = section(_roundsMoves);
    final order = [
      for (final word in [
        '`--dry-run`',
        '`doc_referenced`',
        'apply each `Move:` plan file',
        "the Owner's ok",
        'builder check runs only after',
      ])
        text.indexOf(word),
    ];
    expect(order, everyElement(isNonNegative), reason: '$order');
    expect(order, orderedEquals([...order]..sort()), reason: 'order');
    expectSentences(_roundsMoves, [
      [
        'each `Delete:` line',
        '`Move:` plan file',
        '`Rename:` line',
        '`--dry-run`',
      ],
      ['`doc_referenced`', 'its citers', 'the writers'],
      [
        'citer outside every group',
        'the one writer',
        'cross-group writer',
        'else',
      ],
      ["After the citers' round", 'dry run again'],
      ['its plan is the one shown and run'],
      ['each new name', 'replaces the old one in the drafts list'],
      ['`--yes --plan <hash>`', "Owner's ok"],
    ]);
  });

  test("rounds sends a refused delete's citers by the loop's resume outside its count", () {
    expectSentences(_roundsMoves, [
      [
        'Send them',
        'rounds 1 to 3 resume',
        '`../../specstone-expert-sdd/references/fix-loop.md`',
        'outside its round count',
        'no re-review',
        'the builder check follows',
      ],
    ]);
  });

  test('the builder check findings and the writers questions sort into '
      'answered, minor, and theirs', () {
    expectSentences(_roundsSort, [
      [
        '`Guess`',
        '`Contradiction`',
        '`Stale reader`',
        '`Not carried`',
        '`Misplaced`',
      ],
      ['**answered**', 'change note or the docs answer'],
      ['**minor**', '`Calls made`'],
      ['**theirs**', "only the Owner's answer", 'what gets built'],
    ]);
  });

  test('a fix in a doc outside the drafts list adds that doc to the list', () {
    expectSentences(_roundsSort, [
      ['doc outside the drafts list', 'adds that doc', 'approved with the'],
    ]);
  });

  test("the theirs pile and the writers' open questions go in one message, "
      'most important first', () {
    expectSentences(_roundsSort, [
      [
        'theirs pile',
        "writers' `Open questions:`",
        'one message',
        'most important first',
      ],
    ]);
  });

  test('a check that reads nothing important left asks only the writers '
      'questions', () {
    expectSentences(_roundsSort, [
      ['`nothing important left`', 'only', "writers' open questions"],
    ]);
  });

  test('a split proposal is asked in the round, then moved and filled by a '
      'fresh writer with no resume', () {
    expectSentences(_roundsSort, [
      ['split proposal', 'same message'],
      ['split proposal', "Owner's ok", 'plan file', 'fresh writer'],
      ['same inputs', 'no resume', 'no check'],
      ['fresh writer', 'bar `bundles`'],
      ['new FR', 'drafts list', "writer's report"],
      [
        'split proposal',
        'fresh writer',
        "`report:` the proposing writer's file",
        'no resume',
      ],
    ]);
  });

  test('the brainstorm sends answered and minor items to the fix loop', () {
    expectSentences(_roundsSort, [
      ['**answered**', 'change note or the docs answer', 'enters the fix loop'],
      ['**minor**', '`Calls made`', 'enters the fix loop'],
      ["Write the Owner's answers into the change note"],
      [
        'answered and minor items',
        "the Owner's answers",
        'enter `../../specstone-expert-sdd/references/fix-loop.md`',
        'approval step',
        'once it ends',
      ],
    ]);
    expect(
      _hasSentenceWith(
        _sectionOf(_pluginText(_brainstormSkill), _brainstormDrafts),
        [
          '`references/rounds.md` section 2',
          '`../specstone-expert-sdd/references/fix-loop.md`',
        ],
      ),
      isTrue,
    );
  });

  test('an Owner change that adds behavior takes the reader step first, a '
      'wording change none', () {
    expectSentences(_roundsChange, [
      [
        'new state, input, output, edge case, error, or reader',
        'adds behavior',
        'reader step',
        'before the edit',
      ],
      ['only words or corrects text', 'no reader step'],
    ]);
  });

  test('an Owner change edits the drafts and the change note with no new '
      'check and no amend number', () {
    expectSentences(_roundsChange, [
      ['`specstone set`', 'change note'],
      ['no new check', 'no amend number'],
    ]);
  });

  test("an Owner change in an answer enters the fix loop and only one at the approval ask is main's edit", () {
    expectSentences(_roundsChange, [
      [
        'given in an answer',
        '`../../specstone-expert-sdd/references/fix-loop.md`',
        'section 2',
        'its writer writes it',
      ],
      ['at the approval ask', 'edit each draft', '`specstone set`'],
    ]);
    expect(
      _hasSentenceWith(section(_roundsChange), [
        'in an answer',
        '`specstone set`',
      ]),
      isFalse,
    );
  });

  test('an Owner change at the approval ask takes no re-review', () {
    expectSentences(_roundsChange, [
      [
        '`auto`',
        'Owner change at the approval ask',
        'no re-check',
        'no re-review',
      ],
      ['second `--auto` call', 'third call', 'cap of 2'],
      ['Owner confirmation', 'shows the Owner the change'],
    ]);
  });

  test('rounds names no fix read and no third section', () {
    final text = _oneLine(_pluginText(_roundsReference)).toLowerCase();
    for (final gone in ['fix read', 'fix-read', 'section 3']) {
      expect(text, isNot(contains(gone)), reason: gone);
    }
  });

  test('rounds.md names no retired step', () {
    final text = _oneLine(_pluginText(_roundsReference));
    for (final word in [
      'sweep',
      'design check',
      'delta check',
      'reaudit',
      'removal.md',
      'fix file',
      '`design:`',
      'resume rung',
      'dispatch.md',
      'snapshot',
      'at most 3 rounds',
    ]) {
      expect(text, isNot(contains(word)), reason: word);
    }
  });
}

void _brainstormFlowTests() {
  String step(String heading) =>
      _sectionOf(_pluginText(_brainstormSkill), heading);

  void expectSentences(String heading, List<List<String>> sentences) {
    final text = step(heading);
    for (final words in sentences) {
      expect(_hasSentenceWith(text, words), isTrue, reason: words.join(', '));
    }
  }

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

  test('no PRD or spec doc is written and no writer dispatched before the '
      'approach pick', () {
    expectSentences(_brainstormApproach, [
      ['no PRD or spec doc', 'no writer', 'Owner picks an approach'],
    ]);
  });

  test('a qualifying skill runs the dialogue and its plan hand-off invokes '
      'nothing, else the own flow offers approaches', () {
    expectSentences(_brainstormApproach, [
      ['A skill qualifies', 'run it'],
      ['it keeps the conversation'],
      ['invoke nothing', 'hand-off', 'plan or build skill'],
      ["Specstone's rules win"],
      ['None qualifies', 'one question per message'],
      ['two or three approaches', 'trade-offs', 'recommending one'],
    ]);
  });

  test('a new feature or story takes the placement answers and the '
      "Owner's yes", () {
    expectSentences(_brainstormGround, [
      ['specstone guide feature', 'placement questions'],
      ['go on only after their yes'],
    ]);
  });

  test('step 1 names each story a change reaches, never the feature', () {
    expectSentences(_brainstormGround, [
      ['Several stories', 'each in one call', 'never the feature'],
      ['feature doc', 'the feature'],
    ]);
    expect(
      step(_brainstormGround),
      isNot(contains('Across stories: the feature')),
    );
  });

  test('the runner writes the change note itself with a patterns proposal and '
      'asks each open question before any writer', () {
    expectSentences(_brainstormNote, [
      ['`references/design.md`', 'saved files', "Owner's answers"],
      ['Dispatch nothing to write it'],
      ['`patterns:`', '`specstone guide --pattern`'],
      ['Ask the Owner', 'open question', 'a doc must state'],
      ['Dispatch no writer', 'one is open'],
    ]);
  });

  test('step 3 routes the change by class.md and sends only an Undecided '
      'change to the writers', () {
    expectSentences(_brainstormNote, [
      ['`references/class.md`', 'Undecided'],
    ]);
    final text = _oneLine(_pluginText(_brainstormSkill));
    expect(
      text.indexOf('`references/class.md`'),
      allOf(
        isNonNegative,
        lessThan(text.indexOf('Dispatch `specstone-sdd-engineer`')),
      ),
    );
  });

  test('each reply shows its report line and relay block word for word, also '
      'under auto', () {
    expectSentences(_brainstormDrafts, [
      [
        '`Report:`',
        'relay block',
        'word for word',
        'also under `auto`',
        'no wait',
      ],
    ]);
  });

  test('a dispatch writes no brief and reruns no context call', () {
    expectSentences(_brainstormDrafts, [
      ['Write no brief', 'rerun no `context`', 'grounded target'],
    ]);
  });

  test('one writer takes a change within one work group, else one fresh '
      'writer per group then one cross-group writer, each with its share', () {
    expectSentences(_brainstormDrafts, [
      ['`specstone-sdd-engineer`', '`mode: author`', '`change note:`'],
      ['One group', 'one writer', 'no `docs`'],
      [
        'Two or more',
        'one fresh writer per group',
        'one at a time',
        "`docs:` its group's `targets:` line",
      ],
      ['Only the first writer', '`bundles:`', 'no doc write ran since'],
      [
        'one cross-group writer',
        "`group reports:` each group writer's report",
        '`Elsewhere:`',
      ],
    ]);
    expect(step(_brainstormDrafts), isNot(contains('per story')));
  });

  test('the brainstorm takes its writer count from one groups call on every '
      'Reach doc before the first writer', () {
    expectSentences(_brainstormDrafts, [
      [
        '`specstone context <every Reach doc> --for design --out --groups`',
        'once',
        'first writer dispatch',
      ],
      ['doc the change creates', 'no Reach doc', 'its parent'],
      ['rerun no `context`', 'grounded target', '`--groups` call'],
    ]);
    final text = step(_brainstormDrafts);
    expect(text, isNot(contains('`specstone structure`')));
    expect(
      text.indexOf('--for design --out --groups`'),
      allOf(
        isNonNegative,
        lessThan(text.indexOf('Dispatch `specstone-sdd-engineer`')),
      ),
      reason: 'the groups call comes before the dispatch sentence',
    );
  });

  test('no brainstorm file states a size bound for the writer split', () {
    for (final file in _skillAndAgentFiles().where(
      (file) => file.startsWith('specstone-brainstorming-sdd/'),
    )) {
      final text = _oneLine(_pluginText(file));
      for (final bound in ['50,000', '`N tokens`', 'Above ']) {
        expect(text, isNot(contains(bound)), reason: '$file: $bound');
      }
    }
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
    expectSentences(_brainstormDrafts, [
      ['`job: builder-check`', "change note's path", 'drafts list', 'report'],
      ['No builder check repeats'],
    ]);
  });

  test('the drafts go to approval with an audit report and writer report per run and the change note decisions shown', () {
    expectSentences(_brainstormApproval, [
      [
        _approvePath,
        '`--audit` per audit report',
        '`--author` per writer report',
      ],
      [
        "change note's Decisions",
        'each draft asked',
        'approved list',
        'also when no draft is asked',
      ],
      ['Source map', 'source'],
      ['`check` finding', 'waits for the Owner', 'outside the drafts'],
      ['Owner change', '`references/rounds.md` section 4'],
    ]);
  });

  test("the plan skill gets the whole approved list and the change note's "
      'path and asks how to run the plan', () {
    expectSentences(_brainstormPlan, [
      [
        '`specstone-plan-sdd`',
        'whole approved drafts list',
        "change note's path",
      ],
      ['shows the Owner the plan', 'how to run it'],
    ]);
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
      expect(_oneLine(text), isNot(contains('design document')), reason: file);
    }
  });

  test('a host with no subagent runs the writer and the builder check itself '
      "and says the check is no fresh reader's", () {
    expectSentences(_brainstormNoDispatch, [
      ['no subagent', '`references/no-dispatch.md`'],
    ]);
    final text = _pluginText(_noDispatchReference);
    for (final words in [
      ['no subagent', '`author.md`', '`audit.md`'],
      [
        'no subagent',
        '`../../specstone-expert-sdd/references/fix-loop.md`',
        'one fix pass',
      ],
      ["no fresh reader's", 'Owner'],
    ]) {
      expect(_hasSentenceWith(text, words), isTrue, reason: words.join(', '));
    }
  });

  test('design.md gives the change note one Constraints line per project '
      'vision', () {
    final step = _sectionOf(_pluginText(_designReference), _changeNoteHeading);
    expect(
      _hasSentenceWith(step, [
        '**Constraints**',
        'one line per project vision',
        'every vision',
        'not only the ones the change advances',
        'must not break',
        '`none bears on this change`',
      ]),
      isTrue,
    );
  });

  test('design.md marks a decided decision only when it passes both '
      'decided-line tests', () {
    final step = _sectionOf(_pluginText(_designReference), _changeNoteHeading);
    for (final words in [
      [
        '`D<n> (decided): <text>`',
        'only when it passes both decided-line tests',
      ],
      [
        'one observable behavior',
        '`when <input or state>, <outcome>`',
        'writes its FR with no question',
        '"make it faster"',
      ],
      ["a fact a caller's work breaks on", 'exact values'],
    ]) {
      expect(_hasSentenceWith(step, words), isTrue, reason: words.join(', '));
    }
  });

  test('design.md marks settled decisions decided or names failed test', () {
    final designReference = _pluginText(_designReference);
    final step = _sectionOf(designReference, _changeNoteHeading);
    final tell = _sectionOf(designReference, '## 4. Tell the Owner');
    expect(
      _hasSentenceWith(step, [
        'settle',
        '`(decided)`',
        'both decided-line tests',
        '`(plan)`',
        'whoever settled it',
        'your own call',
        'a source map',
      ]),
      isTrue,
    );
    expect(
      _hasSentenceWith(tell, ['fails', 'the test it fails', 'in the chat']),
      isTrue,
    );
    expect(
      _hasSentenceWith(tell, [
        'Each time an answer changes a decision line',
        'an edit given with the lane answer included',
        'try on the changed lines',
        "section 3's `(decided)` try",
        'this section again',
      ]),
      isTrue,
    );
  });

  test('design.md asks the lane once and writes Owner ok only on Decided', () {
    final tell = _sectionOf(
      _pluginText(_designReference),
      '## 4. Tell the Owner',
    );
    for (final words in [
      [
        '`class.md` steps 1 and 2',
        'Doc-only, Restore, or Internal',
        'no lane question',
      ],
      [
        'goes on to `class.md` step 3',
        'every decision',
        '`(decided)`',
        '`(plan)`',
        'at least one reads `(decided)`',
        'no open question',
        'show the Owner its Decisions in the chat',
        'ask the Owner once',
        'which lane',
        'Decided',
        'while Undecided',
        'builder check',
        'drafts and audits the docs after the build',
        "the Owner's approval before any work",
      ],
      ['`Owner ok: <YYYY-MM-DD>`', 'Decided'],
      ['no `Owner ok:` line', 'Undecided'],
    ]) {
      expect(_hasSentenceWith(tell, words), isTrue, reason: words.join(', '));
    }
  });

  test('the class test asks Doc-only first and sends a Decided change to '
      'plan-sdd', () {
    expect(
      _hasSentenceWith(
        _sectionOf(_pluginText(_designReference), '## 4. Tell the Owner'),
        [
          'a change that goes on to `class.md` step 3 takes its class there',
          'before any writer dispatch',
        ],
      ),
      isTrue,
    );
    final text = _pluginText(_classReference);
    final order = [
      'only one section or field of one doc',
      'become false or missing',
      "the note's `Owner ok:` line",
    ].map(text.indexOf).toList();
    expect(order, everyElement(isNonNegative), reason: '$order');
    expect(order, orderedEquals([...order]..sort()), reason: 'test order');
    for (final words in [
      [
        'In a brainstorm',
        'section 4 of `design.md`',
        'asks the lane before step 3',
      ],
      ['none of the work built from the docs', 'Yes: Doc-only'],
      ['No: Restore or Internal'],
      ['Yes: Decided', 'no: Undecided'],
      ['| Doc-only |', '`specstone-update-sdd`'],
      ['| Restore |', 'departs from an approved doc', 'no doc'],
      ['| Internal |', 'no observable behavior changes', '`covers:`'],
      ['| Undecided |', 'docs first', 'step 4'],
      [
        '| Decided |',
        'the work first',
        'dispatch no writer',
        'no builder check, question round, or fix loop',
        "`specstone-plan-sdd` with the change note's path",
      ],
    ]) {
      expect(_hasSentenceWith(text, words), isTrue, reason: words.join(', '));
    }
  });

  test('an unshown Decided change goes to the Undecided lane', () {
    final text = _pluginText(_classReference);
    expect(
      _hasSentenceWith(text, ['A change not shown Decided is Undecided']),
      isTrue,
    );
    for (final reason in [
      'its class is in doubt',
      'neither `(decided)` nor `(plan)`',
      'fails a decided-line test',
      'no `Owner ok:` line',
    ]) {
      expect(
        text
            .split('\n')
            .any((line) => line.startsWith('- ') && line.contains(reason)),
        isTrue,
        reason: reason,
      );
    }
  });

  test('the skill names no retired stage', () {
    final text = _oneLine(_pluginText(_brainstormSkill));
    for (final word in [
      'sweep',
      'design check',
      'design-check.md',
      'reaudit',
      'removal.md',
      'trim-audit.md',
      'design document',
      'stage: design',
      'amend',
      'fix read',
      'fix-read',
    ]) {
      expect(text, isNot(contains(word)), reason: word);
    }
  });
}

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

// MARK: - re-review

void _reReviewTests() {
  test('the trim audit holds no re-audit', () {
    final text = _pluginText(_trimAuditReference);
    for (final gone in [
      '`findings`',
      'Verdicts:',
      'Outside the round:',
      'ADDRESSED',
      're-audit',
      'runs without `trims`',
    ]) {
      expect(text, isNot(contains(gone)), reason: gone);
    }
    expect(
      _hasSentenceWith(_sectionOf(text, _trimAuditHeading), [
        '`Findings:`',
        'fix loop',
        '`../../specstone-expert-sdd/references/fix-loop.md`',
        '`re-review.md`',
        'never a second trim audit',
      ]),
      isTrue,
    );
    final auditor = _pluginText(_auditor);
    expect(
      _bulletOf(auditor, '- **Trim audit**'),
      isNot(contains('Verdicts:')),
    );
    expect(_oneLine(auditor), isNot(contains('re-audit')));
  });

  test('a trim audit writes an Audited line per target', () {
    expect(
      _hasSentenceWith(
        _sectionOf(_pluginText(_trimAuditReference), _trimAuditHeading),
        ['`Audited:`', 'per target', '`base`'],
      ),
      isTrue,
    );
  });

  test('the builder check files every point under Findings and observations under Notes', () {
    final check = _sectionOf(
      _pluginText(_auditReference),
      _builderCheckHeading,
    );
    for (final words in [
      [
        'every labeled point',
        'under `Findings:`',
        'outside the drafts',
        'adds that doc to the drafts',
      ],
      ['no `Outside the drafts:` section'],
      ['`Notes:`', 'observation', 'no gap', 'main relays'],
    ]) {
      expect(_hasSentenceWith(check, words), isTrue, reason: words.join(', '));
    }
    expect(check, contains('Notes: - <observation>'));
  });

  test(
    'the trim audit opens each outside item with the doc that holds its fix',
    () {
      final audit = _sectionOf(
        _pluginText(_trimAuditReference),
        _trimAuditHeading,
      );
      for (final words in [
        [
          '`Outside the drafts:`',
          'opens with the name of the doc where its fix lies',
          'never a draft of the round',
        ],
        ['gap in a draft', 'under `Findings:`'],
        ['`Notes:`', 'observation', 'no gap', 'main relays'],
      ]) {
        expect(
          _hasSentenceWith(audit, words),
          isTrue,
          reason: words.join(', '),
        );
      }
      expect(audit, contains('Notes: - <observation>'));
      expect(audit, contains('Write no `Notes:` heading when there is none'));
    },
  );

  test('the auditor names a Notes section for each of its five jobs', () {
    final text = _pluginText(_auditor);
    for (final lead in [
      '- **Builder check**',
      '- **Re-review**',
      '- **Trim audit**',
      '- **Decided audit**',
      '- **Plan check**',
    ]) {
      final bullet = _bulletOf(text, lead);
      expect(bullet, contains('`Notes:`'), reason: lead);
    }
    expect(
      _bulletOf(text, '- **Builder check**'),
      contains('no `Outside the drafts:` section'),
    );
  });

  test('the auditor takes findings, and no sections or citers', () {
    final text = _sectionOf(_pluginText(_auditor), '## Input Contract');
    expect(text, contains('**`findings`**'));
    for (final input in ['**`sections`**', '**`citers`**']) {
      expect(text, isNot(contains(input)), reason: input);
    }
  });

  test('the auditor takes five jobs and names the plan check and its load', () {
    final text = _pluginText(_auditor);
    final contract = _sectionOf(text, '## Input Contract');
    expect(
      _hasSentenceWith(contract, [
        '**`job`**',
        '`builder-check`',
        '`re-review`',
        '`trim-audit`',
        '`decided-audit`',
        '`plan-check`',
        'five values',
        'OPEN QUESTIONS:',
      ]),
      isTrue,
    );
    for (final gone in ['two values', 'three values', 'four values']) {
      expect(contract, isNot(contains(gone)), reason: gone);
    }
    final drafts = _bulletOf(text, '- **Drafts**');
    for (final word in ['`re-review`', '`changedSections`']) {
      expect(drafts, contains(word), reason: word);
    }
    for (final words in [
      ['**`findings`**', '`re-review`', 'still open', 'verbatim'],
      ['**`audits`**', '`re-review`', 'oldest first'],
      ['**Answers**', '`re-review`', "the Owner's answers"],
      ['`decided-audit`', 'decided lines'],
      ['`decided-audit`', 'draft lists', 'joined'],
      ['`decided-audit`', 'each sync engineer report'],
    ]) {
      expect(
        _hasSentenceWith(contract, words),
        isTrue,
        reason: words.join(', '),
      );
    }
    final loads = _sectionOf(text, '## On-Demand Loads');
    for (final job in ['re-review', 'decided-audit']) {
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
      '`job: decided-audit`',
      '`job: plan-check`',
    ]) {
      expect(head, contains(job), reason: job);
    }
    expect(
      _hasSentenceWith(contract, ['**`plan`**', '`plan-check`', 'required']),
      isTrue,
    );
    expect(
      _hasSentenceWith(contract, [
        '**`code target`**',
        '`plan-check`',
        'two or more code targets',
      ]),
      isTrue,
    );
    final scope = _sectionOf(text, '## Scope Boundaries');
    for (final words in [
      [
        'In a plan check',
        '`context <target> … --for implement --out --groups`',
      ],
      ["In a trim audit or the Owner's check", 'a doc the files lack'],
    ]) {
      expect(_hasSentenceWith(scope, words), isTrue, reason: words.join(', '));
    }
    expect(
      _hasSentenceWith(_bulletOf(text, '- **Plan check**'), [
        '`Critical`',
        '`Important`',
        '`Minor`',
        '`<plan path>:<line>`',
        'evidence',
      ]),
      isTrue,
    );
    expect(
      _hasSentenceWith(_sectionOf(text, '## Scope Boundaries'), [
        'Edit the plan',
        'plan check',
      ]),
      isTrue,
    );
    final decided = _bulletOf(text, '- **Decided audit**');
    for (final words in [
      '`Contradiction`, `Stale reader`, and `Not carried`',
      '`Fix:` lines',
      '`Audited:`',
    ]) {
      expect(decided, contains(words), reason: words);
    }
    expect(
      _hasSentenceWith(_bulletOf(text, '- **`Fix:` lines**'), [
        'the Decided audit',
        '**Dry run**',
      ]),
      isTrue,
    );
    final report = _bulletOf(text, '- **Re-review**');
    for (final line in [
      '`Findings:`',
      '`Verdicts:`',
      '`Outside the round:`',
      '`Audited:`',
    ]) {
      expect(report, contains(line), reason: line);
    }
    expect(_bulletOf(text, '- **Builder check**'), contains('`Fix:` lines'));
    for (final file in [
      _auditor,
      _auditReference,
      _trimAuditReference,
      _reReviewReference,
      _decidedAuditReference,
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

  test('the Decided audit reports only Contradiction, Stale reader, and Not '
      'carried items, with no feature pattern search', () {
    final text = _pluginText(_decidedAuditReference);
    final first = text.split('\n').first;
    for (final word in ['`specstone-sdd-auditor`', '`job: decided-audit`']) {
      expect(first, contains(word), reason: word);
    }
    final audit = _sectionOf(text, _decidedAuditHeading);
    for (final words in [
      ['only', '`Contradiction`', '`Stale reader`', '`Not carried`'],
      ['`Not carried`', 'decided line', 'no draft carries'],
      ['no feature pattern search'],
      ['no fix loop', 'no re-review'],
      ['steps 1 and 2', '`audit.md`'],
      ['**Dry run**', '`audit.md`'],
      ['approval ask'],
      ['`Audited:`', 'per draft'],
    ]) {
      expect(_hasSentenceWith(audit, words), isTrue, reason: words.join(', '));
    }
    expect(audit, contains('nothing important left'));
    for (final label in ['- Guess:', '- Misplaced:']) {
      expect(audit, isNot(contains(label)), reason: label);
    }
  });

  test('the builder check and the Decided audit count work against any '
      'project vision as a Contradiction', () {
    final check = _sectionOf(
      _pluginText(_auditReference),
      _builderCheckHeading,
    );
    final start = check.indexOf('- `Contradiction`: ');
    final end = check.indexOf('- `Stale reader`: ', start);
    expect([start, end], everyElement(isNonNegative), reason: '$start $end');
    expect(
      _hasSentenceWith(check.substring(start, end), [
        'against any project vision, advanced or not',
        'the doc the Reach list gives it',
        "the vision's ID",
      ]),
      isTrue,
    );
    expect(
      _hasSentenceWith(
        _sectionOf(_pluginText(_decidedAuditReference), _decidedAuditHeading),
        ['`Contradiction`', 'against any project vision'],
      ),
      isTrue,
    );
  });

  test('the builder check writes fix lines under a finding it can settle', () {
    final check = _sectionOf(
      _pluginText(_auditReference),
      _builderCheckHeading,
    );
    expect(
      _hasSentenceWith(check, [
        'an item whose fix you can state',
        'one `Fix: <type>:<name>#<key>` line per section the fix changes',
        'indented two spaces',
        "that section's whole new body",
        _fixFence,
      ]),
      isTrue,
    );
    expect(
      check,
      contains('- Guess: <doc>#<key>: <point> Fix: <type>:<name>#<key>'),
    );
  });

  test('the builder check writes no fix line for an Owner question', () {
    expect(
      _hasSentenceWith(
        _sectionOf(_pluginText(_auditReference), _builderCheckHeading),
        ['question only the Owner settles', 'no `Fix:` line'],
      ),
      isTrue,
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
      for (final words in [
        [
          'one `specstone approve <drafts> --dry-run --json --audit <path> …`',
          'each `audits` path',
          '`base`',
          '`changedSections`',
        ],
        ['one `specstone context <draft> <draft> --for review --out`'],
        ['**Asks**', 'read `findings`', '`audits`', '`fix report`'],
        ['each section', '`changedSections` names', 'nothing else'],
        ['equals its audited copy', 'not listed', 'earlier audit read it'],
        ['no report of `audits` names', 'every section'],
        ['no `changedSections`', 'read whole'],
        ['empty `changedSections`', 'no section of it is read'],
        ['citer', 'citing items', '`grep -n -E`'],
        ['no other doc read', '`search`', '`refs`', '`context` call'],
      ]) {
        expect(_hasSentenceWith(read, words), isTrue, reason: words.join(', '));
      }
      expect(_pluginText(_reReviewReference), isNot(contains('TRIAL:')));
    },
  );

  test('the re-review reports audited lines, one verdict per open finding, '
      'and new gaps', () {
    final read = _sectionOf(_pluginText(_reReviewReference), _reReviewHeading);
    for (final words in [
      ['`Audited:`', 'per draft', '`base` of step 1'],
      ['`Verdicts:`', 'one verdict', 'open finding', 'names one of its drafts'],
      ['restates every finding still open'],
      ['names none of its drafts', 'no `Verdicts:` line'],
      ['new gap', '`Findings:`', '`Fix:` lines', _fixFence],
      ['question only the Owner settles', 'no `Fix:` line'],
      ['`nothing important left`'],
      [
        '`Outside the round:`',
        'fix lies in no draft of the round',
        'name of the doc where its fix lies',
      ],
      [
        'Restate',
        '`Outside the drafts:`',
        '`Outside the round:`',
        'still open',
      ],
      ['`Notes:`', 'outside the read set', 'no gap', 'never extends the loop'],
    ]) {
      expect(_hasSentenceWith(read, words), isTrue, reason: words.join(', '));
    }
    final findings = read.indexOf('Findings: - <Label>: <doc>#<key>: <point>');
    final verdicts = read.indexOf(
      'Verdicts: - ADDRESSED: <item> - NOT ADDRESSED: <item>',
    );
    final outside = read.indexOf(
      'Outside the round: - <doc whose fix it is>: <gap>',
    );
    final notes = read.indexOf('Notes: - <observation>');
    final audited = read.indexOf('Audited: <type>:<name>@<hash>');
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
    expect(
      _hasSentenceWith(text, [
        "Write only the agent's `report:` file",
        'no fix',
      ]),
      isTrue,
    );
    final read = _sectionOf(text, _reReviewHeading);
    for (final words in [
      ['no `check`', 'no `check --repeats`', 'no lens walk', 'no second read'],
      ['Edit no doc and no change note'],
    ]) {
      expect(_hasSentenceWith(read, words), isTrue, reason: words.join(', '));
    }
    final spans = _approveSpans(text);
    expect(spans, isNotEmpty);
    for (final span in spans) {
      expect(span, contains('--dry-run'), reason: span);
    }
    final auditor = _pluginText(_auditor);
    final boundaries = _sectionOf(auditor, '## Scope Boundaries');
    for (final words in [
      ['`check`', 'lens walk', 'a builder check or a re-review'],
      [
        '`approve` only as `specstone approve <names> --dry-run --json`',
        'in a re-review',
        '`specstone approve <names> --dry-run --json --audit <path> …`',
      ],
      ['the writer', 'fixes it'],
    ]) {
      expect(
        _hasSentenceWith(boundaries, words),
        isTrue,
        reason: words.join(', '),
      );
    }
    for (final gone in ['main session fixes', 'dispatched you fixes']) {
      expect(_oneLine(auditor), isNot(contains(gone)), reason: gone);
    }
  });

  test('the re-review takes no round report at the approval step', () {
    final read = _sectionOf(_pluginText(_reReviewReference), _reReviewHeading);
    for (final words in [
      ['`fix report`', 'absent at the approval step'],
      [
        'at the approval step',
        'audit items still open',
        'name its drafts',
        'verbatim',
      ],
    ]) {
      expect(_hasSentenceWith(read, words), isTrue, reason: words.join(', '));
    }
    final auditor = _pluginText(_auditor);
    expect(
      _bulletOf(auditor, '- **`fix report`**'),
      contains('absent at the approval step'),
    );
    expect(_oneLine(auditor), isNot(contains('round reports')));
  });

  test('the approval-step re-review takes findings none and writes Verdicts '
      'none', () {
    final read = _sectionOf(_pluginText(_reReviewReference), _reReviewHeading);
    for (final words in [
      ['at the approval step', 'audit items still open', 'or `none`'],
      ['no open finding naming one of its drafts', 'write `Verdicts: none`'],
    ]) {
      expect(_hasSentenceWith(read, words), isTrue, reason: words.join(', '));
    }
    expect(
      _bulletOf(_pluginText(_auditor), '- **`findings`**'),
      allOf(contains('at the approval step'), contains('or `none`')),
    );
  });

  test('the approval-step re-review files a citer gap under Outside the '
      'round', () {
    expect(
      _hasSentenceWith(
        _sectionOf(_pluginText(_reReviewReference), _reReviewHeading),
        [
          'marked `citer of <type>:<name>`',
          'under `Outside the round:`',
          'never `Findings:`',
          'second `--auto` call names no citer',
        ],
      ),
      isTrue,
    );
  });

  test('the builder check reports a plan decision that states doc behavior as Not carried', () {
    final check = _sectionOf(
      _pluginText(_auditReference),
      _builderCheckHeading,
    );
    final start = check.indexOf('- `Not carried`: ');
    final end = check.indexOf('- `Misplaced`: ', start);
    expect([start, end], everyElement(isNonNegative), reason: '$start $end');
    expect(
      _hasSentenceWith(check.substring(start, end), [
        'A `(plan)` decision',
        'behavior a PRD or spec doc must hold',
        'names that doc',
      ]),
      isTrue,
    );
  });

  test('the auditor states a fix only as Fix lines, never in prose', () {
    for (final (file, heading) in [
      (_auditReference, _builderCheckHeading),
      (_reReviewReference, _reReviewHeading),
    ]) {
      expect(
        _hasSentenceWith(_sectionOf(_pluginText(file), heading), [
          'fix only as `Fix:` lines',
          'never in prose',
        ]),
        isTrue,
        reason: file,
      );
    }
    final auditor = _pluginText(_auditor);
    for (final lead in ['- **Builder check**', '- **Re-review**']) {
      expect(
        _bulletOf(auditor, lead),
        contains('never in prose'),
        reason: lead,
      );
    }
  });

  test('the auditor dry-runs each Fix section with no base before it writes the line', () {
    final check = _sectionOf(
      _pluginText(_auditReference),
      _builderCheckHeading,
    );
    for (final words in [
      [
        'before each `Fix:` line',
        '`specstone set <doc>#<key> --dry-run`',
        'no `--base`',
        'fenced body',
        'stdin',
      ],
      ['each finding it prints', 'doc-level', 'each refusal the body causes'],
      ['dry-run again', 'write the line'],
      ['cannot fix in the body', 'no `Fix:` line'],
    ]) {
      expect(_hasSentenceWith(check, words), isTrue, reason: words.join(', '));
    }
    expect(
      _hasSentenceWith(
        _sectionOf(_pluginText(_reReviewReference), _reReviewHeading),
        ['each `Fix:` line', '**Dry run**', '`audit.md`'],
      ),
      isTrue,
    );
    final boundaries = _sectionOf(_pluginText(_auditor), '## Scope Boundaries');
    expect(
      _hasSentenceWith(boundaries, [
        '`set` only as `specstone set <doc>#<key> --dry-run`',
        'before each `Fix:` line',
      ]),
      isTrue,
    );
    expect(boundaries, isNot(contains('run no `new`, `set`')));
  });

  test(
    'the re-review creates no doc and leaves a new-doc gap with no Fix line',
    () {
      final read = _sectionOf(
        _pluginText(_reReviewReference),
        _reReviewHeading,
      );
      for (final words in [
        ['Edit no doc and no change note', 'add no doc'],
        ['fix is a new doc', 'no `Fix:` line', 'the Owner'],
      ]) {
        expect(_hasSentenceWith(read, words), isTrue, reason: words.join(', '));
      }
      expect(
        _bulletOf(_pluginText(_auditor), '- **`Fix:` lines**'),
        contains('new doc'),
      );
    },
  );

  test(
    'an ADDRESSED verdict of a re-review clears the earlier finding it equals',
    () {
      expect(
        _hasSentenceWith(
          _sectionOf(_pluginText(_reReviewReference), _reReviewHeading),
          ['first line', 'after `- ADDRESSED: `', 'clears', 'equals'],
        ),
        isTrue,
      );
      expect(
        _bulletOf(_pluginText(_auditor), '- **`ADDRESSED` verdicts**'),
        allOf(contains('clears'), contains('equals'), contains('first line')),
      );
    },
  );
}

// MARK: - fix loop

/// The sentences of the fix loop reference file.
List<String> _fixLoopSentences() =>
    _sentencesOf(_pluginText(_fixLoopReference));

/// Expects one of [sentences] to hold every word of each of [wordLists].
void _expectSentencesWith(
  List<String> sentences,
  List<List<String>> wordLists,
) {
  for (final words in wordLists) {
    expect(
      _indexWith(sentences, words),
      isNonNegative,
      reason: words.join(', '),
    );
  }
}

/// The path an agent file names the fix loop reference file by.
const _fixLoopAgentPath = '.agents/skills/$_fixLoopReference';

/// The path a reference of another skill names the fix loop file by.
const _fixLoopRelativePath = '../../$_fixLoopReference';

/// Words of the loop's own rules that no file pointing to it restates.
const _fixLoopRuleWords = [
  'round 5',
  'rounds 4',
  'at most 5',
  'breaker',
  'capable model',
  'at most 3 rounds',
  'one fix round',
];

void _fixLoopTests() {
  test('fix-loop counts rounds per writer and caps them at five', () {
    _expectSentencesWith(_fixLoopSentences(), [
      [
        'A round is one fix dispatch per writer with an open finding',
        'one re-review',
      ],
      ['at most 5 rounds', 'counted from its first fix dispatch'],
      ['writer of the draft it names', "each writer's rounds count apart"],
      ['The loop ends', 'no finding open', 'the breaker decided'],
    ]);
  });

  test('fix-loop resumes the writer with its mode inputs bar bundles for rounds one to three', () {
    _expectSentencesWith(_fixLoopSentences(), [
      [
        '**Rounds 1 to 3, resume**',
        'open findings verbatim',
        '`report:` its own report file',
      ],
      [
        "names its mode and that mode's inputs again, bar `bundles`",
        '`mode: author`',
        "the change note's path",
        '`docs` share',
        '`group reports` for the cross-group writer',
        '`mode: bootstrap`',
        '`procedure`',
        '`batch:` the open findings',
      ],
      [
        'cannot resume',
        'fresh writer of the same agent',
        'same `report:` path',
        'what was tried',
      ],
    ]);
  });

  test('fix-loop sends a fresh writer on a stronger model with the earlier tries line for rounds four and five', () {
    _expectSentencesWith(_fixLoopSentences(), [
      [
        '**Rounds 4 and 5, fresh writer**',
        'more capable model',
        "host's dispatch takes a model",
        'else on the same one',
      ],
      [
        'same inputs bar `bundles`',
        'same `report:` path',
        '`<N>` the rounds already run',
        'A prior writer attempted these fixes <N> times',
      ],
      ['you own them now'],
      ['Read the report file for what was tried'],
    ]);
  });

  test('fix-loop runs one re-review per round across every writer', () {
    _expectSentencesWith(_fixLoopSentences(), [
      [
        'once every writer of the round has reported',
        'one fresh `specstone-sdd-auditor`',
        '`job: re-review`',
        '`findings:` every finding of the run still open, verbatim',
        "each writer's included",
        'breaker-decided ones included',
        "`fix report:` each writer's report path and round number",
        '`drafts:`',
        '`audits:` each earlier audit report of the run, oldest first',
        "the Owner's answers",
        '`<folder>/reports/sdd-auditor.audit.<XXXXXX>.md`',
      ],
    ]);
    expect(_pluginText(_fixLoopReference), isNot(contains('round reports')));
  });

  test('fix-loop routes an outside finding to the cross-group writer or a handed line', () {
    _expectSentencesWith(_fixLoopSentences(), [
      [
        "outside every writer's drafts",
        'in a brainstorm',
        'the one writer',
        'cross-group writer',
        'joins the drafts list',
      ],
      [
        'In a bootstrap round',
        'leaves the loop as a handed line',
        '`trim-round.md` Handed lines',
      ],
      [
        '`Outside the drafts:`',
        'a handed line',
        '`trim-round.md` Handed lines',
      ],
      [
        '`Outside the round:`',
        "counts in its writer's rounds",
        'leaves the loop as a handed line',
      ],
    ]);
    final text = _oneLine(_pluginText(_fixLoopReference));
    for (final gone in [
      '`Citers outside:`',
      'own trim audit and loop',
      "doc's folder",
    ]) {
      expect(text, isNot(contains(gone)), reason: gone);
    }
  });

  test('fix-loop sends a ruled finding to no later fix dispatch and keeps it not addressed', () {
    _expectSentencesWith(_fixLoopSentences(), [
      [
        "still open after its writer's round 5",
        'new finding on a writer past it',
        'stops the loop for that writer',
        'no later fix dispatch takes it',
      ],
      ['reviewer is wrong', 'contestable', 'why the text stands'],
      ['real and deferred'],
      ['load-bearing', 'Owner question'],
      ['parked finding stays `- NOT ADDRESSED:`', '`--auto` still asks'],
      [
        'beside its draft at the approval ask',
        '`Why:`',
        'one message',
        'no second question round',
      ],
      ['`- NOT ADDRESSED:` item', 'bar one the breaker decided'],
    ]);
  });

  test(
    'fix-loop keeps a conflicting or Owner-only finding out of every fix',
    () {
      _expectSentencesWith(_fixLoopSentences(), [
        ['conflicts with the change note or an Owner answer', 'enters no fix'],
        ['Decide it first', '`Calls made`', 'relay to the Owner'],
        [
          'no `Fix:` line that only the Owner settles',
          'enters no fix either',
          'theirs pile',
          'approval ask',
        ],
      ]);
    },
  );

  test(
    'fix-loop has the writer write each fix block unchanged and main none',
    () {
      _expectSentencesWith(_fixLoopSentences(), [
        [
          'the writer writes every fix',
          "each `Fix:` block's body as that section's whole text, unchanged",
        ],
        ['Write no fix text of your own in the loop'],
      ]);
    },
  );

  test(
    'fix-loop returns a round part missing a line once, then counts the round',
    () {
      _expectSentencesWith(_fixLoopSentences(), [
        [
          '`## Round <n>` part',
          '`Changed: <type>:<name>#<key>` line',
          '`Check:` line naming a saved check run after its last write',
          'drafts from one approval dry run',
        ],
        ['missing one goes back to its writer once', 'in the same round'],
        [
          'Still missing one',
          "that writer's round fails and counts toward the 5",
        ],
      ]);
    },
  );

  test(
    'fix-loop without a subagent has main fix once and runs no re-review',
    () {
      _expectSentencesWith(_fixLoopSentences(), [
        [
          'With no subagent',
          'you are the writer for one pass of fixes',
          '`dispatch.md`',
          'no re-review runs',
        ],
        [
          'Each draft with an open finding',
          'Owner confirmation',
          '`Why:`',
          'change made after the audit',
        ],
      ]);
    },
  );

  test(
    'the engineer names each changed section on a Changed line in a fix round',
    () {
      final text = _pluginText(_engineer);
      final input = _bulletOf(
        text.substring(0, text.indexOf('## Output Format')),
        '- **Fix round**',
      );
      final output = _sentencesOf(_sectionOf(text, '## Output Format'));
      _expectSentencesWith(_sentencesOf(input), [
        [
          '`$_fixLoopAgentPath`',
          'open findings verbatim',
          "mode's inputs again, bar `bundles`",
        ],
        [
          "each `Fix:` block's body as that section's whole text, unchanged",
          'never reworded',
        ],
        ['prior writer attempted these fixes', 'reads its `report` file'],
      ]);
      _expectSentencesWith(output, [
        [
          '**Fix round**',
          '`## Round <n>` part',
          'each section you changed',
          '`Changed: <type>:<name>#<key>` line each',
        ],
        [
          '`Check:` line',
          'bare `check` run after your last write',
          'one `specstone approve --dry-run --json` after that write',
        ],
        ['fresh writer given the same `report` file', 'appends the same way'],
      ]);
    },
  );

  test('both bootstrap engineers report a fix round with Changed, Check, and drafts lines', () {
    for (final entry in _bootstrapEntries) {
      final text = _pluginText(entry);
      _expectSentencesWith(_sentencesOf(text), [
        [
          'A fix round of `$_fixLoopRelativePath`',
          'each open finding',
          'through `--base`',
        ],
      ]);
      _expectSentencesWith(_sentencesOf(_sectionOf(text, '## Report')), [
        [
          'A fix round appends its `## Round <n>` part',
          "the engineer's Output Format gives a fix round",
          "its `Check:` line naming step 3's file",
        ],
      ]);
      expect(text, isNot(contains('fix batch')), reason: entry);
      expect(text, isNot(contains('`Changed:` lines')), reason: entry);
    }
  });

  test(
    'expert-sdd points to fix-loop.md once and its pointers hold no loop rule',
    () {
      final expert = _pluginText(_expertSdd);
      expect('references/fix-loop.md'.allMatches(expert), hasLength(1));
      _expectSentencesWith(_sentencesOf(expert), [
        [
          '`references/fix-loop.md`',
          "After a brainstorm's builder check or a bootstrap trim audit",
        ],
      ]);
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
      for (final file in [
        for (final (file, _) in pointers) file,
        _reReviewReference,
        _brainstormSkill,
      ]) {
        final text = _oneLine(_pluginText(file));
        for (final word in _fixLoopRuleWords) {
          expect(text, isNot(contains(word)), reason: '$file: $word');
        }
      }
    },
  );
}

void _authorModeTests() {
  test('author.md gives the cross-group writer the merge step with no type '
      'list', () {
    final sentence = _sentencesOf(_pluginText(_authorReference))
        .singleWhere((sentence) => sentence.contains('cross-group writer'));
    expect(sentence, contains('merge step'));
    for (final type in ['agent', 'skill', 'architecture', 'domain']) {
      expect(sentence, isNot(contains(type)), reason: type);
    }
  });

  test('no brainstorming, engineer, or fix-loop file names story reports or a '
      'story writer', () {
    for (final file in [
      ..._skillAndAgentFiles().where(
        (file) => file.startsWith('specstone-brainstorming-sdd/'),
      ),
      _engineer,
      _fixLoopReference,
    ]) {
      final text = _oneLine(_pluginText(file));
      for (final gone in ['story reports', 'story writer', 'cross-story']) {
        expect(text, isNot(contains(gone)), reason: '$file: $gone');
      }
    }
  });

  test('the engineer takes the author inputs and no old fix-file input', () {
    final contract = _sectionOf(_pluginText(_engineer), '## Input Contract');
    for (final (input, words) in [
      ('change note', ['`change note`', 'author', 'required']),
      ('reach list', ['Reach list', 'start from']),
      (
        'docs',
        ['`docs`', 'two or more work groups', "its group's `targets:` line"],
      ),
      ('docs absent', ['absent, every Reach doc']),
      (
        'group reports',
        [
          '`group reports`',
          'cross-group writer',
          'each doc an `Elsewhere:` line of its `group reports` names',
        ],
      ),
      ('group report lines', ['`Elsewhere:`', '`Decision:`']),
      (
        'bundles',
        ['`bundles`', 'read plan line', 'no doc write', 'first group writer'],
      ),
    ]) {
      expect(_hasSentenceWith(contract, words), isTrue, reason: input);
    }
    for (final gone in [
      '**`guide`**',
      'fix file',
      'amend',
      'design document',
    ]) {
      expect(contract, isNot(contains(gone)), reason: gone);
    }
  });

  test(
    'a missing mode or input, or an other mode, gets only OPEN QUESTIONS',
    () {
      final contract = _sectionOf(_pluginText(_engineer), '## Input Contract');
      for (final (stop, words) in [
        ('missing input', ['OPEN QUESTIONS:', 'one line per gap']),
        ('no other file', ['no file but', '`report:`']),
        ('no entry file', ['stop', 'no entry file']),
        ('no mode', ['no `mode`', 'fresh dispatch']),
        ('plan', ['`plan`', '`specstone-plan-sdd`']),
        (
          'design',
          ['`design`', '`specstone-brainstorming-sdd`', 'change note'],
        ),
        ('audit', ['`mode: audit`', '`specstone-sdd-auditor`']),
      ]) {
        expect(_hasSentenceWith(contract, words), isTrue, reason: stop);
      }
    },
  );

  test('the engineer describes the author input as a change note', () {
    final text = _pluginText(_engineer);
    final head = text.substring(0, text.indexOf('\n---\n', 4));
    expect(head, contains('change note'));
    expect(head, isNot(contains('design')));
  });

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
    final report = _pluginText(_authorReport);
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

  test(
    'the author grounds, saves its guide, and reuses its gate check before its '
    'first write',
    () {
      final step = _sectionOf(_pluginText(_authorReference), '## 1. Read');
      for (final (rule, words) in [
        ('bundles', ['`bundles`', 'each read plan line']),
        (
          'context',
          ['one `specstone context', '--for design --out', 'your share'],
        ),
        ('guide', ['`specstone guide <types> --out', '`--json`', 'every type']),
        ('gate check', ['gate', '`check` file', 'before your first write']),
        ('no second', ['run no second']),
      ]) {
        expect(_hasSentenceWith(step, words), isTrue, reason: rule);
      }
    },
  );

  test('the reader step runs per decision before the first write', () {
    final text = _pluginText(_authorReference);
    const readers = '## 2. Find the readers';
    expect(text.indexOf(readers), isNonNegative);
    expect(text.indexOf(readers), lessThan(text.indexOf('## 3. Write')));
    final step = _sectionOf(text, readers);
    for (final (rule, words) in [
      (
        'statement',
        ['one reader step per decision', 'before your first write'],
      ),
      (
        'terms',
        [
          '`specstone search "<term>"`',
          'each short form',
          '`--type`',
          '`--under`',
        ],
      ),
      ('inbound', ['`Inbound`', '`specstone refs`']),
      ('one hop', ['one hop', 'no recursion']),
      (
        'feature summaries',
        ['summary sections', 'each of its ancestors', '`benefit_hypothesis`'],
      ),
      (
        'spec summaries',
        ['`flow`', '`out_of_scope`', 'architecture `components`', '`fr_trace`'],
      ),
      ('owner link', ['a link to the owner']),
      ('no copy', ['no copy stays']),
      ('repeats', ['`--repeats`', 'no part of']),
    ]) {
      expect(_hasSentenceWith(step, words), isTrue, reason: rule);
    }
    expect(step, isNot(contains('component_details')));
    expect(step, isNot(contains('domain intro')));
  });

  test('the author reads by name list and writes one batch', () {
    final step = _sectionOf(_pluginText(_authorReference), '## 3. Write');
    for (final phrase in [
      'one `specstone get <list> --out "<file>"`',
      'one `specstone set --batch "<file>"`',
      'sdd-engineer.author.batch.<XXXXXX>.txt',
      '`<type>:<name>#<key>`',
      'the bare name',
      '`input_output`',
      'the key alone',
      '`section_not_found`',
      'its block holds the naming line alone',
      'Read a block whole only for a bare name or a rewritten section',
      '` · unchanged` block counts as no draft',
      'its own `get … --out` and its own `set --batch`',
    ]) {
      expect(step, contains(phrase), reason: phrase);
    }
  });

  test('the author gives each decision a line and flags one no doc took', () {
    final step = _sectionOf(_pluginText(_authorReference), '## 3. Write');
    for (final (rule, words) in [
      ('line', ['a `Decision:` line', 'each section that took it']),
      ('not landed', ['`NOT LANDED`', '`Not landed:`', 'why']),
      ('forced', ['never force it into a doc or drop it']),
      ('outside', ['only docs outside your share', 'neither line']),
      (
        'cross-group',
        ['`Not landed:`', 'no `Decision:` line of `group reports`'],
      ),
    ]) {
      expect(_hasSentenceWith(step, words), isTrue, reason: rule);
    }
  });

  test('a group writer passes an outside-share decision on in an Elsewhere '
      'line keyed by D<n>', () {
    final step = _sectionOf(_pluginText(_authorReference), '## 3. Write');
    expect(
      _hasSentenceWith(step, [
        'group writer',
        '`Elsewhere:` line',
        'outside your share',
        '`D<n>`',
      ]),
      isTrue,
      reason: 'author.md',
    );
    final report = _pluginText(_authorReport);
    for (final (rule, words) in [
      ('elsewhere', ['group writer', '`Elsewhere:`', '`D<n>`']),
      (
        'file',
        ['last line', 'your file', "another writer's file", 'stays open'],
      ),
    ]) {
      expect(_hasSentenceWith(report, words), isTrue, reason: rule);
    }
    expect(
      _hasSentenceWith(_sectionOf(_pluginText(_engineer), '## Output Format'), [
        'group writer',
        '`Elsewhere:`',
        '`D<n>`',
      ]),
      isTrue,
      reason: 'engineer',
    );
  });

  test('the author gives a plan decision neither a Decision nor a Not landed '
      'line', () {
    final step = _sectionOf(_pluginText(_authorReference), '## 3. Write');
    for (final (rule, words) in [
      ('plan', ['A `(plan)` decision', 'neither line']),
      (
        'cross-group',
        ['`Not landed:`', 'not marked `(plan)`', '`group reports`'],
      ),
    ]) {
      expect(_hasSentenceWith(step, words), isTrue, reason: rule);
    }
    expect(
      _hasSentenceWith(_sectionOf(_pluginText(_engineer), '## Output Format'), [
        'A `(plan)` decision',
        'neither line',
        'no draft states it',
      ]),
      isTrue,
    );
  });

  test('the author keys each Not landed line by its change note decision and '
      'files a fix it cannot apply under Findings', () {
    final report = _pluginText(_authorReport);
    for (final (rule, words) in [
      ('keyed', ['`Not landed: D<n>:', 'one change note decision', '`D<n>`']),
      ('fix', ['builder check fix you cannot apply', '`Findings:`', 'never']),
    ]) {
      expect(_hasSentenceWith(report, words), isTrue, reason: rule);
    }
    expect(
      _hasSentenceWith(_pluginText(_engineer), [
        'builder check fix you cannot apply',
        '`Findings:`',
        'never `Not landed:`',
      ]),
      isTrue,
    );
  });

  test('a later author round lands a decision on its Decision line in its one '
      'report under a round heading', () {
    final report = _pluginText(_authorReport);
    for (final (rule, words) in [
      ('round', ['later round', 'same report file', '`## Round <n>`']),
      (
        'lands',
        [
          '`Decision:` line',
          'an earlier round left `NOT LANDED`',
          "another writer's included",
        ],
      ),
      ('last line', ['last line', 'decides']),
    ]) {
      expect(_hasSentenceWith(report, words), isTrue, reason: rule);
    }
  });

  test(
    'the author leaves moves and deletes to main and splits by work group',
    () {
      final step = _sectionOf(_pluginText(_authorReference), '## 3. Write');
      for (final (rule, words) in [
        (
          'no move',
          [
            'no `specstone move`',
            'no `specstone rename`',
            'no `specstone delete`',
          ],
        ),
        ('lines', ['`Move:`', '`Rename:`', '`Delete:`', 'main']),
        ('elsewhere', ['`Elsewhere:`', 'outside your share', 'no write']),
        ('cross-group', ['cross-group writer', '`group reports`']),
        ('merge', ['merge step', 'each `Elsewhere:` line']),
      ]) {
        expect(_hasSentenceWith(step, words), isTrue, reason: rule);
      }
    },
  );

  test('the author recovers a refused batch fault by fault', () {
    final step = _sectionOf(
      _pluginText(_authorReference),
      '## 4. Recover a refused batch',
    );
    expect(step, contains('`author-recovery.md`'));
    final text = _oneLine(_pluginText(_authorRecovery));
    for (final phrase in [
      '`output_not_writable`',
      'a write command or a `get` first',
      'Stale block',
      'Gone block',
      'One part twice',
      'removed required section',
      'undeclared section',
      'refused path or line',
      'unchanged block counts as no draft',
    ]) {
      expect(text, contains(phrase), reason: phrase);
    }
  });

  test('the author walks the guide rules, then checks again', () {
    final text = _pluginText(_authorReference);
    final walk = text.indexOf('## 5. Walk and check');
    expect(walk, isNonNegative);
    final step = _sectionOf(text, '## 5. Walk and check');
    for (final (rule, words) in [
      ('rule lines', ['rule lines', 'description lines', '`Frontmatter:`']),
      ('not rule lines', ['`Banned words:`', '`Limits:`', 'no rule lines']),
      ('shared', ['several types', '`==> shared <==`']),
      ('unmet', ['cannot meet', '`Findings:`']),
      ('second check', ['your last write', 'check.author.<XXXXXX>.txt']),
      ('newer check', ['one more bare check']),
      ('newer file', ['newer file', 'unfixed']),
      ('touched', ['touched', 'even one the first run had']),
      ('untouched', ['untouched section', 'unfixed']),
    ]) {
      expect(_hasSentenceWith(step, words), isTrue, reason: rule);
    }
    expect(
      step.indexOf('rule lines'),
      lessThan(step.indexOf('After your last write')),
    );
  });

  test('the author counts from one dry run and proposes a split alone', () {
    final step = _sectionOf(
      _pluginText(_authorReference),
      '## 5. Walk and check',
    );
    for (final (rule, words) in [
      ('counts', ['one `specstone approve --dry-run --json`', 'never from']),
      ('size pointer', ['`item_count_out_of_range`', '`author-size.md`']),
    ]) {
      expect(_hasSentenceWith(step, words), isTrue, reason: rule);
    }
    final size = _pluginText(_authorSize);
    for (final (rule, words) in [
      ('size finding', ['`item_count_out_of_range`', 'edge case lines']),
      ('split proposal', ['split proposal', 'size-fix.md']),
      ('no commands', ['run no `new` or `move`']),
      ('fresh writer', ['fresh writer', 'bar `bundles`']),
    ]) {
      expect(_hasSentenceWith(size, words), isTrue, reason: rule);
    }
  });

  test('engineer may write move plan files under the reports folder', () {
    final scope = _sectionOf(_pluginText(_engineer), '## Scope Boundaries');
    for (final (rule, words) in [
      (
        'write',
        [
          'move plan file',
          '<folder>/reports/sdd-engineer.<mode>.plan.<XXXXXX>.txt',
        ],
      ),
      ('applied by main', ['the main session applies it', 'never you']),
      (
        'barred',
        [
          '`move --plan-file`',
          'included',
          '`move --plan-out <addresses> --out "<plan file>"`',
        ],
      ),
    ]) {
      expect(_hasSentenceWith(scope, words), isTrue, reason: rule);
    }
    expect(
      _hasSentenceWith(_pluginText(_authorReport), [
        '`Move:`',
        '<folder>/reports/sdd-engineer.author.plan.<XXXXXX>.txt',
        'size-fix.md',
      ]),
      isTrue,
    );
  });

  test('author report names its plan file in place of commands', () {
    final report = _pluginText(_authorReport);
    final open = report.indexOf('```');
    final template = report.substring(open, report.indexOf('```', open + 3));
    expect(template, contains('Move: <plan file path>'));
    expect(template, isNot(contains('specstone move')));
    expect(
      _hasSentenceWith(report, ['`Move:`', 'move plan file', 'relay block']),
      isTrue,
    );
    expect(
      _hasSentenceWith(report, [
        'Run no `move` except `move --plan-out … --out` into that file',
      ]),
      isTrue,
    );
    expect(
      _hasSentenceWith(
        _sectionOf(_pluginText(_roundsReference), _roundsMoves),
        ['each `Move:` plan file', 'one `specstone move --plan-file "<file>"`'],
      ),
      isTrue,
    );
  });
}

const _authorReport = 'specstone-brainstorming-sdd/references/author-report.md';

const _authorRecovery =
    'specstone-brainstorming-sdd/references/author-recovery.md';

const _authorSize = 'specstone-brainstorming-sdd/references/author-size.md';

// MARK: - small edit

const _updateSkill = 'specstone-update-sdd/SKILL.md';

void _smallEditTests() {
  test('update-sdd step 4 writes no change note and points to the approval '
      'step with --no-audit', () {
    final text = _pluginText(_updateSkill);
    final step = _sectionOf(text, '## 4. Name the change for the Owner');
    expect(
      _hasSentenceWith(step, ['Write no change note']),
      isTrue,
      reason: 'change note term',
    );
    expect(
      _hasSentenceWith(step, [_approvePath, '`--no-audit`']),
      isTrue,
      reason: 'approval pointer',
    );
    expect(_oneLine(text), isNot(contains('design document')));
  });

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
    expect(_hasSentenceWith(write, ['Leave that flag']), isTrue);
  });

  test('update-sdd merges a base_mismatch into the current text', () {
    final write = _sectionOf(_pluginText(_updateSkill), '## 3. Write the edit');
    expect(
      _hasSentenceWith(write, [
        'Merge your edit into that text',
        'same `specstone set` again with that base',
      ]),
      isTrue,
    );
    expect(_hasSentenceWith(write, ['`base_mismatch`']), isTrue);
  });

  test('update-sdd asks which code target for a name in two targets', () {
    final read = _sectionOf(
      _pluginText(_updateSkill),
      '## 2. Gate on the target, then read it',
    );
    expect(
      _hasSentenceWith(read, [
        'two or more code targets',
        'ask the Owner which one',
        '`specstone-plan-sdd`',
        'DocPath',
      ]),
      isTrue,
    );
  });

  test('update-sdd says the drafts an edited doc holds stay drafts', () {
    final step = _sectionOf(
      _pluginText(_updateSkill),
      '## 4. Name the change for the Owner',
    );
    expect(
      _hasSentenceWith(step, ['edited doc holds drafts', 'stay drafts']),
      isTrue,
    );
  });
}

// MARK: - moved parts

const _readSdd = 'specstone-read-sdd/SKILL.md';

const _reader = 'specstone-sdd-reader.md';

void _movedPartsTests() {
  test('read-sdd opens the implement refs head when the header counts moved '
      'parts', () {
    expect(
      _hasSentenceWith(_pluginText(_readSdd), [
        '`implement`',
        '` · <n> moved`',
        'refs head',
        'after the read plan',
      ]),
      isTrue,
    );
  });

  test('read-sdd counts a moved part among the docs it must open', () {
    final text = _pluginText(_readSdd);
    expect(
      _hasSentenceWith(text, [
        '` · moved`',
        "one of the task's docs",
        'by its range',
        'before acting',
      ]),
      isTrue,
    );
    expect(
      _hasSentenceWith(text, [
        'Read each by its own range',
        'no read of them is a doc read',
      ]),
      isTrue,
    );
  });

  test('read-sdd searches moved parts before any get', () {
    expect(
      _hasSentenceWith(_pluginText(_readSdd), [
        'moved parts included',
        'before any `specstone get`',
      ]),
      isTrue,
    );
  });

  test('a read-first warning stops no read in read-sdd', () {
    expect(
      _hasSentenceWith(_pluginText(_readSdd), [
        'read-first',
        'warning',
        'stops no read',
        'ask nothing',
      ]),
      isTrue,
    );
  });

  test(
    'read-sdd reads a moved part over one host read in consecutive parts',
    () {
      expect(
        _hasSentenceWith(_pluginText(_readSdd), [
          'Read each by its own range',
          'over one host read',
          'consecutive parts',
        ]),
        isTrue,
      );
    },
  );

  test('the reader reads a moved part over one read in consecutive parts', () {
    final workflow = _sectionOf(_pluginText(_reader), '## Workflow');
    expect(
      _hasSentenceWith(workflow, [
        'refs part marked ` · moved`',
        'over one read',
        'consecutive parts',
      ]),
      isTrue,
    );
  });

  test('the reader searches moved refs parts like read-first parts', () {
    final workflow = _sectionOf(_pluginText(_reader), '## Workflow');
    expect(
      _hasSentenceWith(workflow, [
        'refs part marked ` · moved`',
        'as the read-first file is',
        "the host's text search",
      ]),
      isTrue,
    );
  });
}

// MARK: - grounding

const _severalDocs = 'specstone-read-sdd/references/several-docs.md';

void _groundingTests() {
  test('read-sdd names each cited story and doc in one call', () {
    final text = _sectionOf(
      _pluginText(_readSdd),
      '## Pick the targets and mode',
    );
    expect(
      _hasSentenceWith(text, [
        'name each story it cites',
        '`specstone context <story> <story> <doc> --for implement --out`',
      ]),
      isTrue,
    );
    expect(_hasSentenceWith(text, ['Never target the feature']), isTrue);
  });

  test('read-sdd asks for a missing target in main, stops in a subagent', () {
    final skill = _pluginText(_readSdd);
    final text = _sectionOf(skill, '## Pick the targets and mode');
    final calls = _sectionOf(skill, '## Count the calls');
    final severalDocs = _pluginText(_severalDocs);
    expect(
      _hasSentenceWith(text, [
        '`argument_missing`',
        'a main session asks the Owner',
        '`--target <name>`',
      ]),
      isTrue,
    );
    expect(
      _hasSentenceWith(text, [
        'a Subagent runs no further call',
        'reports the missing target',
      ]),
      isTrue,
    );
    expect(
      _hasSentenceWith(calls, ['count each', '`argument_missing` refusal']),
      isTrue,
    );
    expect(
      _hasSentenceWith(calls, [
        'a doc design work newly reaches',
        'takes its own',
      ]),
      isTrue,
    );
    expect(
      _hasSentenceWith(severalDocs, ['never refuses `argument_missing`']),
      isTrue,
    );
    expect(_hasSentenceWith(severalDocs, ['with no `--target`']), isTrue);
  });

  test('read-sdd hands the reader paths and the plan line, no doc text', () {
    final text = _pluginText(_readSdd);
    final section = _sectionOf(text, '## Whole sections from the reader');
    expect(
      _hasSentenceWith(section, [
        'saved file',
        'read plan line as printed',
        'no doc text',
      ]),
      isTrue,
    );
    expect(_hasSentenceWith(text, ['size hands nothing off']), isTrue);
  });

  test('read-sdd grounds a missing design doc by context, never get', () {
    final text = _sectionOf(_pluginText(_readSdd), '## Search before `get`');
    expect(
      _hasSentenceWith(text, [
        'in design work',
        '`specstone context <doc> --for design --out`',
        'never `get`',
      ]),
      isTrue,
    );
    expect(_hasSentenceWith(text, ['base hash before `set`']), isTrue);
  });

  test(
    'read-sdd saves a long guide, get, search, or refs output with --out',
    () {
      final text = _sectionOf(_pluginText(_readSdd), '## Search before `get`');
      expect(
        _hasSentenceWith(text, [
          'Save a long',
          '`guide`',
          '`get`',
          '`search`',
          '`refs`',
          'bare `--out`',
        ]),
        isTrue,
      );
    },
  );

  test('read-sdd reads by the newest index after a rerun', () {
    expect(
      _hasSentenceWith(
        _sectionOf(_pluginText(_readSdd), '## Ground in one call'),
        ['same targets and flags replaces the files', 'newest index'],
      ),
      isTrue,
    );
  });

  test('read-sdd reads every plan range in order, first to last line', () {
    final text = _pluginText(_readSdd);
    expect(
      _hasSentenceWith(_sectionOf(text, '## Ground in one call'), [
        'every range the plan line names',
        'in order',
        "range's first and last line",
        "before the task's first other action",
      ]),
      isTrue,
    );
    final ground = _sectionOf(text, '## Ground in one call');
    expect(_hasSentenceWith(ground, ['Skip none']), isTrue);
    expect(_hasSentenceWith(ground, ['Skip none', 'bar']), isFalse);
    expect(
      _hasSentenceWith(_sectionOf(text, '## Count the calls'), [
        'measured after',
        'never by skipping a range',
      ]),
      isTrue,
    );
  });

  test('read-sdd reads a range past one host read in parts', () {
    expect(
      _hasSentenceWith(
        _sectionOf(_pluginText(_readSdd), '## Ground in one call'),
        ['A range larger than one host read', 'consecutive parts to its end'],
      ),
      isTrue,
    );
  });

  test('the reader reads every plan range in order, first to last line', () {
    final workflow = _sectionOf(_pluginText(_reader), '## Workflow');
    expect(
      _hasSentenceWith(workflow, [
        'every range it names, in order',
        "range's first and last line",
        'consecutive parts to its end',
        'skipping none',
      ]),
      isTrue,
    );
  });
}

// MARK: - boundary rule

void _boundaryRuleTests() {
  test('expert-sdd states the PRD and spec-type boundary and its spec-draft '
      'clause, and holds no subset line', () {
    final text = _pluginText(_expertSdd);
    final rules = _sectionOf(text, '## Rules');
    expect(
      _hasSentenceWith(rules, [
        'PRD owns product behavior',
        'each spec type owns the facts its guide lists',
      ]),
      isTrue,
    );
    expect(
      _hasSentenceWith(rules, [
        'Work built from the docs, such as code or content',
        'no spec states',
        'spec draft first',
      ]),
      isTrue,
    );
    expect(rules, isNot(contains('API spec')));
    expect(text, isNot(contains('spec ⊆ PRD')));
  });

  test('the expert-sdd Docs lead rule holds the decided-line exception', () {
    final rules = _sectionOf(_pluginText(_expertSdd), '## Rules');
    const words = ['decided line', "plan's last task"];
    expect(_hasSentenceWith(rules, words), isTrue);
    final start = rules.indexOf('1. **Docs lead.**');
    final end = rules.indexOf(' 2. **', start);
    expect(start, isNot(-1));
    expect(end, isNot(-1));
    expect(_hasSentenceWith(rules.substring(start, end), words), isTrue);
  });

  test('plan-engineer Ground lets the spec win on the Observable contract '
      'alone and holds no subset line', () {
    final text = _pluginText(_planAgent);
    final ground = _sectionOf(text, '## Ground');
    expect(
      _hasSentenceWith(ground, ['Observable contract', 'the spec wins']),
      isTrue,
    );
    expect(ground.toLowerCase(), isNot(contains('wire contract')));
    expect(text, isNot(contains('spec ⊆ PRD')));
  });

  test('confirm-links records confirmed by the field, naming no doc type', () {
    final text = _pluginText(
      'specstone-expert-sdd/references/confirm-links.md',
    );
    expect(_hasSentenceWith(text, ['`confirmed`', 'field']), isTrue);
    expect(text, isNot(contains('(`api`)')));
  });

  test('expert-sdd writes a feature record at the address its bundle naming '
      'line prints', () {
    final text = _pluginText('specstone-expert-sdd/references/write.md');
    expect(
      _hasSentenceWith(text, [
        'naming line',
        'context <story> --for implement --out',
      ]),
      isTrue,
    );
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

void _planFlowTests() {
  test('the plan check grounds docs, reads code, and ranks each fault', () {
    final text = _pluginText(_planCheck);
    for (final words in [
      [
        '`specstone context <target> … --for implement --out --groups`',
        "task read lines, as the planner's Ground does",
      ],
      ['`--target <code target>` before `--out`', 'when one is given'],
      ['A Decided plan whose tasks name no story', 'Reach targets'],
      ['`==> group`', 'one group at a time'],
      [
        '`change note`',
        'Decisions',
        '`D<n>`',
        'never against the doc it will change',
        'no decided line is itself a fault',
      ],
      ['A non-zero exit', 'stops the check'],
      ['Read the code', 'each task names'],
      ['Read the plan rules', '`../../../agents/specstone-plan-engineer.md`'],
      [
        '`Critical`',
        '`Important`',
        '`Minor`',
        '`<plan path>:<line>`',
        '`<path>:<line>`',
        'evidence',
      ],
      ['`nothing important left`'],
      ['writes no plan and no doc'],
    ]) {
      expect(_hasSentenceWith(text, words), isTrue, reason: words.join(', '));
    }
  });

  test('plan-sdd sends each answers round with the inputs whole', () {
    final text = _pluginText(_planSkill);
    expect(
      _hasSentenceWith(_sectionOf(text, '## 3. Relay the reply'), [
        'same agent while it is live',
        'dispatch a new one',
        '`targets:` whole',
        'never "unchanged"',
      ]),
      isTrue,
    );
    expect(
      _hasSentenceWith(_sectionOf(text, '## 2. Hand off'), [
        'each round reuses it',
      ]),
      isTrue,
    );
  });

  test('plan-sdd sends a Decided change note with no targets and asks no '
      'pick', () {
    final text = _pluginText(_planSkill);
    expect(
      _hasSentenceWith(
        _sectionOf(
          text,
          '## 1. List the stories: the gate, the code target, the targets',
        ),
        ['A Decided change', "note's path alone", 'no pick', 'no `targets:`'],
      ),
      isTrue,
    );
    expect(
      _bulletOf(text, '- `targets:`'),
      allOf(
        contains('leave the line out for a Decided change'),
        isNot(contains('none for a Decided change')),
      ),
    );
  });

  test('plan-sdd says the plan is ready to run when no skill runs it', () {
    expect(
      _hasSentenceWith(
        _sectionOf(_pluginText(_planSkill), '## 4. Ask how to run the plan'),
        ['None qualifies', 'ready to run'],
      ),
      isTrue,
    );
  });

  test('plan-sdd runs no check', () {
    final text = _pluginText(_planSkill);
    expect(
      _hasSentenceWith(
        _sectionOf(
          text,
          '## 1. List the stories: the gate, the code target, the targets',
        ),
        ['Run no `check`'],
      ),
      isTrue,
    );
    expect(_oneLine(text), isNot(contains('specstone check')));
  });

  test('plan-sdd stops with no run skill when the plan is none', () {
    final text = _pluginText(_planSkill);
    final ask = _sectionOf(text, '## 4. Ask how to run the plan');
    expect(
      _hasSentenceWith(ask, [
        '`Plan:` line reads `none`',
        'rows and `Findings:`',
      ]),
      isTrue,
    );
    expect(_hasSentenceWith(ask, ['offer no run skill']), isTrue);
    expect(
      _hasSentenceWith(_sectionOf(text, '## 3. Relay the reply'), [
        '`Plan: none`',
        'no `plan path:`',
      ]),
      isTrue,
    );
  });

  test('plan-sdd dispatches one planner per work group, then one merge '
      'planner', () {
    final groups = _sectionOf(
      _pluginText(_planGroups),
      '## 1. Dispatch the planners',
    );
    for (final words in [
      ['one `specstone-plan-engineer` per group of its `Groups:` block'],
      ["the first dispatch's inputs written out again", 'its own `report:`'],
      ['`group: <k> of <n>`'],
      ['`bundles:`', 'as the block prints them'],
      ['`check:`', "the block's `Check:` file"],
      ['`part:`', '`<folder>/reports/plan-engineer.part.<XXXXXX>.md`'],
      ['may run at once', 'only its own part and report'],
      [
        'After every group planner reports',
        'one `specstone-plan-engineer` with `parts:`',
        'each part file with its report',
      ],
      ["the grouping pass's reply", "the merge planner's reply"],
      ['findings round', 'section 2', 'its relay left to this item'],
    ]) {
      expect(_hasSentenceWith(groups, words), isTrue, reason: words.join());
    }
  });

  test('plan-sdd sends an answer on a row after a merge to a fresh planner of '
      "that row's group, then merges again", () {
    final answers = _sectionOf(
      _pluginText(_planGroups),
      '## 2. Answers after the merge',
    );
    for (final words in [
      [
        'an answer on a row',
        "a fresh planner of that row's group",
        "its group's inputs",
        '`answers:`',
        'its `part:` path, which it amends',
      ],
      ['Then dispatch the merge planner again, once'],
      [
        "A plan check's round goes the same way",
        'each finding',
        'the group whose part holds the task its plan line sits in',
        "a finding on no part's line",
        'the merge planner',
      ],
      ["a check round's", 'section 1 item 3', 'once'],
    ]) {
      expect(_hasSentenceWith(answers, words), isTrue, reason: words.join());
    }
  });

  test("plan-sdd sends the merge planner the Owner's new plan path after a "
      'merge', () {
    final answers = _sectionOf(
      _pluginText(_planGroups),
      '## 2. Answers after the merge',
    );
    expect(
      _hasSentenceWith(answers, [
        'Then dispatch the merge planner again',
        '`plan path:` the plan its `Plan:` line named',
        "or the Owner's new path, as step 3 item 2 gives",
      ]),
      isTrue,
    );
  });

  test('plan-sdd takes a none (groups) reply as no none line and follows the '
      'groups reference', () {
    expect(
      _hasSentenceWith(
        _sectionOf(_pluginText(_planSkill), '## 3. Relay the reply'),
        ['`Plan: none (groups)`', 'no `none` line', '`references/groups.md`'],
      ),
      isTrue,
    );
  });

  test('plan-sdd has main write the plan when the main-writer test passes', () {
    final conditions = _sectionOf(
      _pluginText(_planMainWriter),
      '## 1. The test',
    );
    for (final words in [
      [
        '`specstone context … --out`',
        'every target',
        'each story of an approved drafts list',
        'each story its decided lines change',
      ],
      ['`set`', '`new`', '`move`', '`rename`', 'writer dispatch', 'since'],
      [
        '`specstone context … --for implement --out --groups`',
        'you run',
        "agent file's Ground source 1",
        'Workflow step 2',
        'exits 0',
        'no `==> group` line',
      ],
      ['A non-zero exit', 'no story to name', 'fails condition 2'],
      ['record entry', '`covers:` entry', 'code path'],
      ["condition 2's call", 'only when condition 1 holds'],
      [
        '`../../../agents/specstone-plan-engineer.md`',
        'same inputs',
        '`report:`',
      ],
      ['following it would open a code file', 'stop and dispatch', 'section 2'],
    ]) {
      expect(
        _hasSentenceWith(conditions, words),
        isTrue,
        reason: words.join(', '),
      );
    }
    expect(
      _hasSentenceWith(_pluginText(_planMainWriter), [
        'host with no subagent',
        'skips the test',
        'step 2 of `SKILL.md`',
      ]),
      isTrue,
    );
    expect(
      _hasSentenceWith(_pluginText(_planSkill), [
        'writes the plan',
        'you write it by',
        '`../../agents/specstone-plan-engineer.md`',
      ]),
      isTrue,
    );
    final handOff = _sectionOf(_pluginText(_planSkill), '## 2. Hand off');
    expect(_hasSentenceWith(handOff, ['`references/main-writer.md`']), isTrue);
    expect(
      _hasSentenceWith(handOff, [
        '`../../agents/specstone-plan-engineer.md`',
        'same inputs',
      ]),
      isTrue,
    );
    expect(
      _hasSentenceWith(
        _sectionOf(
          _pluginText(_planSkill),
          '## 1. List the stories: the gate, the code target, the targets',
        ),
        ['Run no `check`', 'whoever follows'],
      ),
      isTrue,
    );
  });

  test(
    'plan-sdd dispatches the planner when a main-writer condition fails',
    () {
      final failed = _sectionOf(
        _pluginText(_planMainWriter),
        '## 2. A failed condition',
      );
      expect(
        _hasSentenceWith(failed, ['`specstone-plan-engineer`', 'dispatch']),
        isTrue,
      );
      expect(
        _hasSentenceWith(failed, [
          'While a dispatch can run',
          '`==> ` headers',
          'implementation lines',
        ]),
        isTrue,
      );
    },
  );

  test('plan-sdd answers a round itself only when it needs no code read', () {
    final rounds = _sectionOf(
      _pluginText(_planMainWriter),
      '## 3. Answer rounds',
    );
    for (final words in [
      ['relay', 'answer rounds', 'run question', 'dispatched plan'],
      [
        'needs no code read',
        'you answer it',
        'unless the agent that answered the last round is live',
      ],
      ["step 2's inputs", '`answers:`', '`plan path:`', 'step 3 item 2'],
      ['relay its report', 'step 3 item 3'],
      ['agent that answered the last round', 'takes the next one'],
      ['names a code path', "that round's Ground call", 'condition 2 or 3'],
      ['needs a code read', 'fresh', '`specstone-plan-engineer`'],
    ]) {
      expect(_hasSentenceWith(rounds, words), isTrue, reason: words.join(', '));
    }
    expect(
      _hasSentenceWith(
        _sectionOf(_pluginText(_planSkill), '## 3. Relay the reply'),
        ['`references/main-writer.md`'],
      ),
      isTrue,
    );
  });

  test('plan-sdd has the planner write the plan unless main holds it', () {
    final text = _pluginText(_planSkill);
    expect(
      _hasSentenceWith(text, [
        '`specstone-plan-engineer`',
        'every plan rule',
        'writes the plan',
        '`references/main-writer.md`',
      ]),
      isTrue,
    );
    expect(_oneLine(text), isNot(contains('You write no plan text')));
  });

  test('plan-sdd runs one fresh plan check before the Owner sees the plan', () {
    final dispatch = _sectionOf(
      _pluginText(_planFreshRead),
      '## 1. Dispatch the check',
    );
    for (final words in [
      [
        '`Plan:`',
        'written plan',
        'first reply',
        'even after a `Plan: none` round',
        "the merge planner's in a run by groups",
      ],
      ['`specstone-sdd-auditor`', '`job: plan-check`', '`plan:`'],
      [
        '`targets:`',
        '`change note:`',
        '`code target:`',
        'each when step 2 sends it',
        '`report:`',
      ],
      ['`../../specstone-expert-sdd/references/dispatch.md`'],
      ['before', 'shows the Owner'],
      ['once a check has run', 'no second plan check'],
      ['you wrote'],
    ]) {
      expect(
        _hasSentenceWith(dispatch, words),
        isTrue,
        reason: words.join(', '),
      );
    }
    expect(
      _hasSentenceWith(
        _sectionOf(_pluginText(_planSkill), '## 3. Relay the reply'),
        [
          "The run's first written plan",
          '`references/fresh-read.md`',
          'before',
        ],
      ),
      isTrue,
    );
    for (final path in [_planGroups, _planMainWriter]) {
      expect(
        _hasSentenceWith(_pluginText(path), ['`fresh-read.md`', 'before']),
        isTrue,
        reason: path,
      );
    }
  });

  test('plan-sdd sends check findings once, else relays the plan', () {
    final act = _sectionOf(
      _pluginText(_planFreshRead),
      '## 2. Act on the check',
    );
    for (final words in [
      [
        '`Critical`',
        '`Important`',
        'first',
        '`Report:`',
        'relay block',
        'word for word',
      ],
      ['every finding', 'once', '`Minor`', '`answers:`', '`plan path:`'],
      ['Outside a run by groups', 'amended reply', 'step 3 item 1'],
      [
        'no `Findings:` line',
        'did not run',
        'never relay',
        'step 3 item 1 with no second check',
      ],
      ['In a run by groups', '`groups.md` section 2', 'its section 1 item 3'],
      ['none', 'as it stands', '`Minor`'],
      ['For a plan you wrote', '`main-writer.md` section 3 gives.'],
    ]) {
      expect(_hasSentenceWith(act, words), isTrue, reason: words.join(', '));
    }
    expect(act.indexOf('`Report:`'), isNonNegative);
    expect(act.indexOf('`Report:`'), lessThan(act.indexOf('`answers:`')));
  });

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

  test(
    'plan-engineer retries the ground call once without refused targets',
    () {
      final workflow = _sectionOf(_pluginText(_planAgent), '## Workflow');
      expect(
        _hasSentenceWith(workflow, ['`doc_not_found`', '`NOT PLANNED` row']),
        isTrue,
      );
      expect(
        _hasSentenceWith(workflow, [
          'once again without those targets',
          'ground and plan the rest',
        ]),
        isTrue,
      );
    },
  );

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
    expect(
      _hasSentenceWith(ground, [
        'read a later source only for what the earlier ones leave out',
      ]),
      isTrue,
    );
    expect(
      _hasSentenceWith(ground, [
        'Never target the feature',
        'never open a doc file by path',
      ]),
      isTrue,
    );
    expect(ground, contains('**Code target:**'));
  });

  test('plan-engineer Ground names the spec docs that cover the story with no '
      'type list', () {
    final ground = _sectionOf(_pluginText(_planAgent), '## Ground');
    expect(ground, isNot(contains('ARCHITECTURE, API')));
    expect(ground, isNot(contains('TECH_STACK')));
  });

  test('plan-engineer takes CI commands and library docs from its bundle '
      'docs', () {
    final ground = _sectionOf(_pluginText(_planAgent), '## Ground');
    expect(
      _hasSentenceWith(ground, [
        'Library docs',
        'each dependency a doc of the bundle names',
      ]),
      isTrue,
    );
    expect(
      _hasSentenceWith(ground, [
        'the CI commands a doc of its bundle names',
        'when it has none',
      ]),
      isTrue,
    );
  });

  test('plan-engineer writes a tests step at the record address its bundle '
      'naming line prints', () {
    final workflow = _sectionOf(_pluginText(_planAgent), '## Workflow');
    expect(workflow, isNot(contains('implementation:<feature>')));
    expect(
      _hasSentenceWith(workflow, [
        '`<record>` is its target',
        'the address its bundle naming line prints',
      ]),
      isTrue,
    );
  });

  test('plan-engineer ends each task but the last with its own sync step', () {
    final workflow = _sectionOf(_pluginText(_planAgent), '## Workflow');
    expect(workflow, contains('`specstone context --for sync --out`'));
    for (final words in [
      ['each task but the last', 'its own sync step', 'after its tests pass'],
      [
        'only the group file of the feature the task built',
        "top-level feature's group for a sub-feature",
      ],
      ['verdict part', 'after its verdict lines', 'one `specstone set --sync'],
    ]) {
      expect(_hasSentenceWith(workflow, words), isTrue, reason: words.join());
    }
  });

  test('plan-engineer puts empty work list lines in its own sync file', () {
    expect(
      _hasSentenceWith(_sectionOf(_pluginText(_planAgent), '## Workflow'), [
        'empty work list',
        '`<folder>/reports/<agent>.sync.<XXXXXX>.md`',
        '`<folder>` the path `specstone folder` prints',
        'one `specstone set --sync',
      ]),
      isTrue,
    );
  });

  test('plan-engineer routes task-end mismatches to the Owner', () {
    expect(
      _hasSentenceWith(_sectionOf(_pluginText(_planAgent), '## Workflow'), [
        '`Mismatches:` point',
        '`Waiting:` line',
        'line still refused',
        "implementer's report",
        'before the next task starts',
      ]),
      isTrue,
    );
  });

  test('plan-engineer runs no sync step when a plan defers record writes', () {
    final workflow = _sectionOf(_pluginText(_planAgent), '## Workflow');
    expect(
      _hasSentenceWith(workflow, [
        'defers record writes',
        'no task runs a sync step',
        'no `context --for sync`',
        'no `specstone set --sync`',
      ]),
      isTrue,
    );
    expect(
      _hasSentenceWith(workflow, [
        "implementer's report",
        'last task',
        'writes them',
      ]),
      isTrue,
    );
  });

  test('plan-engineer writes tests lines before row lines', () {
    final text = _pluginText(_planAgent);
    final workflow = _sectionOf(text, '## Workflow');
    final testsLine = workflow.indexOf('`tests <record> <item>: +<test file>`');
    final rowLine = workflow.indexOf('`row <record> <item>: +<literal>`');
    expect(testsLine, isNonNegative);
    expect(rowLine, greaterThan(testsLine));
    expect(
      _hasSentenceWith(workflow, ['its `tests` lines, then its `row` lines']),
      isTrue,
    );
    expect(text, isNot(contains('--field tests')));
    expect(text, isNot(contains('#verification_matrix')));
  });

  test('plan-engineer copies each row literal from the formatted test', () {
    final workflow = _sectionOf(_pluginText(_planAgent), '## Workflow');
    expect(
      _hasSentenceWith(workflow, [
        'the first string literal of the test',
        'formatted test file writes it',
        r'`$` interpolations and escapes kept',
      ]),
      isTrue,
    );
    expect(
      _hasSentenceWith(workflow, [
        'each literal from the test file after formatting',
        'in place of the name the plan gives',
      ]),
      isTrue,
    );
  });

  test("plan-engineer keeps each task's sync step under a plan skill", () {
    expect(
      _hasSentenceWith(_sectionOf(_pluginText(_planAgent), '## Workflow'), [
        "Specstone's rules win",
        "each task's own sync step",
        'the last `specstone-sync-sdd` task',
      ]),
      isTrue,
    );
  });

  test('plan-engineer carries each plan decision of the change note into a '
      'task step or a header constraint', () {
    final text = _pluginText(_planAgent);
    final workflow = _sectionOf(text, '## Workflow');
    for (final (rule, section, words) in [
      (
        'input',
        _sectionOf(text, '## Input Contract'),
        ['`change note`', '`(plan)` decisions', 'Workflow step 4'],
      ),
      (
        'carry',
        workflow,
        ['`D<n> (plan): <text>`', 'task step', 'header constraint'],
      ),
      (
        'no doc fact',
        workflow,
        ['`(plan)` decision', 'cites its doc', 'no doc fact from the note'],
      ),
      ('header', workflow, ['write a header', '`(plan)` decision', 'step 4']),
    ]) {
      expect(_hasSentenceWith(section, words), isTrue, reason: rule);
    }
  });

  test('plan-engineer gives each okayed decided decision a Decided task', () {
    final text = _pluginText(_planAgent);
    final workflow = _sectionOf(text, '## Workflow');
    for (final (rule, section, words) in [
      (
        'okayed',
        workflow,
        [
          'no `targets`',
          '`D<n> (decided): <text>`',
          'one Decided task',
          '`Owner ok: <YYYY-MM-DD>` line',
        ],
      ),
      ('builds no doc', workflow, ['Decided task builds no doc']),
      (
        'no Owner ok',
        workflow,
        ['no `Owner ok:` line', 'no task builds it', '`Open questions:`'],
      ),
      (
        'with targets',
        workflow,
        ['sent with `targets`', '`(decided)` mark plans nothing of its own'],
      ),
      (
        'read line',
        workflow,
        [
          "Decided task's read line",
          'the story its decided line changes',
          'else it has none',
        ],
      ),
      ('test', workflow, ['`when <input or state>, <outcome>`']),
      (
        'ground',
        _sectionOf(text, '## Ground'),
        ['no `targets`', 'each story a decided line changes', 'none runs'],
      ),
      (
        'bootstrap',
        _sectionOf(text, '## Bootstrap'),
        [
          'a change note and no `targets`',
          "the change note's Decisions",
          'before the Ground call',
          'each story a decided line changes',
        ],
      ),
    ]) {
      expect(_hasSentenceWith(section, words), isTrue, reason: rule);
    }
  });

  test("plan-engineer names each task's class", () {
    expect(
      _hasSentenceWith(_sectionOf(_pluginText(_planAgent), '## Workflow'), [
        'names its class',
        'Restore',
        'Internal',
        'Decided',
        'Undecided',
      ]),
      isTrue,
    );
  });

  test("plan-engineer's last task takes a Decided change note and approves "
      'its drafts before the branch lands', () {
    final workflow = _sectionOf(_pluginText(_planAgent), '## Workflow');
    for (final words in [
      ['a Decided task', 'last task', "the change note's path"],
      ['decided-line mismatch', 'syncs again with the same path'],
      ["Decided drafts' approval", 'before the branch lands'],
    ]) {
      expect(_hasSentenceWith(workflow, words), isTrue, reason: words.join());
    }
  });

  test("plan-engineer defers a Decided task's tests step to the last sync", () {
    expect(
      _hasSentenceWith(_sectionOf(_pluginText(_planAgent), '## Workflow'), [
        'a Decided task judges no link of its decided behavior',
        'its implementer puts those lines in its report',
        "the plan's last sync",
        'once its FR exists',
      ]),
      isTrue,
    );
  });

  test('plan-engineer lets an okayed decided line win over the spec it '
      'changes', () {
    final ground = _sectionOf(_pluginText(_planAgent), '## Ground');
    for (final words in [
      ['okayed decided line', 'wins over the spec it changes'],
      ['okayed decided line is no spec gap'],
    ]) {
      expect(_hasSentenceWith(ground, words), isTrue, reason: words.join());
    }
  });

  test('plan-engineer has a Decided task cite its D-number', () {
    final text = _pluginText(_planAgent);
    expect(
      _hasSentenceWith(_sectionOf(text, '## Workflow'), [
        'a Decided task cites its `D<n>`',
        'never quoting',
      ]),
      isTrue,
    );
    expect(
      _hasSentenceWith(_sectionOf(text, '## Scope Boundaries'), [
        'a Decided task its `D<n>`',
      ]),
      isTrue,
    );
  });

  test('plan-engineer stops at a grouping pass when its Ground call gives two '
      'or more work groups', () {
    final text = _pluginText(_planAgent);
    expect(
      _sectionOf(text, '## Ground'),
      contains('--for implement --out --groups`'),
    );
    final workflow = _sectionOf(text, '## Workflow');
    final output = _sectionOf(text, '## Output Format');
    for (final (section, words) in [
      (workflow, ['two or more work groups', 'a grouping pass']),
      (
        workflow,
        [
          'read no group file',
          "step 3's one `check`",
          '`Plan:` reading `none (groups)`',
          'write no plan',
        ],
      ),
      (workflow, ['one work group', 'the saved files are the docs']),
      (output, ['`none (groups)`', '`Groups:` block', '`Check:` line']),
      (
        output,
        [
          'its `targets:` line',
          'as its header printed it',
          'read plan line, as printed',
        ],
      ),
    ]) {
      expect(_hasSentenceWith(section, words), isTrue, reason: words.join());
    }
  });

  test("plan-engineer as a group planner writes its group's tasks to its part "
      'file alone', () {
    final text = _pluginText(_planAgent);
    expect(
      _sectionOf(text, '## Input Contract'),
      contains('**`group`, `bundles`, `check`, `part`**'),
    );
    final workflow = _sectionOf(text, '## Workflow');
    for (final words in [
      ['A group planner', 'runs no `context` call', 'by its read plan line'],
      ['only the targets its `targets:` line names', 'for those targets alone'],
      [
        'a group planner gives an okayed decision its Decided task',
        'its `targets:` line holds the story',
        "the first group's planner",
        'whose line changes no story',
      ],
      ['A group planner', 'runs no `check`', 'its `check:` file'],
      ['The part file opens with one line', '`Checked folders: <folder>, …`'],
      ['its `part:` file alone', 'never a plan file'],
      [
        '`Cross-group links:` part',
        "`Waits on: <this task's doc> -> <other doc> (group <m>): <why>`",
      ],
    ]) {
      expect(_hasSentenceWith(workflow, words), isTrue, reason: words.join());
    }
    expect(
      _hasSentenceWith(_sectionOf(text, '## Scope Boundaries'), [
        'as a group planner',
        'its `part:` file',
      ]),
      isTrue,
    );
  });

  test('plan-engineer as a group planner plans an FR target in the group whose '
      'targets line names its story', () {
    final workflow = _sectionOf(_pluginText(_planAgent), '## Workflow');
    expect(
      _hasSentenceWith(workflow, [
        'An FR target is in the group',
        'whose `targets:` line names its story',
      ]),
      isTrue,
    );
    expect(
      _oneLine(workflow),
      isNot(contains("in no group's `targets:` line")),
    );
  });

  test('plan-engineer as the merge planner writes one plan from the parts, '
      'ordered by their Waits on lines', () {
    final text = _pluginText(_planAgent);
    expect(
      _sectionOf(text, '## Input Contract'),
      contains('**`parts`** (the merge planner'),
    );
    final workflow = _sectionOf(text, '## Workflow');
    for (final words in [
      ['The merge planner', 'reads no bundle and no doc file'],
      ['part file and its report whole', "the project's instruction files"],
      ["a part file's `Checked folders:` line"],
      [
        'The merge planner gives no Decided task',
        'each okayed one no part gives a task',
        "whose story the grouping pass's call refused",
        'each `D<n>` lands in the plan once',
      ],
      ['A target in no group', "keeps the grouping pass's row"],
      ['renumbered', 'after every task its `Waits on:` lines name'],
      ['each `(plan)` decision written once'],
      ['no `Waits on:` or `Checked folders:` line stays in the plan'],
      ['a cycle among the `Waits on:` lines', "the cycle's tasks"],
      ['an answer amends a part', 'merge again'],
    ]) {
      expect(_hasSentenceWith(workflow, words), isTrue, reason: words.join());
    }
    final output = _sectionOf(text, '## Output Format');
    for (final words in [
      ['the merge planner', "every group's target rows"],
      ['`Checked folders:`', 'never in the relay block'],
      ['from the merge planner', 'each okayed decision no part plans'],
    ]) {
      expect(_hasSentenceWith(output, words), isTrue, reason: words.join());
    }
    final ground = _sectionOf(text, '## Ground');
    for (final words in [
      ['The merge planner reads no bundle', 'source 3 for the plans folder'],
      [
        'An okayed decided line is no spec gap',
        'past one work group',
        'names it under Open questions when no part plans it',
      ],
    ]) {
      expect(_hasSentenceWith(ground, words), isTrue, reason: words.join());
    }
  });
}

// MARK: - Bootstrap routing

const _prdProcedure = 'specstone-bootstrap-prd/references/procedure.md';
const _specProcedure = 'specstone-bootstrap-spec/references/procedure.md';
const _prdMergeUntyped = 'specstone-bootstrap-prd/references/merge-untyped.md';

/// The first line of [markdown] that starts with [prefix].
String _lineStartingWith(String markdown, String prefix) => markdown
    .split('\n')
    .firstWhere((line) => line.startsWith(prefix), orElse: () => '');

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
  test('both bootstrap skills route an old file by the doc that takes its '
      'content', () {
    final prd = _pluginText('specstone-bootstrap-prd/SKILL.md');
    final spec = _pluginText('specstone-bootstrap-spec/SKILL.md');
    for (final (text, words) in [
      (
        prd,
        [
          '`untyped_doc`',
          'old file whose content goes into a `prds/` or `measurements/` doc',
          'a `specs/` path included',
        ],
      ),
      (
        spec,
        [
          '`specstone-bootstrap-prd` takes the rest',
          'old file whose content goes into a `prds/` or `measurements/` doc',
        ],
      ),
    ]) {
      expect(_hasSentenceWith(text, words), isTrue, reason: words.join(', '));
    }
    final prdRow = _lineStartingWith(
      _pluginText(_prdProcedure),
      '| `untyped_doc`',
    );
    final specRow = _lineStartingWith(
      _pluginText(_specProcedure),
      '| `untyped_doc`',
    );
    expect(
      prdRow,
      contains('whose content goes into a `prds/` or `measurements/` doc'),
    );
    expect(specRow, contains('whose content goes into a `specs/` doc'));
    for (final row in [prdRow, specRow]) {
      expect(row, contains('| step 4 |'));
    }
  });

  test('bootstrap-prd merge-untyped.md follows the fix and holds no '
      'competitor map', () {
    final text = _pluginText(_prdMergeUntyped);
    expect(text, isNot(contains('competitor')));
    expect(
      _hasSentenceWith(text, [
        '`required_field_missing`',
        '`required_section_missing`',
        "this round's fill",
      ]),
      isTrue,
    );
  });

  test('bootstrap-prd deletes a specs path it merged with its other old '
      'files', () {
    expect(
      _hasSentenceWith(_pluginText('specstone-bootstrap-prd/SKILL.md'), [
        'path under `specs/` this round did not merge',
        "`specstone-bootstrap-spec`'s delete",
      ]),
      isTrue,
    );
    expect(
      _hasSentenceWith(_pluginText(_prdProcedure), [
        'joins the set',
        'a `specs/` path it merged included',
      ]),
      isTrue,
    );
  });

  test('bootstrap-prd merges an old file whose doc type a pack dropped', () {
    for (final (file, followed) in [
      (_prdMergeUntyped, 'merge it into the doc that takes it'),
      (_prdProcedure, 'follow `merge-untyped.md`'),
    ]) {
      expect(
        _hasSentenceWith(_pluginText(file), [
          '`untyped_doc`',
          'whose doc type a pack dropped',
          followed,
        ]),
        isTrue,
        reason: file,
      );
    }
  });

  test('no old specs file whose content goes to a prds doc is left out of '
      'both deletes', () {
    expect(
      _hasSentenceWith(_pluginText('specstone-bootstrap-spec/SKILL.md'), [
        '`specstone-bootstrap-prd` takes the rest',
        'old file whose content goes into a `prds/` or `measurements/` doc',
      ]),
      isTrue,
    );
    expect(
      _hasSentenceWith(_pluginText(_specProcedure), [
        'old untyped doc this skill takes',
        'joins the set',
      ]),
      isTrue,
    );
    expect(
      _hasSentenceWith(_pluginText('specstone-bootstrap-prd/SKILL.md'), [
        'Leave out each path under `specs/` this round did not merge',
      ]),
      isTrue,
    );
  });

  test('bootstrap-prd merges an old file whose content goes into a '
      'measurements doc', () {
    const words = 'whose content goes into a `prds/` or `measurements/` doc';
    expect(
      _hasSentenceWith(_pluginText(_prdProcedure), [
        '`untyped_doc`',
        words,
        'follow `merge-untyped.md`',
      ]),
      isTrue,
    );
    for (final file in [_prdProcedure, _prdMergeUntyped]) {
      expect(
        _hasSentenceWith(_pluginText(file), ['`untyped_doc`', words]),
        isTrue,
        reason: file,
      );
    }
  });

  test('bootstrap-spec hands an old file whose content goes into a prds doc '
      'to bootstrap-prd', () {
    final spec = _pluginText(_specProcedure);
    expect(
      _hasSentenceWith(spec, [
        'old file whose content goes into such a doc',
        'go to `specstone-bootstrap-prd`',
      ]),
      isTrue,
    );
    expect(
      _hasSentenceWith(spec, [
        'Stop when each left goes to `specstone-bootstrap-prd`',
        'clears with no write',
      ]),
      isTrue,
    );
  });

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
      expect(
        pointer.single,
        contains('its waits and sync before you stop'),
        reason: skill,
      );
      expect('fix-loop.md'.allMatches(text), hasLength(1), reason: skill);
      for (final word in _fixLoopRuleWords) {
        expect(_oneLine(text), isNot(contains(word)), reason: '$skill: $word');
      }
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

  test('each bootstrap procedure sends a leftover to its finding fix', () {
    for (final file in [_prdProcedure, _specProcedure]) {
      expect(
        _hasSentenceWith(_pluginText(file), [
          '`fix`',
          'the finding',
          'section that takes it',
        ]),
        isTrue,
        reason: file,
      );
    }
  });

  test('a leftover skill follows its holder doc', () {
    for (final skill in _bootstrapSkills) {
      final text = _pluginText(skill);
      expect(
        _hasSentenceWith(text, ['A leftover goes by the doc that holds it']),
        isTrue,
        reason: skill,
      );
      expect(
        _hasSentenceWith(text, [
          'every `to` type',
          'outside `prd-core`',
          '`specstone-bootstrap-spec`',
        ]),
        isTrue,
        reason: skill,
      );
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

  test('bootstrap-spec starts a round on an answered uncovered file only '
      'through an unsent pick', () {
    final step = _sectionOf(
      _pluginText('specstone-bootstrap-spec/SKILL.md'),
      _bootstrapAfterReports,
    );
    expect(
      _hasSentenceWith(step, [
        'starts a round at step 2 unless',
        'it is an answered `code_uncovered` file',
        'file with no `picks:` pick left to send, it is a helper',
      ]),
      isTrue,
    );
  });
}
