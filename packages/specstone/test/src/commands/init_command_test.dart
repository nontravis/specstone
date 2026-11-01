import 'dart:io';

import 'package:specstone_core/src/templates/shipped_pack_files.dart'
    show shippedPackVersions;
import 'package:test/test.dart';

import '../../../../specstone_core/test/helpers/git_repo.dart';
import '../../../../specstone_core/test/helpers/legacy_fixture.dart';
import '../../../../specstone_core/test/helpers/shipped_pins.dart';
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
  test("f06/us03/s2: an Agent's shell sets up the same files", () async {
    final root = await writeTree({'keep.txt': 'x\n'});
    final (:runner, :out, :err) = writeRunner(root);

    final status = await runner.run(['init']);

    expect(status, 0);
    expect(err.toString(), isEmpty);
    expect(
      out.toString(),
      startsWith('created docs/prds/PROJECT.md (draft)\n'),
    );
    expect(out.toString(), endsWith(_configLine()));
    expect(
      File('${root.path}/.specstone/config.yaml').readAsStringSync(),
      shippedPinsConfig(),
    );
  });

  test(
    'f06/us03/fr02/e07: list --draft lists every doc init created',
    () async {
      final root = await writeTree({'keep.txt': 'x\n'});
      final (:runner, :out, :err) = writeRunner(root);
      await runner.run(['init']);
      expect(out.toString(), endsWith(_configLine()));

      final listed = writeRunner(root);
      final listRunner = listed.runner;
      final listOut = listed.out;
      final listErr = listed.err;
      for (final type in ['project', 'features', 'gnfr', 'tech_stack']) {
        expect(
          await listRunner.run(['list', type, '--draft']),
          0,
          reason: type,
        );
        expect(
          listOut.toString(),
          contains('$type ($type) — $type · draft · '),
        );
        listOut.clear();
      }
      expect(listErr.toString(), isEmpty);
    },
  );

  test('f06/us03/s5: init in a configured folder prints the config_exists '
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

  test('f06/us03/fr01: init takes no argument', () async {
    final root = await writeTree({'keep.txt': 'x\n'});
    final (:runner, :out, :err) = writeRunner(root);

    expect(await runner.run(['init', 'extra']), 64);
    expect(out.toString(), isEmpty);
  });
}
