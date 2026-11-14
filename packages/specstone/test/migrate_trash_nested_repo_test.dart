import 'dart:io';

import 'package:specstone_core/src/index_query/index_store.dart'
    show specstoneGitignoreLines;
import 'package:test/test.dart';

import '../../specstone_core/test/helpers/git_repo.dart';
import '../../specstone_core/test/helpers/legacy_fixture.dart' show commitRepo;
import '../../specstone_core/test/helpers/shipped_pins.dart';
import '../../specstone_core/test/helpers/skill_files.dart';
import '../../specstone_core/test/helpers/temp_tree.dart';
import '../../specstone_core/test/helpers/write_fixture.dart' show testHome;
import 'helpers/built_cli.dart';

const _entry = '.claude/skills/specstone-old';

void main() {
  late String binary;

  setUpAll(() async {
    binary = await buildSpecstone();
  });

  /// Runs the binary in [root] with [args] and the test home folder.
  Future<ProcessResult> run(Directory root, List<String> args) => Process.run(
    binary,
    args,
    workingDirectory: root.path,
    environment: {'HOME': testHome().path, 'USERPROFILE': testHome().path},
  );

  /// Writes a project on the shipped pins whose `specstone-old` skill folder
  /// is a repository of its own, committed as the project's repository
  /// finds it, with [ignore] as the project's ignore file.
  Future<Directory> project({String ignore = ''}) async {
    final root = await writeTree({
      '.specstone/config.yaml': shippedPinsConfig(),
      '.specstone/.gitignore': '${specstoneGitignoreLines.join('\n')}\n',
      '.gitignore': ignore,
      ...skillFileTexts(),
      '$_entry/SKILL.md': 'old\n',
    });
    final nested = Directory('${root.path}/$_entry');
    expect(git(nested, ['init', '-q']).exitCode, 0);
    expect(git(nested, ['add', '-A']).exitCode, 0);
    expect(git(nested, ['commit', '-q', '-m', 'inner']).exitCode, 0);
    commitRepo(root);
    return root;
  }

  /// Plans the migrate in [root], then applies exactly that plan.
  Future<({ProcessResult dry, ProcessResult applied})> migrate(
    Directory root,
  ) async {
    final dry = await run(root, ['migrate', '--dry-run']);
    expect(dry.exitCode, 0, reason: '${dry.stdout}\n${dry.stderr}');
    final hash = RegExp(
      r'^plan ([0-9a-f]+)$',
      multiLine: true,
    ).firstMatch(dry.stdout as String)!.group(1)!;
    final applied = await run(root, ['migrate', '--yes', '--plan', hash]);
    return (dry: dry, applied: applied);
  }

  List<String> subjects(Directory root) =>
      '${git(root, ['log', '--format=%s']).stdout}'.trim().split('\n');

  test('an entry that is a repository the project tracks as one entry moves '
      'to the trash and commit 2 records its removal', () async {
    final root = await project();
    final before = subjects(root);

    final (:dry, :applied) = await migrate(root);

    expect(dry.stdout, contains('  agent files: 1 files\n'));
    expect(applied.exitCode, 0, reason: '${applied.stdout}\n${applied.stderr}');
    expect(Directory('${root.path}/$_entry').existsSync(), isFalse);
    expect(subjects(root), hasLength(before.length + 1));
    expect(
      '${git(root, ['show', '--name-only', '--format=', 'HEAD']).stdout}'
          .trim(),
      _entry,
    );
    expect('${git(root, ['status', '--porcelain']).stdout}'.trim(), isEmpty);
  });

  test('an entry that is a repository the project never tracked moves to '
      'the trash and commit 2 stages nothing for it', () async {
    final root = await project(ignore: '$_entry/\n');
    final before = subjects(root);

    final (:dry, :applied) = await migrate(root);

    expect(dry.stdout, contains('  agent files: 1 files\n'));
    expect(applied.exitCode, 0, reason: '${applied.stdout}\n${applied.stderr}');
    expect(Directory('${root.path}/$_entry').existsSync(), isFalse);
    expect(subjects(root), before);
    expect('${git(root, ['status', '--porcelain']).stdout}'.trim(), isEmpty);
  });
}
