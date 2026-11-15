// The test names and expected texts are plan literals kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/setup_migration/agent_files.dart';
import 'package:specstone_core/src/version.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/shipped_pins.dart';
import '../../helpers/skill_files.dart';
import '../../helpers/temp_tree.dart';

const _stale =
    'consistency_check/find_template_breaks/report_stale_agent_blocks';
const _print = 'consistency_check/find_template_breaks/print_findings';
const _migrate = 'run `specstone migrate`';
const _agentMd = '.specstone/AGENT.md';
const _upgrade = 'run `specstone upgrade`';
const _fenceOpen =
    'a code fence is still open at the end of the file and `specstone '
    'migrate` refuses the file; close the code fence that opens on this line';
const _markersMalformed =
    'the Specstone marker lines are malformed and `specstone migrate` '
    'refuses the file; repair the block by hand';
const _settingsStale =
    '.claude/settings.json lacks the Specstone hook or holds one that '
    'differs from what the running CLI writes; $_migrate';
const _settingsMissing = '.claude/settings.json is missing; $_migrate';
const _settingsMalformed =
    '.claude/settings.json is not one JSON object and `specstone migrate` '
    'refuses the file; repair it by hand';

/// The config text of a project whose agent files carry the stamp [version].
String _stamped(String version) =>
    '${shippedPinsConfig()}agent_files_version: $version\n';

/// The message a stale file carries when the stamp [version] lies above the
/// running Version.
String _newer(String lead, String version) =>
    '$lead; the files come from specstone $version, newer than this '
    'specstone $specstoneVersion; $_upgrade';

/// A `.claude/settings.json` text holding one Specstone matcher group, the
/// one the CLI writes unless a parameter departs from it.
String _settings({
  String matcher = 'Write|Edit',
  List<String> args = const ['hook', 'post-edit'],
  Object? timeout,
  Map<String, Object?> owner = const {},
  List<Object?> ownerGroups = const [],
}) => jsonEncode({
  ...owner,
  'hooks': {
    'PostToolUse': [
      ...ownerGroups,
      {
        'matcher': matcher,
        'hooks': [
          {
            'type': 'command',
            'command': 'specstone',
            'args': args,
            'timeout': ?timeout,
          },
        ],
      },
    ],
  },
});

String _imports() => importBlock(
  cliVersion: specstoneVersion,
  agentMdPath: _agentMd,
  projectDocPath: 'docs/prds/PROJECT.md',
);

String _inline() => inlineBlock(cliVersion: specstoneVersion);

/// Returns the `agent_block_stale` findings of a check over the fixture
/// project plus [extra].
Future<List<Finding>> _staleOf(Map<String, String> extra) async => [
  for (final f in checkOf(await writeCheckProject(extra: extra)).findings)
    if (f.kind == FindingKind.agentBlockStale) f,
];

/// Returns the `agent_block_stale` findings of a check over the fixture
/// project at `project/`, with a repository top at `project/other/`, or at
/// `other/` beside the project when [outside].
///
/// [config] is the text after the pins of `.specstone/config.yaml`.
Future<List<Finding>> _staleBeside({
  String config = '',
  Map<String, String> otherFiles = const {},
  bool codeEntry = true,
  bool outside = false,
}) async {
  final top = outside ? 'other' : 'project/other';
  final entry = outside ? '../other/' : 'other/';
  final project = {
    ...checkProjectFiles(),
    '.specstone/config.yaml': '${shippedPinsConfig()}$config',
    if (codeEntry)
      ...edit(techStack, [('  - app/lib/\n', '  - app/lib/\n  - $entry\n')]),
  };
  final base = await writeTree({
    for (final MapEntry(:key, :value) in project.entries) 'project/$key': value,
    '$top/.git/HEAD': 'ref\n',
    for (final MapEntry(:key, :value) in otherFiles.entries) '$top/$key': value,
  });
  return [
    for (final f in checkOf(Directory('${base.path}/project')).findings)
      if (f.kind == FindingKind.agentBlockStale) f,
  ];
}

