import 'dart:convert';
import 'dart:io';

import 'package:specstone/src/command_runner.dart';
import 'package:specstone_core/specstone_core.dart';
import 'package:test/test.dart';

import '../../helpers/fixture_packs.dart';
import '../../helpers/temp_tree.dart';

const _buildUsage =
    'Usage: specstone build <target> [--format html|pdf] [--output <file>] '
    '[--json]';

const _featureDir = 'docs/prds/features/f03_template_packs';
const _feature = '$_featureDir/FEATURE.md';
const _storyA = '$_featureDir/us01_a/USER_STORY.md';
const _frX = '$_featureDir/us01_a/functional_requirements/fr01_x.md';
const _storyB = '$_featureDir/us02_b/USER_STORY.md';

const _featureText =
    '# F-03 Template packs\n\n## Feature name\n- **Human:** Packs\n\n'
    '## Feature goal\n- **why:** share templates\n';
const _storyAText =
    '# Story A\n\n## Summary\nFirst.\n\n## Acceptance Criteria\nDone.\n';
const _frXText = '# Requirement X\n\n## Statement\nShall.\n';
const _storyBText =
    '# Story B\n\n## Summary\nSecond.\n\n## Acceptance Criteria\nDone.\n';

const Map<String, String> _fixture = {
  _feature: _featureText,
  _storyA: _storyAText,
  _frX: _frXText,
  _storyB: _storyBText,
};

