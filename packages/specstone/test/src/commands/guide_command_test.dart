import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:specstone/src/command_runner.dart';
import 'package:specstone_core/specstone_core.dart';
import 'package:test/test.dart';

import '../../../../specstone_core/test/helpers/shipped_pins.dart';
import '../../helpers/temp_tree.dart';

const _configPath = '.specstone/config.yaml';
const _guideUsage = 'Usage: specstone guide [type …] [--json]';

/// A project doc type that adds `fr` beside the shipped fixture's two.
const _frLayer = <String, String>{
  '.specstone/templates/fr.yaml':
      'id: fr\ndescription: One requirement.\npath: frs/{slug}.md\n',
};

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

    test('lists one doc type id per line', () async {
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

    test('a type prints its writing guide', () async {
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

    test('guide <type> --json prints bundle and a section '
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

    test('guide feature --json prints maxDepth 2 after path', () async {
      final runner = await runnerIn(
        await projectWith({
          '.specstone/templates/feature.yaml': 'max_depth: 2\n',
        }),
      );

      expect(await runner.run(['guide', 'feature', '--json']), 0);
      final json = jsonDecode(out.toString()) as Map<String, Object?>;
      final keys = json.keys.toList();
      expect(keys.indexOf('maxDepth'), keys.indexOf('path') + 1);
      expect(json['maxDepth'], 2);
    });

    test('guide <type> '
        '--json prints lint.maxItemChars as a project layer sets it, and no '
        'such key with no layer', () async {
      final runner = await runnerIn(
        await projectWith({
          '.specstone/templates/feature.yaml': 'lint: {max_item_chars: 900}\n',
        }),
      );

      expect(await runner.run(['guide', 'feature', '--json']), 0);
      final json = jsonDecode(out.toString()) as Map<String, Object?>;
      expect((json['lint']! as Map<String, Object?>)['maxItemChars'], 900);

      out.clear();
      final plain = await runnerIn(await projectWith({}));
      expect(await plain.run(['guide', 'feature', '--json']), 0);
      final unset = jsonDecode(out.toString()) as Map<String, Object?>;
      expect(
        (unset['lint'] as Map<String, Object?>?)?.containsKey('maxItemChars'),
        isNot(true),
      );
    });

    test('f03/us01/fr03, db-r7: guide <type> --json prints a section summary '
        'set by a project layer', () async {
      final runner = await runnerIn(
        await projectWith({
          '.specstone/templates/feature.yaml':
              'sections: [{id: goal, summary: true}]\n',
        }),
      );

      expect(await runner.run(['guide', 'feature', '--json']), 0);
      final json = jsonDecode(out.toString()) as Map<String, Object?>;
      final sections = (json['sections']! as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(sections.first['summary'], isTrue);
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

    test('an unknown type with --json prints the envelope '
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

    test('a project '
        'doc-type file named Grid.yaml exits 78 as unknown_value', () async {
      final runner = await runnerIn(
        await projectWith({'.specstone/templates/Grid.yaml': 'max_depth: 1\n'}),
      );

      expect(await runner.run(['guide', '--json']), 78);
      final error =
          (jsonDecode(err.toString()) as Map<String, Object?>)['error']!
              as Map<String, Object?>;
      expect(error['code'], 'unknown_value');
      expect(error['file'], '.specstone/templates/Grid.yaml');
      expect(error['key'], 'id');
    });

    test('a broken project template prints file and line on '
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

    test('--json reports a fault for a doc type as one '
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

    test('a pin older than the carried version exits 78 and '
        'names packs.prd-core', () async {
      final project = await writeTree({
        _configPath: 'packs:\n  prd-core: 1.0.0\n',
      });
      final runner = await runnerIn(project);

      expect(await runner.run(['guide']), 78);
      expect(err.toString(), contains('packs.prd-core'));
      expect(out.toString(), isEmpty);
    });

    test('a pin newer than the carried version exits 78', () async {
      final project = await writeTree({
        _configPath: 'packs:\n  prd-core: 2.0.0\n',
      });
      final runner = await runnerIn(project);

      expect(await runner.run(['guide']), 78);
      expect(err.toString(), contains('packs.prd-core'));
    });

    for (final args in [
      ['--version'],
      ['--help'],
      ['help'],
      <String>[],
      ['help', 'guide'],
    ]) {
      test('f03/us05/s2, f03/us01/fr04/e04, f03/us05/fr01/e07, '
          '`${args.join(' ')}` ignores a broken config', () async {
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

    test('two type arguments that no pack defines exit 64, naming both and '
        'the usage', () async {
      final runner = await runnerIn(await projectWith({}));

      expect(await runner.run(['guide', 'a', 'b']), 64);
      expect(out.toString(), isEmpty);
      expect(
        err.toString(),
        contains('Could not find doc types named "a", "b".\n\n$_guideUsage'),
      );
    });

    test('E01: two '
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

    test('E01: one '
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

    test('E01: an '
        'unknown id named twice is named once', () async {
      final runner = await runnerIn(await projectWith({}));

      expect(await runner.run(['guide', 'featur', 'featur']), 64);
      expect(out.toString(), isEmpty);
      expect(
        err.toString(),
        contains('Could not find a doc type named "featur".\n\n$_guideUsage'),
      );
    });

    test('E07: a repeated '
        'id prints once at its first place under ==> lines', () async {
      final runner = await runnerIn(await projectWith(_frLayer));

      expect(await runner.run(['guide', 'fr', 'user_story', 'fr']), 0);
      expect(
        out.toString(),
        '==> fr <==\n'
        'One requirement.\n'
        '==> user_story <==\n'
        'One story\n',
      );
      expect(err.toString(), isEmpty);
    });

    test('E08: one id '
        'named twice prints its guide once, with no ==> line', () async {
      final runner = await runnerIn(await projectWith(_frLayer));

      expect(await runner.run(['guide', 'fr', 'fr']), 0);
      expect(out.toString(), 'One requirement.\n');
      expect(err.toString(), isEmpty);
    });

    test("read several doc types' guides in "
        'one call, each once in the order named under its own line', () async {
      final runner = await runnerIn(await projectWith(_frLayer));

      expect(await runner.run(['guide', 'user_story', 'feature', 'fr']), 0);
      expect(
        out.toString(),
        '==> user_story <==\n'
        'One story\n'
        '==> feature <==\n'
        'A feature groups the stories that serve one goal.\n\n'
        'Second paragraph.\n\n'
        '## Feature goal\n\n'
        'Why, problem, and audience, one sentence each.\n'
        '==> fr <==\n'
        'One requirement.\n',
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

    test('E01: an empty '
        'id refuses the call with exit 64 and names ""', () async {
      final runner = await runnerIn(await projectWith({}));

      expect(await runner.run(['guide', '']), 64);
      expect(out.toString(), isEmpty);
      expect(
        err.toString(),
        contains('Could not find a doc type named "".\n\n$_guideUsage'),
      );
    });

    test('E01: an empty '
        'id beside a known one refuses the whole call', () async {
      final runner = await runnerIn(await projectWith(_frLayer));

      expect(await runner.run(['guide', 'fr', '']), 64);
      expect(out.toString(), isEmpty);
      expect(
        err.toString(),
        contains('Could not find a doc type named "".\n\n$_guideUsage'),
      );
    });

    test('a project '
        'layer that overrides a shipped type prints the override in the '
        'order named', () async {
      final runner = await runnerIn(
        await projectWith({
          ..._frLayer,
          '.specstone/templates/user_story.yaml':
              'description: An overridden story.\n',
        }),
      );

      expect(await runner.run(['guide', 'user_story', 'fr']), 0);
      expect(
        out.toString(),
        '==> user_story <==\n'
        'An overridden story.\n'
        '==> fr <==\n'
        'One requirement.\n',
      );
      expect(err.toString(), isEmpty);
    });

    test('E04: a broken '
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

    test('E04: a broken '
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

    test('one unknown doc type among '
        'several refuses the whole call and names it', () async {
      final runner = await runnerIn(await projectWith(_frLayer));

      expect(await runner.run(['guide', 'feature', 'stroy', 'fr']), 64);
      expect(out.toString(), isEmpty);
      expect(
        err.toString(),
        contains('Could not find a doc type named "stroy".\n\n$_guideUsage'),
      );
    });

    test('E01: unknown '
        'ids with --json print one envelope naming each, and stdout stays '
        'empty', () async {
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
    });

    test('E01: one '
        'unknown id among known ones with --json names it in the singular '
        'form', () async {
      final runner = await runnerIn(await projectWith({}));

      expect(await runner.run(['guide', 'feature', 'featur', '--json']), 64);
      expect(out.toString(), isEmpty);
      final error =
          (jsonDecode(err.toString()) as Map<String, Object?>)['error']!
              as Map<String, Object?>;
      expect(error['code'], 'doc_type_unknown');
      expect(error['message'], 'Could not find a doc type named "featur".');
    });

    test(
      'E07: a '
      'repeated id with --json prints one array in order, the id once',
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
  });

  group('specstone guide with the shipped writing guides', () {
    late StringBuffer out;
    late StringBuffer err;

    setUp(() {
      out = StringBuffer();
      err = StringBuffer();
    });

    Future<SpecstoneCommandRunner> shippedRunner() async =>
        SpecstoneCommandRunner(
          out: out,
          err: err,
          templates: TemplateResolver(),
          workingDirectory: await writeTree({_configPath: shippedPinsConfig()}),
          homeDirectory: await writeTree({}),
        );

    test('template_packs/write_prd_docs_from_prd_core/'
        'write_shipped_writing_guides E05: guide feature names the three size '
        'findings in order, with the no-split case', () async {
      final runner = await shippedRunner();

      expect(await runner.run(['guide', 'feature']), 0);
      final guide = out.toString();
      final chars = guide.indexOf('`chars_over_limit`');
      final lines = guide.indexOf('`lines_over_limit`');
      final item = guide.indexOf('`item_over_limit`');
      expect(chars, isNonNegative);
      expect(lines, greaterThan(chars));
      expect(item, greaterThan(lines));
      expect(guide, contains('fewer than 4 stories'));
      expect(guide, contains('never both'));
      expect(guide, contains('a split never shrinks one item'));
      expect(guide, contains('Cut no text to pass a size'));
      expect(err.toString(), isEmpty);
    });

    test('template_packs/write_spec_docs_from_software_tech/'
        'write_spec_writing_guides: guide api names the FR Rationale as the '
        'home of a legacy Why line', () async {
      final runner = await shippedRunner();

      expect(await runner.run(['guide', 'api']), 0);
      expect(
        out.toString(),
        contains('the reason a legacy Why line gives goes to the `Rationale`'),
      );
      expect(err.toString(), isEmpty);
    });
  });
}
