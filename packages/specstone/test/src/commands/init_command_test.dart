import 'dart:io';

import 'package:specstone_core/src/setup_migration/host_render.dart';
import 'package:specstone_core/src/templates/shipped_pack_files.dart'
    show shippedPackVersions;
import 'package:test/test.dart';

import '../../../../specstone_core/test/helpers/git_repo.dart';
import '../../../../specstone_core/test/helpers/legacy_fixture.dart';
import '../../../../specstone_core/test/helpers/shipped_pins.dart';
import '../../../../specstone_core/test/helpers/skill_files.dart';
import '../../../../specstone_core/test/helpers/temp_tree.dart';
import '../../helpers/write_runner.dart';

String _configLine() {
  final versions = shippedPackVersions();
  return 'created .specstone/config.yaml: '
      'prd-core ${versions['prd-core']}, '
      'software-tech ${versions['software-tech']}\n';
}

/// Returns the hash on the `plan <hash>` line `migrate --dry-run` prints in
/// [root].
Future<String> _dryRunPlanHash(Directory root) async {
  final (:runner, :out, :err) = writeRunner(root);
  expect(await runner.run(['migrate', '--dry-run']), 0);
  final lines = out.toString().split('\n');
  return lines[lines.length - 3].substring('plan '.length);
}

