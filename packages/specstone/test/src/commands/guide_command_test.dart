import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:specstone/src/command_runner.dart';
import 'package:specstone_core/specstone_core.dart';
import 'package:test/test.dart';

import '../../../../specstone_core/test/helpers/shipped_pins.dart';
import '../../helpers/built_cli.dart';
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

    test('guide --json prints bundleRefs', () async {
      final runner = await runnerIn(
        await projectWith({
          '.specstone/templates/feature.yaml':
              'bundle: [implement]\nbundle_refs: true\n',
        }),
      );

      expect(await runner.run(['guide', 'feature', '--json']), 0);
      final json = jsonDecode(out.toString()) as Map<String, Object?>;
      expect(json['bundleRefs'], isTrue);
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

  group('specstone guide --pattern', () {
    late StringBuffer out;
    late StringBuffer err;

    setUp(() {
      out = StringBuffer();
      err = StringBuffer();
    });

    Future<SpecstoneCommandRunner> runnerIn(Directory project) async =>
        SpecstoneCommandRunner(
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

    test('a project pattern joins the shipped ids and carries no pack '
        'under --json', () async {
      final runner = await runnerIn(
        await projectWith({
          '.specstone/templates/patterns/onboarding.yaml': '''
id: onboarding
description: Onboarding checklist.
items:
  - id: welcome
    text: Name the welcome step.
''',
        }),
      );

      expect(await runner.run(['guide', '--pattern']), 0);
      expect(out.toString(), 'auth\ncrud\nonboarding\nsignup\n');

      out.clear();
      expect(await runner.run(['guide', '--pattern', '--json']), 0);
      final list = jsonDecode(out.toString()) as List<Object?>;
      expect(list[2], {
        'id': 'onboarding',
        'description': 'Onboarding checklist.',
      });
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

    test('a project file over a shipped pattern lists it once and keeps '
        'its pack', () async {
      final runner = await runnerIn(
        await projectWith({
          '.specstone/templates/patterns/crud.yaml': '''
id: crud
description: Project CRUD.
items:
  - id: export
    text: Export all records.
''',
        }),
      );

      expect(await runner.run(['guide', '--pattern']), 0);
      expect(out.toString(), 'auth\ncrud\nsignup\n');

      out.clear();
      expect(await runner.run(['guide', '--pattern', '--json']), 0);
      final crud = (jsonDecode(out.toString()) as List<Object?>)
          .cast<Map<String, Object?>>()
          .singleWhere((p) => p['id'] == 'crud');
      expect(crud['pack'], 'software-tech');
      expect(crud['description'], 'Project CRUD.');
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
        '  }\n'
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
      expect(out.toString(), 'The auth doc type.\n');
    });

    test('a doc type id is no pattern id under --pattern', () async {
      final runner = await runnerIn(await projectWith());

      expect(await runner.run(['guide', '--pattern', 'feature']), 64);
      expect(out.toString(), isEmpty);
      expect(
        err.toString(),
        'Could not find a feature pattern named "feature".\n',
      );
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

    test(
      'a pattern that extends another prints the base items first',
      () async {
        final runner = await runnerIn(await projectWith());

        expect(await runner.run(['guide', '--pattern', 'signup']), 0);
        expect(
          out.toString(),
          'Sign-up.\n'
          '- **lockout** Name the lockout rule.\n'
          '- **reset** Name the reset path.\n'
          '- **verify_email** Name the email check.\n',
        );
      },
    );

    test('an item a project layer disables is not printed', () async {
      final runner = await runnerIn(
        await projectWith({
          '.specstone/templates/patterns/auth.yaml': '''
id: auth
items:
  - id: reset
    disabled: true
''',
        }),
      );

      expect(await runner.run(['guide', '--pattern', 'auth']), 0);
      expect(
        out.toString(),
        'Sign-in.\n- **lockout** Name the lockout rule.\n',
      );
    });

    test('a pattern with no reference prints no sources line', () async {
      final runner = await runnerIn(await projectWith());

      expect(await runner.run(['guide', '--pattern', 'auth']), 0);
      expect(out.toString(), isNot(contains('Pattern sources:')));
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

  group('specstone guide --json in the built CLI with a readability layer', () {
    late String binary;

    setUpAll(() async => binary = await buildSpecstone());

    test('--json prints the merged maxSentenceWords map from a project layer, '
        'and no maxSentenceChars', () async {
      final project = await writeTree({
        _configPath: shippedPinsConfig(),
        '.specstone/templates/domain.yaml':
            'lint: {max_sentence_words: {default: 30}}\n',
      });

      final result = await Process.run(binary, [
        'guide',
        'domain',
        '--json',
      ], workingDirectory: project.path);

      expect(result.exitCode, 0, reason: '${result.stderr}');
      final json = jsonDecode(result.stdout as String) as Map<String, Object?>;
      final lint = json['lint']! as Map<String, Object?>;
      expect(lint['maxSentenceWords'], {'default': 30, 'ko': 17});
      expect(lint.containsKey('maxSentenceChars'), isFalse);
    });
  });

  group('specstone guide --pattern in the built CLI', () {
    late String binary;

    setUpAll(() async => binary = await buildSpecstone());

    Future<ProcessResult> run(Directory project, List<String> args) =>
        Process.run(binary, [
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

    test('prints two patterns under ==> lines and exits 0', () async {
      final result = await run(await project(), ['import', 'export']);

      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(
        result.stdout,
        '==> import <==\n'
        'Import one resource.\n'
        '- **dedupe** Say how a duplicate row reads.\n'
        '==> export <==\n'
        'Export one resource.\n'
        '- **format** Name each export format.\n'
        'Pattern sources:\n'
        '- Handbook\n',
      );
      expect(result.stderr, isEmpty);
    });

    test('an unknown id with --json exits 64, stdout empty, the envelope on '
        'stderr', () async {
      final result = await run(await project(), ['expor', '--json']);

      expect(result.exitCode, 64);
      expect(result.stdout, isEmpty);
      final error =
          (jsonDecode(result.stderr as String)
                  as Map<String, Object?>)['error']!
              as Map<String, Object?>;
      expect(error['code'], 'feature_pattern_unknown');
      expect(
        error['message'],
        'Could not find a feature pattern named "expor".',
      );
    });
  });

  group('specstone guide in the built CLI with a patterns carrier', () {
    late String binary;

    setUpAll(() async => binary = await buildSpecstone());

    const disabledFile = '.specstone/templates/feature.yaml';

    Future<ProcessResult> run(List<String> args) async {
      final project = await writeTree({
        _configPath: shippedPinsConfig(),
        disabledFile: 'sections:\n  - id: out_of_scope\n    disabled: true\n',
      });
      return Process.run(binary, [
        'guide',
        ...args,
      ], workingDirectory: project.path);
    }

    test('a layer that disables out_of_scope on feature exits 78 naming the '
        'file and the key', () async {
      final result = await run([]);

      expect(result.exitCode, 78, reason: '${result.stdout}');
      expect(result.stdout, isEmpty);
      expect(result.stderr, startsWith('$disabledFile: '));
      expect(result.stderr, contains('sections.out_of_scope'));
    });

    test('--json prints the unknown_value envelope with the file and the '
        'key', () async {
      final result = await run(['--json']);

      expect(result.exitCode, 78, reason: '${result.stdout}');
      expect(result.stdout, isEmpty);
      final error =
          (jsonDecode(result.stderr as String)
                  as Map<String, Object?>)['error']!
              as Map<String, Object?>;
      expect(error['code'], 'unknown_value');
      expect(error['file'], disabledFile);
      expect(error['key'], 'sections.out_of_scope');
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

  group('specstone guide --out', () {
    late StringBuffer out;
    late StringBuffer err;

    setUp(() {
      out = StringBuffer();
      err = StringBuffer();
    });

    Future<SpecstoneCommandRunner> runnerIn(Directory folder) async =>
        SpecstoneCommandRunner(
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
      expect(written, startsWith('==> fr <==\n'));
      expect(written, contains('==> user_story <==\n'));
      final header = out.toString();
      expect(header, startsWith('==> guide: '));
      expect(header.trimRight().split('\n'), hasLength(1));
      expect(err.toString(), isEmpty);
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

    test('a path given names the file inside a project', () async {
      final folder = await project();
      final runner = await runnerIn(folder);

      expect(await runner.run(['guide', 'fr', '--out', 'notes/fr.txt']), 0);
      expect(
        File('${folder.path}/notes/fr.txt').readAsStringSync(),
        contains('One requirement.'),
      );
    });

    test('--out "" exits 64 and writes no file', () async {
      final folder = await project();
      final runner = await runnerIn(folder);

      expect(await runner.run(['guide', 'fr', '--out', '']), 64);
      expect(out.toString(), isEmpty);
      expect(
        Directory('${folder.path}/.specstone/reports').existsSync(),
        isFalse,
      );
    });

    test('--out= with no path exits 64 and writes no file', () async {
      final folder = await project();
      final runner = await runnerIn(folder);

      expect(await runner.run(['guide', 'fr', '--out=']), 64);
      expect(out.toString(), isEmpty);
      expect(
        Directory('${folder.path}/.specstone/reports').existsSync(),
        isFalse,
      );
    });

    test('a bare guide --out inside a project writes guide.all.txt', () async {
      final folder = await project();
      final runner = await runnerIn(folder);

      expect(await runner.run(['guide', '--out']), 0, reason: err.toString());
      expect(reportOf(folder, 'guide.all.txt'), 'feature\nfr\nuser_story\n');
      expect(out.toString(), startsWith('==> guide: '));
    });

    test('a path inside the docs root exits 73 and writes nothing', () async {
      final folder = await project();
      final runner = await runnerIn(folder);

      expect(await runner.run(['guide', 'fr', '--out', 'docs/x.txt']), 73);
      expect(out.toString(), isEmpty);
      expect(File('${folder.path}/docs/x.txt').existsSync(), isFalse);
    });

    test(
      'a bare --out outside a project exits 73 and writes nothing',
      () async {
        final folder = await writeTree({});
        final runner = await runnerIn(folder);

        expect(await runner.run(['guide', '--out']), 73);
        expect(out.toString(), isEmpty);
        expect(folder.listSync(), isEmpty);
      },
    );

    test('a path given outside a project writes there', () async {
      final folder = await writeTree({});
      final runner = await runnerIn(folder);

      expect(await runner.run(['guide', '--out', '${folder.path}/x.txt']), 0);
      expect(
        File('${folder.path}/x.txt').readAsStringSync(),
        'feature\nuser_story\n',
      );
    });

    test(
      'prd-core and software-tech list fourteen and fifteen doc types',
      () async {
        final project = await writeTree({_configPath: shippedPinsConfig()});
        final runner = SpecstoneCommandRunner(
          out: out,
          err: err,
          templates: TemplateResolver(),
          workingDirectory: project,
          homeDirectory: await writeTree({}),
        );

        expect(await runner.run(['guide', '--json']), 0);
        final packs = [
          for (final row in jsonDecode(out.toString()) as List<Object?>)
            (row! as Map<String, Object?>)['pack'],
        ];
        expect(packs.where((pack) => pack == 'prd-core'), hasLength(14));
        expect(packs.where((pack) => pack == 'software-tech'), hasLength(15));
      },
    );
  });
}
