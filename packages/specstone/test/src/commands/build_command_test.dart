import 'dart:convert';
import 'dart:io';

import 'package:specstone/src/command_runner.dart';
import 'package:specstone_core/specstone_core.dart';
import 'package:test/test.dart';

import '../../../../specstone_core/test/helpers/posix_modes.dart';
import '../../../../specstone_core/test/helpers/relative_link.dart';
import '../../helpers/fixture_packs.dart';
import '../../helpers/temp_tree.dart';

final String? _linksUnavailable = Platform.isWindows
    ? 'a link needs a privilege on Windows'
    : null;

const _zeta = '''
id: zeta
description: A second doc type on the feature path.
path: prds/features/f{nn}_template_packs/FEATURE.md
''';

const _noTrustRefusal =
    'cannot write .specstone/build/docs.html: the docs folder ';

const _buildUsage =
    'Usage: specstone build <target> [--format html] '
    '[--paper a4|a5|letter|legal] [--landscape] [--margin <length>] '
    '[--output <file>] [--json]';

const _featureDir = 'docs/prds/features/f03_template_packs';
const _feature = '$_featureDir/FEATURE.md';
const _storyA = '$_featureDir/us01_a/USER_STORY.md';
const _frX = '$_featureDir/us01_a/functional_requirements/fr01_x.md';
const _storyB = '$_featureDir/us02_b/USER_STORY.md';

const _featureText =
    '# F-03 Template packs\n\n## Feature name\n\n- **Human:** Packs\n\n'
    '## Feature goal\n\n- **why:** share templates\n';
const _storyAText =
    '# Story A\n\n## Summary\n\nFirst.\n\n## Acceptance Criteria\n\nDone.\n';
const _frXText = '# Requirement X\n\n## Statement\n\nShall.\n';
const _storyBText =
    '# Story B\n\n## Summary\n\nSecond.\n\n## Acceptance Criteria\n\nDone.\n';

