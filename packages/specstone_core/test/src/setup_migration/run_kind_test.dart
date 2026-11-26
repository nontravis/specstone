import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:specstone_core/src/release_version.dart';
import 'package:specstone_core/src/setup_migration/agent_files.dart';
import 'package:specstone_core/src/setup_migration/migrate_fault.dart';
import 'package:specstone_core/src/setup_migration/run_kind.dart';
import 'package:specstone_core/src/setup_migration/upgrade_plan.dart';
import 'package:specstone_core/src/shipped_generators.dart'
    show shippedGenerators;
import 'package:specstone_core/src/templates/template_fault.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:specstone_core/src/version.dart';
import 'package:test/test.dart';

import '../../helpers/record_fixture.dart' show oneTargetConfig, twinConfig;
import '../../helpers/shipped_pins.dart';
import '../../helpers/skill_files.dart';
import '../../helpers/temp_tree.dart';
import '../../helpers/upgrade_fixture.dart';

final String _journal = jsonEncode(
  const MoveJournal([
    CommitStep(message: 'move', paths: ['a'], base: 'abc'),
  ]).toJson(),
);

const _laidOutFeature = '## Problem\n\nn\n\n## Benefit hypothesis\n\ng\n';
const _offLayoutFeature = '## Benefit hypothesis\n\ng\n\n\n## Problem\n\nn\n';

RunKind _choose(Directory root, {Directory? home, bool hasAdds = false}) =>
    chooseRun(
      root,
      templates: TemplateResolver(),
      homeDirectory: home,
      hasAdds: hasAdds,
    );

Matcher _pinNewer() => throwsA(
  isA<TemplateFault>()
      .having((f) => f.code, 'code', FaultCode.packPinNewer)
      .having((f) => f.key, 'key', 'packs.prd-core'),
);

Matcher _agentFilesNewer({String stamp = '99.0.0'}) => throwsA(
  isA<MigrateFault>()
      .having((f) => f.code, 'code', MigrateFaultCode.agentFilesNewer)
      .having((f) => f.exitStatus, 'exit status', 78)
      .having((f) => f.file, 'file', '.specstone/config.yaml')
      .having((f) => f.key, 'key', 'agent_files_version')
      .having(
        (f) => f.message,
        'message',
        'the agent files were written by Specstone $stamp, and this '
            'Specstone is $specstoneVersion; run specstone upgrade, then run '
            'specstone migrate again',
      ),
);

Future<Directory> _project(Map<String, String> files) async {
  final base = await writeTree({
    for (final entry in files.entries) 'proj/${entry.key}': entry.value,
  });
  return Directory.fromUri(base.uri.resolve('proj/'));
}

String _inline() => inlineBlock(cliVersion: specstoneVersion);

