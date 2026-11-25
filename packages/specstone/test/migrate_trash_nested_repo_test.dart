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

/// A shipped skill file the project edited, so a run has one write to make.
final String _edited = skillPaths().first;

void main() {
  late String binary;

  setUpAll(() async {
    binary = await buildSpecstone();
  });

  /// Runs the binary in [root] with [args] and the test home folder.
  Future<ProcessResult> run(Directory root, List<String> args) => runSpecstone(
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
      _edited: 'hand edit\n',
      '$_entry/SKILL.md': 'old\n',
    });
    final nested = Directory('${root.path}/$_entry');
    expect(git(nested, ['init', '-q']).exitCode, 0);
    expect(git(nested, ['add', '-A']).exitCode, 0);
    expect(git(nested, ['commit', '-q', '-m', 'inner']).exitCode, 0);
    commitRepo(root);
    return root;
  }

  List<String> subjects(Directory root) =>
      '${git(root, ['log', '--format=%s']).stdout}'.trim().split('\n');

  const leftLine = '$_entry lies under .git; left as it is';

  for (final (:label, :ignore) in [
    (label: 'the project tracks as one entry', ignore: ''),
    (label: 'the project never tracked', ignore: '$_entry/\n'),
  ]) {
    test('an entry that is a repository $label stays whole and is named on '
        'stderr while the run writes its other file', () async {
      final root = await project(ignore: ignore);
      final before = subjects(root);

      final dry = await run(root, ['migrate', '--dry-run']);
      final hash = RegExp(
        r'^plan ([0-9a-f]+)$',
        multiLine: true,
      ).firstMatch(dry.stdout as String)!.group(1)!;
      final applied = await run(root, ['migrate', '--yes', '--plan', hash]);

      for (final result in [dry, applied]) {
        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
        expect(result.stderr, contains(leftLine));
      }
      expect(dry.stdout, contains('  agent files: 1 files\n'));
      expect(File('${root.path}/$_entry/SKILL.md').readAsStringSync(), 'old\n');
      expect(Directory('${root.path}/$_entry/.git').existsSync(), isTrue);
      expect(subjects(root), hasLength(before.length + 1));
      expect(
        '${git(root, ['show', '--name-only', '--format=', 'HEAD']).stdout}'
            .trim()
            .split('\n'),
        unorderedEquals([_edited, '.specstone/config.yaml']),
      );
      expect('${git(root, ['status', '--porcelain']).stdout}'.trim(), isEmpty);
    });
  }
}
