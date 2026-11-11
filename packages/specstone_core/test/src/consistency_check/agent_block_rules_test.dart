// The test names and expected texts are plan literals kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:io';

import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/setup_migration/agent_files.dart';
import 'package:specstone_core/src/version.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/shipped_pins.dart';
import '../../helpers/temp_tree.dart';

const _stale =
    'consistency_check/find_template_breaks/report_stale_agent_blocks';
const _print = 'consistency_check/find_template_breaks/print_findings';
const _migrate = 'run `specstone migrate`';
const _agentMd = '.specstone/AGENT.md';

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
    expect(
      found.single.message,
      'the code fence that opens on this line is unclosed and '
      '`specstone migrate` refuses the file; close the code fence that '
      'opens on this line',
    );
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
      expect(
        found.single.message,
        'the code fence that opens on this line is unclosed and '
        '`specstone migrate` refuses the file; close the code fence that '
        'opens on this line',
      );
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
}
