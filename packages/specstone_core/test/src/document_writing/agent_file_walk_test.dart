import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/document_writing/agent_file_walk.dart';
import 'package:specstone_core/src/git_process.dart';
import 'package:specstone_core/src/templates/project_config.dart';
import 'package:test/test.dart';

import '../../helpers/git_repo.dart';
import '../../helpers/legacy_fixture.dart' show commitRepo;
import '../../helpers/shipped_pins.dart';
import '../../helpers/temp_tree.dart';

final String? _skip = hasGit ? null : 'git is not available';

/// A [RunGit] that starts the real `git` with a clean environment.
ProcessResult _realGit(
  List<String> arguments, {
  required String workingDirectory,
  Map<String, String>? environment,
}) => Process.runSync(
  'git',
  arguments,
  workingDirectory: workingDirectory,
  environment: cleanGitEnvironment(),
  includeParentEnvironment: false,
  stdoutEncoding: utf8,
);

/// The `config.yaml` of a project whose repository tops are [tops].
String _configText(List<String> tops) {
  final entries = [for (final top in tops) '  - $top\n'];
  final roots = tops.isEmpty ? '' : 'agent_file_roots:\n${entries.join()}';
  return '${shippedPinsConfig(['prd-core'])}$roots';
}

/// Writes the project under `proj/` and the sibling repository folders of
/// [files], and returns the project root.
Future<Directory> _project(
  Map<String, String> files, {
  List<String> tops = const [],
}) async {
  final base = await writeTree({
    for (final MapEntry(:key, :value) in files.entries) key: value,
    'proj/.specstone/config.yaml': _configText(tops),
  });
  return Directory('${base.path}/proj');
}

List<String> _walk(Directory root, [RunGit runGit = _realGit]) =>
    agentFilesOf(root, ProjectConfig.read(root), runGit);

void main() {
  group('with a commit', () {
    test('reads the files the repository tracks and skips the rest', () async {
      final root = await _project({
        'proj/CLAUDE.md': '',
        'proj/docs/notes/AGENTS.md': '',
        'proj/.claude/skills/s/SKILL.md': '',
        'proj/lib/a.dart': '',
        'proj/.gitignore': 'ignored/\n',
        'proj/ignored/.codex/x.md': '',
      });
      commitRepo(root);
      File('${root.path}/GEMINI.md').writeAsStringSync('');
      File('${root.path}/.cursor/rules/own.mdc')
        ..createSync(recursive: true)
        ..writeAsStringSync('');

      expect(_walk(root), [
        '.claude/skills/s/SKILL.md',
        'CLAUDE.md',
        'docs/notes/AGENTS.md',
      ]);
    }, skip: _skip);

    test('skips a tracked file the work tree no longer holds', () async {
      final root = await _project({'proj/CLAUDE.md': '', 'proj/AGENTS.md': ''});
      commitRepo(root);
      File('${root.path}/AGENTS.md').deleteSync();

      expect(_walk(root), ['CLAUDE.md']);
    }, skip: _skip);

    test('skips a nested repository and a linked work tree', () async {
      final root = await _project({'proj/CLAUDE.md': ''});
      commitRepo(root);
      final inner = Directory('${root.path}/vendor/inner')
        ..createSync(recursive: true);
      File('${inner.path}/AGENTS.md').writeAsStringSync('');
      commitRepo(inner);
      expect(
        git(root, [
          'worktree',
          'add',
          '-q',
          '-b',
          'side',
          '.worktrees/w',
        ]).exitCode,
        0,
      );

      expect(_walk(root), ['CLAUDE.md']);
    }, skip: _skip);

    test('adds the instruction files at each top, tracked or not, and '
        'the agent files that top tracks', () async {
      final root = await _project(
        {
          'proj/CLAUDE.md': '',
          'other/GEMINI.md': '',
          'other/.claude/tracked.md': '',
          'other/src/AGENTS.md': '',
        },
        tops: ['../other'],
      );
      commitRepo(root);
      final other = Directory('${root.parent.path}/other');
      commitRepo(other);
      File('${other.path}/AGENTS.md').writeAsStringSync('');
      File('${other.path}/.cursor/rules/specstone.mdc')
        ..createSync(recursive: true)
        ..writeAsStringSync('');
      File('${other.path}/.claude/untracked.md').writeAsStringSync('');

      expect(_walk(root), [
        '../other/.claude/tracked.md',
        '../other/.cursor/rules/specstone.mdc',
        '../other/AGENTS.md',
        '../other/GEMINI.md',
        '../other/src/AGENTS.md',
        'CLAUDE.md',
      ]);
    }, skip: _skip);

    test(
      'lists a file once when a top lies inside the project repository',
      () async {
        final root = await _project(
          {'proj/CLAUDE.md': '', 'proj/part/AGENTS.md': ''},
          tops: ['part'],
        );
        commitRepo(root);

        expect(_walk(root), ['CLAUDE.md', 'part/AGENTS.md']);
      },
      skip: _skip,
    );
  });

  group('without a usable git state', () {
    Future<Directory> unreadyProject() => _project(
      {
        'proj/CLAUDE.md': '',
        'proj/docs/AGENTS.md': '',
        'proj/.claude/x.md': '',
        'other/GEMINI.md': '',
        'other/.claude/y.md': '',
      },
      tops: ['../other'],
    );

    const instructionFilesOnly = ['../other/GEMINI.md', 'CLAUDE.md'];

    test(
      'reads the instruction files alone in a work tree with no commit',
      () async {
        final root = await unreadyProject();
        expect(git(root, ['init', '-q']).exitCode, 0);
        expect(git(root, ['add', '-A']).exitCode, 0);

        expect(_walk(root), instructionFilesOnly);
      },
      skip: _skip,
    );

    test('reads the instruction files alone outside a git work tree', () async {
      final root = await unreadyProject();

      expect(_walk(root), instructionFilesOnly);
    }, skip: _skip);

    test('reads the instruction files alone when git cannot start', () async {
      final root = await unreadyProject();

      final files = _walk(
        root,
        (arguments, {required workingDirectory, environment}) =>
            throw ProcessException('git', arguments, 'no git'),
      );

      expect(files, instructionFilesOnly);
    });

    test('reads the instruction files alone when an old git meets a foreign '
        'git dir, and runs no verb', () async {
      final root = await unreadyProject();
      final verbs = <List<String>>[];
      final runGit = guardedGit((
        arguments, {
        required workingDirectory,
        environment,
      }) {
        verbs.add(arguments);
        if (arguments.first == '--version') {
          return ProcessResult(0, 0, 'git version 2.37.0\n', '');
        }
        return ProcessResult(0, 0, '/foreign/gitdir\n${root.path}\n', '');
      });

      expect(_walk(root, runGit), instructionFilesOnly);
      expect(verbs.map((arguments) => arguments.first).toSet(), {
        '--version',
        'rev-parse',
      });
      expect(
        verbs.where((arguments) => arguments.first == 'rev-parse'),
        everyElement(['rev-parse', '--absolute-git-dir', '--show-toplevel']),
      );
    });
  });
}
