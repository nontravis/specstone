// The test names and expected texts are plan literals kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/setup_migration/agent_files.dart';
import 'package:specstone_core/src/version.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';

const _stale =
    'consistency_check/find_template_breaks/report_stale_agent_blocks';
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
}