const _recordType = '''
id: implementation
description: One feature record.
path: .specstone/records/f{nn}_{slug}/IMPLEMENTATION.md
parent: feature
per_target: true
fields:
  - id: statuses
    type: record_status
    list: true
''';

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

    /// The refusal under test must have written nothing: no `.specstone/build`
    /// entry of any kind, and no file at [output].
    void expectNothingWritten(Directory project, String output) {
      expect(
        FileSystemEntity.typeSync(
          project.uri.resolve('.specstone/build').toFilePath(),
        ),
        FileSystemEntityType.notFound,
        reason: 'the refusal left a .specstone/build entry',
      );
      expect(exists(project, output), isFalse);
    }

    test('a folder builds to its mirrored '
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

    for (final target in const [
      '.specstone/records',
      '.specstone/records/f03_template_packs/IMPLEMENTATION.md',
    ]) {
      test('a records target $target is 64 and writes nothing', () async {
        final project = await fixtureProject({
          ..._fixture,
          '.specstone/templates/implementation.yaml': _recordType,
          '.specstone/records/f03_template_packs/IMPLEMENTATION.md':
              '# Packs record\n',
        });
        final runner = await runnerIn(project);

        expect(await runner.run(['build', target, '--json']), 64);
        expect(out.toString(), isEmpty);
        final error =
            (jsonDecode(err.toString()) as Map<String, dynamic>)['error']
                as Map<String, dynamic>;
        expect(error['code'], 'target_outside_docs_root');
        expectNothingWritten(project, '.specstone/build/$target.html');
      });
    }

    test('a file keeps its .md in the output name', () async {
      final project = await fixtureProject(_fixture);
      final runner = await runnerIn(project);

      expect(await runner.run(['build', _feature]), 0);
      expect(out.toString(), '.specstone/build/$_feature.html\n');
      expect(exists(project, '.specstone/build/$_feature.html'), isTrue);
    });

    test('the docs root and a docs/docs folder get '
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

    test('a rebuild overwrites its own file '
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

    test('an absolute --output creates its parent and prints '
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

    test('a relative --output resolves from the working '
        'directory and prints relative to the project root', () async {
      final project = await fixtureProject(_fixture);
      final runner = await runnerIn(
        Directory.fromUri(project.uri.resolve('docs/')),
      );

      expect(
        await runner.run([
          'build',
          'prds/features',
          '--output',
          '../out/a.html',
        ]),
        0,
      );
      expect(out.toString(), 'out/a.html\n');
      expect(exists(project, 'out/a.html'), isTrue);
    });

    test('an off-template doc warns on stderr, renders in disk '
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

    test('links become an anchor, an outside-link span, and a '
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

    test('a file no doc type matches warns and the build still '
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

    test('a target outside the docs root is '
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

    test('no target is 64 with the target '
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

    test('no target under --json prints the '
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

    test('an output whose parent is a file '
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

    test('a file at .specstone/build is 73 with the JSON '
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

    test('--json prints output and warnings on stdout, '
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

    test('no project is 78 with the project_not_found '
        'message', () async {
      final bare = await writeTree({'docs/a.md': '# a\n'});
      final runner = await runnerIn(bare);

      expect(await runner.run(['build', 'docs']), 78);
      expect(out.toString(), isEmpty);
      expect(err.toString(), startsWith('no Specstone project'));
    });

    test('a pack version the config cannot satisfy is 78 '
        'with a template fault', () async {
      final project = await fixtureProject({
        ..._fixture,
        '.specstone/config.yaml': 'packs:\n  prd-core: 9.9.9\n',
      });
      final runner = await runnerIn(project);

      expect(await runner.run(['build', 'docs']), 78);
      expect(out.toString(), isEmpty);
      expect(err.toString(), isNotEmpty);
    });

    test('a template load fault prints its pack code with exit 78 and '
        'writes nothing', () async {
      final project = await fixtureProject({
        ..._fixture,
        '.specstone/config.yaml': 'packs:\n  prd-core: 9.9.9\n',
      });
      final runner = await runnerIn(project);

      expect(await runner.run(['build', 'docs', '--json']), 78);
      expect(out.toString(), isEmpty);
      final error =
          (jsonDecode(err.toString()) as Map<String, dynamic>)['error']
              as Map<String, dynamic>;
      expect(error['code'], 'pack_pin_newer');
      expectNothingWritten(project, '.specstone/build/docs.html');
    });

    test('a target that does not exist is 64 with target_not_found and '
        'writes nothing', () async {
      final project = await fixtureProject(_fixture);
      final runner = await runnerIn(project);

      expect(await runner.run(['build', 'docs/missing', '--json']), 64);
      expect(out.toString(), isEmpty);
      expect(jsonDecode(err.toString()), {
        'error': {
          'code': 'target_not_found',
          'message': 'the target docs/missing does not exist',
        },
      });
      expectNothingWritten(project, '.specstone/build/docs/missing.html');
    });

    test('a file two doc types match is skipped with both type ids and the '
        'rest build with exit 0', () async {
      final project = await fixtureProject(_fixture);
      final runner = await runnerIn(project, packs: {'zeta.yaml': _zeta});

      expect(await runner.run(['build', _featureDir]), 0);
      expect(out.toString(), '.specstone/build/$_featureDir.html\n');
      expect(
        err.toString(),
        '⚠️ WARNING: $_feature: doc types feature, zeta match this path; '
        'skipped\n',
      );
      final html = read(project, '.specstone/build/$_featureDir.html');
      expect(html, contains('Story A'));
      expect(html, isNot(contains('F-03 Template packs')));
    });

    test('a doc that is not UTF-8 text is skipped with its warning and the '
        'rest build with exit 0', () async {
      final project = await fixtureProject(_fixture);
      File.fromUri(project.uri.resolve(_storyA))
          .writeAsBytesSync([0x23, 0x20, 0xFF, 0x0A]);
      final runner = await runnerIn(project);

      expect(await runner.run(['build', _featureDir]), 0);
      expect(out.toString(), '.specstone/build/$_featureDir.html\n');
      expect(err.toString(), '⚠️ WARNING: $_storyA: not UTF-8 text; skipped\n');
      final html = read(project, '.specstone/build/$_featureDir.html');
      expect(html, contains('Story B'));
      expect(html, isNot(contains('Story A')));
    });

    test('an unreadable doc file is skipped with its warning and the rest '
        'build with exit 0', () async {
      final project = await fixtureProject(_fixture);
      final doc = File.fromUri(project.uri.resolve(_storyA));
      await Process.run('chmod', ['000', doc.path]);
      addTearDown(() => Process.run('chmod', ['644', doc.path]));
      final runner = await runnerIn(project);

      expect(await runner.run(['build', _featureDir]), 0);
      expect(err.toString(), '⚠️ WARNING: $_storyA: cannot be read; skipped\n');
      final html = read(project, '.specstone/build/$_featureDir.html');
      expect(html, contains('Story B'));
      expect(html, isNot(contains('Story A')));
    }, skip: unreadablePathSkipReason() ?? false);

    test('an unlistable folder is skipped with its warning and the other docs '
        'build with exit 0', () async {
      final project = await fixtureProject(_fixture);
      final folder = Directory.fromUri(
        project.uri.resolve('$_featureDir/us02_b/'),
      );
      await Process.run('chmod', ['000', folder.path]);
      addTearDown(() => Process.run('chmod', ['755', folder.path]));
      final runner = await runnerIn(project);

      expect(await runner.run(['build', _featureDir]), 0);
      expect(
        err.toString(),
        '⚠️ WARNING: $_featureDir/us02_b/: cannot be read; skipped\n',
      );
      final html = read(project, '.specstone/build/$_featureDir.html');
      expect(html, contains('Story A'));
      expect(html, contains('Requirement X'));
      expect(html, isNot(contains('Story B')));
    }, skip: unreadablePathSkipReason() ?? false);

    test('a doc the markdown parser fails on warns and the build exits 0 '
        'with the file written', () async {
      final project = await fixtureProject({
        ..._fixture,
        _frX: '$_frXText\n[a]:<b\\\n',
      });
      final runner = await runnerIn(project);

      expect(await runner.run(['build', _featureDir]), 0);
      expect(out.toString(), '.specstone/build/$_featureDir.html\n');
      expect(
        err.toString(),
        '⚠️ WARNING: $_frX: the markdown parser failed; its body is shown as '
        'plain text\n',
      );
      expect(exists(project, '.specstone/build/$_featureDir.html'), isTrue);
    });

    group(
      'a clone whose docs link leaves the project, with no trust record',
      () {
        Future<({Directory clone, Directory ext})> linkedClone() async {
          final base = await writeTree({
            for (final MapEntry(:key, :value) in _fixture.entries)
              'ext/${key.substring('docs/'.length)}': value,
            'clone/.specstone/config.yaml': 'packs:\n  prd-core: 1.1.0\n',
          });
          createRelativeLink('${base.path}/clone/docs', '../ext');
          return (
            clone: Directory('${base.path}/clone'),
            ext: Directory('${base.path}/ext'),
          );
        }

        test('the default output is refused with 73 and nothing is '
            'written', () async {
          final (:clone, :ext) = await linkedClone();
          final runner = await runnerIn(clone);

          expect(await runner.run(['build', 'docs', '--json']), 73);
          expect(out.toString(), isEmpty);
          expect(jsonDecode(err.toString()), {
            'error': {
              'code': 'output_not_writable',
              'message':
                  '$_noTrustRefusal${ext.resolveSymbolicLinksSync()} lies '
                  'outside the project; run specstone trust at a terminal to '
                  'allow it',
              'file': '.specstone/build/docs.html',
            },
          });
          expectNothingWritten(clone, '.specstone/build/docs.html');
        }, skip: _linksUnavailable);

        test('a named --output is written in a project with no trust '
            'record', () async {
          final (:clone, ext: _) = await linkedClone();
          final runner = await runnerIn(clone);

          expect(
            await runner.run(['build', 'docs', '--output', 'out/a.html']),
            0,
          );
          expect(out.toString(), 'out/a.html\n');
          expect(err.toString(), isEmpty);
          expect(read(clone, 'out/a.html'), contains('F-03 Template packs'));
        }, skip: _linksUnavailable);
      },
    );

    test('a .specstone/build link out of the project is refused with the '
        'cannot write message and nothing is written', () async {
      final project = await fixtureProject(_fixture);
      final elsewhere = await Directory.systemTemp.createTemp(
        'specstone_elsewhere_',
      );
      addTearDown(() => elsewhere.delete(recursive: true));
      Link.fromUri(project.uri.resolve('.specstone/build'))
          .createSync(elsewhere.path);
      final runner = await runnerIn(project);

      expect(await runner.run(['build', 'docs', '--json']), 73);
      expect(out.toString(), isEmpty);
      expect(jsonDecode(err.toString()), {
        'error': {
          'code': 'output_not_writable',
          'message':
              'cannot write .specstone/build/docs.html: it leads outside the '
              'project',
          'file': '.specstone/build/docs.html',
        },
      });
      expect(elsewhere.listSync(), isEmpty);
    }, skip: _linksUnavailable);

    group('an --output inside the docs root', () {
      test('html to a new file in docs/ is 73 and '
          'renders nothing', () async {
        final project = await fixtureProject(_fixture);
        final runner = await runnerIn(project);

        expect(
          await runner.run([
            'build', _featureDir, '--format', 'html', //
            '--output', 'docs/x.html',
          ]),
          73,
        );
        expect(out.toString(), isEmpty);
        expect(
          err.toString(),
          'docs/x.html: the output path is inside the docs root\n',
        );
        expect(exists(project, 'docs/x.html'), isFalse);
      });

      test('html over a source doc leaves the source '
          'byte-identical', () async {
        final project = await fixtureProject(_fixture);
        final runner = await runnerIn(project);

        expect(
          await runner.run([
            'build', _featureDir, '--format', 'html', //
            '--output', _feature,
          ]),
          73,
        );
        expect(read(project, _feature), _featureText);
        expect(
          err.toString(),
          '$_feature: the output path is inside the docs root\n',
        );
      });

      test('a .. path and a symlink into docs/ do not slip '
          'past the guard', () async {
        final project = await fixtureProject(_fixture);
        final runner = await runnerIn(project);

        expect(
          await runner.run([
            'build', _featureDir, //
            '--output', 'missing/../docs/x.html',
          ]),
          73,
        );
        expect(exists(project, 'docs/x.html'), isFalse);

        if (Platform.isWindows) return;
        final alias = Link.fromUri(project.uri.resolve('alias'));
        await alias.create('${project.path}/docs');
        out.clear();
        err.clear();

        expect(
          await runner.run(['build', _featureDir, '--output', 'alias/y.html']),
          73,
        );
        expect(exists(project, 'docs/y.html'), isFalse);
        expect(err.toString(), contains('inside the docs root'));
      });

      test('--json prints the envelope with the file on '
          'stderr', () async {
        final project = await fixtureProject(_fixture);
        final runner = await runnerIn(project);

        expect(
          await runner.run([
            'build',
            _featureDir,
            '--json',
            '--output',
            'docs/x.html',
          ]),
          73,
        );
        expect(out.toString(), isEmpty);
        expect(jsonDecode(err.toString()), {
          'error': {
            'code': 'output_not_writable',
            'message': 'the output path is inside the docs root',
            'file': 'docs/x.html',
          },
        });
      });
    });

    test(
      'an --output inside the records root is 73 and renders nothing',
      () async {
        const recordPath =
            '.specstone/records/f03_template_packs/IMPLEMENTATION.md';
        const recordText = '---\nstatuses: []\n---\n\n# Record\n';
        final project = await fixtureProject({
          ..._fixture,
          '.specstone/templates/implementation.yaml': _recordType,
          recordPath: recordText,
        });
        final runner = await runnerIn(project);

        expect(
          await runner.run(['build', _featureDir, '--output', recordPath]),
          73,
        );
        expect(out.toString(), isEmpty);
        expect(
          err.toString(),
          '$recordPath: the output path is inside the records root\n',
        );
        expect(read(project, recordPath), recordText);
      },
    );

    test('--paper letter --landscape '
        '--margin 1in writes the page rule', () async {
      final project = await fixtureProject(_fixture);
      final runner = await runnerIn(project);

      expect(
        await runner.run([
          'build', _featureDir, //
          '--paper', 'letter', '--landscape', '--margin', '1in',
        ]),
        0,
      );
      expect(out.toString(), '.specstone/build/$_featureDir.html\n');
      expect(
        read(project, '.specstone/build/$_featureDir.html'),
        contains('@page { size: letter landscape; margin: 1in; }'),
      );
    });

    test('no page options write A4 '
        'portrait with 20mm', () async {
      final project = await fixtureProject(_fixture);
      final runner = await runnerIn(project);

      expect(await runner.run(['build', _featureDir]), 0);
      expect(
        read(project, '.specstone/build/$_featureDir.html'),
        contains('@page { size: A4 portrait; margin: 20mm; }'),
      );
    });

    test('--paper b5 is 64 in text and json and writes nothing', () async {
      final project = await fixtureProject(_fixture);
      final runner = await runnerIn(project);

      expect(await runner.run(['build', _featureDir, '--paper', 'b5']), 64);
      expect(out.toString(), isEmpty);
      expect(
        err.toString(),
        '--paper takes a4, a5, letter, or legal, not b5\n',
      );
      expectNothingWritten(project, '.specstone/build/$_featureDir.html');

      err.clear();
      expect(
        await runner.run(['build', _featureDir, '--paper', 'b5', '--json']),
        64,
      );
      expect(out.toString(), isEmpty);
      expect(jsonDecode(err.toString()), {
        'error': {
          'code': 'argument_invalid',
          'message': '--paper takes a4, a5, letter, or legal, not b5',
        },
      });
    });

    test('a bad paper reports before a bad '
        'margin', () async {
      final project = await fixtureProject(_fixture);
      final runner = await runnerIn(project);

      expect(
        await runner.run([
          'build',
          _featureDir,
          '--paper',
          'b5',
          '--margin',
          '5',
        ]),
        64,
      );
      expect(
        err.toString(),
        '--paper takes a4, a5, letter, or legal, not b5\n',
      );
      expectNothingWritten(project, '.specstone/build/$_featureDir.html');
    });

    test('a bad format reports before '
        'a bad paper', () async {
      final project = await fixtureProject(_fixture);
      final runner = await runnerIn(project);

      expect(
        await runner.run(['build', 'docs', '--format', 'pdf', '--paper', 'b5']),
        64,
      );
      expect(err.toString(), '--format takes html, not pdf\n');
      expectNothingWritten(project, '.specstone/build/docs.html');
    });

    test('a negative margin refuses by '
        'the length rule in both spellings', () async {
      final project = await fixtureProject(_fixture);
      final runner = await runnerIn(project);

      for (final args in [
        ['build', _featureDir, '--margin', '-5mm'],
        ['build', _featureDir, '--margin=-5mm'],
      ]) {
        err.clear();
        expect(await runner.run(args), 64);
        expect(
          err.toString(),
          '--margin takes a length in mm, cm, or in, such as 20mm, '
          'not -5mm\n',
        );
        expectNothingWritten(project, '.specstone/build/$_featureDir.html');
      }
    });

    test('half the a4 short side '
        'refuses in landscape too', () async {
      final project = await fixtureProject(_fixture);
      final runner = await runnerIn(project);

      expect(
        await runner.run([
          'build', _featureDir, '--landscape', '--margin', '105mm', //
        ]),
        64,
      );
      expect(
        err.toString(),
        '--margin takes less than 105mm on a4, not 105mm\n',
      );
      expectNothingWritten(project, '.specstone/build/$_featureDir.html');
    });

    test('a bad option outside a project is '
        'argument_invalid', () async {
      final bare = await writeTree({'docs/a.md': '# a\n'});
      final runner = await runnerIn(bare);

      expect(await runner.run(['build', 'docs', '--paper', 'b5']), 64);
      expect(
        err.toString(),
        '--paper takes a4, a5, letter, or legal, not b5\n',
      );

      err.clear();
      expect(await runner.run(['build', 'docs', '--margin', '5']), 64);
      expect(
        err.toString(),
        '--margin takes a length in mm, cm, or in, such as 20mm, not 5\n',
      );

      err.clear();
      expect(await runner.run(['build', 'docs', '--format', 'pdf']), 64);
      expect(err.toString(), '--format takes html, not pdf\n');
    });

    for (final format in ['pdf', 'docx']) {
      test('--format $format is 64 argument_invalid '
          'in text and json, and writes nothing', () async {
        final project = await fixtureProject(_fixture);
        final runner = await runnerIn(project);

        expect(await runner.run(['build', 'docs', '--format', format]), 64);
        expect(out.toString(), isEmpty);
        expect(err.toString(), '--format takes html, not $format\n');
        expectNothingWritten(project, '.specstone/build/docs.html');

        err.clear();
        expect(
          await runner.run(['build', 'docs', '--format', format, '--json']),
          64,
        );
        expect(out.toString(), isEmpty);
        expect(jsonDecode(err.toString()), {
          'error': {
            'code': 'argument_invalid',
            'message': '--format takes html, not $format',
          },
        });
        expectNothingWritten(project, '.specstone/build/docs.html');
      });
    }

    test('a write fault after a skipped file keeps its '
        'warning, in text and json', () async {
      final project = await fixtureProject({
        ..._fixture,
        'docs/specs/notes.md': 'notes\n',
        'blocker': 'x',
      });
      final runner = await runnerIn(project);
      const warning =
          'docs/specs/notes.md: no doc type matches this path; '
          'skipped';

      expect(
        await runner.run(['build', 'docs', '--output', 'blocker/x.html']),
        73,
      );
      expect(out.toString(), isEmpty);
      expect(
        err.toString(),
        '⚠️ WARNING: $warning\n'
        'blocker/x.html: the output path is not writable\n',
      );

      err.clear();
      expect(
        await runner.run([
          'build', 'docs', '--json', '--output', 'blocker/x.html', //
        ]),
        73,
      );
      expect(jsonDecode(err.toString()), {
        'error': {
          'code': 'output_not_writable',
          'message': 'the output path is not writable',
          'file': 'blocker/x.html',
        },
        'warnings': [warning],
      });
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
