import 'dart:convert';
import 'dart:io';

import 'package:specstone/src/command_runner.dart';
import 'package:specstone_core/specstone_core.dart';
import 'package:test/test.dart';

import '../../helpers/fixture_packs.dart';
import '../../helpers/temp_tree.dart';

const _formatUsage =
    'Usage: specstone format [<file|folder>] [--check] [--json]';

const _featureDir = 'docs/prds/features/f05_rendering';
const _feature = '$_featureDir/FEATURE.md';
const _notes = '$_featureDir/notes.md';
const _storyDir = '$_featureDir/us01_format_docs';
const _story = '$_storyDir/USER_STORY.md';

const _featureFormatted =
    '# F-05\n\n## Feature name\n- **Human:** Rendering\n\n'
    '## Feature goal\n- **why:** share docs\n';
const _featureOutOfOrder =
    '# F-05\n\n## Feature goal\n- **why:** share docs\n\n'
    '## Feature name\n- **Human:** Rendering\n';
const _storyFormatted =
    '# US-01\n\n## Summary\nFormat docs.\n\n## Acceptance Criteria\nDone.\n';
const _storyOutOfOrder =
    '# US-01\n\n## Acceptance Criteria\nDone.\n\n## Summary\nFormat docs.\n';
const _storyUnknown = '$_storyFormatted\n## Notes\nx\n';

/// Returns why a read-only folder cannot stop a write here, else null.
String? _readOnlyFolderSkipReason() {
  if (Platform.isWindows) return 'chmod does not apply on Windows';
  final user = Process.runSync('id', ['-u']).stdout.toString().trim();
  return user == '0' ? 'the process ignores folder permissions (root)' : null;
}

