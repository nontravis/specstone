import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:specstone/src/command_runner.dart';
import 'package:specstone_core/specstone_core.dart';
import 'package:test/test.dart';

import '../../../../specstone_core/test/helpers/shared_lines.dart';
import '../../../../specstone_core/test/helpers/shipped_pins.dart';
import '../../helpers/built_cli.dart';
import '../../helpers/temp_tree.dart';
import '../../helpers/write_runner.dart';

const _configPath = '.specstone/config.yaml';
const _guideUsage = 'Usage: specstone guide [type …] [--json]';

/// The doc `Limits:` line of a doc type whose layers set no limit.
const _docLimits = 'Limits: $builtInLimitClauses';

/// A project doc type that adds `fr` beside the shipped fixture's two.
const _frLayer = <String, String>{
  '.specstone/templates/fr.yaml':
      'id: fr\ndescription: One requirement.\npath: frs/{slug}.md\n',
};

Uint8List _bytes(String text) => Uint8List.fromList(utf8.encode(text));

/// True when an ancestor of the system temp folder holds a project config.
bool _tempHasConfigAncestor() {
  Directory? dir = Directory.systemTemp.absolute;
  while (dir != null) {
    if (File.fromUri(dir.uri.resolve(_configPath)).existsSync()) return true;
    final parent = dir.parent;
    dir = parent.path == dir.path ? null : parent;
  }
  return false;
}

/// The shipped fixture: `prd-core` holds `feature` and `user_story`.
Map<String, Uint8List> shipped() => {
  'prd-core/pack.yaml': _bytes('name: prd-core\nversion: 1.1.0\n'),
  'prd-core/feature.yaml': _bytes('''
id: feature
description: |
  A feature groups the stories that serve one goal.

  Second paragraph.
path: prds/features/f{nn}_{slug}/FEATURE.md
sections:
  - id: goal
    header: Feature goal
    description: Why, problem, and audience, one sentence each.
'''),
  'prd-core/user_story.yaml': _bytes(
    'id: user_story\ndescription: One story\npath: us{nn}_{slug}/US.md\n',
  ),
};

const _cycleConfig =
    'packs:\n  prd-core: 1.1.0\n  nont-a: 1.0.0\n  nont-b: 1.0.0\n';

/// A home folder whose personal packs `nont-a` and `nont-b` extend each other.
Future<Directory> _cycleHome() => writeTree({
  '.specstone/packs/nont-a/pack.yaml':
      'name: nont-a\nversion: 1.0.0\nextends: nont-b\n',
  '.specstone/packs/nont-b/pack.yaml':
      'name: nont-b\nversion: 1.0.0\nextends: nont-a\n',
});

const _patternConfig = 'packs:\n  prd-core: 1.1.0\n  software-tech: 1.0.0\n';

/// The shipped fixture plus a `software-tech` pack that holds three feature
/// patterns, `signup` extending `auth`.
Map<String, Uint8List> _shippedWithPatterns() => {
  ...shipped(),
  'software-tech/pack.yaml': _bytes('name: software-tech\nversion: 1.0.0\n'),
  'software-tech/patterns/auth.yaml': _bytes('''
id: auth
description: Sign-in.
items:
  - id: lockout
    text: Name the lockout rule.
  - id: reset
    text: Name the reset path.
'''),
  'software-tech/patterns/signup.yaml': _bytes('''
id: signup
description: Sign-up.
extends: auth
items:
  - id: verify_email
    text: Name the email check.
'''),
  'software-tech/patterns/crud.yaml': _bytes('''
id: crud
description: |
  Create, read, list, update, and delete one resource.

  Second paragraph.
items:
  - id: soft_delete
    text: A deleted record stays restorable for a stated time.
  - id: page_list
    text: A list returns its records in pages with a stable order.
reference:
  - title: Google AIP-164 Soft delete
    url: https://google.aip.dev/164
'''),
};

