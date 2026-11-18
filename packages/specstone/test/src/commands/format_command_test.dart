import 'dart:convert';
import 'dart:io';

import 'package:specstone/src/command_runner.dart';
import 'package:specstone_core/specstone_core.dart';
import 'package:test/test.dart';

import '../../../../specstone_core/test/helpers/agent_skills.dart'
    show skillDocText, skillProjectPacks;
import '../../../../specstone_core/test/helpers/check_fixture.dart'
    show writeCheckProject;
import '../../../../specstone_core/test/helpers/shipped_pins.dart';
import '../../../../specstone_core/test/helpers/software_design_system.dart'
    show softwareDesignSystemConfig;
import '../../helpers/built_cli.dart';
import '../../helpers/fixture_packs.dart';
import '../../helpers/read_fixture.dart';
import '../../helpers/temp_tree.dart';

const _formatUsage =
    'Usage: specstone format [<file|folder>] [--check] [--json]';

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

    test('S10: a layout-only doc gets trimmed table '
        'cells, a two-space line break, no other trailing space, and a '
        'blank line under each heading', () async {
      const disk =
          '# F-05\n## Feature name\n| a   | b  |\n|-----|----|\n'
          '| x   | yy |\n## Feature goal\nfirst    \nsecond \t\n';
      final project = await fixtureProject({_feature: disk});
      final runner = await runnerIn(project);

      expect(await runner.run(['format', _feature]), 0);

      expect(
        read(project, _feature),
        '# F-05\n\n## Feature name\n\n| a | b |\n|---|---|\n'
        '| x | yy |\n\n## Feature goal\n\nfirst  \nsecond\n',
      );
    });

    test('S3: adds no section, '
        'leaves draft as written, and check still lists the gap', () async {
      const disk = '---\ndraft: false\n---\n# F-05\n\n## Feature name\n\nx\n';
      final project = await fixtureProject({_feature: disk});
      final runner = await runnerIn(project);

      expect(await runner.run(['format', _feature]), 0);
      expect(read(project, _feature), disk);
      out.clear();
      expect(await runner.run(['check']), 1);
      expect(out.toString(), contains('required_section_missing'));
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

    test('a doc ending inside a fence is refused and left '
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
          {'path': _feature, 'status': 'formatted'},
          {'path': _notes, 'status': 'skipped'},
          {'path': _story, 'status': 'unchanged'},
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
''';
      final toc = generatedOpenMarker('note_toc');
      const end = generatedEndMarker;
      const notePath = 'docs/notes/a.md';

      Future<SpecstoneCommandRunner> noteRunnerIn(
        Directory workingDirectory,
      ) async {
        final home = await writeTree({});
        return SpecstoneCommandRunner(
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

      test('S1: a stale block gets '
          'the generator text now and every line outside it keeps its '
          'text', () async {
        const before = '# A\n\n## Contents\n\n';
        const after = '\nbody line\n\nlast line\n';
        final project = await fixtureProject({
          notePath: '$before$toc\nold\n$end$after',
        });

        expect(await (await noteRunnerIn(project)).run(['format']), 0);

        expect(read(project, notePath), '$before$toc\ntoc\n$end$after');
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

      test('f01/us01/fr05/e03: format warns on stderr when the index was '
          'rebuilt', () async {
        final project = await damagedNoteProject();

        expect(await (await noteRunnerIn(project)).run(['format']), 0);

        expect(err.toString(), '⚠️ WARNING: $damagedWarning\n');
      });

      test('f01/us01/fr05/e03: format --json lists the rebuilt-index warning '
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

      test('f01/us01/fr05/e03: format prints one warning for a non-UTF-8 doc, '
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
      final runner = SpecstoneCommandRunner();

      expect(runner.generators.kinds, runner.templates.generatorKinds);
    });

    test('the default runner registers journey_flow, scenario_copy, '
        'feature_catalog, and component_catalog', () {
      expect(SpecstoneCommandRunner().generators.kinds, {
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
        Process.run(binary, args, workingDirectory: project.path);

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

    test('a component written after the block leaves the doc as it is and '
        'format --check lists it stale', () async {
      final project = await writeTree(catalogFiles());
      expect((await run(project, ['format', discoveryFile])).exitCode, 0);
      final formatted = discoveryOf(project);
      File(
        '${project.path}/docs/specs/design_system/components/buttons/'
        'ghost_button.md',
      ).writeAsStringSync(component('Fades out.'));

      expect(discoveryOf(project), formatted);
      final check = await run(project, ['format', '--check']);

      expect(check.exitCode, 1, reason: '${check.stdout}${check.stderr}');
      expect(check.stdout, contains(discoveryFile));
      expect(discoveryOf(project), formatted);
      expect(discoveryOf(project), isNot(contains('ghost_button')));
    });

    test('format rewrites the block of an approved discovery doc and keeps '
        'it approved', () async {
      final project = await writeCheckProject(
        extra: catalogFiles(
          block:
              '${generatedOpenMarker('component_catalog')}\nold\n'
              '$generatedEndMarker\n',
        ),
      );
      final approval = RegExp(
        r'^approved: .*$',
        multiLine: true,
      ).firstMatch(discoveryOf(project))!.group(0)!;

      final result = await run(project, ['format', discoveryFile]);

      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      final text = discoveryOf(project);
      expect(text, contains(approval));
      expect(text, isNot(contains('draft: true')));
      expect(text, contains('| buttons/primary_button |'));
      expect(text, isNot(contains('\nold\n')));
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

  group('skill reference files on the shipped agent-skills', () {
    late String binary;

    setUpAll(() async => binary = await buildSpecstone());

    const skill = 'docs/specs/skills/review.md';
    const button =
        'docs/specs/design_system/components/buttons/primary_button.md';
    const tokens = 'docs/specs/design_system/foundations/TOKENS.md';
    const references = '.claude/skills/review/references/specs/design_system';
    const buttonLink =
        '[Primary button](../design_system/components/buttons/primary_button.md)';
    const tokensLink = '[Tokens](../design_system/foundations/TOKENS.md)';
    const buttonBody = '# Primary button\n\n## Purpose\n\nStarts an action.\n';

    Map<String, String> files(List<String> sources) => {
      '.specstone/config.yaml': shippedPinsConfig(skillProjectPacks),
      skill: skillDocText(sources: sources),
      button: '---\nfeature: login\nlifecycle: stable\n---\n\n$buttonBody',
      tokens: '# Tokens\n\n## Token list\n\n- color.primary\n',
    };

    Future<ProcessResult> run(Directory project, List<String> args) =>
        Process.run(binary, args, workingDirectory: project.path);

    test('format on a skill doc writes its reference files, listed in path '
        'order', () async {
      final project = await writeTree(files([tokensLink, buttonLink]));

      final result = await run(project, ['format', skill]);

      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(
        result.stdout,
        '$references/components/buttons/primary_button.md: formatted\n'
        '$references/foundations/TOKENS.md: formatted\n',
      );
      expect(
        File('${project.path}/$references/components/buttons/primary_button.md')
            .readAsStringSync(),
        '---\nlifecycle: stable\n---\n\n$buttonBody',
      );
    });

    test('a refused skill doc prints its code and message, and --json '
        'carries skillRefusal, exit 1, while the other docs are '
        'written', () async {
      final project = await writeTree(
        files([tokensLink, '[Old](../design_system/OLD.md)']),
      );

      final text = await run(project, ['format']);
      final json = await run(project, ['format', '--json']);

      expect(text.exitCode, 1, reason: '${text.stderr}');
      expect(
        text.stdout,
        '$button: formatted\n'
        '$skill: refused: skill_source_missing: the source names no doc: '
        '../design_system/OLD.md\n',
      );
      expect(json.exitCode, 1, reason: '${json.stderr}');
      expect(
        (jsonDecode(json.stdout as String) as Map<String, Object?>)['files'],
        contains(
          equals({
            'path': skill,
            'status': 'refused',
            'skillRefusal': 'skill_source_missing',
          }),
        ),
      );
      expect(Directory('${project.path}/.claude').existsSync(), isFalse);
    });

    test('--check lists a stale and a leftover reference file, exit 1, and '
        '--json gives each its status; format keeps the leftover', () async {
      final project = await writeTree(files([tokensLink]));
      await run(project, ['format']);
      const old = '.claude/skills/review/references/specs/old.md';
      File('${project.path}/$old')
        ..createSync(recursive: true)
        ..writeAsStringSync('# Old\n');
      File('${project.path}/$tokens')
          .writeAsStringSync('# Tokens\n\n## Token list\n\n- color.accent\n');
      final before = File('${project.path}/$references/foundations/TOKENS.md')
          .readAsStringSync();

      final text = await run(project, ['format', '--check']);
      final json = await run(project, ['format', '--check', '--json']);

      expect(text.exitCode, 1, reason: '${text.stderr}');
      expect(
        text.stdout,
        '$references/foundations/TOKENS.md\n$old: leftover\n',
      );
      expect(
        (jsonDecode(json.stdout as String) as Map<String, Object?>)['files'],
        containsAllInOrder([
          {'path': '$references/foundations/TOKENS.md', 'status': 'formatted'},
          {'path': old, 'status': 'leftover'},
        ]),
      );
      expect(
        File('${project.path}/$references/foundations/TOKENS.md')
            .readAsStringSync(),
        before,
      );
      final plain = await run(project, ['format']);
      expect(plain.exitCode, 0, reason: '${plain.stderr}');
      expect(plain.stdout, '$references/foundations/TOKENS.md: formatted\n');
      expect(File('${project.path}/$old').existsSync(), isTrue);
    });
  });
}
