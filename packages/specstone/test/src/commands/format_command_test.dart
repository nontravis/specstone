import 'dart:convert';
import 'dart:io';

import 'package:specstone/src/command_runner.dart';
import 'package:specstone_core/specstone_core.dart';
import 'package:test/test.dart';

import '../../../../specstone_core/test/helpers/shipped_pins.dart';
import '../../../../specstone_core/test/helpers/software_design_system.dart'
    show softwareDesignSystemConfig;
import '../../helpers/built_cli.dart';
import '../../helpers/fixture_packs.dart';
import '../../helpers/read_fixture.dart';
import '../../helpers/temp_tree.dart';
import '../../helpers/write_runner.dart';

const _formatUsage =
    'Usage: specstone format [<file|folder>] [--check [--out [<path>]]] '
    '[--json]';

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

const _featureDir = 'docs/prds/features/f05_rendering';
const _feature = '$_featureDir/FEATURE.md';
const _notes = '$_featureDir/notes.md';
const _storyDir = '$_featureDir/us01_format_docs';
const _story = '$_storyDir/USER_STORY.md';
const _featureJson = 'prds/features/f05_rendering/FEATURE.md';
const _notesJson = 'prds/features/f05_rendering/notes.md';
const _storyJson = 'prds/features/f05_rendering/us01_format_docs/USER_STORY.md';

const _featureFormatted =
    '# F-05\n\n## Feature name\n\n- **Human:** Rendering\n\n'
    '## Feature goal\n\n- **why:** share docs\n';
const _featureOutOfOrder =
    '# F-05\n\n## Feature goal\n\n- **why:** share docs\n\n'
    '## Feature name\n\n- **Human:** Rendering\n';
const _storyFormatted =
    '# US-01\n\n## Summary\n\nFormat docs.\n\n'
    '## Acceptance Criteria\n\nDone.\n';