void main() {
  group('specstone guide', () {
    late StringBuffer out;
    late StringBuffer err;

    setUp(() {
      out = StringBuffer();
      err = StringBuffer();
    });

    Future<SpecstoneCommandRunner> runnerIn(Directory project) async {
      final home = await writeTree({});
      return SpecstoneCommandRunner(
        console: FakeConsole(),
        out: out,
        err: err,
        templates: TemplateResolver(shippedFiles: shipped()),
        workingDirectory: project,
        homeDirectory: home,
      );
    }

    Future<Directory> projectWith(Map<String, String> files) =>
        writeTree({_configPath: 'packs:\n  prd-core: 1.1.0\n', ...files});

    test('lists one doc type id per line', () async {
      final runner = await runnerIn(await projectWith({}));

      expect(await runner.run(['guide']), 0);
      expect(out.toString(), 'feature\nuser_story\n');
      expect(err.toString(), isEmpty);
    });

    test('--json lists id, pack, and description '
        'of each doc type', () async {
      final runner = await runnerIn(await projectWith({}));

      expect(await runner.run(['guide', '--json']), 0);
      expect(jsonDecode(out.toString()), [
        {
          'id': 'feature',
          'pack': 'prd-core',
          'description': 'A feature groups the stories that serve one goal.',
        },
        {'id': 'user_story', 'pack': 'prd-core', 'description': 'One story'},
      ]);
      expect(err.toString(), isEmpty);
    });

    test('a type prints its writing guide', () async {
      final runner = await runnerIn(await projectWith({}));

      expect(await runner.run(['guide', 'feature']), 0);
      expect(
        out.toString(),
        'A feature groups the stories that serve one goal.\n\n'
        'Second paragraph.\n\n$_docLimits\n\n'
        '## Feature goal\n'
        'Optional.\n'
        'Why, problem, and audience, one sentence each.\n',
      );
      expect(err.toString(), isEmpty);
    });

    test('a type with --json prints the merged '
        'schema with a two-space indent', () async {
      final runner = await runnerIn(await projectWith({}));

      expect(await runner.run(['guide', 'feature', '--json']), 0);
      final decoded = jsonDecode(out.toString()) as Map<String, Object?>;
      expect(decoded['id'], 'feature');
      expect(decoded['path'], 'prds/features/f{nn}_{slug}/FEATURE.md');
      expect(decoded.containsKey('parent'), isFalse);
      expect(out.toString(), startsWith('{\n  "id": "feature",\n'));
      expect(err.toString(), isEmpty);
    });

    test('a path_from type with --json prints paths after description and '
        'no path', () async {
      final runner = await runnerIn(
        await projectWith({
          '.specstone/templates/feature.yaml':
              'path: prds/features/{slug}/f{nn}_{slug}/FEATURE.md\n',
          '.specstone/templates/area_index.yaml':
              'id: area_index\ndescription: One index per group.\n'
              'path_from: feature_groups\nfile: AREA.md\n',
        }),
      );

      expect(await runner.run(['guide', 'area_index', '--json']), 0);
      final decoded = jsonDecode(out.toString()) as Map<String, Object?>;
      expect(decoded.keys.take(3), ['id', 'description', 'paths']);
      expect(decoded['paths'], ['prds/features/{slug}/AREA.md']);
      expect(decoded.containsKey('path'), isFalse);
      expect(err.toString(), isEmpty);
    });

    test('an unknown type prints usage and '
        'exits 64', () async {
      final runner = await runnerIn(await projectWith({}));

      expect(await runner.run(['guide', 'featur']), 64);
      expect(
        err.toString(),
        contains('Could not find a doc type named "featur".\n\n$_guideUsage'),
      );
      expect(out.toString(), isEmpty);
    });

    // The test name stays one literal so specstone check can find it.
    // ignore: lines_longer_than_80_chars
    test('an unknown type with --json prints the envelope pretty-printed with no file or key', () async {
      final runner = await runnerIn(await projectWith({}));

      for (final args in [
        ['guide', 'featur', '--json'],
        ['guide', 'feature', 'featur', '--json'],
      ]) {
        err.clear();
        expect(await runner.run(args), 64, reason: args.join(' '));
        expect(out.toString(), isEmpty);
        expect(
          err.toString(),
          '{\n'
          '  "error": {\n'
          '    "code": "doc_type_unknown",\n'
          '    "message": "Could not find a doc type named \\"featur\\"."\n'
          '  },\n'
          '  "warnings": []\n'
          '}\n',
          reason: args.join(' '),
        );
      }
    });

    test(
      'a broken project template with no type prints file and line, exit 78',
      () async {
        final runner = await runnerIn(
          await projectWith({'.specstone/templates/feature.yaml': 'id: [\n'}),
        );

        expect(await runner.run(['guide']), 78);
        expect(
          err.toString(),
          matches(RegExp(r'^\.specstone/templates/feature\.yaml:\d+: ')),
        );
        expect(out.toString(), isEmpty);
      },
    );

    test('--json reports a fault as one '
        'envelope on stderr and exits 78', () async {
      final runner = await runnerIn(
        await projectWith({'.specstone/templates/feature.yaml': 'bogus: 1\n'}),
      );

      expect(await runner.run(['guide', '--json']), 78);
      expect(out.toString(), isEmpty);
      expect(err.toString(), startsWith('{\n  "error": {\n    "code"'));
      final error =
          (jsonDecode(err.toString()) as Map<String, Object?>)['error']!
              as Map<String, Object?>;
      expect(error['code'], 'unknown_key');
      expect(error['message'], isA<String>());
      expect(error['file'], '.specstone/templates/feature.yaml');
      expect(error['key'], 'bogus');
    });

    for (final args in [
      ['--version'],
      ['--help'],
      ['help'],
      <String>[],
      ['help', 'guide'],
    ]) {
      test('`${args.join(' ')}` ignores a broken config', () async {
        final project = await writeTree({_configPath: 'packs: [\n'});
        final runner = await runnerIn(project);

        expect(await runner.run(args), 0);
        expect(err.toString(), isEmpty);
      });
    }

    test('guide --help prints the usage to out and exits 0', () async {
      final runner = await runnerIn(await projectWith({}));

      expect(await runner.run(['guide', '--help']), 0);
      expect(out.toString(), contains(_guideUsage));
      expect(err.toString(), isEmpty);
    });

    test('help guide prints the usage to out and exits 0', () async {
      final runner = await runnerIn(await projectWith({}));

      expect(await runner.run(['help', 'guide']), 0);
      expect(out.toString(), contains(_guideUsage));
      expect(err.toString(), isEmpty);
    });

    // The test name stays one literal so specstone check can find it.
    // ignore: lines_longer_than_80_chars
    test('two type arguments that no pack defines exit 64, naming both and the usage', () async {
      final runner = await runnerIn(await projectWith({}));

      expect(await runner.run(['guide', 'a', 'b']), 64);
      expect(out.toString(), isEmpty);
      expect(
        err.toString(),
        contains('Could not find doc types named "a", "b".\n\n$_guideUsage'),
      );
      expect(
        err.toString(),
        startsWith('Could not find doc types named "a", "b".\n\n$_guideUsage'),
      );
      expect(err.toString(), isNot(contains('doc_type_unknown')));
    });

    test('two '
        'unknown ids among known ones refuse the whole call, name each, and '
        'print no guide', () async {
      final runner = await runnerIn(await projectWith({}));

      expect(await runner.run(['guide', 'featur', 'feature', 'stroy']), 64);
      expect(out.toString(), isEmpty);
      expect(
        err.toString(),
        contains(
          'Could not find doc types named "featur", "stroy".\n\n$_guideUsage',
        ),
      );
    });

    test('one '
        'unknown id among known ones names it in the singular form and '
        'prints no guide', () async {
      final runner = await runnerIn(await projectWith({}));

      expect(await runner.run(['guide', 'feature', 'featur']), 64);
      expect(out.toString(), isEmpty);
      expect(
        err.toString(),
        contains('Could not find a doc type named "featur".\n\n$_guideUsage'),
      );
    });

    test('an '
        'unknown id named twice is named once', () async {
      final runner = await runnerIn(await projectWith({}));

      expect(await runner.run(['guide', 'featur', 'featur']), 64);
      expect(out.toString(), isEmpty);
      expect(
        err.toString(),
        contains('Could not find a doc type named "featur".\n\n$_guideUsage'),
      );
    });

    test(
      'a repeated id prints once at its first place under ==> lines',
      () async {
        final runner = await runnerIn(await projectWith(_frLayer));

        expect(await runner.run(['guide', 'fr', 'user_story', 'fr']), 0);
        expect(
          out.toString(),
          '==> shared <==\n'
          '==> fr <==\n'
          'One requirement.\n\n$_docLimits\n'
          '==> user_story <==\n'
          'One story\n\n$_docLimits\n',
        );
        expect(err.toString(), isEmpty);
      },
    );

    test(
      'one id named twice prints its guide once, with no ==> line',
      () async {
        final runner = await runnerIn(await projectWith(_frLayer));

        expect(await runner.run(['guide', 'fr', 'fr']), 0);
        expect(out.toString(), 'One requirement.\n\n$_docLimits\n');
        expect(err.toString(), isEmpty);
      },
    );

    test("read several doc types' guides in "
        'one call, each once in the order named under its own line', () async {
      final runner = await runnerIn(await projectWith(_frLayer));

      expect(await runner.run(['guide', 'user_story', 'feature', 'fr']), 0);
      expect(
        out.toString(),
        '==> shared <==\n'
        '==> user_story <==\n'
        'One story\n\n$_docLimits\n'
        '==> feature <==\n'
        'A feature groups the stories that serve one goal.\n\n'
        'Second paragraph.\n\n$_docLimits\n\n'
        '## Feature goal\n'
        'Optional.\n'
        'Why, problem, and audience, one sentence each.\n'
        '==> fr <==\n'
        'One requirement.\n\n$_docLimits\n',
      );
      expect(err.toString(), isEmpty);
    });

    test('several merged schemas for a '
        'program come as one list in the order named', () async {
      final runner = await runnerIn(await projectWith(_frLayer));

      expect(
        await runner.run(['guide', 'user_story', 'feature', 'fr', '--json']),
        0,
      );
      final json = jsonDecode(out.toString()) as List<Object?>;
      expect(json.cast<Map<String, Object?>>().map((type) => type['id']), [
        'user_story',
        'feature',
        'fr',
      ]);
      expect(out.toString(), startsWith('[\n  {\n    "id": "user_story",\n'));
      expect(err.toString(), isEmpty);
    });

    test('an empty '
        'id refuses the call with exit 64 and names ""', () async {
      final runner = await runnerIn(await projectWith({}));

      expect(await runner.run(['guide', '']), 64);
      expect(out.toString(), isEmpty);
      expect(
        err.toString(),
        contains('Could not find a doc type named "".\n\n$_guideUsage'),
      );
    });

    test('an empty '
        'id beside a known one refuses the whole call', () async {
      final runner = await runnerIn(await projectWith(_frLayer));

      expect(await runner.run(['guide', 'fr', '']), 64);
      expect(out.toString(), isEmpty);
      expect(
        err.toString(),
        contains('Could not find a doc type named "".\n\n$_guideUsage'),
      );
    });

    test('a broken '
        'template file with an unknown id among the types exits 78 with the '
        'template fault and no output', () async {
      final runner = await runnerIn(
        await projectWith({'.specstone/templates/fr.yaml': 'id: [\n'}),
      );

      expect(await runner.run(['guide', 'fr', 'nope']), 78);
      expect(out.toString(), isEmpty);
      expect(
        err.toString(),
        matches(RegExp(r'^\.specstone/templates/fr\.yaml:\d+: ')),
      );
    });

    test('a broken '
        'template file with an unknown id among the types exits 78 with one '
        'JSON envelope', () async {
      final runner = await runnerIn(
        await projectWith({'.specstone/templates/fr.yaml': 'bogus: 1\n'}),
      );

      expect(await runner.run(['guide', 'fr', 'nope', '--json']), 78);
      expect(out.toString(), isEmpty);
      final error =
          (jsonDecode(err.toString()) as Map<String, Object?>)['error']!
              as Map<String, Object?>;
      expect(error['code'], 'unknown_key');
      expect(error['file'], '.specstone/templates/fr.yaml');
      expect(error['key'], 'bogus');
    });

    test(
      'unknown ids with --json print one envelope naming each, stdout empty',
      () async {
        final runner = await runnerIn(await projectWith({}));

        expect(
          await runner.run(['guide', 'featur', 'feature', 'stroy', '--json']),
          64,
        );
        expect(out.toString(), isEmpty);
        expect(err.toString(), startsWith('{\n  "error": {\n    "code"'));
        final error =
            (jsonDecode(err.toString()) as Map<String, Object?>)['error']!
                as Map<String, Object?>;
        expect(error['code'], 'doc_type_unknown');
        expect(
          error['message'],
          'Could not find doc types named "featur", "stroy".',
        );
      },
    );

    test(
      'a repeated id with --json prints one array in order, the id once',
      () async {
        final runner = await runnerIn(await projectWith(_frLayer));

        expect(
          await runner.run(['guide', 'fr', 'user_story', 'fr', '--json']),
          0,
        );
        final json = jsonDecode(out.toString()) as List<Object?>;
        expect(json.cast<Map<String, Object?>>().map((type) => type['id']), [
          'fr',
          'user_story',
        ]);
        expect(err.toString(), isEmpty);
      },
    );

    test('one id named '
        'twice with --json prints the object alone', () async {
      final runner = await runnerIn(await projectWith(_frLayer));

      expect(await runner.run(['guide', 'fr', 'fr', '--json']), 0);
      final json = jsonDecode(out.toString()) as Map<String, Object?>;
      expect(json['id'], 'fr');
      expect(out.toString(), startsWith('{\n  "id": "fr",\n'));
      expect(err.toString(), isEmpty);
    });

    SpecstoneCommandRunner runnerWithHome(Directory project, Directory home) =>
        SpecstoneCommandRunner(
          console: FakeConsole(),
          out: out,
          err: err,
          templates: TemplateResolver(shippedFiles: shipped()),
          workingDirectory: project,
          homeDirectory: home,
        );

    Map<String, Object?> errorOf() =>
        (jsonDecode(err.toString()) as Map<String, Object?>)['error']!
            as Map<String, Object?>;

    test('a config fault, a personal pack.yaml fault, and a multi-file fault '
        'under a type id print the text message and exit 78', () async {
      final configRunner = await runnerIn(
        await writeTree({_configPath: 'packs: [\n'}),
      );
      expect(await configRunner.run(['guide', 'feature']), 78);
      expect(out.toString(), isEmpty);
      expect(
        err.toString(),
        matches(RegExp(r'^\.specstone/config\.yaml:\d+: ')),
      );
      expect(err.toString(), isNot(startsWith('{')));

      err.clear();
      final packRunner = runnerWithHome(
        await writeTree({
          _configPath: 'packs:\n  prd-core: 1.1.0\n  nont-a: 1.0.0\n',
        }),
        await writeTree({'.specstone/packs/nont-a/pack.yaml': 'name: [\n'}),
      );
      expect(await packRunner.run(['guide', 'feature']), 78);
      expect(out.toString(), isEmpty);
      expect(
        err.toString(),
        matches(RegExp(r'^~/\.specstone/packs/nont-a/pack\.yaml:\d+: ')),
      );

      err.clear();
      final cycleRunner = runnerWithHome(
        await writeTree({_configPath: _cycleConfig}),
        await _cycleHome(),
      );
      expect(await cycleRunner.run(['guide', 'feature']), 78);
      expect(out.toString(), isEmpty);
      expect(
        err.toString(),
        startsWith('~/.specstone/packs/nont-b/pack.yaml: '),
      );
      expect(
        err.toString(),
        endsWith('; also ~/.specstone/packs/nont-a/pack.yaml\n'),
      );
    });

    test('a faulty config file or personal pack.yaml under guide with no type '
        'exits 78 with its code', () async {
      final configRunner = await runnerIn(
        await writeTree({_configPath: 'packs: [\n'}),
      );
      expect(await configRunner.run(['guide', '--json']), 78);
      expect(out.toString(), isEmpty);
      expect(errorOf()['code'], 'yaml_syntax');
      expect(errorOf()['file'], _configPath);

      err.clear();
      final packRunner = runnerWithHome(
        await writeTree({
          _configPath: 'packs:\n  prd-core: 1.1.0\n  nont-a: 1.0.0\n',
        }),
        await writeTree({'.specstone/packs/nont-a/pack.yaml': 'name: [\n'}),
      );
      expect(await packRunner.run(['guide', '--json']), 78);
      expect(out.toString(), isEmpty);
      expect(errorOf()['code'], 'yaml_syntax');
      expect(errorOf()['file'], '~/.specstone/packs/nont-a/pack.yaml');
    });

    test(
      'guide --json holds the yaml_syntax line, relatedFiles for a multi-file '
      'fault, and no file or key when none applies',
      () async {
        final syntax = await runnerIn(
          await projectWith({'.specstone/templates/feature.yaml': 'id: [\n'}),
        );
        expect(await syntax.run(['guide', '--json']), 78);
        expect(errorOf()['code'], 'yaml_syntax');
        expect(errorOf()['file'], '.specstone/templates/feature.yaml');
        expect(errorOf()['line'], isA<int>());
        expect(errorOf().containsKey('key'), isFalse);
        expect(errorOf().containsKey('relatedFiles'), isFalse);

        err.clear();
        final cycle = runnerWithHome(
          await writeTree({_configPath: _cycleConfig}),
          await _cycleHome(),
        );
        expect(await cycle.run(['guide', '--json']), 78);
        expect(errorOf()['code'], 'extends_cycle');
        expect(errorOf()['file'], '~/.specstone/packs/nont-b/pack.yaml');
        expect(errorOf()['relatedFiles'], [
          '~/.specstone/packs/nont-a/pack.yaml',
        ]);

        err.clear();
        final unknown = await runnerIn(await projectWith({}));
        expect(await unknown.run(['guide', 'featur', '--json']), 64);
        expect(errorOf().keys, ['code', 'message']);
      },
    );

    test(
      'outside a project guide loads every shipped pack and checks no pin',
      () async {
        final runner = SpecstoneCommandRunner(
          console: FakeConsole(),
          out: out,
          err: err,
          templates: TemplateResolver(
            shippedFiles: {
              ...shipped(),
              'software-tech/pack.yaml': _bytes(
                'name: software-tech\nversion: 1.0.0\n',
              ),
              'software-tech/topic.yaml': _bytes(
                'id: topic\ndescription: One topic.\npath: topics/{slug}.md\n',
              ),
            },
          ),
          workingDirectory: await writeTree({}),
          homeDirectory: await writeTree({}),
        );

        expect(await runner.run(['guide']), 0);
        expect(out.toString(), 'feature\ntopic\nuser_story\n');
        expect(err.toString(), isEmpty);
      },
      skip: _tempHasConfigAncestor()
          ? 'an ancestor of the system temp folder holds $_configPath'
          : false,
    );

    group('in the built CLI', () {
      late String binary;

      setUpAll(() async => binary = await buildSpecstone());

      Future<String> guideOut(Directory project, List<String> args) async {
        final result = await runSpecstone(binary, [
          'guide',
          ...args,
        ], workingDirectory: project.path);
        expect(result.exitCode, 0, reason: '${result.stderr}');
        return result.stdout as String;
      }

      test('the text guide lists every declared field and marks every '
          'section as --json gives', () async {
        final project = await writeTree({_configPath: shippedPinsConfig()});
        final ids = const LineSplitter().convert(await guideOut(project, []));
        final builtIn = builtInFields.map((field) => field.id).toSet();
        expect(ids, isNotEmpty);

        for (final id in ids) {
          final text = await guideOut(project, [id]);
          final json = jsonDecode(
            await guideOut(project, [id, '--json']),
          ) as Map<String, Object?>;

          for (final field
              in (json['fields']! as List<Object?>)
                  .cast<Map<String, Object?>>()) {
            final fieldId = field['id']! as String;
            final line = '\n- `$fieldId` (';
            if (builtIn.contains(fieldId)) {
              expect(text, isNot(contains(line)), reason: '$id.$fieldId');
              continue;
            }
            final flag = field['required'] == true ? 'required' : 'optional';
            expect(text, contains('$line$flag, '), reason: '$id.$fieldId');
          }
          for (final section
              in (json['sections']! as List<Object?>)
                  .cast<Map<String, Object?>>()) {
            final isConditional =
                section['whenField'] != null || section['requiredWhen'] != null;
            final isRequired =
                section['required'] == true || section['requiredWhen'] != null;
            final word = isRequired ? 'Required' : 'Optional';
            final mark = isConditional ? '$word when ' : word;
            expect(
              text,
              contains('## ${section['header']}\n$mark'),
              reason: '$id.${section['id']}',
            );
          }
        }
      });

      test('the guide of a shipped type prints its limits lines', () async {
        const sectionSizeKeys = {
          'minLines',
          'maxLines',
          'maxChars',
          'maxItemLines',
          'maxSubsections',
          'itemCount',
          'maxSentences',
          'maxCodeBlocks',
        };
        final project = await writeTree({_configPath: shippedPinsConfig()});
        final ids = const LineSplitter().convert(await guideOut(project, []));
        expect(ids, isNotEmpty);

        for (final id in ids) {
          final text = await guideOut(project, [id]);
          final json = jsonDecode(
            await guideOut(project, [id, '--json']),
          ) as Map<String, Object?>;
          final docLines = text
              .split('\n')
              .where((line) => line.startsWith('Limits: '));
          expect(docLines, hasLength(1), reason: id);

          for (final field
              in (json['fields']! as List<Object?>)
                  .cast<Map<String, Object?>>()) {
            final fieldId = field['id']! as String;
            final start = text.indexOf('\n- `$fieldId` (');
            if (start < 0) continue;
            final next = text.indexOf('\n- `', start + 1);
            final end = next < 0 ? text.indexOf('\n\nLimits: ', start) : next;
            final line = text.substring(start, end);
            expect(
              line.contains('\n  Limits: '),
              ((field['lint'] as Map<String, Object?>?) ?? {}).isNotEmpty,
              reason: '$id.$fieldId',
            );
            final targets = (field['docTypes'] as List<Object?>?) ?? const [];
            if (targets.isNotEmpty) {
              expect(
                line,
                contains(' → ${targets.join(', ')})'),
                reason: '$id.$fieldId',
              );
            }
          }
          for (final section
              in (json['sections']! as List<Object?>)
                  .cast<Map<String, Object?>>()) {
            final lint = (section['lint'] as Map<String, Object?>?) ?? {};
            final start = text.indexOf('## ${section['header']}\n');
            final line = text.substring(
              start,
              text.indexOf('\n', start + '## ${section['header']}\n'.length),
            );
            expect(
              line.endsWith('\nRequired.') ||
                  line.endsWith('\nOptional.') ||
                  line.endsWith('; left out otherwise.'),
              !lint.keys.any(sectionSizeKeys.contains),
              reason: '$id.${section['id']}',
            );
          }
        }
      });
    });
  });

  group('specstone guide --pattern', () {
    late StringBuffer out;
    late StringBuffer err;

    setUp(() {
      out = StringBuffer();
      err = StringBuffer();
    });

    Future<SpecstoneCommandRunner> runnerIn(Directory project) async =>
        SpecstoneCommandRunner(
          console: FakeConsole(),
          out: out,
          err: err,
          templates: TemplateResolver(shippedFiles: _shippedWithPatterns()),
          workingDirectory: project,
          homeDirectory: await writeTree({}),
        );

    Future<Directory> projectWith([Map<String, String> files = const {}]) =>
        writeTree({_configPath: _patternConfig, ...files});

    Future<Map<String, Object?>> errorOf(List<String> args) async {
      final runner = await runnerIn(await projectWith());
      expect(await runner.run(args), 64);
      expect(out.toString(), isEmpty);
      return (jsonDecode(err.toString()) as Map<String, Object?>)['error']!
          as Map<String, Object?>;
    }

    test('lists every pattern id in code point order, one per line', () async {
      final runner = await runnerIn(await projectWith());

      expect(await runner.run(['guide', '--pattern']), 0);
      expect(out.toString(), 'auth\ncrud\nsignup\n');
      expect(err.toString(), isEmpty);
    });

    test('--json lists id, pack, and the first description line, '
        'pretty-printed', () async {
      final runner = await runnerIn(await projectWith());

      expect(await runner.run(['guide', '--pattern', '--json']), 0);
      expect(out.toString(), startsWith('[\n  {\n    "id": "auth",\n'));
      expect(jsonDecode(out.toString()), [
        {'id': 'auth', 'pack': 'software-tech', 'description': 'Sign-in.'},
        {
          'id': 'crud',
          'pack': 'software-tech',
          'description': 'Create, read, list, update, and delete one resource.',
        },
        {'id': 'signup', 'pack': 'software-tech', 'description': 'Sign-up.'},
      ]);
      expect(err.toString(), isEmpty);
    });

    test('a broken pattern file exits 78 with stdout empty', () async {
      final runner = await runnerIn(
        await projectWith({
          '.specstone/templates/patterns/crud.yaml': 'id: [\n',
        }),
      );

      expect(await runner.run(['guide', '--pattern']), 78);
      expect(out.toString(), isEmpty);
      expect(
        err.toString(),
        matches(RegExp(r'^\.specstone/templates/patterns/crud\.yaml:\d+: ')),
      );
    });

    test('a merge fault or a config fault under guide --pattern exits 78 '
        'naming its file', () async {
      final merge = await runnerIn(
        await projectWith({
          '.specstone/templates/patterns/crud.yaml':
              'id: crud\nextends: ghost\n',
        }),
      );
      expect(await merge.run(['guide', '--pattern']), 78);
      expect(out.toString(), isEmpty);
      expect(
        err.toString(),
        startsWith('.specstone/templates/patterns/crud.yaml: '),
      );

      err.clear();
      final config = await runnerIn(
        await writeTree({_configPath: 'packs: [\n'}),
      );
      expect(await config.run(['guide', '--pattern']), 78);
      expect(out.toString(), isEmpty);
      expect(err.toString(), startsWith('$_configPath:'));
    });

    test('a pattern prints its description, items, and sources', () async {
      final runner = await runnerIn(await projectWith());

      expect(await runner.run(['guide', '--pattern', 'crud']), 0);
      expect(
        out.toString(),
        'Create, read, list, update, and delete one resource.\n\n'
        'Second paragraph.\n'
        '- **soft_delete** A deleted record stays restorable for a stated '
        'time.\n'
        '- **page_list** A list returns its records in pages with a stable '
        'order.\n'
        'Pattern sources:\n'
        '- Google AIP-164 Soft delete: https://google.aip.dev/164\n',
      );
      expect(err.toString(), isEmpty);
    });

    test('an unknown id exits 64 with the message alone on stderr and '
        'stdout empty', () async {
      final runner = await runnerIn(await projectWith());

      expect(await runner.run(['guide', '--pattern', 'featur']), 64);
      expect(out.toString(), isEmpty);
      expect(
        err.toString(),
        'Could not find a feature pattern named "featur".\n',
      );
    });

    test('several unknown ids among known ones are all named in the '
        'plural form', () async {
      final runner = await runnerIn(await projectWith());

      expect(
        await runner.run(['guide', '--pattern', 'crd', 'crud', 'ath']),
        64,
      );
      expect(out.toString(), isEmpty);
      expect(
        err.toString(),
        'Could not find feature patterns named "crd", "ath".\n',
      );
    });

    test('an unknown id with --json prints the error envelope on '
        'stderr, pretty-printed, with no file or key', () async {
      final runner = await runnerIn(await projectWith());

      expect(await runner.run(['guide', '--pattern', 'crd', '--json']), 64);
      expect(out.toString(), isEmpty);
      expect(
        err.toString(),
        '{\n'
        '  "error": {\n'
        '    "code": "feature_pattern_unknown",\n'
        '    "message": "Could not find a feature pattern named \\"crd\\"."\n'
        '  },\n'
        '  "warnings": []\n'
        '}\n',
      );
    });

    test('several unknown ids with --json name each in one message', () async {
      final error = await errorOf(['guide', '--pattern', 'a', 'b', '--json']);

      expect(error['code'], 'feature_pattern_unknown');
      expect(
        error['message'],
        'Could not find feature patterns named "a", "b".',
      );
    });

    test('--pattern reads the pattern and no flag reads the doc type '
        'of the same id', () async {
      final runner = await runnerIn(
        await projectWith({
          '.specstone/templates/auth.yaml':
              'id: auth\ndescription: The auth doc type.\npath: auth.md\n',
        }),
      );

      expect(await runner.run(['guide', '--pattern', 'auth']), 0);
      expect(out.toString(), startsWith('Sign-in.\n- **lockout** '));

      out.clear();
      expect(await runner.run(['guide', 'auth']), 0);
      expect(out.toString(), 'The auth doc type.\n\n$_docLimits\n');
    });

    test('a repeated id prints its body once, with no ==> line', () async {
      final runner = await runnerIn(await projectWith());

      expect(await runner.run(['guide', '--pattern', 'crud']), 0);
      final once = out.toString();
      out.clear();

      expect(await runner.run(['guide', '--pattern', 'crud', 'crud']), 0);
      expect(out.toString(), once);
      expect(out.toString(), isNot(contains('==>')));
    });

    test('two or more distinct ids print under ==> lines in argument '
        'order, a repeat once', () async {
      final runner = await runnerIn(await projectWith());

      expect(
        await runner.run(['guide', '--pattern', 'crud', 'auth', 'crud']),
        0,
      );
      final text = out.toString();
      expect(text, startsWith('==> crud <==\nCreate, read, list'));
      expect(text, contains('==> auth <==\nSign-in.\n'));
      expect('==> crud <=='.allMatches(text), hasLength(1));
      expect(text.indexOf('==> crud <=='), lessThan(text.indexOf('==> auth')));
      expect(err.toString(), isEmpty);
    });

    test(
      '--json prints one object for one distinct id, even named twice',
      () async {
        final runner = await runnerIn(await projectWith());

        expect(
          await runner.run(['guide', '--pattern', 'crud', 'crud', '--json']),
          0,
        );
        expect(out.toString(), startsWith('{\n  "id": "crud",\n'));
        expect(jsonDecode(out.toString()), {
          'id': 'crud',
          'pack': 'software-tech',
          'description':
              'Create, read, list, update, and delete one resource.\n\n'
              'Second paragraph.',
          'items': [
            {
              'id': 'soft_delete',
              'text': 'A deleted record stays restorable for a stated time.',
            },
            {
              'id': 'page_list',
              'text':
                  'A list returns its records in pages with a stable order.',
            },
          ],
          'reference': [
            {
              'title': 'Google AIP-164 Soft delete',
              'url': 'https://google.aip.dev/164',
            },
          ],
        });
      },
    );

    test(
      '--json prints an array in argument order for two or more ids',
      () async {
        final runner = await runnerIn(await projectWith());

        expect(
          await runner.run(['guide', '--pattern', 'signup', 'auth', '--json']),
          0,
        );
        final json = (jsonDecode(out.toString()) as List<Object?>)
            .cast<Map<String, Object?>>();
        expect(json.map((p) => p['id']), ['signup', 'auth']);
        expect(json.first['extends'], 'auth');
        expect(json.last.containsKey('extends'), isFalse);
        expect(err.toString(), isEmpty);
      },
    );
  });

  group('specstone guide --json in the built CLI with a record matrix', () {
    late String binary;

    setUpAll(() async => binary = await buildSpecstone());

    test('guide json prints outputRef on the record matrix section '
        'only', () async {
      final project = await writeTree({
        _configPath: shippedPinsConfig(),
        '.specstone/templates/implementation.yaml':
            'sections:\n'
            '  - {id: verification_matrix, header: Matrix, output_ref: true}\n',
      });

      final result = await runSpecstone(binary, [
        'guide',
        'implementation',
        '--json',
      ], workingDirectory: project.path);

      expect(result.exitCode, 0, reason: '${result.stderr}');
      final json = jsonDecode(result.stdout as String) as Map<String, Object?>;
      final sections = (json['sections']! as List<Object?>)
          .cast<Map<String, Object?>>();
      final marked = [
        for (final section in sections)
          if (section.containsKey('outputRef')) section['id'],
      ];
      expect(marked, ['verification_matrix']);
      final matrix = sections.firstWhere(
        (section) => section['id'] == 'verification_matrix',
      );
      expect(matrix['outputRef'], isTrue);
    });
  });

  group('specstone guide naming several types with shared lines', () {
    late StringBuffer out;

    setUp(() => out = StringBuffer());

    /// Runs `guide fr user_story` over a `prd-core` pack that holds
    /// [sharedLines].
    Future<void> guideBoth(String sharedLines) async {
      final project = await writeTree({
        _configPath: 'packs:\n  prd-core: 1.1.0\n',
      });
      final runner = SpecstoneCommandRunner(
        console: FakeConsole(),
        out: out,
        err: StringBuffer(),
        templates: TemplateResolver(
          shippedFiles: {
            ...shipped(),
            'prd-core/pack.yaml': _bytes(
              'name: prd-core\nversion: 1.1.0\n$sharedLines',
            ),
            'prd-core/fr.yaml': _bytes(
              'id: fr\ndescription: One requirement.\npath: frs/{slug}.md\n',
            ),
          },
        ),
        workingDirectory: project,
        homeDirectory: await writeTree({}),
      );

      expect(await runner.run(['guide', 'fr', 'user_story']), 0);
    }

    test('guide fr user_story prints the lines both share once under the '
        'shared block', () async {
      await guideBoth(
        'shared_lines:\n'
        '  - id: cite_rule\n'
        '    text: Cite by link.\n'
        '  - id: tone_rule\n'
        '    text: Say it once.\n',
      );

      expect(
        out.toString(),
        '==> shared <==\n'
        'Cite by link.\n'
        'Say it once.\n'
        '==> fr <==\n'
        'One requirement.\n\n$_docLimits\n'
        '==> user_story <==\n'
        'One story\n\n$_docLimits\n',
      );
    });

    test('a shared line that reaches only one named type prints under that '
        'type', () async {
      await guideBoth(
        'shared_lines:\n'
        '  - id: cite_rule\n'
        '    text: Cite by link.\n'
        '  - id: fr_rule\n'
        '    text: Name the verb.\n'
        '    for_doc_types: [fr]\n',
      );

      expect(
        out.toString(),
        '==> shared <==\n'
        'Cite by link.\n'
        '==> fr <==\n'
        'One requirement.\n'
        'Name the verb.\n\n$_docLimits\n'
        '==> user_story <==\n'
        'One story\n\n$_docLimits\n',
      );
    });
  });

  group('specstone guide --pattern in the built CLI', () {
    late String binary;

    setUpAll(() async => binary = await buildSpecstone());

    Future<ProcessResult> run(Directory project, List<String> args) =>
        runSpecstone(binary, [
          'guide',
          '--pattern',
          ...args,
        ], workingDirectory: project.path);

    Future<Directory> project() => writeTree({
      _configPath: shippedPinsConfig(),
      '.specstone/templates/patterns/export.yaml': '''
id: export
description: Export one resource.
items:
  - id: format
    text: Name each export format.
reference:
  - title: Handbook
''',
      '.specstone/templates/patterns/import.yaml': '''
id: import
description: Import one resource.
items:
  - id: dedupe
    text: Say how a duplicate row reads.
''',
    });

    test('lists the project patterns and exits 0', () async {
      final result = await run(await project(), []);

      expect(result.exitCode, 0, reason: '${result.stderr}');
      final ids = const LineSplitter().convert(result.stdout as String);
      expect(ids, containsAllInOrder(['export', 'import']));
      expect(ids, [...ids]..sort(), reason: 'code point order');
      expect(result.stderr, isEmpty);
    });
  });

  group('specstone guide with the shipped packs', () {
    late StringBuffer out;
    late StringBuffer err;

    setUp(() {
      out = StringBuffer();
      err = StringBuffer();
    });

    Future<SpecstoneCommandRunner> runnerFor({
      String? packs,
      Directory? working,
    }) async => SpecstoneCommandRunner(
      console: FakeConsole(),
      out: out,
      err: err,
      templates: TemplateResolver(),
      workingDirectory:
          working ??
          await writeTree({_configPath: packs ?? shippedPinsConfig()}),
      homeDirectory: await writeTree({}),
    );

    Future<Map<String, Object?>> schemaOf(
      SpecstoneCommandRunner runner,
      String id,
    ) async {
      out.clear();
      expect(await runner.run(['guide', id, '--json']), 0, reason: id);
      return jsonDecode(out.toString()) as Map<String, Object?>;
    }

    test('lists each doc type with the pack that owns it', () async {
      final runner = await runnerFor();

      expect(await runner.run(['guide', '--json']), 0);
      final entries = (jsonDecode(out.toString()) as List<Object?>)
          .cast<Map<String, Object?>>();
      String packOf(String id) =>
          entries.singleWhere((e) => e['id'] == id)['pack']! as String;
      expect(packOf('fr'), 'prd-core');
      expect(packOf('architecture'), 'software-tech');
      for (final entry in entries) {
        expect(entry['description'], isNotEmpty, reason: '${entry['id']}');
      }
      out.clear();
      expect(await runner.run(['guide']), 0);
      expect(
        out.toString(),
        [for (final entry in entries) '${entry['id']}\n'].join(),
      );
      expect(err.toString(), isEmpty);
    });

    test('with only prd-core no field of a doc type points at code', () async {
      final runner = await runnerFor(packs: shippedPinsConfig(['prd-core']));

      final fields =
          ((await schemaOf(runner, 'fr'))['fields']! as List<Object?>)
              .cast<Map<String, Object?>>();
      expect(fields, isNotEmpty);
      for (final field in fields) {
        expect(field['type'], isNot('output_ref'), reason: '${field['id']}');
        expect(field.containsKey('pointer'), isFalse, reason: '${field['id']}');
      }
    });

    test(
      'guide journey prints the sizing rule, then goal, flow, and steps',
      () async {
        final runner = await runnerFor();

        expect(await runner.run(['guide', 'journey']), 0);
        expect(
          out.toString(),
          stringContainsInOrder([
            '## Goal\nRequired; ≤ 1 line.\n',
            '## Flow\nRequired.\n',
            '## Steps\nRequired.\n',
          ]),
        );
        expect(err.toString(), isEmpty);
      },
    );

    test('guide glossary prints its rules, then terms with its template and '
        'the 300-character cap', () async {
      final runner = await runnerFor();

      expect(await runner.run(['guide', 'glossary']), 0);
      expect(
        out.toString(),
        stringContainsInOrder([
          '≤ 300 characters per item',
          '## Terms\nOptional; ≤ 1 line per item.\n',
        ]),
      );
      expect(err.toString(), isEmpty);
    });

    test('guide goal prints its rules, then the three horizons with their '
        'span and Serves rule', () async {
      final runner = await runnerFor();

      expect(await runner.run(['guide', 'goal']), 0);
      expect(
        out.toString(),
        stringContainsInOrder([
          '## Long-term goals\nOptional.\n',
          '## Mid-term goals\nOptional.\n',
          '## Short-term goals\nOptional.\n',
        ]),
      );
      expect(err.toString(), isEmpty);
    });

    test('guide measurement prints the log rule and goal link, then its five '
        'sections', () async {
      final runner = await runnerFor();

      expect(await runner.run(['guide', 'measurement']), 0);
      expect(
        out.toString(),
        stringContainsInOrder([
          '## Scope\n',
          '## Method\n',
          '## Baseline\n',
          '## Results\n',
          '## Open causes\n',
        ]),
      );
      expect(err.toString(), isEmpty);
    });

    test('every doc type prints its sections in the order its schema '
        'gives', () async {
      final runner = await runnerFor();
      expect(await runner.run(['guide']), 0);
      final ids = const LineSplitter().convert(out.toString());

      for (final id in ids) {
        final headers = [
          for (final section
              in ((await schemaOf(runner, id))['sections']! as List<Object?>)
                  .cast<Map<String, Object?>>())
            '## ${section['header']}\n',
        ];
        out.clear();
        expect(await runner.run(['guide', id]), 0, reason: id);
        final at = headers.map(out.toString().indexOf).toList();
        expect(at, everyElement(isNonNegative), reason: id);
        expect(at, orderedEquals(List.of(at)..sort()), reason: id);
      }
      expect(err.toString(), isEmpty);
    });

    test('every shipped feature pattern prints', () async {
      final runner = await runnerFor();
      expect(await runner.run(['guide', '--pattern']), 0);
      final ids = const LineSplitter().convert(out.toString());
      expect(ids, isNotEmpty);

      for (final id in ids) {
        out.clear();
        expect(await runner.run(['guide', '--pattern', id]), 0, reason: id);
        expect(out.toString(), contains('- **'), reason: id);
      }
      expect(err.toString(), isEmpty);
    });
  });

  group('specstone guide --out', () {
    late StringBuffer out;
    late StringBuffer err;

    setUp(() {
      out = StringBuffer();
      err = StringBuffer();
    });

    Future<SpecstoneCommandRunner> runnerIn(Directory folder) async =>
        SpecstoneCommandRunner(
          console: FakeConsole(),
          out: out,
          err: err,
          templates: TemplateResolver(shippedFiles: _shippedWithPatterns()),
          workingDirectory: folder,
          homeDirectory: await writeTree({}),
        );

    Future<Directory> project() =>
        writeTree({_configPath: _patternConfig, ..._frLayer});

    String reportOf(Directory project, String name) =>
        File('${project.path}/.specstone/reports/$name').readAsStringSync();

    test('guide <types> --out writes guide.<types>.txt and prints its '
        'header', () async {
      final folder = await project();
      final runner = await runnerIn(folder);

      expect(await runner.run(['guide', 'fr', 'user_story', '--out']), 0);
      final written = reportOf(folder, 'guide.fr.user_story.txt');
      expect(written, startsWith('==> shared <==\n'));
      expect(written, contains('==> fr <==\n'));
      expect(written, contains('==> user_story <==\n'));
      final header = out.toString();
      expect(header, startsWith('==> guide: '));
      expect(header.trimRight().split('\n'), hasLength(1));
      expect(err.toString(), isEmpty);
    });

    test('the header line counts the written lines and tokens and ends with '
        'the report path', () async {
      final folder = await project();
      final runner = await runnerIn(folder);

      expect(await runner.run(['guide', 'fr', 'user_story', '--out']), 0);
      final file = File(
        '${folder.path}/.specstone/reports/guide.fr.user_story.txt',
      );
      final header = RegExp(
        r'^==> guide: (\d+) lines, (\d+) tokens · (.+) <==\n$',
      ).firstMatch(out.toString());
      expect(header, isNotNull, reason: out.toString());
      expect(
        int.parse(header![1]!),
        const LineSplitter().convert(file.readAsStringSync()).length,
      );
      expect(int.parse(header[2]!), greaterThan(0));
      expect(header[3], file.resolveSymbolicLinksSync());
    });

    test('guide --pattern --out writes guide-pattern.all.txt', () async {
      final folder = await project();
      final runner = await runnerIn(folder);

      expect(await runner.run(['guide', '--pattern', '--out']), 0);
      expect(reportOf(folder, 'guide-pattern.all.txt'), contains('crud'));
      expect(out.toString(), startsWith('==> guide: '));
    });

    test('guide --pattern crud --out writes guide-pattern.crud.txt', () async {
      final folder = await project();
      final runner = await runnerIn(folder);

      expect(await runner.run(['guide', '--pattern', 'crud', '--out']), 0);
      expect(
        reportOf(folder, 'guide-pattern.crud.txt'),
        contains('soft_delete'),
      );
    });

    test('guide <type> --json --out writes the schema JSON and prints out, '
        'lines, and tokens', () async {
      final folder = await project();
      final runner = await runnerIn(folder);

      expect(await runner.run(['guide', 'fr', '--json', '--out']), 0);
      final file = File('${folder.path}/.specstone/reports/guide.fr.json');
      final schema =
          jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
      expect(schema['id'], 'fr');
      final printed = jsonDecode(out.toString()) as Map<String, Object?>;
      expect(printed['out'], file.resolveSymbolicLinksSync());
      expect(printed['lines'], isA<int>());
      expect(printed['tokens'], isA<int>());
    });

    test('guide <type> --json --out prints a header with an empty warnings '
        'array', () async {
      final folder = await project();
      final runner = await runnerIn(folder);

      expect(await runner.run(['guide', 'fr', '--json', '--out']), 0);
      final header = jsonDecode(out.toString()) as Map<String, Object?>;
      expect(header.keys, containsAll(['out', 'lines', 'tokens', 'warnings']));
      expect(header['warnings'], <Object?>[]);
    });

    test('guide <type> --json prints the schema with no warnings '
        'key', () async {
      final folder = await project();
      final runner = await runnerIn(folder);

      expect(await runner.run(['guide', 'fr', '--json']), 0);
      final schema = jsonDecode(out.toString()) as Map<String, Object?>;
      expect(schema['id'], 'fr');
      expect(schema, isNot(contains('warnings')));
    });

    test('a path given names the file inside a project', () async {
      final folder = await project();
      final runner = await runnerIn(folder);

      expect(await runner.run(['guide', 'fr', '--out', 'notes/fr.txt']), 0);
      expect(
        File('${folder.path}/notes/fr.txt').readAsStringSync(),
        contains('One requirement.'),
      );
    });

    test('guide fr --out and guide fr --json --out to a named reports file '
        'write both', () async {
      final folder = await project();
      final runner = await runnerIn(folder);
      final reports = '${folder.path}/.specstone/reports';

      expect(
        await runner.run(['guide', 'fr', '--out', '$reports/guide.ab12cd.txt']),
        0,
        reason: err.toString(),
      );
      expect(
        reportOf(folder, 'guide.ab12cd.txt'),
        contains('One requirement.'),
      );
      expect(out.toString(), startsWith('==> guide: '));

      out.clear();
      expect(
        await runner.run([
          'guide',
          'fr',
          '--json',
          '--out',
          '$reports/guide.ab12cd.json',
        ]),
        0,
        reason: err.toString(),
      );
      final schema = jsonDecode(
        reportOf(folder, 'guide.ab12cd.json'),
      ) as Map<String, Object?>;
      expect(schema['id'], 'fr');
      final printed = jsonDecode(out.toString()) as Map<String, Object?>;
      expect(
        printed['out'],
        File('$reports/guide.ab12cd.json').resolveSymbolicLinksSync(),
      );
      expect(File('$reports/guide.fr.txt').existsSync(), isFalse);
    });

    test('a given --out under .specstone/ outside bundles/ and reports/ exits '
        '73 and writes nothing', () async {
      final folder = await project();
      final runner = await runnerIn(folder);
      final refused = File('${folder.path}/.specstone/guide.ab12cd.txt');

      expect(await runner.run(['guide', 'fr', '--out', refused.path]), 73);
      expect(out.toString(), isEmpty);
      expect(refused.existsSync(), isFalse);
    });

    test('a bare guide --out inside a project writes guide.all.txt', () async {
      final folder = await project();
      final runner = await runnerIn(folder);

      expect(await runner.run(['guide', '--out']), 0, reason: err.toString());
      expect(reportOf(folder, 'guide.all.txt'), 'feature\nfr\nuser_story\n');
      expect(out.toString(), startsWith('==> guide: '));
    });

    test('a bare guide with a type id and --out outside a project exits 73 '
        'with output_not_writable and writes nothing', () async {
      final folder = await writeTree({});
      final runner = await runnerIn(folder);

      expect(await runner.run(['guide', 'feature', '--out']), 73);
      expect(out.toString(), isEmpty);
      expect(folder.listSync(), isEmpty);

      err.clear();
      expect(await runner.run(['guide', 'feature', '--json', '--out']), 73);
      expect(out.toString(), isEmpty);
      expect(folder.listSync(), isEmpty);
      final error =
          (jsonDecode(err.toString()) as Map<String, Object?>)['error']!
              as Map<String, Object?>;
      expect(error['code'], 'output_not_writable');
    });

    test('an empty --out path exits 64 with argument_invalid in the json '
        'envelope and writes nothing', () async {
      final folder = await project();
      final runner = await runnerIn(folder);

      for (final outArgs in [
        ['--out', ''],
        ['--out='],
      ]) {
        err.clear();
        expect(await runner.run(['guide', 'fr', '--json', ...outArgs]), 64);
        final error =
            (jsonDecode(err.toString()) as Map<String, Object?>)['error']!
                as Map<String, Object?>;
        expect(error['code'], 'argument_invalid', reason: '$outArgs');
        expect(
          Directory('${folder.path}/.specstone/reports').existsSync(),
          isFalse,
        );
      }
    });

    test('a path inside the docs root exits 73 and writes nothing', () async {
      final folder = await project();
      final runner = await runnerIn(folder);

      expect(await runner.run(['guide', 'fr', '--out', 'docs/x.txt']), 73);
      expect(out.toString(), isEmpty);
      expect(File('${folder.path}/docs/x.txt').existsSync(), isFalse);
    });

    test('a path given outside a project writes there', () async {
      final folder = await writeTree({});
      final runner = await runnerIn(folder);

      expect(await runner.run(['guide', '--out', '${folder.path}/x.txt']), 0);
      expect(
        File('${folder.path}/x.txt').readAsStringSync(),
        'feature\nuser_story\n',
      );
    });
  });
}