void main() {
  test(
    '$_stale E35: a stale block at the second target top is a finding',
    () async {
      final base = await writeTree({
        for (final MapEntry(:key, :value) in checkProjectFiles().entries)
          'project/$key': value,
        'project/.specstone/config.yaml':
            '${shippedPinsConfig()}targets:\n  flutter:\n'
            '    code_root: flutter_ws\n  jaspr:\n    code_root: jaspr_ws\n'
            'agent_file_roots:\n  - flutter_ws\n  - jaspr_ws\n',
        'project/flutter_ws/.git/HEAD': 'ref\n',
        'project/jaspr_ws/.git/HEAD': 'ref\n',
        'project/flutter_ws/AGENTS.md': _inline(),
        'project/jaspr_ws/AGENTS.md': _inline().replaceFirst(
          '## Rules',
          '## Old',
        ),
      });
      final findings = [
        for (final f in checkOf(Directory('${base.path}/project')).findings)
          if (f.kind == FindingKind.agentBlockStale &&
              f.path.endsWith('AGENTS.md'))
            f,
      ];

      expect(findings.map((f) => f.path), ['jaspr_ws/AGENTS.md']);
    },
  );

  test(
    '$_stale E01: every agent file as the CLI writes it has no finding',
    () async {
      expect(
        await _staleOf({
          'CLAUDE.md': 'Owner\n${_imports()}',
          'AGENTS.md': _inline(),
          _agentMd: agentMdText,
          '.cursor/rules/specstone.mdc': cursorRulesText(
            cliVersion: specstoneVersion,
          ),
        }),
        isEmpty,
      );
    },
  );

  test(
    '$_stale E02: an older version in the BEGIN line is no finding',
    () async {
      expect(
        await _staleOf({
          'AGENTS.md': _inline().replaceFirst(specstoneVersion, '0.0.1'),
          _agentMd: agentMdText,
        }),
        isEmpty,
      );
    },
  );

  test('$_stale E02: files an earlier pre-release wrote are no finding for the '
      'CLI as it ships', () async {
    // Below every shipped version, so it never equals specstoneVersion.
    const preRelease = '0.0.1-beta.1';
    expect(preRelease, isNot(specstoneVersion));
    expect(
      await _staleOf({
        'CLAUDE.md':
            'Owner\n${importBlock(cliVersion: preRelease, agentMdPath: _agentMd, projectDocPath: 'docs/prds/PROJECT.md')}',
        'AGENTS.md': inlineBlock(cliVersion: preRelease),
        _agentMd: agentMdText,
        '.cursor/rules/specstone.mdc': cursorRulesText(cliVersion: preRelease),
      }),
      isEmpty,
    );
  });

  test(
    '$_stale Output: a hand-edited block is one finding on its BEGIN line, no name',
    () async {
      final found = await _staleOf({
        'AGENTS.md': 'top\n${_inline().replaceFirst('Rules', 'Rule')}',
        _agentMd: agentMdText,
      });

      expect(found, hasLength(1));
      expect(found.single.path, 'AGENTS.md');
      expect(found.single.line, 2);
      expect(found.single.name, isNull);
      expect(
        found.single.message,
        'the Specstone block differs from what the running CLI writes; $_migrate',
      );
    },
  );

  test(
    '$_stale Output: AGENT.md with other bytes is one finding on line 1',
    () async {
      final found = await _staleOf({_agentMd: 'hand edit\n'});

      expect([for (final f in found) '${f.path}:${f.line}'], ['$_agentMd:1']);
      expect(
        found.single.message,
        '$_agentMd differs from what the running CLI writes; $_migrate',
      );
    },
  );

  test(
    '$_stale Output: an import block without AGENT.md is one finding',
    () async {
      final found = await _staleOf({'CLAUDE.md': 'x\n${_imports()}'});

      expect([for (final f in found) '${f.path}:${f.line}'], ['CLAUDE.md:2']);
      expect(
        found.single.message,
        'the block imports $_agentMd, which is missing; $_migrate',
      );
    },
  );

  test(
    '$_stale Output: malformed marker lines are one finding on the first marker',
    () async {
      final found = await _staleOf({
        'CLAUDE.md': 'x\n<!-- BEGIN specstone v1.0.0 -->\nno end\n',
        _agentMd: agentMdText,
      });

      expect([for (final f in found) '${f.path}:${f.line}'], ['CLAUDE.md:2']);
      expect(
        found.single.message,
        'the Specstone marker lines are malformed and `specstone migrate` '
        'refuses the file; repair the block by hand',
      );
    },
  );

  test(
    '$_stale E04: a file with no block, and no rules file, is no finding',
    () async {
      expect(
        await _staleOf({'CLAUDE.md': 'Owner only\n', '.cursor/x': ''}),
        isEmpty,
      );
    },
  );

  test('$_stale R56: an unclosed fence says close the fence that opens on this '
      'line', () async {
    final found = await _staleOf({
      'CLAUDE.md': 'x\n```\ncode\n${_imports()}',
      _agentMd: agentMdText,
    });

    expect([for (final f in found) '${f.path}:${f.line}'], ['CLAUDE.md:2']);
    expect(found.single.message, _fenceOpen);
  });

  test(
    '$_stale R56: an unclosed fence after a well-formed block still wins the '
    'line',
    () async {
      final found = await _staleOf({
        'CLAUDE.md': '${_imports()}x\n```\ncode\n',
        _agentMd: agentMdText,
      });

      expect([for (final f in found) '${f.path}:${f.line}'], ['CLAUDE.md:6']);
      expect(found.single.message, _fenceOpen);
    },
  );

  test(
    '$_stale E11: a hand-edited rules frontmatter is one finding on line 1',
    () async {
      final found = await _staleOf({
        '.cursor/rules/specstone.mdc': cursorRulesText(
          cliVersion: specstoneVersion,
        ).replaceFirst('alwaysApply: true', 'alwaysApply: false'),
        _agentMd: agentMdText,
      });

      expect(
        [for (final f in found) '${f.path}:${f.line}'],
        ['.cursor/rules/specstone.mdc:1'],
      );
    },
  );

  group('$_print E10: waitsFor by drift kind', () {
    test(
      'a stale block waits for the Owner, `migrate` running on their word',
      () async {
        final found = await _staleOf({
          'AGENTS.md': 'top\n${_inline().replaceFirst('Rules', 'Rule')}',
          _agentMd: agentMdText,
        });

        expect(found.single.waitsFor, WaitsFor.owner);
        expect(
          found.single.textLines.single,
          endsWith(' (waits for the Owner)'),
        );
      },
    );

    test('a stale AGENT.md waits for the Owner', () async {
      final found = await _staleOf({_agentMd: 'hand edit\n'});

      expect(found.single.waitsFor, WaitsFor.owner);
    });

    test('a missing AGENT.md waits for the Owner', () async {
      final found = await _staleOf({'CLAUDE.md': 'x\n${_imports()}'});

      expect(found.single.waitsFor, WaitsFor.owner);
    });

    test('an unlisted repository top waits for the Owner', () async {
      final found = await _staleBeside();

      expect(found.single.waitsFor, WaitsFor.owner);
    });

    test('malformed marker lines wait for the Agent, a hand repair', () async {
      final found = await _staleOf({
        'CLAUDE.md': 'x\n<!-- BEGIN specstone v1.0.0 -->\nno end\n',
        _agentMd: agentMdText,
      });

      expect(found.single.waitsFor, WaitsFor.agent);
      expect(found.single.toJson()['waitsFor'], 'agent');
      expect(
        found.single.textLines.single,
        isNot(contains('waits for the Owner)')),
      );
    });

    test('an open code fence waits for the Agent', () async {
      final found = await _staleOf({
        'CLAUDE.md': 'x\n```\ncode\n${_imports()}',
        _agentMd: agentMdText,
      });

      expect(found.single.waitsFor, WaitsFor.agent);
    });
  });

  group('a repository top', () {
    test(
      '$_stale E13: a top a code entry reaches and the config does not list is '
      'one finding on the top folder',
      () async {
        final found = await _staleBeside();

        expect(found, hasLength(1));
        expect(found.single.path, 'other');
        expect(found.single.line, 1);
        expect(
          found.single.message,
          'the repository top is not in agent_file_roots yet; $_migrate',
        );
      },
    );

    test(
      '$_stale E13: a top that code_root reaches is also unlisted',
      () async {
        final found = await _staleBeside(
          config: 'code_root: other\n',
          codeEntry: false,
        );

        expect([for (final f in found) f.path], ['other']);
      },
    );

    test('$_stale R99: a top outside the project root, which no run writes, '
        'is no finding, listed or not', () async {
      expect(await _staleBeside(outside: true), isEmpty);
      expect(
        await _staleBeside(
          config: 'code_root: ../other\n',
          codeEntry: false,
          outside: true,
        ),
        isEmpty,
      );
      expect(
        await _staleBeside(
          config: 'agent_file_roots:\n  - ../other\n',
          otherFiles: {'AGENTS.md': _inline().replaceFirst('Rules', 'Rule')},
          outside: true,
        ),
        isEmpty,
      );
    });

    test('$_stale E12: a listed top with a hand-edited block is one finding on '
        'its file', () async {
      final found = await _staleBeside(
        config: 'agent_file_roots:\n  - other\n',
        otherFiles: {'AGENTS.md': _inline().replaceFirst('Rules', 'Rule')},
      );

      expect(found, hasLength(1));
      expect(found.single.path, 'other/AGENTS.md');
      expect(found.single.line, 1);
      expect(
        found.single.message,
        'the Specstone block differs from what the running CLI writes; '
        '$_migrate',
      );
    });

    test(
      '$_stale E12: a listed top whose block is as written has no finding',
      () async {
        final found = await _staleBeside(
          config: 'agent_file_roots:\n  - other\n',
          otherFiles: {'AGENTS.md': _inline()},
        );

        expect(found, isEmpty);
      },
    );
  });

  group('skill and agent files', () {
    const codexToml = '.codex/agents/specstone-sdd-engineer.toml';
    const procedure =
        '.agents/skills/specstone-sync-sdd/references/procedure.md';
    const planAgent = '.claude/agents/specstone-plan-engineer.md';

    /// The `path:line` of each finding of a check over the fixture project
    /// holding every shipped file but for [changes], where a null text drops
    /// the file.
    Future<List<Finding>> staleSkillFiles(
      Map<String, String?> changes, {
      String? target,
    }) async {
      final files = {...skillFileTexts(), ...changes}
        ..removeWhere((_, text) => text == null);
      final project = await writeCheckProject(
        extra: {for (final e in files.entries) e.key: e.value!},
      );
      return [
        for (final f in checkOf(project, target: target).findings)
          if (f.kind == FindingKind.agentBlockStale) f,
      ];
    }

    String where(Finding f) => '${f.path}:${f.line}';

    test('files as the CLI writes them have no finding', () async {
      expect(await staleSkillFiles({}), isEmpty);
    });

    test('a stale settings file is one finding the Owner clears with '
        'migrate', () async {
      final found = await staleSkillFiles({settingsFilePath: '{}\n'});

      expect(found.map(where), ['$settingsFilePath:1']);
      expect(found.single.waitsFor, WaitsFor.owner);
      expect(found.single.message, _settingsStale);
    });

    test('a missing settings file is one finding the Owner clears with '
        'migrate', () async {
      final found = await staleSkillFiles({settingsFilePath: null});

      expect(found.map(where), ['$settingsFilePath:1']);
      expect(found.single.waitsFor, WaitsFor.owner);
      expect(found.single.message, _settingsMissing);
    });

    test('a malformed settings file is one finding the Agent repairs by '
        'hand, and check does not throw', () async {
      final found = await staleSkillFiles({settingsFilePath: '{'});

      expect(found.map(where), ['$settingsFilePath:1']);
      expect(found.single.waitsFor, WaitsFor.agent);
      expect(found.single.message, _settingsMalformed);
    });

    test('a hand-edited Codex agent file is one finding on '
        'line 1', () async {
      final found = await staleSkillFiles({codexToml: 'hand edit\n'});

      expect(found.map(where), ['$codexToml:1']);
      expect(found.single.name, isNull);
      expect(found.single.waitsFor, WaitsFor.owner);
      expect(
        found.single.message,
        'the Specstone skill or agent file differs from what the running CLI '
        'writes; $_migrate',
      );
    });

    test('a file missing inside a skill folder is one finding at '
        'its path', () async {
      expect(skillFileTexts(), contains(procedure));

      final found = await staleSkillFiles({procedure: null});

      expect(found.map(where), ['$procedure:1']);
      expect(found.single.waitsFor, WaitsFor.owner);
      expect(
        found.single.message,
        'the Specstone skill or agent file is missing; $_migrate',
      );
    });

    test('an agent file missing while the skills folder is '
        'filled is one finding', () async {
      expect(skillFileTexts(), contains(planAgent));

      final found = await staleSkillFiles({planAgent: null});

      expect(found.map(where), ['$planAgent:1']);
    });

    test('both Claude Code folders emptied give no finding for '
        'them', () async {
      final emptied = {
        for (final path in skillFileTexts().keys)
          if (path.startsWith('.claude/')) path: null,
      };
      expect(emptied, isNotEmpty);

      expect(await staleSkillFiles(emptied), isEmpty);
    });

    test('an entry the CLI does not ship is one finding at the '
        'entry', () async {
      final found = await staleSkillFiles({
        '.claude/skills/specstone-old/SKILL.md': 'old\n',
      });

      expect(found.map(where), ['.claude/skills/specstone-old:1']);
      expect(found.single.waitsFor, WaitsFor.owner);
      expect(
        found.single.message,
        'the running CLI does not ship this Specstone file; $_migrate',
      );
    });

    test('an entry not named for Specstone has no finding', () async {
      expect(
        await staleSkillFiles({'.claude/skills/own-skill/SKILL.md': 'own\n'}),
        isEmpty,
      );
    });

    test('a check with a target reports no skill or agent '
        'file', () async {
      expect(
        await staleSkillFiles({codexToml: 'hand edit\n'}, target: 'login'),
        isEmpty,
      );
    });
  });

  group('$_stale E27 to E33: the settings file', () {
    const codexToml = '.codex/agents/specstone-sdd-engineer.toml';

    Future<List<Finding>> settingsOf(
      String? text, {
      Map<String, String?> more = const {},
    }) async {
      final files = {...skillFileTexts(), settingsFilePath: text, ...more}
        ..removeWhere((_, value) => value == null);
      return _staleOf({for (final e in files.entries) e.key: e.value!});
    }

    Future<List<Finding>> settingsAtTop(String? text) async {
      final files = {...skillFileTexts(), settingsFilePath: text}
        ..removeWhere((_, value) => value == null);
      return _staleBeside(
        config: 'agent_file_roots:\n  - other\n',
        otherFiles: {for (final e in files.entries) e.key: e.value!},
      );
    }

    for (final (place, check) in <(String, _SettingsCheck)>[
      ('the project root', settingsOf),
      ('a listed top', settingsAtTop),
    ]) {
      final prefix = place == 'the project root' ? '' : 'other/';

      group('at $place', () {
        test('E27: exactly the one group has no finding', () async {
          expect(await check(settingsFileText), isEmpty);
          expect(await check(_settings()), isEmpty);
        });

        test(
          'E28: an old matcher or an added timeout is one finding',
          () async {
            for (final text in [
              _settings(matcher: 'Edit'),
              _settings(timeout: 5),
              '{}',
            ]) {
              final found = await check(text);

              expect(
                [for (final f in found) '${f.path}:${f.line}'],
                ['$prefix$settingsFilePath:1'],
              );
              expect(found.single.message, _settingsStale);
              expect(found.single.waitsFor, WaitsFor.owner);
            }
          },
        );

        test('E29: a missing file is one finding', () async {
          final found = await check(null);

          expect(
            [for (final f in found) '${f.path}:${f.line}'],
            ['$prefix$settingsFilePath:1'],
          );
          expect(found.single.message, _settingsMissing);
          expect(found.single.waitsFor, WaitsFor.owner);
        });

        test('E30: a file that is not one JSON object is one finding the '
            'Agent repairs', () async {
          for (final text in ['{', '[]', '']) {
            final found = await check(text);

            expect(
              [for (final f in found) '${f.path}:${f.line}'],
              ['$prefix$settingsFilePath:1'],
            );
            expect(found.single.message, _settingsMalformed);
            expect(found.single.waitsFor, WaitsFor.agent);
          }
        });

        test(
          'E31: a handler the binary does not write is one finding',
          () async {
            final found = await check(
              _settings(args: ['hook', 'session-start']),
            );

            expect(found.single.message, _settingsStale);
          },
        );

        test('E33: the Owner keys, groups, and handlers are never '
            'compared', () async {
          expect(
            await check(
              _settings(
                owner: {
                  'permissions': {
                    'allow': ['Bash(ls)'],
                  },
                },
                ownerGroups: [
                  {
                    'matcher': 'Bash',
                    'hooks': [
                      {'type': 'command', 'command': 'own-tool'},
                    ],
                  },
                ],
              ),
            ),
            isEmpty,
          );
        });
      });
    }

    test(
      'E32: the Claude Code group opted out is read for no finding',
      () async {
        final opted = {
          for (final path in skillFileTexts().keys)
            if (path.startsWith('.claude/') && path != settingsFilePath)
              path: null,
        };

        expect(await settingsOf('{', more: opted), isEmpty);
        expect(await settingsOf(null, more: opted), isEmpty);
      },
    );

    test('E08: a check with a target reports no settings finding', () async {
      final files = {...skillFileTexts(), settingsFilePath: '{}'};
      final project = await writeCheckProject(extra: files);

      expect([
        for (final f in checkOf(project, target: 'login').findings)
          if (f.kind == FindingKind.agentBlockStale) f,
      ], isEmpty);
    });

    test('a hand edit to one skill file keeps its message', () async {
      final found = await settingsOf(
        settingsFileText,
        more: {codexToml: 'hand edit\n'},
      );

      expect(found.map((f) => f.path), [codexToml]);
    });
  });

  group('$_stale E34 to E37: the fix follows the stamp', () {
    const codexToml = '.codex/agents/specstone-sdd-engineer.toml';
    const skillLead =
        'the Specstone skill or agent file differs from what the running CLI '
        'writes';
    const blockLead =
        'the Specstone block differs from what the running CLI writes';
    const settingsLead =
        '.claude/settings.json lacks the Specstone hook or holds one that '
        'differs from what the running CLI writes';
    final staleBlock = 'top\n${_inline().replaceFirst('Rules', 'Rule')}';

    /// The findings of a check over every shipped file but for [changes],
    /// the config stamped [version] when it is not null.
    Future<List<Finding>> findingsOf(
      Map<String, String?> changes, {
      String? version,
    }) async {
      final files = {
        ...skillFileTexts(),
        _agentMd: agentMdText,
        if (version != null) '.specstone/config.yaml': _stamped(version),
        ...changes,
      }..removeWhere((_, text) => text == null);
      return _staleOf({for (final e in files.entries) e.key: e.value!});
    }

    for (final (row, version) in <(String, String?)>[
      ('E34 no stamp', null),
      ('E34 a stamp below the running Version', '0.0.1'),
      ('E35 a stamp equal to the running Version', specstoneVersion),
    ]) {
      test('$row: a block, a skill file, and the settings file name '
          'migrate', () async {
        final found = await findingsOf({
          'AGENTS.md': staleBlock,
          codexToml: 'hand edit\n',
          settingsFilePath: '{}',
        }, version: version);

        expect(
          {for (final f in found) f.path: f.message},
          {
            'AGENTS.md': '$blockLead; $_migrate',
            codexToml: '$skillLead; $_migrate',
            settingsFilePath: _settingsStale,
          },
        );
        expect(found.map((f) => f.waitsFor), everyElement(WaitsFor.owner));
      });
    }

    test('E36: a stamp above the running Version names the stamp, the '
        'running Version, and upgrade', () async {
      final found = await findingsOf({
        'AGENTS.md': staleBlock,
        codexToml: 'hand edit\n',
        settingsFilePath: '{}',
      }, version: '99.0.0');

      expect(
        {for (final f in found) f.path: f.message},
        {
          'AGENTS.md': _newer(blockLead, '99.0.0'),
          codexToml: _newer(skillLead, '99.0.0'),
          settingsFilePath: _newer(settingsLead, '99.0.0'),
        },
      );
      expect(found.map((f) => f.waitsFor), everyElement(WaitsFor.owner));
    });

    test('E36: a missing file and an unlisted top name upgrade too', () async {
      final missing = await findingsOf({
        settingsFilePath: null,
        _agentMd: null,
        'CLAUDE.md': 'x\n${_imports()}',
      }, version: '99.0.0');

      expect(
        {for (final f in missing) f.path: f.message},
        {
          settingsFilePath: _newer(
            '.claude/settings.json is missing',
            '99.0.0',
          ),
          'CLAUDE.md': _newer(
            'the block imports $_agentMd, which is missing',
            '99.0.0',
          ),
        },
      );
    });

    test('E36: the hand-fix messages keep their text and wait for the '
        'Agent', () async {
      final found = await findingsOf({
        'CLAUDE.md': 'x\n<!-- BEGIN specstone v1.0.0 -->\nno end\n',
        'AGENTS.md': 'x\n```\ncode\n${_inline()}',
        settingsFilePath: '{',
      }, version: '99.0.0');

      expect(
        {for (final f in found) f.path: f.message},
        {
          'CLAUDE.md': _markersMalformed,
          'AGENTS.md': _fenceOpen,
          settingsFilePath: _settingsMalformed,
        },
      );
      expect(found.map((f) => f.waitsFor), everyElement(WaitsFor.agent));
    });

    test('the hand-fix messages are the same under every stamp', () async {
      for (final version in <String?>[null, '0.0.1', specstoneVersion]) {
        final found = await findingsOf({
          'CLAUDE.md': 'x\n<!-- BEGIN specstone v1.0.0 -->\nno end\n',
          settingsFilePath: '{',
        }, version: version);

        expect(
          {for (final f in found) f.path: f.message},
          {
            'CLAUDE.md': _markersMalformed,
            settingsFilePath: _settingsMalformed,
          },
        );
      }
    });

    test('E37: a stamp above the running Version over matching files has no '
        'finding', () async {
      expect(await findingsOf({}, version: '99.0.0'), isEmpty);
    });
  });
}

typedef _SettingsCheck = Future<List<Finding>> Function(String? text);