void main() {
  group('specstone format', () {
    late StringBuffer out;
    late StringBuffer err;

    setUp(() {
      out = StringBuffer();
      err = StringBuffer();
    });

    Future<SpecstoneCommandRunner> runnerIn(Directory workingDirectory) async {
      final home = await writeTree({});
      return SpecstoneCommandRunner(
        out: out,
        err: err,
        templates: TemplateResolver(shippedFiles: fixturePackFiles()),
        workingDirectory: workingDirectory,
        homeDirectory: home,
      );
    }

    String read(Directory project, String path) =>
        File.fromUri(project.uri.resolve(path)).readAsStringSync();

    test('f05/us01/s1: formats one file named by path to the template order '
        'and prints one line', () async {
      final project = await fixtureProject({_feature: _featureOutOfOrder});
      final runner = await runnerIn(project);

      expect(await runner.run(['format', _feature]), 0);
      expect(out.toString(), '$_feature: formatted\n');
      expect(err.toString(), isEmpty);
      expect(read(project, _feature), _featureFormatted);
    });

    test('f05/us01/s2, f05/us01/fr01: with no target formats every doc under '
        'the docs root', () async {
      final project = await fixtureProject({
        _feature: _featureOutOfOrder,
        _story: _storyOutOfOrder,
      });
      final runner = await runnerIn(project);

      expect(await runner.run(['format']), 0);
      expect(out.toString(), '$_feature: formatted\n$_story: formatted\n');
      expect(read(project, _feature), _featureFormatted);
      expect(read(project, _story), _storyFormatted);
    });

    test('f05/us01/s3: adds a missing required section with its starter text '
        'and keeps the frontmatter', () async {
      final project = await fixtureProject({
        _feature: '---\ndraft: false\n---\n# F-05\n\n## Feature name\nx\n',
      });
      final runner = await runnerIn(project);

      expect(await runner.run(['format', _feature]), 0);
      expect(
        read(project, _feature),
        '---\ndraft: false\n---\n# F-05\n\n## Feature name\nx\n\n'
        '## Feature goal\n- **why:**\n',
      );
    });

    test('f05/us01/s4: rewrites a header to the form the template writes', () async {
      final project = await fixtureProject({
        _feature:
            '# F-05\n\n## Feature name\nx\n\n## feature   goal\n- **why:** y\n',
      });
      final runner = await runnerIn(project);

      expect(await runner.run(['format', _feature]), 0);
      expect(
        read(project, _feature),
        '# F-05\n\n## Feature name\nx\n\n## Feature goal\n- **why:** y\n',
      );
    });

    test('f05/us01/s5: --check lists the doc that would change, exits 1, and '
        'writes nothing', () async {
      final project = await fixtureProject({
        _feature: _featureOutOfOrder,
        _story: _storyFormatted,
      });
      final runner = await runnerIn(project);

      expect(await runner.run(['format', '--check']), 1);
      expect(out.toString(), '$_feature\n');
      expect(err.toString(), isEmpty);
      expect(read(project, _feature), _featureOutOfOrder);
      expect(read(project, _story), _storyFormatted);
    });

    test('f05/us01/s6: a doc no doc type matches is skipped with a warning on '
        'stderr; the rest is formatted', () async {
      final project = await fixtureProject({
        _feature: _featureOutOfOrder,
        _notes: 'free text',
      });
      final runner = await runnerIn(project);

      expect(await runner.run(['format', _featureDir]), 0);
      expect(out.toString(), '$_feature: formatted\n');
      expect(
        err.toString(),
        '⚠️ WARNING: $_notes: no doc type matches this path; skipped\n',
      );
      expect(read(project, _feature), _featureFormatted);
      expect(read(project, _notes), 'free text');
    });

    test('f05/us01/s7: a doc with a header the template lacks is refused and '
        'left byte for byte; exit 1', () async {
      final project = await fixtureProject({_story: _storyUnknown});
      final runner = await runnerIn(project);

      expect(await runner.run(['format']), 1);
      expect(out.toString(), '$_story: refused: unknown header "## Notes"\n');
      expect(read(project, _story), _storyUnknown);
    });

    test('f05/us01/fr04: a doc ending inside a fence is refused and left '
        'byte for byte; exit 1; --json marks unclosedFence', () async {
      const unclosed = '# US-01\n\n## Summary\nx\n```\ncode\n';
      final project = await fixtureProject({_story: unclosed});
      final runner = await runnerIn(project);

      expect(await runner.run(['format']), 1);
      expect(out.toString(), '$_story: refused: unclosed code fence\n');
      expect(read(project, _story), unclosed);

      out.clear();
      expect(await runner.run(['format', '--json']), 1);
      expect(jsonDecode(out.toString()), {
        'files': [
          {'path': _story, 'status': 'refused', 'unclosedFence': true},
        ],
        'warnings': <String>[],
      });
    });

    test('f05/us01/s8: a target outside the docs root, then a missing target, '
        'exit 64 and change nothing', () async {
      final project = await fixtureProject({
        _feature: _featureOutOfOrder,
        'README.md': '# Readme\n',
      });
      final runner = await runnerIn(Directory('${project.path}/docs'));

      expect(await runner.run(['format', '../README.md']), 64);
      expect(
        err.toString(),
        'the target ../README.md lies outside the docs root docs/\n',
      );
      expect(out.toString(), isEmpty);

      err.clear();
      expect(await runner.run(['format', 'missing.md']), 64);
      expect(err.toString(), 'the target missing.md does not exist\n');
      expect(out.toString(), isEmpty);
      expect(read(project, _feature), _featureOutOfOrder);
      expect(read(project, 'README.md'), '# Readme\n');
    });

    test('f05/us01/s9: outside a project prints project_not_found text on '
        'stderr; exit 78', () async {
      final runner = await runnerIn(await writeTree({}));

      expect(await runner.run(['format']), 78);
      expect(out.toString(), isEmpty);
      expect(
        err.toString(),
        'no Specstone project: no folder from the working directory upward '
        'holds .specstone/config.yaml\n',
      );
    });

    test('f05/us01/fr08/e01: --json prints every file and the warnings on '
        'stdout and nothing on stderr', () async {
      final project = await fixtureProject({
        _feature: _featureOutOfOrder,
        _notes: 'free text',
        _story: _storyFormatted,
      });
      final runner = await runnerIn(project);

      expect(await runner.run(['format', _featureDir, '--json']), 0);
      expect(err.toString(), isEmpty);
      expect(jsonDecode(out.toString()), {
        'files': [
          {'path': _feature, 'status': 'formatted'},
          {'path': _notes, 'status': 'skipped'},
          {'path': _story, 'status': 'unchanged'},
        ],
        'warnings': ['$_notes: no doc type matches this path; skipped'],
      });
      expect(out.toString(), endsWith('}\n'));
      expect(out.toString(), contains('\n  "files": ['));
    });

    test('f05/us01/fr08/e03: --json outside a project prints the error '
        'envelope on stderr and nothing on stdout; exit 78', () async {
      final runner = await runnerIn(await writeTree({}));

      expect(await runner.run(['format', '--json']), 78);
      expect(out.toString(), isEmpty);
      final error =
          (jsonDecode(err.toString()) as Map<String, Object?>)['error']!
              as Map<String, Object?>;
      expect(error['code'], 'project_not_found');
      expect(error['message'], startsWith('no Specstone project: '));
      expect(error.containsKey('file'), isFalse);
    });

    test('f05/us01/fr08/e01: --json with --check lists the doc that would '
        'change, writes nothing, and exits 1', () async {
      final project = await fixtureProject({_feature: _featureOutOfOrder});
      final runner = await runnerIn(project);

      expect(await runner.run(['format', '--check', '--json']), 1);
      expect(jsonDecode(out.toString()), {
        'files': [
          {'path': _feature, 'status': 'formatted'},
        ],
        'warnings': <String>[],
      });
      expect(read(project, _feature), _featureOutOfOrder);
    });

    test('a template fault reaches format as its F-03 code, exit 78', () async {
      final project = await writeTree({'.specstone/config.yaml': 'packs: [\n'});
      final runner = await runnerIn(project);

      expect(await runner.run(['format']), 78);
      expect(out.toString(), isEmpty);
      expect(err.toString(), contains('config.yaml'));
    });

    test(
      'f05/us01/fr07: a doc that cannot be written is output_not_writable '
      'with its path, exit 73; docs written before it stay written',
      () async {
        final project = await fixtureProject({
          _feature: _featureOutOfOrder,
          _story: _storyOutOfOrder,
        });
        final storyDir = Directory('${project.path}/$_storyDir');
        await Process.run('chmod', ['555', storyDir.path]);
        addTearDown(() => Process.run('chmod', ['755', storyDir.path]));
        final runner = await runnerIn(project);

        expect(await runner.run(['format', '--json']), 73);

        expect(out.toString(), isEmpty);
        final error =
            (jsonDecode(err.toString()) as Map<String, Object?>)['error']!
                as Map<String, Object?>;
        expect(error['code'], 'output_not_writable');
        expect(error['file'], _story);
        expect(error['message'], isA<String>());
        expect(read(project, _feature), _featureFormatted);
        expect(read(project, _story), _storyOutOfOrder);
      },
      skip: _readOnlyFolderSkipReason(),
    );

    test('f05/us01/fr07: a read-only doc that needs a rewrite is '
        'output_not_writable, exit 73, and stays untouched', () async {
      final project = await fixtureProject({_feature: _featureOutOfOrder});
      final doc = File('${project.path}/$_feature');
      await Process.run('chmod', ['444', doc.path]);
      addTearDown(() => Process.run('chmod', ['644', doc.path]));
      final runner = await runnerIn(project);

      expect(await runner.run(['format']), 73);

      expect(out.toString(), isEmpty);
      expect(err.toString(), '$_feature: the doc is read-only\n');
      expect(read(project, _feature), _featureOutOfOrder);
    }, skip: _readOnlyFolderSkipReason() ?? false);

    test('f05/us01/fr02: a doc that cannot be read is skipped with a warning '
        'and the run exits 0', () async {
      final project = await fixtureProject({
        _feature: _featureFormatted,
        _story: _storyOutOfOrder,
      });
      final doc = File('${project.path}/$_feature');
      await Process.run('chmod', ['000', doc.path]);
      addTearDown(() => Process.run('chmod', ['644', doc.path]));
      final runner = await runnerIn(project);

      expect(await runner.run(['format']), 0);

      expect(out.toString(), '$_story: formatted\n');
      expect(
        err.toString(),
        '⚠️ WARNING: $_feature: cannot be read; skipped\n',
      );
    }, skip: _readOnlyFolderSkipReason() ?? false);

    test('help format prints the usage to out and exits 0', () async {
      final runner = await runnerIn(await fixtureProject({}));

      expect(await runner.run(['help', 'format']), 0);
      expect(out.toString(), contains(_formatUsage));
      expect(err.toString(), isEmpty);
    });

    test('two targets is a usage error and exits 64', () async {
      final runner = await runnerIn(await fixtureProject({}));

      expect(await runner.run(['format', 'a', 'b']), 64);
      expect(out.toString(), isEmpty);
      expect(err.toString(), contains(_formatUsage));
    });
  });
}