const _storyOutOfOrder =
    '# US-01\n\n## Acceptance Criteria\n\nDone.\n\n'
    '## Summary\n\nFormat docs.\n';

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
        console: FakeConsole(),
        out: out,
        err: err,
        templates: TemplateResolver(shippedFiles: fixturePackFiles()),
        workingDirectory: workingDirectory,
        homeDirectory: home,
      );
    }

    String read(Directory project, String path) =>
        File.fromUri(project.uri.resolve(path)).readAsStringSync();

    test('formats one file named by path to the template order '
        'and prints one line', () async {
      final project = await fixtureProject({_feature: _featureOutOfOrder});
      final runner = await runnerIn(project);

      expect(await runner.run(['format', _feature]), 0);
      expect(out.toString(), '$_feature: formatted\n');
      expect(err.toString(), isEmpty);
      expect(read(project, _feature), _featureFormatted);
    });

    // ignore: lines_longer_than_80_chars -- the test name stays one literal
    test('format takes a DocPath target from the project root and from a subfolder', () async {
      final project = await fixtureProject({
        _feature: _featureOutOfOrder,
        'scratch/keep.txt': '',
      });

      final fromRoot = await runnerIn(project);
      expect(await fromRoot.run(['format', _featureJson]), 0);
      expect(out.toString(), '$_feature: formatted\n');
      expect(read(project, _feature), _featureFormatted);

      File.fromUri(project.uri.resolve(_feature))
          .writeAsStringSync(_featureOutOfOrder);
      out.clear();
      final fromSubfolder = await runnerIn(
        Directory.fromUri(project.uri.resolve('scratch/')),
      );
      expect(await fromSubfolder.run(['format', _featureJson]), 0);
      expect(out.toString(), '$_feature: formatted\n');
      expect(read(project, _feature), _featureFormatted);
    });

    test('formats a record named by its path under the records root', () async {
      const record = '.specstone/records/f05_rendering/IMPLEMENTATION.md';
      final project = await fixtureProject({
        '.specstone/templates/implementation.yaml': _recordType,
        record: '# Record\nbody   \n',
      });
      final runner = await runnerIn(project);

      expect(await runner.run(['format', record]), 0);
      expect(out.toString(), '$record: formatted\n');
      expect(err.toString(), isEmpty);
      expect(read(project, record), '# Record\n\nbody\n');
    });

    test('with no target formats every doc under '
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

    test('--check lists the doc that would change, exits 1, and '
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

    for (final json in [false, true]) {
      test('--check${json ? ' --json' : ''} --out saves the check reply and '
          'keeps the exit status 1', () async {
        final project = await fixtureProject({
          _feature: _featureOutOfOrder,
          _story: _storyFormatted,
        });
        final call = ['format', '--check', if (json) '--json'];
        expect(await (await runnerIn(project)).run(call), 1);
        final printed = out.toString();
        out.clear();

        expect(
          await (await runnerIn(project)).run([...call, '--out', 'check.txt']),
          1,
        );

        expect(err.toString(), isEmpty);
        expect(read(project, 'check.txt'), printed);
        if (json) {
          expect(jsonDecode(out.toString()), containsPair('lines', isA<int>()));
        } else {
          expect(
            out.toString(),
            matches(RegExp(r'^==> format: \d+ lines, \d+ tokens · ')),
          );
        }
        expect(read(project, _feature), _featureOutOfOrder);
        expect(read(project, _story), _storyFormatted);
      });
    }

    test(
      '--out with no --check is argument_invalid and formats nothing',
      () async {
        final project = await fixtureProject({_feature: _featureOutOfOrder});
        final runner = await runnerIn(project);

        expect(await runner.run(['format', '--out', 'gone.txt']), 64);

        expect(out.toString(), isEmpty);
        expect(err.toString(), '--out goes with --check\n');
        expect(
          File.fromUri(project.uri.resolve('gone.txt')).existsSync(),
          isFalse,
        );
        expect(read(project, _feature), _featureOutOfOrder);
      },
    );

    test('a doc no doc type matches is skipped with a warning on '
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

    test('a target outside the docs root, then a missing target, '
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

    test('outside a project prints project_not_found text on '
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

    test('--json prints every file and the warnings on '
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
          {'path': _featureJson, 'status': 'formatted'},
          {'path': _notesJson, 'status': 'skipped'},
          {'path': _storyJson, 'status': 'unchanged'},
        ],
        'warnings': ['$_notes: no doc type matches this path; skipped'],
      });
      expect(out.toString(), endsWith('}\n'));
      expect(out.toString(), contains('\n  "files": ['));
    });

    test('--json outside a project prints the error '
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

    test('--json with --check lists the doc that would '
        'change, writes nothing, and exits 1', () async {
      final project = await fixtureProject({_feature: _featureOutOfOrder});
      final runner = await runnerIn(project);

      expect(await runner.run(['format', '--check', '--json']), 1);
      expect(jsonDecode(out.toString()), {
        'files': [
          {'path': _featureJson, 'status': 'formatted'},
        ],
        'warnings': <String>[],
      });
      expect(read(project, _feature), _featureOutOfOrder);
    });

    test('a template fault reaches format as its code, exit 78', () async {
      final project = await writeTree({'.specstone/config.yaml': 'packs: [\n'});
      final runner = await runnerIn(project);

      expect(await runner.run(['format']), 78);
      expect(out.toString(), isEmpty);
      expect(err.toString(), contains('config.yaml'));
    });

    test(
      'a template fault under --json prints one error object, exit 78',
      () async {
        final project = await writeTree({
          '.specstone/config.yaml': 'packs: [\n',
        });
        final runner = await runnerIn(project);

        expect(await runner.run(['format', '--json']), 78);

        expect(out.toString(), isEmpty);
        final error =
            (jsonDecode(err.toString()) as Map<String, Object?>)['error']!
                as Map<String, Object?>;
        expect(error['code'], 'yaml_syntax');
        expect(error['file'], '.specstone/config.yaml');
      },
    );

    test('no target and no docs folder exits 64 as a missing target', () async {
      final runner = await runnerIn(await fixtureProject({}));

      expect(await runner.run(['format', '--json']), 64);

      expect(out.toString(), isEmpty);
      final error =
          (jsonDecode(err.toString()) as Map<String, Object?>)['error']!
              as Map<String, Object?>;
      expect(error['code'], 'target_not_found');
    });

    test(
      'a doc that cannot be written is output_not_writable '
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

    test('a read-only doc that needs a rewrite is '
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

    test('a doc that cannot be read is skipped with a warning '
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

    group('generated blocks', () {
      const noteDoc = '''
id: note
description: A note with a generated block.
path: notes/{slug}.md
generators: [note_toc]
sections:
  - id: contents
    header: Contents
    required: true
''';
      final toc = generatedOpenMarker('note_toc');
      const end = generatedEndMarker;
      const notePath = 'docs/notes/a.md';

      Future<SpecstoneCommandRunner> noteRunnerIn(
        Directory workingDirectory,
      ) async {
        final home = await writeTree({});
        return SpecstoneCommandRunner(
          console: FakeConsole(),
          out: out,
          err: err,
          templates: TemplateResolver(
            shippedFiles: fixturePackFiles(extra: {'note.yaml': noteDoc}),
            generatorKinds: {...shippedGeneratorKinds, 'note_toc'},
          ),
          generators: GeneratorRegistry<DocIndex>({
            'note_toc': (doc, docPath, type, index) => [
              const GeneratedBlock(
                kind: 'note_toc',
                sectionId: 'contents',
                place: SectionTop(),
                text: 'toc',
              ),
            ],
          }),
          workingDirectory: workingDirectory,
          homeDirectory: home,
        );
      }

      test('format opens the index only when a doc type under '
          'the Target lists generators', () async {
        final shipped = await fixtureProject({_feature: _featureFormatted});
        final plain = await noteRunnerIn(shipped);
        const index = '.specstone/index.sqlite';

        expect(await plain.run(['format']), 0);
        expect(File.fromUri(shipped.uri.resolve(index)).existsSync(), isFalse);

        final notes = await fixtureProject({
          notePath: '# A\n\n## Contents\n\nbody\n',
        });
        final withNote = await noteRunnerIn(notes);

        expect(await withNote.run(['format']), 0);
        expect(File.fromUri(notes.uri.resolve(index)).existsSync(), isTrue);
        expect(
          read(notes, notePath),
          '# A\n\n## Contents\n\n$toc\ntoc\n$end\n\nbody\n',
        );
      });

      test('new writes the doc with the generator text of the doc '
          'type that lists generators', () async {
        final project = await fixtureProject({});

        expect(
          await (await noteRunnerIn(project))
              .run(['new', 'note', '--slug', 'a']),
          0,
        );

        final written = read(project, notePath);
        expect(written, contains('$toc\ntoc\n$end\n'));
        expect(written, contains('## Contents'));
        expect(written.indexOf('## Contents'), lessThan(written.indexOf(toc)));
      });

      Future<Directory> damagedNoteProject() async {
        final project = await fixtureProject({
          notePath: '# A\n\n## Contents\nbody\n',
        });
        expect(await (await noteRunnerIn(project)).run(['format']), 0);
        final index = File.fromUri(
          project.uri.resolve('.specstone/index.sqlite'),
        );
        final bytes = index.readAsBytesSync();
        // Page 1 and the file size survive; the first read of a lost page
        // fails and the session rebuilds the index.
        index.writeAsBytesSync([
          ...bytes.sublist(0, 4096),
          ...List<int>.filled(bytes.length - 4096, 0xAB),
        ]);
        out.clear();
        err.clear();
        return project;
      }

      const damagedWarning =
          'the index was damaged and was rebuilt from the markdown files';

      test('format warns on stderr when the index was '
          'rebuilt', () async {
        final project = await damagedNoteProject();

        expect(await (await noteRunnerIn(project)).run(['format']), 0);

        expect(err.toString(), '⚠️ WARNING: $damagedWarning\n');
      });

      test('format --json lists the rebuilt-index warning '
          'in warnings', () async {
        final project = await damagedNoteProject();

        expect(
          await (await noteRunnerIn(project)).run(['format', '--json']),
          0,
        );

        final json = jsonDecode(out.toString()) as Map<String, Object?>;
        expect(json['warnings'], [damagedWarning]);
        expect(err.toString(), isEmpty);
      });

      test(
        'an index that cannot be written stops format with its code, exit 73',
        () async {
          final project = await fixtureProject({
            notePath: '# A\n\n## Contents\n\nbody\n',
          });
          final dot = Directory('${project.path}/.specstone');
          await Process.run('chmod', ['555', dot.path]);
          addTearDown(() => Process.run('chmod', ['755', dot.path]));

          expect(
            await (await noteRunnerIn(project)).run(['format', '--json']),
            73,
          );

          expect(out.toString(), isEmpty);
          final error =
              (jsonDecode(err.toString()) as Map<String, Object?>)['error']!
                  as Map<String, Object?>;
          expect(error['code'], 'index_not_writable');
          expect(read(project, notePath), '# A\n\n## Contents\n\nbody\n');
        },
        skip: _readOnlyFolderSkipReason(),
      );

      test('format prints one warning for a non-UTF-8 doc, '
          'its own, not the index session per-doc warning', () async {
        final project = await fixtureProject({
          notePath: '# A\n\n## Contents\nbody\n',
        });
        File.fromUri(project.uri.resolve('docs/notes/bad.md'))
            .writeAsBytesSync([0x23, 0x20, 0xFF, 0x0A]);

        expect(await (await noteRunnerIn(project)).run(['format']), 0);

        expect(
          err.toString(),
          '⚠️ WARNING: docs/notes/bad.md: not UTF-8 text; skipped\n',
        );
      });
    });

    test('a runner built without generators uses a registry whose kinds '
        'equal the template resolver kinds', () {
      final runner = SpecstoneCommandRunner(console: FakeConsole());

      expect(runner.generators.kinds, runner.templates.generatorKinds);
    });

    test('the default runner registers journey_flow, scenario_copy, '
        'feature_catalog, and component_catalog', () {
      expect(SpecstoneCommandRunner(console: FakeConsole()).generators.kinds, {
        'journey_flow',
        'scenario_copy',
        'feature_catalog',
        'component_catalog',
      });
    });

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

  group('the component catalog on the shipped software-design-system', () {
    late String binary;

    setUpAll(() async => binary = await buildSpecstone());

    const discovery = 'specs/design_system/DISCOVERY.md';
    const discoveryFile = 'docs/$discovery';
    const catalogHead =
        '| Component | Group | Purpose | Lifecycle | Doc |\n'
        '|---|---|---|---|---|';

    String component(String purpose) =>
        '---\nlifecycle: stable\nfeature: login\n---\n\n# Component\n\n'
        '## Purpose\n\n$purpose\n';

    String group(String name) => '# $name\n\n## Purpose\n\nGroups $name.\n';

    String row(String group, String name, String purpose) =>
        '| $group/$name | $group | $purpose | stable | '
        '[specs/design_system/components/$group/$name.md]'
        '(components/$group/$name.md) |';

    Map<String, String> catalogFiles({String block = ''}) => {
      '.specstone/config.yaml': softwareDesignSystemConfig(),
      discoveryFile:
          '# Discovery\n\n## Finding a component\n\nLook in a group.\n\n'
          '## Component catalog\n\n$block',
      'docs/specs/design_system/components/inputs/GROUP.md': group('Inputs'),
      'docs/specs/design_system/components/inputs/text_field.md': component(
        'Takes one line of text. Shows a label.',
      ),
      'docs/specs/design_system/components/buttons/GROUP.md': group('Buttons'),
      'docs/specs/design_system/components/buttons/primary_button.md':
          component('Starts an action.'),
    };

    Future<ProcessResult> run(Directory project, List<String> args) =>
        runSpecstone(binary, args, workingDirectory: project.path);

    String discoveryOf(Directory project) =>
        File('${project.path}/$discoveryFile').readAsStringSync();

    test('format lists each component with its group, purpose, lifecycle, '
        'and doc path, in tree order', () async {
      final project = await writeTree(catalogFiles());

      final result = await run(project, ['format', discoveryFile]);

      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      final text = discoveryOf(project);
      final first = row('buttons', 'primary_button', 'Starts an action.');
      final second = row('inputs', 'text_field', 'Takes one line of text.');
      expect(text, contains('$catalogHead\n$first\n$second\n'));
      expect(
        text,
        startsWith(
          '# Discovery\n\n## Finding a component\n\nLook in a group.\n',
        ),
      );
    });
  });

  group('the features doc on the shipped prd-core', () {
    const featuresDoc = 'docs/prds/FEATURES.md';
    const approvedStamp = 'approved: "0123456789ab"';
    const featuresRoot = 'docs/prds/features';

    String story(String status) =>
        '---\nstatus: $status\n---\n\n# Agent uses it\n\n'
        '## Use Case\nUse it.\n';

    String feature(String title, {String front = ''}) =>
        '${front.isEmpty ? '' : '---\n$front---\n\n'}# $title\n\n'
        '## Problem\nNeed it.\n';

    String read(Directory project) =>
        File.fromUri(project.uri.resolve(featuresDoc)).readAsStringSync();

    Future<String> formatFeaturesDoc(Directory project) async {
      final run = readRunner(project);
      expect(
        await run.runner.run(['format', featuresDoc]),
        0,
        reason: '${run.out}${run.err}',
      );
      expect(run.err.toString(), isEmpty);
      return read(project);
    }

    test('format writes the catalog, rewrites an edited line, lists a new '
        'feature, and keeps the doc approved', () async {
      final project = await writeTree({
        '.specstone/config.yaml': shippedPinsConfig(['prd-core']),
        featuresDoc:
            '---\n$approvedStamp\n---\n\n# Feature map\n\n## Features\n\n'
            '## System interaction diagram\n\n```mermaid\nflowchart LR\n'
            '  Owner --> Shop\n```\n\n## Systems\n\n| System | Description |\n'
            '|---|---|\n| Shop | Sells goods. |\n',
        '$featuresRoot/f01_shop/FEATURE.md': feature(
          'Shop',
          front:
              'summary: Lets a shopper buy goods.\nvision:\n  - PV-01\n'
              'goals:\n  - PG-01\n',
        ),
        '$featuresRoot/f01_shop/us01_greet/USER_STORY.md': story('implemented'),
        '$featuresRoot/f01_shop/f01_cart/FEATURE.md': feature('Cart'),
        '$featuresRoot/f01_shop/f01_cart/us01_add/USER_STORY.md': story(
          'planned',
        ),
        '$featuresRoot/f02_blog/FEATURE.md': feature(
          'Blog',
          front: 'summary: Lets an author publish posts.\n',
        ),
        '$featuresRoot/f02_blog/us01_post/USER_STORY.md': story('implemented'),
        '$featuresRoot/f03_pay/FEATURE.md': feature('Pay'),
        '$featuresRoot/f03_pay/us01_charge/USER_STORY.md': story('implemented'),
      });

      final first = await formatFeaturesDoc(project);

      expect(
        first,
        contains('3 features · 4 stories · 2 implemented, 1 planned'),
      );
      expect(
        first,
        contains(
          '| [Shop](features/f01_shop/FEATURE.md) | Lets a shopper buy goods. '
          '| planned | 1/2 | PV-01, PG-01 |',
        ),
      );
      expect(
        first,
        contains(
          '| [Pay](features/f03_pay/FEATURE.md) | — | implemented | 1/1 | — |',
        ),
      );
      expect(first, isNot(contains('Cart')));

      File.fromUri(project.uri.resolve(featuresDoc)).writeAsStringSync(
        first.replaceFirst('Lets a shopper buy goods.', 'edited by hand'),
      );
      File.fromUri(project.uri.resolve('$featuresRoot/f04_search/FEATURE.md'))
        ..createSync(recursive: true)
        ..writeAsStringSync(feature('Search'));
      File.fromUri(
          project.uri.resolve(
            '$featuresRoot/f04_search/us01_find/USER_STORY.md',
          ),
        )
        ..createSync(recursive: true)
        ..writeAsStringSync(story('planned'));

      final second = await formatFeaturesDoc(project);

      expect(
        second,
        contains('4 features · 5 stories · 2 implemented, 2 planned'),
      );
      expect(
        second,
        contains(
          '| [Search](features/f04_search/FEATURE.md) | — | planned | 0/1 | — |',
        ),
      );
      expect(second, contains('Lets a shopper buy goods.'));
      expect(second, isNot(contains('edited by hand')));
      expect(second, contains(approvedStamp));
      expect(second, isNot(contains('draft: true')));
    });
  });
}
