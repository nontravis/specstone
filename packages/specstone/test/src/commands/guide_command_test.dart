import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:specstone/src/command_runner.dart';
import 'package:specstone_core/specstone_core.dart';
import 'package:test/test.dart';

import '../../../../specstone_core/test/helpers/marketing.dart';
import '../../../../specstone_core/test/helpers/personal_branding.dart';
import '../../../../specstone_core/test/helpers/prd_core.dart';
import '../../../../specstone_core/test/helpers/shipped_pins.dart';
import '../../../../specstone_core/test/helpers/software_design_system.dart';
import '../../../../specstone_core/test/helpers/software_tech.dart';
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
        'Second paragraph.\n\n'
        '## Feature goal\n\n'
        'Optional section.\n'
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

    test('guide <type> --json prints export on the doc type and root and '
        'export on a field when written, and omits each when not', () async {
      final runner = await runnerIn(
        await projectWith({
          '.specstone/templates/feature.yaml':
              'export: false\nfields:\n'
              '  - {id: covers, type: output_ref, pointer: exact, '
              'root: project, export: false}\n',
        }),
      );

      expect(await runner.run(['guide', 'feature', '--json']), 0);
      final json = jsonDecode(out.toString()) as Map<String, Object?>;
      expect(json['export'], isFalse);
      final covers = (json['fields']! as List)
          .cast<Map<String, Object?>>()
          .singleWhere((f) => f['id'] == 'covers');
      expect(covers['root'], 'project');
      expect(covers['export'], isFalse);

      out.clear();
      final plain = await runnerIn(await projectWith({}));
      expect(await plain.run(['guide', 'feature', '--json']), 0);
      final unset = jsonDecode(out.toString()) as Map<String, Object?>;
      expect(unset.containsKey('export'), isFalse);
      for (final field
          in (unset['fields']! as List).cast<Map<String, Object?>>()) {
        expect(field.containsKey('root'), isFalse);
        expect(field.containsKey('export'), isFalse);
      }
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

    test('guide <type> --json prints a section summary '
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

    test('a repeated '
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

    test('one id '
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
        'Optional section.\n'
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

    test('one '
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
          out: out,
          err: err,
          templates: TemplateResolver(shippedFiles: shipped()),
          workingDirectory: project,
          homeDirectory: home,
        );

    Map<String, Object?> errorOf() =>
        (jsonDecode(err.toString()) as Map<String, Object?>)['error']!
            as Map<String, Object?>;

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
      'a personal pack pin that differs from its home folder version exits 78 '
      'under guide',
      () async {
        final runner = runnerWithHome(
          await writeTree({
            _configPath: 'packs:\n  prd-core: 1.1.0\n  nont-a: 1.0.0\n',
          }),
          await writeTree({
            '.specstone/packs/nont-a/pack.yaml':
                'name: nont-a\nversion: 1.1.0\n',
          }),
        );

        expect(await runner.run(['guide']), 78);
        expect(out.toString(), isEmpty);
        expect(err.toString(), startsWith('$_configPath: packs.nont-a: '));
        expect(err.toString(), contains('1.0.0'));
        expect(err.toString(), contains('1.1.0'));
      },
    );

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

    test('a text fault about several files names each file under guide with no '
        'type', () async {
      final runner = runnerWithHome(
        await writeTree({_configPath: _cycleConfig}),
        await _cycleHome(),
      );

      expect(await runner.run(['guide']), 78);
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

    test('guide <type> --json holds the yaml_syntax line, relatedFiles for a '
        'multi-file fault, and no key when none applies', () async {
      final syntax = await runnerIn(
        await projectWith({'.specstone/templates/feature.yaml': 'id: [\n'}),
      );
      expect(await syntax.run(['guide', 'feature', '--json']), 78);
      expect(out.toString(), isEmpty);
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
      expect(await cycle.run(['guide', 'feature', '--json']), 78);
      expect(out.toString(), isEmpty);
      expect(errorOf()['code'], 'extends_cycle');
      expect(errorOf()['relatedFiles'], [
        '~/.specstone/packs/nont-a/pack.yaml',
      ]);
      expect(errorOf().containsKey('key'), isFalse);

      err.clear();
      final unknown = await runnerIn(await projectWith({}));
      expect(await unknown.run(['guide', 'feature', 'featur', '--json']), 64);
      expect(out.toString(), isEmpty);
      expect(errorOf().keys, ['code', 'message']);
    });

    test(
      'outside a project guide loads every shipped pack and checks no pin',
      () async {
        final runner = SpecstoneCommandRunner(
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
        final result = await Process.run(binary, [
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
            final mark = isConditional ? '$word when ' : '$word section.\n';
            expect(
              text,
              contains('## ${section['header']}\n\n$mark'),
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

    test('a doc type id under --pattern with --json is '
        'feature_pattern_unknown with exit 64', () async {
      final runner = await runnerIn(await projectWith(_frLayer));

      expect(await runner.run(['guide', '--pattern', 'fr', '--json']), 64);
      expect(out.toString(), isEmpty);
      final error =
          (jsonDecode(err.toString()) as Map<String, Object?>)['error']!
              as Map<String, Object?>;
      expect(error['code'], 'feature_pattern_unknown');
      expect(error['message'], 'Could not find a feature pattern named "fr".');
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

  group('specstone guide in the built CLI with a field lint', () {
    late String binary;

    setUpAll(() async => binary = await buildSpecstone());

    Future<ProcessResult> guideFeature(String fieldLint) async {
      final project = await writeTree({
        _configPath: shippedPinsConfig(),
        '.specstone/templates/feature.yaml':
            'fields:\n  - id: tagline\n    type: string\n'
            '    lint: $fieldLint\n',
      });
      return Process.run(binary, [
        'guide',
        'feature',
        '--json',
      ], workingDirectory: project.path);
    }

    test('--json prints the merged field lint of a valid layer', () async {
      final result = await guideFeature(
        '{max_sentences: 1, max_sentence_words: {default: 20}, '
        'max_sentence_chars: {default: 80}}',
      );

      expect(result.exitCode, 0, reason: '${result.stderr}');
      final json = jsonDecode(result.stdout as String) as Map<String, Object?>;
      final fields = (json['fields']! as List<Object?>)
          .cast<Map<String, Object?>>();
      final tagline = fields.singleWhere((f) => f['id'] == 'tagline');
      expect(tagline['lint'], {
        'maxSentences': 1,
        'maxSentenceWords': {'default': 20},
        'maxSentenceChars': {'default': 80},
      });
    });

    test('a field lint with one map and no partner exits 78 naming the '
        'absent key', () async {
      final result = await guideFeature('{max_sentence_words: {default: 20}}');

      expect(result.exitCode, 78);
      final error =
          (jsonDecode(result.stderr as String)
                  as Map<String, Object?>)['error']!
              as Map<String, Object?>;
      expect(error['code'], 'missing_key');
      expect(error['file'], '.specstone/templates/feature.yaml');
      expect(error['key'], 'fields.tagline.lint.max_sentence_chars');
    });
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

      final result = await Process.run(binary, [
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

  group('specstone guide in the built CLI with a conditional section', () {
    late String binary;

    setUpAll(() async => binary = await buildSpecstone());

    test('anti_persona prints a condition line, not a required mark, under '
        'each section its anti_type binds', () async {
      final project = await writeTree({_configPath: shippedPinsConfig()});

      final result = await Process.run(binary, [
        'guide',
        'anti_persona',
      ], workingDirectory: project.path);

      expect(result.exitCode, 0, reason: '${result.stderr}');
      final sections = {
        for (final block in (result.stdout as String).split('\n## ').skip(1))
          block.split('\n').first: block,
      };
      const bound = [
        'Motivations',
        'Actions',
        'Tools',
        'Needs',
        'Consequences',
      ];
      for (final header in bound) {
        expect(
          sections[header],
          startsWith(
            '$header\n\nRequired when `anti_type` is `misuser`; '
            'left out otherwise.\n',
          ),
          reason: header,
        );
        expect(sections[header], isNot(contains('Required section.')));
      }
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

    Map<String, Object?> errorOf() =>
        (jsonDecode(err.toString()) as Map<String, Object?>)['error']!
            as Map<String, Object?>;

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

    test(
      'outside a project it lists every shipped doc type',
      () async {
        final runner = await runnerFor(working: await writeTree({}));

        expect(await runner.run(['guide']), 0);
        final ids = const LineSplitter().convert(out.toString());
        expect(
          ids,
          [
            ...prdCoreIds,
            ...softwareTechIds,
            ...softwareDesignSystemIds,
            ...marketingIds,
            ...personalBrandingIds,
            'skill',
          ]..sort(),
        );
        expect(err.toString(), isEmpty);

        out.clear();
        expect(await runner.run(['guide', 'voice']), 0);
        final headers = RegExp(
          r'^## .+$',
          multiLine: true,
        ).allMatches(out.toString()).map((m) => m[0]).toList();
        expect(headers.last, '## Writing habits');
        expect(err.toString(), isEmpty);
      },
      skip: _tempHasConfigAncestor()
          ? 'an ancestor of the system temp folder holds $_configPath'
          : false,
    );

    test('a project listing the three packs lists the nineteen design-system '
        'doc types beside the others', () async {
      final runner = await runnerFor(packs: softwareDesignSystemConfig());

      expect(await runner.run(['guide']), 0);
      expect(
        const LineSplitter().convert(out.toString()),
        [...prdCoreIds, ...softwareTechIds, ...softwareDesignSystemIds]..sort(),
      );
      expect(err.toString(), isEmpty);
    });

    test('a project without software-design-system refuses guide component '
        'with the usage', () async {
      final runner = await runnerFor();

      expect(await runner.run(['guide', 'component']), 64);
      expect(
        err.toString(),
        contains(
          'Could not find a doc type named "component".\n\n$_guideUsage',
        ),
      );
      expect(out.toString(), isEmpty);
    });

    test('guide component --json prints the group parent and the lifecycle, '
        'feature, and design_source fields with their export keys', () async {
      final runner = await runnerFor(packs: softwareDesignSystemConfig());

      final schema = await schemaOf(runner, 'component');
      expect(schema['parent'], 'component_group');
      final fields = {
        for (final f
            in (schema['fields']! as List<Object?>)
                .cast<Map<String, Object?>>())
          f['id']! as String: f,
      };
      expect(fields['lifecycle']!['enum'], ['beta', 'stable', 'deprecated']);
      expect(fields['lifecycle']!.containsKey('export'), isFalse);
      expect(fields['feature']!['export'], false);
      expect(fields['design_source']!['export'], false);
    });

    test(
      'guide contributing --json sets export false and guide tokens --json '
      'holds the built-in fields, no perTarget, and one required section',
      () async {
        final runner = await runnerFor(packs: softwareDesignSystemConfig());

        expect((await schemaOf(runner, 'contributing'))['export'], false);
        final tokens = await schemaOf(runner, 'tokens');
        expect(tokens.containsKey('perTarget'), isFalse);
        expect(
          (tokens['fields']! as List<Object?>).map(
            (f) => (f! as Map<String, Object?>)['id'],
          ),
          builtInFields.map((f) => f.id),
        );
        expect(tokens['sections'], [containsPair('id', 'token_list')]);
        expect(
          ((tokens['sections']! as List<Object?>).single!
              as Map<String, Object?>)['required'],
          true,
        );
      },
    );

    test('guide guidelines, guide setup, and guide component print their '
        'statements and rules', () async {
      final runner = await runnerFor(packs: softwareDesignSystemConfig());

      expect(await runner.run(['guide', 'guidelines']), 0);
      expect(
        out.toString(),
        allOf(
          contains(
            'Shared code structure, such as a component base class, stays in '
            'the `software-tech` spec docs.',
          ),
          contains(
            'GUIDELINES holds each hard rule, such as "no raw colors", and '
            "the project's own lint verifies the code against it.",
          ),
        ),
      );
      out.clear();
      expect(await runner.run(['guide', 'setup']), 0);
      expect(
        out.toString(),
        contains(
          "The install contract is the source of the skill's install page.",
        ),
      );
      out.clear();
      expect(await runner.run(['guide', 'component']), 0);
      expect(
        out.toString(),
        allOf(
          contains('The component doc holds no code'),
          contains('Specstone never generates props from it.'),
          contains(
            'Examples state each scenario as prop values, never as code.',
          ),
          contains('## Keyboard\n\nOptional section.\n'),
        ),
      );
      expect(err.toString(), isEmpty);
    });

    test('guide --pattern on a project listing all four packs prints the ten '
        'ids of software-tech', () async {
      final tech = await runnerFor();
      expect(await tech.run(['guide', '--pattern']), 0);
      final techIds = const LineSplitter().convert(out.toString());
      out.clear();

      final all = await runnerFor(
        packs: shippedPinsConfig([
          ...softwareDesignSystemPacks,
          'agent-skills',
        ]),
      );
      expect(await all.run(['guide', '--pattern']), 0);

      expect(techIds, hasLength(10));
      expect(const LineSplitter().convert(out.toString()), techIds);
      expect(err.toString(), isEmpty);
    });

    test('a project listing prd-core and agent-skills lists skill beside the '
        'prd-core doc types and prints its guide with no spec pack', () async {
      final runner = await runnerFor(
        packs: shippedPinsConfig(['prd-core', 'agent-skills']),
      );

      expect(await runner.run(['guide']), 0);
      expect(
        const LineSplitter().convert(out.toString()),
        [...prdCoreIds, 'skill']..sort(),
      );

      out.clear();
      expect(await runner.run(['guide', 'skill']), 0);
      expect(out.toString(), contains('## Sources\n\nRequired section.\n'));
      expect(err.toString(), isEmpty);
    });

    test('guide skill --json prints its path, output, feature, and sources '
        'section', () async {
      final runner = await runnerFor(
        packs: shippedPinsConfig(['prd-core', 'agent-skills']),
      );

      final schema = await schemaOf(runner, 'skill');
      expect(schema['path'], 'specs/skills/{slug}.md');
      final fields = (schema['fields']! as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(fields.map((f) => f['id']), containsAll(['output', 'feature']));
      final covers = fields.singleWhere((f) => f['id'] == 'covers');
      expect(covers['root'], 'project');
      final sections = (schema['sections']! as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(sections.map((s) => s['id']), [
        'purpose',
        'when_to_use',
        'sources',
      ]);
    });

    test('a project listing prd-core alone refuses guide skill with the '
        'usage', () async {
      final runner = await runnerFor(packs: shippedPinsConfig(['prd-core']));

      expect(await runner.run(['guide', 'skill']), 64);
      expect(
        err.toString(),
        contains('Could not find a doc type named "skill".\n\n$_guideUsage'),
      );
      expect(out.toString(), isEmpty);
    });

    test('a project listing prd-core alone refuses guide campaign with the '
        'usage', () async {
      final runner = await runnerFor(packs: shippedPinsConfig(['prd-core']));

      expect(await runner.run(['guide', 'campaign']), 64);
      expect(
        err.toString(),
        contains('Could not find a doc type named "campaign".\n\n$_guideUsage'),
      );
      expect(out.toString(), isEmpty);
    });

    test('guide campaign_results --json and guide positioning --json print '
        'their parent and sections with no perTarget', () async {
      final runner = await runnerFor(
        packs: shippedPinsConfig(['prd-core', 'marketing']),
      );
      List<Map<String, Object?>> sectionsOf(Map<String, Object?> schema) =>
          (schema['sections']! as List<Object?>).cast<Map<String, Object?>>();

      final results = await schemaOf(runner, 'campaign_results');
      expect(results['parent'], 'campaign');
      expect(results.containsKey('perTarget'), isFalse);
      expect(sectionsOf(results).map((s) => s['id']), [
        'funnel',
        'channels',
        'spend',
      ]);
      expect(sectionsOf(results).map((s) => s['required']), everyElement(true));

      final positioning = await schemaOf(runner, 'positioning');
      expect(positioning.containsKey('perTarget'), isFalse);
      expect(sectionsOf(positioning).map((s) => s['id']), [
        'competitive_alternatives',
        'unique_attributes',
        'value',
        'best_fit_customers',
        'market_category',
      ]);
      expect(
        sectionsOf(positioning).map((s) => s['required']),
        everyElement(isNot(true)),
      );
    });

    test('guide campaign --json prints the feature parent, the plan section, '
        'and covers with pointer prefix and root project', () async {
      final runner = await runnerFor(
        packs: shippedPinsConfig(['prd-core', 'marketing']),
      );

      final schema = await schemaOf(runner, 'campaign');
      expect(schema['parent'], 'feature');
      expect(schema.containsKey('perTarget'), isFalse);
      final sections = (schema['sections']! as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(sections.map((s) => s['id']), ['plan']);
      final covers = (schema['fields']! as List<Object?>)
          .cast<Map<String, Object?>>()
          .singleWhere((f) => f['id'] == 'covers');
      expect(covers['pointer'], 'prefix');
      expect(covers['root'], 'project');
    });

    test('guide campaign prints both guide statements and no code_root '
        'line', () async {
      final runner = await runnerFor(
        packs: shippedPinsConfig(['prd-core', 'marketing']),
      );

      expect(await runner.run(['guide', 'campaign']), 0);
      expect(
        out.toString(),
        allOf(
          contains(
            'The docs hold the stable facts and the campaign plan; the '
            "project's own skills write the content outside the docs.",
          ),
          contains('A learning edits the doc it corrects.'),
          isNot(contains('code_root')),
        ),
      );
      expect(err.toString(), isEmpty);
    });

    test('guide voice prints the marketing sections, then Writing habits '
        'last', () async {
      final runner = await runnerFor(
        packs: shippedPinsConfig(personalBrandingPacks),
      );

      expect(await runner.run(['guide', 'voice']), 0);
      final headers = RegExp(
        r'^## (.+)$',
        multiLine: true,
      ).allMatches(out.toString()).map((m) => m[1]).toList();
      expect(headers.sublist(headers.indexOf('Tone')), [
        'Tone',
        'Words',
        'Writing habits',
      ]);
      expect(err.toString(), isEmpty);
    });

    test('a project listing prd-core and marketing refuses guide story with '
        'the usage', () async {
      final runner = await runnerFor(
        packs: shippedPinsConfig(['prd-core', 'marketing']),
      );

      expect(await runner.run(['guide', 'story']), 64);
      expect(
        err.toString(),
        contains('Could not find a doc type named "story".\n\n$_guideUsage'),
      );
      expect(out.toString(), isEmpty);
    });

    test('guide proof --json prints the three optional sections and no '
        'perTarget', () async {
      final runner = await runnerFor(
        packs: shippedPinsConfig(personalBrandingPacks),
      );

      final schema = await schemaOf(runner, 'proof');
      expect(schema.containsKey('perTarget'), isFalse);
      final sections = (schema['sections']! as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(sections.map((s) => s['id']), [
        'results',
        'testimonials',
        'credentials',
      ]);
      expect(sections.map((s) => s['required']), everyElement(isNot(true)));
    });

    test('with only prd-core a software-tech type is neither listed nor '
        'printed', () async {
      final runner = await runnerFor(packs: shippedPinsConfig(['prd-core']));

      expect(await runner.run(['guide']), 0);
      final ids = const LineSplitter().convert(out.toString());
      expect(ids, contains('fr'));
      expect(ids, isNot(contains('architecture')));

      out.clear();
      expect(await runner.run(['guide', 'architecture']), 64);
      expect(
        err.toString(),
        contains(
          'Could not find a doc type named "architecture".\n\n$_guideUsage',
        ),
      );
      expect(out.toString(), isEmpty);

      err.clear();
      expect(await runner.run(['guide', 'architecture', '--json']), 64);
      expect(errorOf()['code'], 'doc_type_unknown');
      expect(out.toString(), isEmpty);
    });

    test(
      'software-tech without prd-core exits 78 as prd_core_missing',
      () async {
        final runner = await runnerFor(
          packs: shippedPinsConfig(['software-tech']),
        );

        expect(await runner.run(['guide', '--json']), 78);
        expect(errorOf()['code'], 'prd_core_missing');
        expect(out.toString(), isEmpty);
      },
    );

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
            'A journey: ',
            'Keep one goal of one persona, from the start',
            '## Goal\n\nRequired section.\n',
            '## Flow\n\nRequired section.\n',
            '## Steps\n\nRequired section.\n',
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
          'The project glossary doc: ',
          'Keep each entry to 300 characters or fewer',
          '## Terms\n\nOptional section.\n',
          '- **<Term>** — <one-line definition tying to a concrete entity>',
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
          'The project goal doc: ',
          '## Long-term goals\n\nOptional section.\n',
          'a goal for a year or more',
          'Its `**Serves:**` names a vision.\n',
          '## Mid-term goals\n\nOptional section.\n',
          'a goal for a quarter or more',
          'Its `**Serves:**` names a vision or a long-term goal.\n',
          '## Short-term goals\n\nOptional section.\n',
          'a goal for under a quarter',
          'names a vision, a long-term goal, or a mid-term goal.\n',
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
          'A measurement: ',
          "to the measured goal's `### PG-` heading in the goal doc.",
          'Results is a log: a run adds its row on top',
          '## Scope\n',
          '## Method\n',
          '## Baseline\n',
          '## Results\n',
          '## Open causes\n',
        ]),
      );
      expect(err.toString(), isEmpty);
    });

    test('a prd-core-only project lists exactly the fourteen prd-core doc '
        'types', () async {
      final runner = await runnerFor(packs: shippedPinsConfig(['prd-core']));

      expect(await runner.run(['guide']), 0);
      final ids = const LineSplitter().convert(out.toString());
      expect(ids, hasLength(14));
      expect(ids, [...prdCoreIds]..sort());
      expect(err.toString(), isEmpty);
    });

    test('a prd-core and software-tech project lists the fourteen and the '
        'fifteen doc types', () async {
      final runner = await runnerFor();

      expect(await runner.run(['guide']), 0);
      final ids = const LineSplitter().convert(out.toString());
      expect(ids, hasLength(29));
      expect(ids, [...prdCoreIds, ...softwareTechIds]..sort());
      expect(err.toString(), isEmpty);
    });

    test('guide index on a software-tech project exits 64 as '
        'doc_type_unknown with the usage', () async {
      final runner = await runnerFor();

      expect(await runner.run(['guide', 'index']), 64);
      expect(
        err.toString(),
        contains('Could not find a doc type named "index".\n\n$_guideUsage'),
      );
      expect(out.toString(), isEmpty);

      err.clear();
      expect(await runner.run(['guide', 'index', '--json']), 64);
      expect(errorOf()['code'], 'doc_type_unknown');
      expect(out.toString(), isEmpty);
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

    test('guide --pattern lists the campaign patterns of marketing, and the '
        'ten of software-tech beside them in code point order', () async {
      const campaign = ['product_launch', 'promotion', 'referral', 'retention'];
      final marketing = await runnerFor(
        packs: shippedPinsConfig(['prd-core', 'marketing']),
      );
      expect(await marketing.run(['guide', '--pattern']), 0);
      expect(const LineSplitter().convert(out.toString()), campaign);

      out.clear();
      expect(await marketing.run(['guide', '--pattern', '--json']), 0);
      final entries = (jsonDecode(out.toString()) as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(entries.map((e) => e['pack']), everyElement('marketing'));
      expect(entries.map((e) => e['description']), [
        'a launch of a new product or feature to its audience',
        'a time-boxed offer that drives sales',
        'a program in which customers bring new customers',
        'a program that keeps existing customers buying',
      ]);

      out.clear();
      final both = await runnerFor(
        packs: shippedPinsConfig(['prd-core', 'software-tech', 'marketing']),
      );
      expect(await both.run(['guide', '--pattern']), 0);
      final ids = const LineSplitter().convert(out.toString());
      expect(ids, hasLength(14));
      expect(ids, List.of(ids)..sort());
      expect(ids, containsAll(campaign));
      expect(err.toString(), isEmpty);
    });

    test('a project pattern file named like a campaign pattern lists it once '
        'and keeps marketing as its pack', () async {
      final runner = await runnerFor(
        working: await writeTree({
          _configPath: shippedPinsConfig(['prd-core', 'marketing']),
          '.specstone/templates/patterns/promotion.yaml': '''
id: promotion
items:
  - id: partner_codes
    text: Each partner gets its own code.
''',
        }),
      );

      expect(await runner.run(['guide', '--pattern', '--json']), 0);
      final entries = (jsonDecode(out.toString()) as List<Object?>)
          .cast<Map<String, Object?>>();
      final promotions = entries.where((e) => e['id'] == 'promotion');
      expect(promotions, hasLength(1));
      expect(promotions.single['pack'], 'marketing');
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
  });
}