void main() {
  group('specstone build', () {
    late StringBuffer out;
    late StringBuffer err;

    setUp(() {
      out = StringBuffer();
      err = StringBuffer();
    });

    Future<SpecstoneCommandRunner> runnerIn(
      Directory workingDirectory, {
      Map<String, String> packs = const {},
    }) async {
      final home = await writeTree({});
      return SpecstoneCommandRunner(
        out: out,
        err: err,
        templates: TemplateResolver(
          shippedFiles: fixturePackFiles(extra: packs),
        ),
        workingDirectory: workingDirectory,
        homeDirectory: home,
      );
    }

    String read(Directory project, String path) =>
        File.fromUri(project.uri.resolve(path)).readAsStringSync();

    bool exists(Directory project, String path) =>
        File.fromUri(project.uri.resolve(path)).existsSync();

    test('f05/us02/fr04/e01, f05/us02/s1: a folder builds to its mirrored '
        'path with the docs in tree order', () async {
      final project = await fixtureProject(_fixture);
      final runner = await runnerIn(project);

      expect(await runner.run(['build', _featureDir]), 0);
      expect(out.toString(), '.specstone/build/$_featureDir.html\n');
      expect(err.toString(), isEmpty);
      final html = read(project, '.specstone/build/$_featureDir.html');
      final order = [
        '<a href="#doc-1">F-03 Template packs</a>',
        '<a href="#doc-2">Story A</a>',
        '<a href="#doc-3">Requirement X</a>',
        '<a href="#doc-4">Story B</a>',
      ].map(html.indexOf).toList();
      expect(order, everyElement(isNonNegative));
      expect(order, [...order]..sort());
    });

    test(
      'f05/us02/fr04/e02: a file keeps its .md in the output name',
      () async {
        final project = await fixtureProject(_fixture);
        final runner = await runnerIn(project);

        expect(await runner.run(['build', _feature]), 0);
        expect(out.toString(), '.specstone/build/$_feature.html\n');
        expect(exists(project, '.specstone/build/$_feature.html'), isTrue);
      },
    );

    test('f05/us02/fr04/e03: the docs root and a docs/docs folder get '
        'separate files', () async {
      final project = await fixtureProject({
        ..._fixture,
        'docs/docs/prds/d01_context.md': '# Context\n',
      });
      final runner = await runnerIn(project);

      expect(await runner.run(['build', 'docs']), 0);
      final first = read(project, '.specstone/build/docs.html');
      out.clear();

      expect(await runner.run(['build', 'docs/docs']), 0);
      expect(out.toString(), '.specstone/build/docs/docs.html\n');
      expect(read(project, '.specstone/build/docs.html'), first);
      expect(exists(project, '.specstone/build/docs/docs.html'), isTrue);
    });

    test('f05/us02/fr04/e04, s03/inv14: a rebuild overwrites its own file '
        'only, and x.md and x/ stay two files', () async {
      final project = await fixtureProject({
        ..._fixture,
        'docs/x.md': '# x file\n',
        'docs/x/y.md': '# y\n',
      });
      final runner = await runnerIn(project);
      const folderOut = '.specstone/build/$_featureDir.html';

      expect(await runner.run(['build', _featureDir]), 0);
      File.fromUri(project.uri.resolve(_feature))
          .writeAsStringSync(_featureText.replaceFirst('F-03', 'F-33'));
      expect(await runner.run(['build', _featureDir]), 0);
      expect(read(project, folderOut), contains('F-33 Template packs'));
      final folderHtml = read(project, folderOut);

      expect(await runner.run(['build', _feature]), 0);
      expect(read(project, folderOut), folderHtml);
      expect(exists(project, '.specstone/build/$_feature.html'), isTrue);

      expect(await runner.run(['build', 'docs/x.md']), 0);
      expect(await runner.run(['build', 'docs/x']), 0);
      expect(exists(project, '.specstone/build/docs/x.md.html'), isTrue);
      expect(exists(project, '.specstone/build/docs/x.html'), isTrue);
    });

    test('f05/us02/fr04: an absolute --output creates its parent and prints '
        'the path as given', () async {
      final project = await fixtureProject(_fixture);
      final share = await Directory.systemTemp.createTemp('specstone_share_');
      addTearDown(() => share.delete(recursive: true));
      final target = '${share.path}/share/f05.html';
      final runner = await runnerIn(project);

      expect(await runner.run(['build', _feature, '--output', target]), 0);
      expect(out.toString(), '$target\n');
      expect(File(target).existsSync(), isTrue);
    });

    test('f05/us02/fr04: a relative --output resolves from the working '
        'directory and prints relative to the project root', () async {
      final project = await fixtureProject(_fixture);
      final runner = await runnerIn(
        Directory.fromUri(project.uri.resolve('docs/')),
      );

      expect(
        await runner.run(['build', 'prds/features', '--output', 'out/a.html']),
        0,
      );
      expect(out.toString(), 'docs/out/a.html\n');
      expect(exists(project, 'docs/out/a.html'), isTrue);
    });

    test('f05/us02/s2: a mermaid block ships the script and a pre', () async {
      final project = await fixtureProject({
        _feature: '$_featureText\n```mermaid\ngraph TD; A-->B;\n```\n',
      });
      final runner = await runnerIn(project);

      expect(await runner.run(['build', _feature]), 0);
      final html = read(project, '.specstone/build/$_feature.html');
      expect(html, contains('<pre class="mermaid">'));
      expect(html, contains('"use strict";var __esbuild_esm_mermaid_nm'));
    });

    test('f05/us02/s3: an off-template doc warns on stderr, renders in disk '
        'order, and exits 0', () async {
      final project = await fixtureProject({
        _feature:
            '# F-03\n\n## Feature goal\n- **why:** x\n\n'
            '## Feature name\n- **Human:** y\n',
      });
      final runner = await runnerIn(project);

      expect(await runner.run(['build', _feature]), 0);
      expect(
        err.toString(),
        '⚠️ WARNING: $_feature does not match its template; run specstone '
        'format\n',
      );
      final html = read(project, '.specstone/build/$_feature.html');
      expect(
        html.indexOf('Feature goal'),
        lessThan(html.indexOf('Feature name')),
      );
    });

    test('f05/us02/s4: links become an anchor, an outside-link span, and a '
        'kept web link', () async {
      final project = await fixtureProject({
        ..._fixture,
        _storyA:
            '# Story A\n\n## Summary\n'
            '[b](../us02_b/USER_STORY.md) '
            '[out](../../../../../README.md) '
            '[web](https://example.com/spec)\n\n'
            '## Acceptance Criteria\nDone.\n',
        'docs/other.md': '# other\n',
      });
      final runner = await runnerIn(project);

      expect(await runner.run(['build', _featureDir]), 0);
      final html = read(project, '.specstone/build/$_featureDir.html');
      expect(html, contains('<a href="#doc-4">b</a>'));
      expect(html, contains('<span class="outside-link">'));
      expect(html, contains('<a href="https://example.com/spec">web</a>'));
    });

    test('f05/us02/s5: a draft doc shows the Draft label', () async {
      final project = await fixtureProject({
        _feature: '---\ndraft: true\n---\n$_featureText',
      });
      final runner = await runnerIn(project);

      expect(await runner.run(['build', _feature]), 0);
      expect(
        read(project, '.specstone/build/$_feature.html'),
        contains('<p class="draft">Draft</p>'),
      );
    });

    test('f05/us02/s6: a file no doc type matches warns and the build still '
        'writes', () async {
      final project = await fixtureProject({
        ..._fixture,
        '$_featureDir/notes.md': 'notes\n',
      });
      final runner = await runnerIn(project);

      expect(await runner.run(['build', _featureDir]), 0);
      expect(err.toString(), contains('$_featureDir/notes.md'));
      expect(err.toString(), startsWith('⚠️ WARNING: '));
      expect(exists(project, '.specstone/build/$_featureDir.html'), isTrue);
    });

    test('f05/us02/s7, f05/us02/fr01/e02: a target outside the docs root is '
        '64 and writes nothing', () async {
      final project = await fixtureProject({
        ..._fixture,
        'README.md': '# readme\n',
      });
      final runner = await runnerIn(
        Directory.fromUri(project.uri.resolve('docs/')),
      );

      expect(await runner.run(['build', '../README.md']), 64);
      expect(out.toString(), isEmpty);
      expect(err.toString(), contains('docs'));
      expect(
        Directory.fromUri(project.uri.resolve('.specstone/build')).existsSync(),
        isFalse,
      );
    });

    test('f05/us02/s7, f05/us02/fr01/e02: no target is 64 with the target '
        'message', () async {
      final project = await fixtureProject(_fixture);
      final runner = await runnerIn(project);

      expect(await runner.run(['build']), 64);
      expect(out.toString(), isEmpty);
      expect(
        err.toString(),
        'no target given: name a file or folder under the docs root to '
        'build\n',
      );
      expect(
        Directory.fromUri(project.uri.resolve('.specstone/build')).existsSync(),
        isFalse,
      );
    });

    test('f05/us02/s7, f05/us02/fr01/e02: no target under --json prints the '
        'envelope on stderr only', () async {
      final project = await fixtureProject(_fixture);
      final runner = await runnerIn(project);

      expect(await runner.run(['build', '--json']), 64);
      expect(out.toString(), isEmpty);
      final error =
          (jsonDecode(err.toString()) as Map<String, dynamic>)['error']
              as Map<String, dynamic>;
      expect(error['code'], 'target_missing');
    });

    test('f05/us02/s8, f05/us02/fr04/e06: an output whose parent is a file '
        'is 73 and nothing is written', () async {
      final project = await fixtureProject({..._fixture, 'blocker': 'x'});
      final runner = await runnerIn(project);

      expect(
        await runner.run(['build', _feature, '--output', 'blocker/x.html']),
        73,
      );
      expect(out.toString(), isEmpty);
      expect(
        err.toString(),
        'blocker/x.html: the output path is not writable\n',
      );
      expect(
        File.fromUri(project.uri.resolve('blocker')).readAsStringSync(),
        'x',
      );
    });

    test('f05/us02/fr04/e06: a file at .specstone/build is 73 with the JSON '
        'envelope on stderr', () async {
      final project = await fixtureProject({
        ..._fixture,
        '.specstone/build': 'x',
      });
      final runner = await runnerIn(project);

      expect(await runner.run(['build', 'docs', '--json']), 73);
      expect(out.toString(), isEmpty);
      expect(jsonDecode(err.toString()), {
        'error': {
          'code': 'output_not_writable',
          'message': 'the output path is not writable',
          'file': '.specstone/build/docs.html',
        },
      });
    });

    test('f05/us02/fr04/e07: --json prints output and warnings on stdout, '
        'stderr stays empty', () async {
      final project = await fixtureProject({
        ..._fixture,
        'docs/specs/notes.md': 'notes\n',
      });
      final runner = await runnerIn(project);

      expect(await runner.run(['build', 'docs', '--json']), 0);
      expect(err.toString(), isEmpty);
      expect(jsonDecode(out.toString()), {
        'output': '.specstone/build/docs.html',
        'warnings': [
          'docs/specs/notes.md: no doc type matches this path; skipped',
        ],
      });
      expect(out.toString(), contains('\n  "output"'));
    });

    test('f05/us02/fr01/e03: no project is 78 with the project_not_found '
        'message', () async {
      final bare = await writeTree({'docs/a.md': '# a\n'});
      final runner = await runnerIn(bare);

      expect(await runner.run(['build', 'docs']), 78);
      expect(out.toString(), isEmpty);
      expect(err.toString(), startsWith('no Specstone project'));
    });

    test('f05/us02/fr01/e07: a pack version the config cannot satisfy is 78 '
        'with an F-03 fault', () async {
      final project = await fixtureProject({
        ..._fixture,
        '.specstone/config.yaml': 'packs:\n  prd-core: 9.9.9\n',
      });
      final runner = await runnerIn(project);

      expect(await runner.run(['build', 'docs']), 78);
      expect(out.toString(), isEmpty);
      expect(err.toString(), isNotEmpty);
    });

    test('an unsupported --format is a usage error and exits 64', () async {
      final runner = await runnerIn(await fixtureProject(_fixture));

      expect(await runner.run(['build', 'docs', '--format', 'docx']), 64);
      expect(out.toString(), isEmpty);
      expect(err.toString(), contains(_buildUsage));
    });

    test('two targets is a usage error and exits 64', () async {
      final runner = await runnerIn(await fixtureProject(_fixture));

      expect(await runner.run(['build', 'a', 'b']), 64);
      expect(out.toString(), isEmpty);
      expect(err.toString(), contains(_buildUsage));
    });

    test('help build prints the usage to out and exits 0', () async {
      final runner = await runnerIn(await fixtureProject({}));

      expect(await runner.run(['help', 'build']), 0);
      expect(out.toString(), contains(_buildUsage));
      expect(err.toString(), isEmpty);
    });
  });
}