void main() {
  test('a pending migrate journal is resume', () async {
    final root = await writeTree({
      MoveJournal.journalPath: _journal,
      '.specstone/config.yaml': shippedPinsConfig(),
    });

    expect(_choose(root), RunKind.resume);
  });

  test('a config beside a legacy context doc chooses by the pins '
      'alone', () async {
    final equal = await writeTree({
      '.specstone/config.yaml': shippedPinsConfig(),
      'docs/prds/d01_context.md': '# D-01\n',
    });
    final home = await acmeHome();
    final older = await writeTree({
      '.specstone/config.yaml': '${shippedPinsConfig()}$acmeOldPinLine',
      'docs/prds/d01_context.md': '# D-01\n',
    });

    expect(_choose(equal), RunKind.none);
    expect(_choose(older, home: home), RunKind.upgrade);
  });

  test('pins equal to the carried versions '
      'are none', () async {
    final root = await writeTree({
      '.specstone/config.yaml': shippedPinsConfig(),
    });

    expect(_choose(root), RunKind.none);
  });

  test('an add makes the run an upgrade with every pin equal', () async {
    final root = await writeTree({
      '.specstone/config.yaml': shippedPinsConfig(),
    });

    expect(_choose(root, hasAdds: true), RunKind.upgrade);
  });

  test('an add leaves a pending journal as it is', () async {
    final journal = await writeTree({
      MoveJournal.journalPath: _journal,
      '.specstone/config.yaml': shippedPinsConfig(),
    });

    expect(_choose(journal, hasAdds: true), RunKind.resume);
  });

  test('pins equal and every typed doc laid out is none', () async {
    final root = await writeTree({
      '.specstone/config.yaml': shippedPinsConfig(),
      'docs/prds/features/f01_a/FEATURE.md': _laidOutFeature,
    });

    expect(_choose(root), RunKind.none);
  });

  test('pins equal and one typed doc off its layout is upgrade', () async {
    final root = await writeTree({
      '.specstone/config.yaml': shippedPinsConfig(),
      'docs/prds/features/f01_a/FEATURE.md': _laidOutFeature,
      'docs/prds/features/f02_b/FEATURE.md': _offLayoutFeature,
    });

    expect(_choose(root), RunKind.upgrade);
  });

  test('a doc format refuses alone is none', () async {
    final root = await writeTree({
      '.specstone/config.yaml': shippedPinsConfig(),
      'docs/prds/features/f01_a/FEATURE.md': '## Notes\nx   \n',
    });

    expect(_choose(root), RunKind.none);
  });

  test(
    'a newer pin refuses pack_pin_newer, alone or beside an older pin',
    () async {
      final alone = await writeTree({
        '.specstone/config.yaml': 'packs:\n  prd-core: 9.0.0\n',
      });
      final home = await acmeHome();
      final beside = await writeTree({
        '.specstone/config.yaml': 'packs:\n  prd-core: 9.0.0\n$acmeOldPinLine',
      });

      expect(() => _choose(alone), _pinNewer());
      expect(() => _choose(beside, home: home), _pinNewer());
    },
  );

  test('with two newer pins the refusal names the earlier '
      'pack in code point order', () async {
    final root = await writeTree({
      '.specstone/config.yaml':
          'packs:\n  software-tech: 9.0.0\n  prd-core: 9.0.0\n',
    });

    expect(() => _choose(root), _pinNewer());
  });

  group('an agent_files_version above the running Version', () {
    String config({String pins = '', String stamp = '99.0.0'}) =>
        '${pins.isEmpty ? shippedPinsConfig() : pins}'
        'agent_files_version: $stamp\n';

    test('refuses agent_files_newer with every pin equal', () async {
      final root = await writeTree({'.specstone/config.yaml': config()});

      expect(() => _choose(root), _agentFilesNewer());
    });

    test('a dev stamp of the next minor refuses agent_files_newer with every '
        'pin equal', () async {
      final running = ReleaseVersion.tryParse(specstoneVersion)!;
      final stamp = '${running.major}.${int.parse(running.minor) + 1}.0-dev.39';
      final root = await writeTree({
        '.specstone/config.yaml': config(stamp: stamp),
      });

      expect(() => _choose(root), _agentFilesNewer(stamp: stamp));
    });

    group('a dev stamp of 1.3.0-dev.39 against a running Version', () {
      for (final (running, isNewer) in [
        ('1.2.0', true),
        ('1.2.0-beta.1', true),
        ('1.3.0-beta.1', true),
        ('1.3.0-dev.38', true),
        ('1.3.0-dev.39', false),
        ('1.3.0-dev.40', false),
        ('1.3.0-rc.1', false),
        ('1.3.0', false),
        ('1.4.0-dev.1', false),
      ]) {
        test('$running ${isNewer ? 'refuses' : 'accepts'}', () {
          final stamp = ReleaseVersion.tryParse('1.3.0-dev.39')!;
          final version = ReleaseVersion.tryParse(running)!;

          expect(
            () => requireAgentFilesNotNewer(stamp, version),
            isNewer
                ? throwsA(
                    isA<MigrateFault>()
                        .having(
                          (f) => f.code,
                          'code',
                          MigrateFaultCode.agentFilesNewer,
                        )
                        .having(
                          (f) => f.message,
                          'message',
                          'the agent files were written by Specstone '
                              '1.3.0-dev.39, and this Specstone is $running; '
                              'run specstone upgrade, then run specstone '
                              'migrate again',
                        ),
                  )
                : returnsNormally,
          );
        });
      }

      test('no stamp accepts', () {
        expect(
          () => requireAgentFilesNotNewer(
            null,
            ReleaseVersion.tryParse('1.2.0')!,
          ),
          returnsNormally,
        );
      });
    });

    test('refuses agent_files_newer beside an older pin, where the run '
        'would be upgrade', () async {
      final home = await acmeHome();
      final root = await writeTree({
        '.specstone/config.yaml': config(
          pins: '${shippedPinsConfig(['prd-core'])}$acmeOldPinLine',
        ),
      });

      expect(() => _choose(root, home: home), _agentFilesNewer());
    });

    test('refuses agent_files_newer over agent files that differ', () async {
      final root = await writeTree({
        '.specstone/config.yaml': config(),
        '.specstone/AGENT.md': 'other bytes\n',
      });

      expect(() => _choose(root), _agentFilesNewer());
    });

    test('a newer pin still refuses first', () async {
      final root = await writeTree({
        '.specstone/config.yaml':
            'packs:\n  prd-core: 9.0.0\nagent_files_version: 99.0.0\n',
      });

      expect(() => _choose(root), _pinNewer());
    });

    test('a stamp equal to the running Version is none', () async {
      final root = await writeTree({
        '.specstone/config.yaml': config(stamp: specstoneVersion),
      });

      expect(_choose(root), RunKind.none);
    });

    test('a stamp below the running Version, or no stamp, is none', () async {
      final below = await writeTree({
        '.specstone/config.yaml': config(stamp: '0.0.1'),
      });
      final absent = await writeTree({
        '.specstone/config.yaml': shippedPinsConfig(),
      });

      expect(_choose(below), RunKind.none);
      expect(_choose(absent), RunKind.none);
    });
  });

  test('a personal pack pinned below its home-folder version '
      'is upgrade', () async {
    final home = await acmeHome();
    final root = await writeTree({
      '.specstone/config.yaml':
          '${shippedPinsConfig(['prd-core'])}$acmeOldPinLine',
    });

    expect(_choose(root, home: home), RunKind.upgrade);
  });

  group('agent file drift with every pin equal', () {
    test('a stale block is an upgrade', () async {
      final root = await _project({
        '.specstone/config.yaml': shippedPinsConfig(),
        '.specstone/AGENT.md': agentMdText,
        'AGENTS.md': 'top\n${_inline().replaceFirst('Rules', 'Rule')}',
      });

      expect(_choose(root), RunKind.upgrade);
    });

    test('agent files as the CLI writes them are none', () async {
      final root = await _project({
        '.specstone/config.yaml': shippedPinsConfig(),
        '.specstone/AGENT.md': agentMdText,
        'AGENTS.md': _inline(),
      });

      expect(_choose(root), RunKind.none);
    });

    test('a skill file that differs is an upgrade', () async {
      final texts = skillFileTexts();
      final path = texts.keys.first;
      final root = await _project({
        '.specstone/config.yaml': shippedPinsConfig(),
        ...texts,
        path: '${texts[path]}hand edit\n',
      });

      expect(_choose(root), RunKind.upgrade);
    });

    test('an entry missing from a group in use is an '
        'upgrade', () async {
      final texts = skillFileTexts();
      final root = await _project({
        '.specstone/config.yaml': shippedPinsConfig(),
        for (final MapEntry(:key, :value) in texts.entries)
          if (key != texts.keys.first) key: value,
      });

      expect(_choose(root), RunKind.upgrade);
    });

    test('an unshipped specstone entry is an upgrade', () async {
      final root = await _project({
        '.specstone/config.yaml': shippedPinsConfig(),
        ...skillFileTexts(),
        '.claude/skills/specstone-old/SKILL.md': 'old\n',
      });

      expect(_choose(root), RunKind.upgrade);
    });

    test('every skill and agent file as the CLI writes '
        'it is none', () async {
      final root = await _project({
        '.specstone/config.yaml': shippedPinsConfig(),
        ...skillFileTexts(),
      });

      expect(_choose(root), RunKind.none);
    });

    test('only a stale settings file is an upgrade', () async {
      final root = await _project({
        '.specstone/config.yaml': shippedPinsConfig(),
        ...skillFileTexts(),
        settingsFilePath:
            '{"hooks":{"PostToolUse":[{"matcher":"Write","hooks":[{"type":'
            '"command","command":"specstone","args":["hook","post-edit"]}]}]}}',
      });

      expect(_choose(root), RunKind.upgrade);
    });

    test('only a missing settings file is an upgrade', () async {
      final texts = skillFileTexts();
      final root = await _project({
        '.specstone/config.yaml': shippedPinsConfig(),
        for (final MapEntry(:key, :value) in texts.entries)
          if (key != settingsFilePath) key: value,
      });

      expect(_choose(root), RunKind.upgrade);
    });

    test('a current settings file leaves none', () async {
      final root = await _project({
        '.specstone/config.yaml': shippedPinsConfig(),
        ...skillFileTexts(),
      });

      expect(_choose(root), RunKind.none);
    });

    test('a malformed settings file is an upgrade, never a throw', () async {
      final root = await _project({
        '.specstone/config.yaml': shippedPinsConfig(),
        ...skillFileTexts(),
        settingsFilePath: '{',
      });

      expect(_choose(root), RunKind.upgrade);
    });

    test('a stale settings file of an opted-out group is none', () async {
      final root = await _project({
        '.specstone/config.yaml': shippedPinsConfig(),
        '.claude/skills/own-skill/SKILL.md': 'own\n',
        settingsFilePath: '{',
      });

      expect(_choose(root), RunKind.none);
    });

    test('only a stale Codex hooks file is an upgrade', () async {
      final root = await _project({
        '.specstone/config.yaml': shippedPinsConfig(),
        ...skillFileTexts(),
        codexHooksFilePath:
            '{"hooks":{"PreToolUse":[{"matcher":"Bash|PowerShell","hooks":'
            '[{"type":"command","command":"specstone hook pre-shell"}]}]}}',
      });

      expect(_choose(root), RunKind.upgrade);
    });

    test('only a missing Codex hooks file in a Codex group in use is an '
        'upgrade', () async {
      final root = await _project({
        '.specstone/config.yaml': shippedPinsConfig(),
        for (final MapEntry(:key, :value) in skillFileTexts().entries)
          if (key != codexHooksFilePath) key: value,
      });

      expect(_choose(root), RunKind.upgrade);
    });

    test(
      'a stale Codex hooks file of an opted-out Codex group is none',
      () async {
        final root = await _project({
          '.specstone/config.yaml': shippedPinsConfig(),
          '.codex/agents/own-agent.toml': 'own\n',
          codexHooksFilePath: '{',
        });

        expect(_choose(root), RunKind.none);
      },
    );

    test('a group no folder of which holds a specstone '
        'entry is opted out, none', () async {
      final root = await _project({
        '.specstone/config.yaml': shippedPinsConfig(),
        '.claude/skills/own-skill/SKILL.md': 'own\n',
      });

      expect(_choose(root), RunKind.none);
    });

    test('an import block naming a missing AGENT.md is an '
        'upgrade', () async {
      final root = await _project({
        '.specstone/config.yaml': shippedPinsConfig(),
        'CLAUDE.md': importBlock(
          cliVersion: specstoneVersion,
          agentMdPath: '.specstone/AGENT.md',
          projectDocPath: 'docs/prds/PROJECT.md',
          goalDocPath: 'docs/prds/GOAL.md',
          featuresDocPath: 'docs/prds/FEATURES.md',
        ),
      });

      expect(_choose(root), RunKind.upgrade);
    });

    test('a repository top the config does not list is an '
        'upgrade', () async {
      final base = await writeTree({
        'proj/.specstone/config.yaml':
            '${shippedPinsConfig()}code_root: other\n',
        'proj/other/.git/HEAD': 'ref\n',
      });

      expect(
        _choose(Directory.fromUri(base.uri.resolve('proj/'))),
        RunKind.upgrade,
      );
    });

    test('a repository top outside the project root, which '
        'no run writes, is none', () async {
      final base = await writeTree({
        'proj/.specstone/config.yaml':
            '${shippedPinsConfig()}code_root: ../other\n',
        'other/.git/HEAD': 'ref\n',
      });

      expect(
        _choose(Directory.fromUri(base.uri.resolve('proj/'))),
        RunKind.none,
      );
    });

    test('a repository top a code entry reaches, found in a '
        'tech stack doc, is an upgrade', () async {
      final base = await writeTree({
        'proj/.specstone/config.yaml': shippedPinsConfig(),
        'proj/docs/specs/TECH_STACK.md':
            '---\ncode:\n  - other/\n---\n# Tech stack\n',
        'proj/other/.git/HEAD': 'ref\n',
      });

      expect(
        _choose(Directory.fromUri(base.uri.resolve('proj/'))),
        RunKind.upgrade,
      );
    });

    test('a repository top the config lists is none', () async {
      final base = await writeTree({
        'proj/.specstone/config.yaml':
            '${shippedPinsConfig()}code_root: other\n'
            'agent_file_roots:\n  - other\n',
        'proj/other/.git/HEAD': 'ref\n',
      });

      expect(
        _choose(Directory.fromUri(base.uri.resolve('proj/'))),
        RunKind.none,
      );
    });

    test('malformed markers are an upgrade, not a refusal', () async {
      final root = await _project({
        '.specstone/config.yaml': shippedPinsConfig(),
        'AGENTS.md': '<!-- BEGIN specstone v1.0.0 -->\nno end line\n',
      });

      expect(_choose(root), RunKind.upgrade);
    });
  });

  group('a second target over a one-target spec tree', () {
    const draftArchitecture = '---\ndraft: true\n---\n# Feedback\n';

    Future<Directory> twinProject(String config, Map<String, String> docs) =>
        writeTree({
          '.specstone/config.yaml': config,
          for (final MapEntry(:key, :value) in docs.entries) 'docs/$key': value,
        });

    test('two targets and a per-target doc at its one-target path are an '
        'upgrade, though every pin is equal', () async {
      final root = await twinProject(twinConfig(), {
        'specs/f02_feedback/ARCHITECTURE.md': draftArchitecture,
      });

      expect(_choose(root), RunKind.upgrade);
    });

    test('a doc already under a target folder is none', () async {
      final root = await twinProject(twinConfig(), {
        'specs/flutter/f02_feedback/ARCHITECTURE.md': draftArchitecture,
      });

      expect(_choose(root), RunKind.none);
    });

    test('a file no per-target doc type matches is none', () async {
      final root = await twinProject(twinConfig(), {
        'specs/INDEX.md': draftArchitecture,
      });

      expect(_choose(root), RunKind.none);
    });

    test('one target, named or not, is none, since the spec root stays '
        'specs/', () async {
      final named = await twinProject(
        '${shippedPinsConfig()}targets:\n  flutter:\n    code_root: ws\n',
        {'specs/f02_feedback/ARCHITECTURE.md': draftArchitecture},
      );
      final unnamed = await twinProject(oneTargetConfig(), {
        'specs/f02_feedback/ARCHITECTURE.md': draftArchitecture,
      });

      expect(_choose(named), RunKind.none);
      expect(_choose(unnamed), RunKind.none);
    });
  });

  group('the layout compare', () {
    test('line endings are set aside, a laid out CRLF doc is none, an off'
        ' layout one is an upgrade', () async {
      String crlf(String text) => text.replaceAll('\n', '\r\n');
      final laid = await writeTree({
        '.specstone/config.yaml': shippedPinsConfig(),
        'docs/prds/features/f01_a/FEATURE.md': crlf(_laidOutFeature),
      });
      final off = await writeTree({
        '.specstone/config.yaml': shippedPinsConfig(),
        'docs/prds/features/f01_a/FEATURE.md': crlf(_offLayoutFeature),
      });

      expect(_choose(laid), RunKind.none);
      expect(_choose(off), RunKind.upgrade);
    });

    test('a generated block keeps its derived text, an off layout line'
        ' outside it still makes an upgrade', () async {
      const block =
          '<!-- specstone:generated feature_catalog (do not edit) -->\n'
          'derived   text  \n\n\n'
          '<!-- specstone:generated end -->\n';
      final inside = await writeTree({
        '.specstone/config.yaml': shippedPinsConfig(),
        'docs/prds/FEATURES.md': '## Features\n\n$block',
      });
      final outside = await writeTree({
        '.specstone/config.yaml': shippedPinsConfig(),
        'docs/prds/FEATURES.md': '## Features\n\n$block\nafter   \n',
      });

      expect(_choose(inside), RunKind.none);
      expect(_choose(outside), RunKind.upgrade);
    });
  });

  group('a stale agent file with every pin equal', () {
    test('.specstone/AGENT.md with other bytes alone is an upgrade whose'
        ' plan holds the agent files step alone', () async {
      final root = await _project({
        '.specstone/config.yaml': shippedPinsConfig(),
        '.specstone/AGENT.md': 'other bytes\n',
      });

      final plan = planUpgradeRun(
        Directory(root.resolveSymbolicLinksSync()),
        templates: TemplateResolver(),
        homeDirectory: null,
        generators: shippedGenerators(),
      );

      expect(_choose(root), RunKind.upgrade);
      expect(
        plan.toText(),
        'pack upgrade: pins unchanged, agent files only\n'
        'commit 2, rewrites:\n'
        '  agent files: 1 files\n',
      );
      expect(plan.lists.agentFiles, ['.specstone/AGENT.md']);
      expect(plan.moves, isEmpty);
    });

    test('an agent file that differs, with its skill files current,'
        ' is an upgrade', () async {
      final texts = skillFileTexts();
      final path = texts.keys.firstWhere(
        (key) => key.startsWith('.claude/agents/'),
      );
      final root = await _project({
        '.specstone/config.yaml': shippedPinsConfig(),
        ...texts,
        path: '${texts[path]}hand edit\n',
      });

      expect(_choose(root), RunKind.upgrade);
    });

    test('an agent file missing, with its skill files present,'
        ' is an upgrade', () async {
      final texts = skillFileTexts();
      final path = texts.keys.firstWhere(
        (key) => key.startsWith('.claude/agents/'),
      );
      final root = await _project({
        '.specstone/config.yaml': shippedPinsConfig(),
        for (final MapEntry(:key, :value) in texts.entries)
          if (key != path) key: value,
      });

      expect(_choose(root), RunKind.upgrade);
    });
  });

  group('a file or top where no run writes', () {
    const stale =
        'Owner\n<!-- BEGIN specstone v0.0.1 -->\nold rules\n'
        '<!-- END specstone -->\n';

    test('an instruction file with no Specstone block, at the root or at'
        ' a listed top, starts no run', () async {
      final atRoot = await _project({
        '.specstone/config.yaml': shippedPinsConfig(),
        'CLAUDE.md': 'Owner rules\n',
      });
      final atTop = await _project({
        '.specstone/config.yaml':
            '${shippedPinsConfig()}code_root: other\n'
            'agent_file_roots:\n  - other\n',
        'other/.git/HEAD': 'ref\n',
        'other/AGENTS.md': 'Owner rules\n',
      });

      expect(_choose(atRoot), RunKind.none);
      expect(_choose(atTop), RunKind.none);
    });

    test('an instruction file linked outside the project root starts'
        ' no run', () async {
      final base = await writeTree({
        'shared/CLAUDE.md': stale,
        'proj/.specstone/config.yaml': shippedPinsConfig(),
      });
      final project = Directory.fromUri(base.uri.resolve('proj/'));
      Link(project.uri.resolve('CLAUDE.md').toFilePath())
          .createSync(base.uri.resolve('shared/CLAUDE.md').toFilePath());

      expect(_choose(project), RunKind.none);
    }, skip: Platform.isWindows ? 'symbolic links need a privilege' : null);

    test('an instruction file linked below a .git entry starts'
        ' no run', () async {
      final project = await _project({
        '.specstone/config.yaml': shippedPinsConfig(),
        '.git/config': stale,
      });
      Link(project.uri.resolve('CLAUDE.md').toFilePath())
          .createSync('.git/config');

      expect(_choose(project), RunKind.none);
    }, skip: Platform.isWindows ? 'symbolic links need a privilege' : null);
  });

  group('the matrix-fold upgrade with every pin equal', () {
    const foldRecord = '.specstone/records/f01_login/IMPLEMENTATION.md';
    const frName = 'email_login/validate_credentials';

    Future<Directory> foldProject({String? coverage, required String row}) =>
        writeTree({
          '.specstone/config.yaml':
              '${shippedPinsConfig()}'
              '${coverage == null ? '' : 'verification_coverage: $coverage\n'}',
          'docs/prds/features/f01_login/FEATURE.md': '# Login\n',
          'docs/prds/features/f01_login/us01_email_login/USER_STORY.md':
              '# Email login\n',
          'docs/prds/features/f01_login/us01_email_login/'
                  'fr01_validate_credentials.md':
              '# Validate credentials\n',
          foldRecord:
              "---\nstatuses:\n  - 'email_login:implemented'\n---\n\n"
              '# Login implementation\n\n## Verification matrix\n\n$row\n',
        });

    test('a per-edge-case row of an FR is upgrade under off and fr', () async {
      for (final coverage in <String?>[null, 'fr']) {
        final root = await foldProject(
          coverage: coverage,
          row: '- $frName E01: `rejects a wrong key`',
        );

        expect(_choose(root), RunKind.upgrade, reason: '$coverage');
      }
    });

    test('edge_case, a story row, and a folded row are none', () async {
      final edgeCase = await foldProject(
        coverage: 'edge_case',
        row: '- $frName E01: `rejects a wrong key`',
      );
      final story = await foldProject(
        coverage: 'fr',
        row: '- email_login E01: `signs in`',
      );
      final folded = await foldProject(
        coverage: 'fr',
        row: '- $frName: `rejects a wrong key`',
      );

      expect(_choose(edgeCase), RunKind.none);
      expect(_choose(story), RunKind.none);
      expect(_choose(folded), RunKind.none);
    });
  });
}
