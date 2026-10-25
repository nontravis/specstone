import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:specstone/src/command_runner.dart';
import 'package:specstone_core/specstone_core.dart';
import 'package:test/test.dart';

import '../../helpers/temp_tree.dart';

const _configPath = '.specstone/config.yaml';
const _guideUsage = 'Usage: specstone guide [type] [--json]';

Uint8List _bytes(String text) => Uint8List.fromList(utf8.encode(text));

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
        out: out,
        err: err,
        templates: TemplateResolver(shippedFiles: shipped()),
        workingDirectory: project,
        homeDirectory: home,
      );
    }

    Future<Directory> projectWith(Map<String, String> files) =>
        writeTree({_configPath: 'packs:\n  prd-core: 1.1.0\n', ...files});

    test('f03/us01/fr01: lists one doc type id per line', () async {
      final runner = await runnerIn(await projectWith({}));

      expect(await runner.run(['guide']), 0);
      expect(out.toString(), 'feature\nuser_story\n');
      expect(err.toString(), isEmpty);
    });

    test('f03/us01/s8, f03/us01/fr01: --json lists id, pack, and description '
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

    test('f03/us01/fr02: a type prints its writing guide', () async {
      final runner = await runnerIn(await projectWith({}));

      expect(await runner.run(['guide', 'feature']), 0);
      expect(
        out.toString(),
        'A feature groups the stories that serve one goal.\n\n'
        'Second paragraph.\n\n'
        '## Feature goal\n\n'
        'Why, problem, and audience, one sentence each.\n',
      );
      expect(err.toString(), isEmpty);
    });

    test('f03/us01/s4, f03/us01/fr03: a type with --json prints the merged '
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

    test('f03/us01/fr03: guide <type> --json prints bundle and a section '
        'query set by a project layer', () async {
      final runner = await runnerIn(
        await projectWith({
          '.specstone/templates/feature.yaml':
              'bundle: [query]\nsections: [{id: goal, query: true}]\n',
        }),
      );

      expect(await runner.run(['guide', 'feature', '--json']), 0);
      final json = jsonDecode(out.toString()) as Map<String, Object?>;
      final keys = json.keys.toList();
      expect(keys.indexOf('bundle'), keys.indexOf('path') + 1);
      expect(json['bundle'], ['query']);
      final sections = (json['sections']! as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(sections.first['query'], isTrue);
    });

    test('f03/us01/s6, f03/us01/fr02/e01: an unknown type prints usage and '
        'exits 64', () async {
      final runner = await runnerIn(await projectWith({}));

      expect(await runner.run(['guide', 'featur']), 64);
      expect(
        err.toString(),
        contains('Could not find a doc type named "featur".\n\n$_guideUsage'),
      );
      expect(out.toString(), isEmpty);
    });

    test('f03/us01/fr03/e01: an unknown type with --json prints the envelope '
        'pretty-printed with no file or key', () async {
      final runner = await runnerIn(await projectWith({}));

      expect(await runner.run(['guide', 'featur', '--json']), 64);
      expect(out.toString(), isEmpty);
      expect(
        err.toString(),
        '{\n'
        '  "error": {\n'
        '    "code": "doc_type_unknown",\n'
        '    "message": "Could not find a doc type named \\"featur\\"."\n'
        '  }\n'
        '}\n',
      );
    });

    test('f03/us01/s7, f03/us01/fr01/e02: a broken project '
        'template prints file and line on stderr and exits 78', () async {
      final runner = await runnerIn(
        await projectWith({'.specstone/templates/feature.yaml': 'id: [\n'}),
      );

      expect(await runner.run(['guide']), 78);
      expect(
        err.toString(),
        matches(RegExp(r'^\.specstone/templates/feature\.yaml:\d+: ')),
      );
      expect(out.toString(), isEmpty);
    });

    test('f03/us01/fr01/e04: --json reports a fault as one '
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

    test('f03/us01/fr02/e04: a broken project template prints file and line on '
        'stderr for a doc type and exits 78', () async {
      final runner = await runnerIn(
        await projectWith({'.specstone/templates/feature.yaml': 'id: [\n'}),
      );

      expect(await runner.run(['guide', 'feature']), 78);
      expect(
        err.toString(),
        matches(RegExp(r'^\.specstone/templates/feature\.yaml:\d+: ')),
      );
      expect(out.toString(), isEmpty);
    });

    test('f03/us01/fr03/e04: --json reports a fault for a doc type as one '
        'envelope on stderr and exits 78', () async {
      final runner = await runnerIn(
        await projectWith({'.specstone/templates/feature.yaml': 'bogus: 1\n'}),
      );

      expect(await runner.run(['guide', 'feature', '--json']), 78);
      expect(out.toString(), isEmpty);
      expect(err.toString(), startsWith('{\n  "error": {\n    "code"'));
      final error =
          (jsonDecode(err.toString()) as Map<String, Object?>)['error']!
              as Map<String, Object?>;
      expect(error['code'], 'unknown_key');
      expect(error['file'], '.specstone/templates/feature.yaml');
      expect(error['key'], 'bogus');
    });

    test('f03/us01/fr01/e03: a pin older than the carried version exits 78 and '
        'names packs.prd-core', () async {
      final project = await writeTree({
        _configPath: 'packs:\n  prd-core: 1.0.0\n',
      });
      final runner = await runnerIn(project);

      expect(await runner.run(['guide']), 78);
      expect(err.toString(), contains('packs.prd-core'));
      expect(out.toString(), isEmpty);
    });

    test(
      'f03/us05/fr02/e04: a pin newer than the carried version exits 78',
      () async {
        final project = await writeTree({
          _configPath: 'packs:\n  prd-core: 2.0.0\n',
        });
        final runner = await runnerIn(project);

        expect(await runner.run(['guide']), 78);
        expect(err.toString(), contains('packs.prd-core'));
      },
    );

    for (final args in [
      ['--version'],
      ['--help'],
      ['help'],
      <String>[],
      ['help', 'guide'],
    ]) {
      test(
        'f03/us05/s2, f03/us01/fr04/e04, f03/us05/fr01/e07, '
        'f03/us05/fr02/e03: `${args.join(' ')}` ignores a broken config',
        () async {
          final project = await writeTree({_configPath: 'packs: [\n'});
          final runner = await runnerIn(project);

          expect(await runner.run(args), 0);
          expect(err.toString(), isEmpty);
        },
      );
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

    test('two type arguments is a usage error and exits 64', () async {
      final runner = await runnerIn(await projectWith({}));

      expect(await runner.run(['guide', 'a', 'b']), 64);
      expect(out.toString(), isEmpty);
      expect(err.toString(), contains(_guideUsage));
    });
  });
}