void main() {
  test('list --draft lists every doc init created', () async {
    final root = await writeTree({'keep.txt': 'x\n'});
    final (:runner, :out, :err) = writeRunner(root);
    await runner.run(['init']);
    expect(out.toString(), endsWith(_configLine()));

    final listed = writeRunner(root);
    final listRunner = listed.runner;
    final listOut = listed.out;
    final listErr = listed.err;
    for (final type in [
      'project',
      'goal',
      'glossary',
      'features',
      'gnfr',
      'tech_stack',
    ]) {
      expect(await listRunner.run(['list', type, '--draft']), 0, reason: type);
      expect(listOut.toString(), contains('$type ($type) — $type · draft · '));
      listOut.clear();
    }
    expect(listErr.toString(), isEmpty);
  });

  test('init prints '
      'the agent files before the config line', () async {
    final root = await writeTree({'CLAUDE.md': "Owner's rules\n"});
    final (:runner, :out, :err) = writeRunner(root);

    expect(await runner.run(['init']), 0);

    expect(
      out.toString(),
      endsWith(
        'created .specstone/AGENT.md\n'
        'updated CLAUDE.md\n'
        '${skillCountLines().join('\n')}\n'
        '${_configLine()}',
      ),
    );
    for (final file in renderHostFiles()) {
      expect(
        File('${root.path}/${file.path}').readAsStringSync(),
        file.text,
        reason: file.path,
      );
    }
  });

  test('init prints created for a new settings file and updated for an '
      'existing one', () async {
    final fresh = await writeTree({'keep.txt': 'x\n'});
    final existing = await writeTree({'.claude/settings.json': '{}\n'});
    final first = writeRunner(fresh);
    final second = writeRunner(existing);

    expect(await first.runner.run(['init']), 0);
    expect(await second.runner.run(['init']), 0);

    expect(first.out.toString(), contains('\ncreated .claude/settings.json\n'));
    expect(
      second.out.toString(),
      contains('\nupdated .claude/settings.json\n'),
    );
    expect(first.err.toString(), isEmpty);
  });

  test(
    'init refuses a malformed settings file, exit 65, writing nothing',
    () async {
      final root = await writeTree({'.claude/settings.json': '{ not json'});
      final (:runner, :out, :err) = writeRunner(root);

      expect(await runner.run(['init']), 65);

      expect(out.toString(), isEmpty);
      expect(err.toString(), contains('.claude/settings.json'));
      expect(Directory('${root.path}/.specstone').existsSync(), isFalse);
      expect(
        File('${root.path}/.claude/settings.json').readAsStringSync(),
        '{ not json',
      );
    },
  );

  test('init prints no old plugin line, even with the plugin on', () async {
    final root = await writeTree({
      '.claude/settings.json':
          '{"enabledPlugins": {"specstone@specstone": true}}',
    });
    final (:runner, :out, :err) = writeRunner(root);

    expect(await runner.run(['init']), 0);

    expect(err.toString(), isEmpty);
  });

  test(
    'E05: init '
    'refuses a malformed instruction file, exit 65, writing nothing',
    () async {
      final root = await writeTree({
        'CLAUDE.md': '<!-- BEGIN specstone v1.0.0 -->\nno end\n',
      });
      final (:runner, :out, :err) = writeRunner(root);

      expect(await runner.run(['init']), 65);

      expect(out.toString(), isEmpty);
      expect(err.toString(), startsWith('CLAUDE.md:1: '));
      expect(Directory('${root.path}/.specstone').existsSync(), isFalse);
      expect(Directory('${root.path}/docs').existsSync(), isFalse);
    },
  );

  test('init in a configured folder prints the config_exists '
      'line', () async {
    final root = await writeTree({
      '.specstone/config.yaml': shippedPinsConfig(),
    });
    final (:runner, :out, :err) = writeRunner(root);

    final status = await runner.run(['init']);

    expect(status, 64);
    expect(out.toString(), isEmpty);
    expect(
      err.toString(),
      '.specstone/config.yaml: this folder is already a Specstone project; '
      'run specstone migrate to upgrade its packs\n',
    );
  });

  test('ms-r11: init on a legacy folder with neither a terminal nor --yes '
      'exits 77 naming both ways', () async {
    final root = await gitFixture(acmeLegacy);
    final (:runner, :out, :err) = writeRunner(root);

    expect(await runner.run(['init']), 77);
    expect(out.toString(), startsWith('legacy migration: '));
    expect(
      err.toString(),
      'migrate applies only at an interactive terminal, or with --yes after '
      "the Owner's ok in the chat\n",
    );
  }, skip: hasGit ? null : 'git is not available');

  for (final (args, message) in [
    (
      ['--yes'],
      '--yes needs --plan <hash>, the plan line specstone migrate '
          '--dry-run prints.',
    ),
    (['--plan', '1a2b3c4d5e6f'], '--plan goes only with --yes.'),
  ]) {
    test('ms-r11: init ${args.join(' ')} is a usage error, exit 64', () async {
      final root = await writeTree({'keep.txt': 'x\n'});
      final (:runner, :out, :err) = writeRunner(root);

      expect(await runner.run(['init', ...args]), 64);
      expect(out.toString(), isEmpty);
      expect(err.toString(), startsWith('$message\n'));
      expect(Directory('${root.path}/.specstone').existsSync(), isFalse);
    });
  }

  test("ms-r11: init --yes --plan with migrate's dry-run hash applies the "
      'legacy run with no terminal and no prompt', () async {
    final root = await gitFixture(acmeLegacy);
    final hash = await _dryRunPlanHash(root);
    final (:runner, :out, :err) = writeRunner(root);

    expect(await runner.run(['init', '--yes', '--plan', hash]), 0);
    expect(err.toString(), isEmpty);
    expect(out.toString(), isNot(contains('apply? [y/N] ')));
    final subjects = (git(root, ['log', '--format=%s']).stdout as String)
        .trim()
        .split('\n');
    expect(subjects, hasLength(3));
  }, skip: hasGit ? null : 'git is not available');

  test('ms-r11: init --yes --plan on an empty folder sets up the drafts as '
      'init does; no plan applies there', () async {
    final root = await writeTree({'keep.txt': 'x\n'});
    final (:runner, :out, :err) = writeRunner(root);

    expect(await runner.run(['init', '--yes', '--plan', '000000000000']), 0);
    expect(err.toString(), isEmpty);
    expect(out.toString(), endsWith(_configLine()));
  });

  test('init takes no argument', () async {
    final root = await writeTree({'keep.txt': 'x\n'});
    final (:runner, :out, :err) = writeRunner(root);

    expect(await runner.run(['init', 'extra']), 64);
    expect(out.toString(), isEmpty);
  });
}
