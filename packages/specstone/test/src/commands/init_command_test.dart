import 'dart:io';

import 'package:specstone_core/src/setup_migration/host_render.dart';
import 'package:specstone_core/src/templates/shipped_pack_files.dart'
    show shippedPackVersions;
import 'package:test/test.dart';

import '../../../../specstone_core/test/helpers/shipped_pins.dart';
import '../../../../specstone_core/test/helpers/skill_files.dart';
import '../../../../specstone_core/test/helpers/temp_tree.dart';
import '../../helpers/write_runner.dart';

/// The config line `init` prints, then the Codex trust line that follows it.
String _closingLines() {
  final versions = shippedPackVersions();
  return 'created .specstone/config.yaml: '
      'prd-core ${versions['prd-core']}, '
      'software-tech ${versions['software-tech']}\n'
      'trust the Specstone hook in Codex: open /hooks in a trusted project\n';
}

void main() {
  test('list --draft lists every doc init created', () async {
    final root = await writeTree({'keep.txt': 'x\n'});
    final (:runner, :out, :err) = writeRunner(root);
    await runner.run(['init']);
    expect(out.toString(), endsWith(_closingLines()));

    final listed = writeRunner(root);
    final listRunner = listed.runner;
    final listOut = listed.out;
    final listErr = listed.err;
    const fixedTitles = {
      'project': 'Project context',
      'goal': 'Project goals',
      'glossary': 'Domain glossary',
      'features': 'Feature map',
      'gnfr': 'Project-wide non-functional requirements',
      'tech_stack': 'Tech stack',
    };
    for (final MapEntry(key: type, value: title) in fixedTitles.entries) {
      expect(await listRunner.run(['list', type, '--draft']), 0, reason: type);
      expect(listOut.toString(), contains('$type ($type) — $title · draft · '));
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
        '${_closingLines()}',
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
    'init on a CLAUDE.md with an unclosed Specstone block '
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

  test(
    'init --yes --plan is a usage error, exit 64, and writes nothing',
    () async {
      final root = await writeTree({'keep.txt': 'x\n'});
      final (:runner, :out, :err) = writeRunner(root);

      expect(await runner.run(['init', '--yes', '--plan', '000000000000']), 64);
      expect(out.toString(), isEmpty);
      expect(err.toString(), contains('"--yes"'));
      expect(err.toString(), contains('Usage: specstone init'));
      expect(Directory('${root.path}/.specstone').existsSync(), isFalse);
    },
  );

  test('init takes no argument', () async {
    final root = await writeTree({'keep.txt': 'x\n'});
    final (:runner, :out, :err) = writeRunner(root);

    expect(await runner.run(['init', 'extra']), 64);
    expect(out.toString(), isEmpty);
  });
}
