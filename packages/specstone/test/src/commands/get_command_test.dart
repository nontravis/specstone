import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/templates/shipped_pack_files.dart'
    show shippedPackVersions;
import 'package:test/test.dart';

import '../../../../specstone_core/test/helpers/rulebook_fixture.dart';
import '../../helpers/read_fixture.dart';
import '../../helpers/temp_tree.dart';

/// The config text pinning both shipped packs with the targets [targets].
String targetedConfig(Map<String, String> targets) {
  final versions = shippedPackVersions();
  final pins = [
    for (final pack in ['prd-core', 'software-tech'])
      '  $pack: ${versions[pack]}\n',
  ];
  final entries = [
    for (final e in targets.entries) '  ${e.key}:\n    code_root: ${e.value}\n',
  ];
  return 'packs:\n${pins.join()}targets:\n${entries.join()}';
}

/// Writes a two-target fixture: the feature `feedback/toast`, its
/// architecture doc in both targets, the domain doc in flutter alone.
///
/// A key in [extra] replaces or adds a file.
Future<Directory> writeTargetedProject({Map<String, String> extra = const {}}) {
  const base = <String, String>{
    '.specstone/templates/architecture.yaml':
        'id: architecture\nper_target: true\n',
    rulebookLayerFile: rulebookLayer,
    '.specstone/templates/implementation.yaml':
        'id: implementation\n'
        'description: One feature record per target.\n'
        'path: specs/f{nn}_{slug}/IMPLEMENTATION.md\n'
        'parent: feature\n'
        'per_target: true\n'
        'fields:\n'
        '  - id: statuses\n'
        '    type: record_status\n'
        '    list: true\n',
    '.specstone/templates/feature.yaml': 'max_depth: 1\n',
    '.specstone/config.yaml': '',
    'flutter_lib/.keep': '',
    'jaspr_lib/.keep': '',
    'docs/prds/features/f02_feedback/f03_toast/FEATURE.md':
        '---\nvision:\n  - PV-01\n---\n\n# Toast\n\n## Problem\nBurnt toast.\n',
    'docs/specs/flutter/f02_feedback/f03_toast/ARCHITECTURE.md':
        '# Toast architecture\n',
    'docs/specs/jaspr/f02_feedback/f03_toast/ARCHITECTURE.md':
        '# Toast architecture\n',
    'docs/specs/flutter/f02_feedback/f03_toast/DOMAIN.md': '# Toast domain\n',
    'docs/specs/flutter/f02_feedback/IMPLEMENTATION.md': '# Record\n',
    'docs/specs/jaspr/f02_feedback/IMPLEMENTATION.md': '# Record\n',
  };
  return writeReadProject(
    extra: {
      ...base,
      '.specstone/config.yaml': targetedConfig({
        'flutter': 'flutter_lib',
        'jaspr': 'jaspr_lib',
      }),
      ...extra,
    },
  );
}

void main() {
  test('get login prints the feature and its spec doc and exits 0', () async {
    final (:runner, :out, :err) = readRunner(await writeReadProject());
    expect(await runner.run(['get', 'login']), 0);
    expect(
      out.toString(),
      startsWith(
        '==> login (feature) · prds/features/f01_login/FEATURE.md · base ',
      ),
    );
  });
  group('several names', () {
    const featurePath = 'prds/features/f01_login/FEATURE.md';

    test('--json holds the docs in argument order', () async {
      final (:runner, :out, :err) = readRunner(await writeReadProject());
      expect(
        await runner.run([
          'get',
          'prds/d01_context.md#project_name',
          'login',
          '--json',
        ]),
        0,
      );
      final docs = (jsonDecode(out.toString()) as Map)['docs']! as List;
      expect(
        [for (final doc in docs) (doc as Map)['path']],
        ['prds/d01_context.md', featurePath, 'specs/f01_login/ARCHITECTURE.md'],
      );
    });

    test('one name that finds nothing refuses the whole call, stdout empty, '
        'exit 64', () async {
      final (:runner, :out, :err) = readRunner(await writeReadProject());
      expect(await runner.run(['get', 'login', 'logn', 'nope']), 64);
      expect(out.toString(), isEmpty);
      expect(
        err.toString(),
        'no doc carries the name logn; no doc carries the name nope\n',
      );
      expect(await runner.run(['get', 'login', 'login#acceptance']), 64);
      expect(out.toString(), isEmpty);
      expect(
        err.toString(),
        endsWith(
          'no doc named login holds a section with the key acceptance\n',
        ),
      );
    });

    test('faults of two codes print one stderr line each, exit status '
        "the first fault's", () async {
      final (:runner, :out, :err) = readRunner(await writeReadProject());
      expect(await runner.run(['get', 'logn', 'login#acceptance', 'nope']), 64);
      expect(out.toString(), isEmpty);
      expect(
        err.toString(),
        'no doc carries the name logn; no doc carries the name nope\n'
        'no doc named login holds a section with the key acceptance\n',
      );
    });
  });
  test('no name is argument_missing, exit 64', () async {
    final (:runner, :out, :err) = readRunner(await writeReadProject());
    expect(await runner.run(['get']), 64);
    expect(err.toString(), 'get needs a name, such as specstone get login\n');
  });
  test('--json puts section_not_found on stderr with stdout empty', () async {
    final (:runner, :out, :err) = readRunner(await writeReadProject());
    expect(await runner.run(['get', 'login#acceptance', '--json']), 64);
    expect(
      ((jsonDecode(err.toString()) as Map)['error'] as Map)['code'],
      'section_not_found',
    );
    expect(out.toString(), isEmpty);
  });
  test('no name under --json is the argument_missing envelope, exit 64, '
      'stdout empty', () async {
    final (:runner, :out, :err) = readRunner(await writeReadProject());
    expect(await runner.run(['get', '--json']), 64);
    expect(out.toString(), isEmpty);
    expect(
      ((jsonDecode(err.toString()) as Map)['error'] as Map)['code'],
      'argument_missing',
    );
  });
  test('outside a project the fault is project_not_found, and under a 9.9.9 '
      'pin it is the pin fault, with no index built', () async {
    final outside = readRunner(await writeTree({}));
    expect(await outside.runner.run(['get', 'login', '--json']), 78);
    expect(
      ((jsonDecode(outside.err.toString()) as Map)['error'] as Map)['code'],
      'project_not_found',
    );
    final pinned = await writeReadProject(
      extra: {'.specstone/config.yaml': 'packs:\n  prd-core: 9.9.9\n'},
    );
    final run = readRunner(pinned);
    expect(await run.runner.run(['get', 'login', '--json']), 78);
    expect(
      ((jsonDecode(run.err.toString()) as Map)['error'] as Map)['code'],
      'pack_pin_newer',
    );
    expect(
      File('${pinned.path}/.specstone/index.sqlite').existsSync(),
      isFalse,
    );
  });
  test('an untyped doc whose file name holds @ is printed by get and planned '
      'by delete --dry-run', () async {
    final project = await writeReadProject(
      extra: {'docs/prds/a@b.md': '# At\n'},
    );
    final get = readRunner(project);
    expect(await get.runner.run(['get', 'prds/a@b.md']), 0);
    expect(get.out.toString(), contains('prds/a@b.md'));
    expect(get.out.toString(), contains('# At'));
    final delete = readRunner(project);
    expect(
      await delete.runner.run(['delete', 'prds/a@b.md', '--dry-run']),
      0,
      reason: delete.err.toString(),
    );
    expect(delete.out.toString(), startsWith('prds/a@b.md'));
    expect(delete.out.toString(), contains('dry run: nothing removed'));
  });

  group('journey options', () {
    const journeyDoc = 'docs/prds/journeys/sign_in/JOURNEY.md';
    const journeyText =
        '# Sign in\n\n## Goal\nReach home.\n\n## Flow\n\n## Steps\n'
        '### 1. Open the page\nstep: login/email_login S1\n';

    const storyDoc =
        'docs/prds/features/f01_login/us01_email_login/USER_STORY.md';
    const storyText =
        '# Agent signs in with email\n\n## Use Case\nSign in.\n\n'
        '## Acceptance Criteria\n\n### Scenario 1 — [happy] Sign in\n'
        '- **Given** an account\n- **Then** the Agent sees home\n';

    Future<Directory> project({String text = journeyText}) =>
        writeReadProject(extra: {journeyDoc: text, storyDoc: storyText});

    test('--paths with --code is argument_conflict, exit 64', () async {
      final (:runner, :out, :err) = readRunner(await project());
      expect(
        await runner.run(['get', 'sign_in', '--paths', '--code', '--json']),
        64,
      );
      expect((jsonDecode(err.toString()) as Map)['error'], {
        'code': 'argument_conflict',
        'message': '--code and --paths cannot be given together',
      });
    });
    test('--paths with a section key is argument_conflict, exit 64', () async {
      final (:runner, :out, :err) = readRunner(await project());
      expect(
        await runner.run(['get', 'journey:sign_in#steps', '--paths', '--json']),
        64,
      );
      expect((jsonDecode(err.toString()) as Map)['error'], {
        'code': 'argument_conflict',
        'message': '--paths takes no #<section key>',
      });
    });
    test(
      '--code with a section key is argument_conflict, exit 64, stdout empty '
      'and no bundle written',
      () async {
        final dir = await project();
        final (:runner, :out, :err) = readRunner(dir);
        expect(
          await runner.run([
            'get',
            'journey:sign_in#steps',
            '--code',
            '--json',
          ]),
          64,
        );
        expect(out.toString(), isEmpty);
        expect((jsonDecode(err.toString()) as Map)['error'], {
          'code': 'argument_conflict',
          'message': '--code takes no #<section key>',
        });
        err.clear();
        expect(
          await runner.run(['get', 'journey:sign_in#steps', '--code', '--out']),
          64,
        );
        expect(out.toString(), isEmpty);
        expect(err.toString(), '--code takes no #<section key>\n');
        final reports = Directory(
          [dir.path, '.specstone', 'reports'].join(Platform.pathSeparator),
        );
        expect(
          !reports.existsSync() || reports.listSync().isEmpty,
          isTrue,
          reason: 'no --out file',
        );
      },
    );
    test('--paths reads a path holding # whole, so it is no section '
        'key and no argument_conflict', () async {
      final (:runner, :out, :err) = readRunner(
        await writeReadProject(
          extra: {'docs/prds/notes#draft.md': '# Draft\n'},
        ),
      );
      await runner.run(['get', 'prds/notes#draft.md', '--paths', '--json']);
      expect(err.toString(), isNot(contains('argument_conflict')));
      expect(err.toString(), isNot(contains('takes no #<section key>')));
    });
    test(
      'get journey:<slug> --paths prints on stdout, warnings on stderr, exit 0',
      () async {
        final (:runner, :out, :err) = readRunner(await project());
        expect(await runner.run(['get', 'journey:sign_in', '--paths']), 0);
        expect(
          out.toString(),
          startsWith(
            '==> sign_in (journey) · prds/journeys/sign_in/JOURNEY.md <==\n'
            'journey:sign_in path 1\n1. Open the page — login/email_login S1\n'
            '- **Given** an account\n- **Then** the Agent sees home\n',
          ),
        );
        expect(err.toString(), isEmpty);
      },
    );
    test(
      'a step naming no scenario warns on stderr and still exits 0',
      () async {
        final (:runner, :out, :err) = readRunner(
          await project(text: journeyText.replaceFirst('S1', 'S9')),
        );
        expect(await runner.run(['get', 'sign_in', '--paths']), 0);
        expect(
          err.toString(),
          '⚠️ WARNING: sign_in: step 1 names no scenario\n',
        );
      },
    );
    for (final option in ['--paths', '--code']) {
      test(
        '$option with two names is argument_invalid, exit 64, nothing printed',
        () async {
          final (:runner, :out, :err) = readRunner(await project());
          expect(
            await runner.run([
              'get',
              'journey:sign_in',
              'login',
              option,
              '--json',
            ]),
            64,
          );
          expect(out.toString(), isEmpty);
          expect((jsonDecode(err.toString()) as Map)['error'], {
            'code': 'argument_invalid',
            'message': '$option takes one name, got 2',
          });
          err.clear();
          expect(
            await runner.run(['get', 'journey:sign_in', 'login', option]),
            64,
          );
          expect(out.toString(), isEmpty);
          expect(err.toString(), '$option takes one name, got 2\n');
        },
      );
    }
    test(
      'get journey:<slug> --code --json prints one object, exit 0',
      () async {
        final (:runner, :out, :err) = readRunner(await project());
        expect(
          await runner.run(['get', 'journey:sign_in', '--code', '--json']),
          0,
        );
        final printed = jsonDecode(out.toString()) as Map;
        expect(printed.keys, ['journeys', 'warnings']);
        expect(
          ((printed['journeys'] as List).single as Map)['steps'],
          hasLength(1),
        );
      },
    );
  });

  group('--out', () {
    const journeyDoc = 'docs/prds/journeys/sign_in/JOURNEY.md';
    const journeyText =
        '# Sign in\n\n## Goal\nReach home.\n\n## Flow\n\n## Steps\n'
        '### 1. Open the page\nstep: login/email_login S1\n';
    const storyDoc =
        'docs/prds/features/f01_login/us01_email_login/USER_STORY.md';
    const storyText =
        '# Agent signs in with email\n\n## Use Case\nSign in.\n\n'
        '## Acceptance Criteria\n\n### Scenario 1 — [happy] Sign in\n'
        '- **Given** an account\n- **Then** the Agent sees home\n';

    test('writes the doc to .specstone/reports/get.<name>.txt and prints its '
        'header', () async {
      final project = await writeReadProject();
      final run = readRunner(project);
      expect(
        await run.runner.run(['get', 'feature:login', '--out']),
        0,
        reason: run.err.toString(),
      );
      final file = File(
        '${project.path}/.specstone/reports/get.feature-login.txt',
      );
      expect(file.readAsStringSync(), startsWith('==> login (feature) · '));
      final lines = run.out.toString().trimRight().split('\n');
      expect(lines, hasLength(1));
      expect(lines.single, startsWith('==> get: '));
      expect(lines.single, contains(file.resolveSymbolicLinksSync()));
    });

    test('the header holds the line and token counts of the file, and '
        '--json --out prints out, lines, and tokens', () async {
      final project = await writeReadProject();
      final run = readRunner(project);
      expect(await run.runner.run(['get', 'feature:login', '--out']), 0);
      final text = File(
        '${project.path}/.specstone/reports/get.feature-login.txt',
      ).readAsStringSync();
      final header = RegExp(r'^==> get: (\d+) lines, (\d+) tokens · .+ <==$')
          .firstMatch(run.out.toString().trimRight());
      expect(header, isNotNull);
      expect(int.parse(header![1]!), text.trimRight().split('\n').length);
      expect(int.parse(header[2]!), greaterThan(0));
      final json = readRunner(project);
      expect(
        await json.runner.run(['get', 'feature:login', '--json', '--out']),
        0,
      );
      final printed = jsonDecode(json.out.toString()) as Map;
      expect(printed.keys, containsAll(['out', 'lines', 'tokens']));
      expect(printed['out'], endsWith('get.feature-login.json'));
      expect(printed['lines'], isA<int>());
      expect(printed['tokens'], greaterThan(0));
    });

    test('--paths --out names its file get-paths.<journey>.txt', () async {
      final project = await writeReadProject(
        extra: {journeyDoc: journeyText, storyDoc: storyText},
      );
      final run = readRunner(project);
      expect(
        await run.runner.run(['get', 'sign_in', '--paths', '--out']),
        0,
        reason: run.err.toString(),
      );
      final file = File(
        '${project.path}/.specstone/reports/get-paths.sign_in.txt',
      );
      expect(file.readAsStringSync(), contains('1. Open the page'));
      expect(run.out.toString(), startsWith('==> get: '));
    });

    test('a typed name has its colon turned to a dash in the bare file name, '
        'for --paths and --code', () async {
      for (final option in ['paths', 'code']) {
        final project = await writeReadProject(
          extra: {journeyDoc: journeyText, storyDoc: storyText},
        );
        final run = readRunner(project);
        expect(
          await run.runner.run([
            'get',
            'journey:sign_in',
            '--$option',
            '--out',
          ]),
          0,
          reason: run.err.toString(),
        );
        final file = File(
          [
            project.path,
            '.specstone',
            'reports',
            'get-$option.journey-sign_in.txt',
          ].join(Platform.pathSeparator),
        );
        expect(file.existsSync(), isTrue, reason: option);
        expect(run.out.toString(), startsWith('==> get: '), reason: option);
      }
    });

    test(
      '--json --out carries the session warnings in the file as printed',
      () async {
        final project = await writeReadProject();
        File(
          [
            project.path,
            '.specstone',
            'index.sqlite',
          ].join(Platform.pathSeparator),
        ).writeAsStringSync('not a database');
        final run = readRunner(project);
        expect(
          await run.runner.run(['get', 'feature:login', '--json', '--out']),
          0,
          reason: run.err.toString(),
        );
        final file = File(
          [
            project.path,
            '.specstone',
            'reports',
            'get.feature-login.json',
          ].join(Platform.pathSeparator),
        );
        final written =
            jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
        expect(written['warnings'], isNotEmpty);
        final printed = jsonDecode(run.out.toString()) as Map<String, Object?>;
        expect(printed['warnings'], written['warnings']);
      },
    );

    test('a path given names the file, and its folder is made', () async {
      final project = await writeReadProject();
      final run = readRunner(project);
      expect(
        await run.runner.run(['get', 'login', '--out', 'out/login.txt']),
        0,
        reason: run.err.toString(),
      );
      expect(
        File('${project.path}/out/login.txt').readAsStringSync(),
        startsWith('==> login (feature) · '),
      );
    });

    test('a path under .specstone/reports/ names the file and prints its '
        'header', () async {
      final project = await writeReadProject();
      final run = readRunner(project);
      final target = [
        project.path,
        '.specstone',
        'reports',
        'get.ab12cd.txt',
      ].join(Platform.pathSeparator);
      expect(
        await run.runner.run(['get', 'feature:login', '--out', target]),
        0,
        reason: run.err.toString(),
      );
      final file = File(target);
      expect(file.readAsStringSync(), startsWith('==> login (feature) · '));
      expect(run.out.toString(), startsWith('==> get: '));
      expect(run.out.toString(), contains(file.resolveSymbolicLinksSync()));
    });

    test('--out "" is argument_invalid, exit 64, and writes no file', () async {
      final project = await writeReadProject();
      final run = readRunner(project);
      expect(await run.runner.run(['get', 'login', '--out', '']), 64);
      expect(run.out.toString(), isEmpty);
      expect(
        Directory('${project.path}/.specstone/reports').existsSync(),
        isFalse,
      );
    });

    test('a path under .specstone/ outside bundles/ and reports/ exits 73 and '
        'the config stays whole', () async {
      final project = await writeReadProject();
      final config = File('${project.path}/.specstone/config.yaml');
      final before = config.readAsBytesSync();
      final run = readRunner(project);
      expect(
        await run.runner.run([
          'get',
          'login',
          '--out',
          '.specstone/config.yaml',
        ]),
        73,
      );
      expect(run.out.toString(), isEmpty);
      expect(config.readAsBytesSync(), before);
    });

    test('a name that finds nothing exits 64 and writes no file', () async {
      final project = await writeReadProject();
      final run = readRunner(project);
      expect(await run.runner.run(['get', 'nope', '--out']), 64);
      expect(run.out.toString(), isEmpty);
      expect(
        Directory('${project.path}/.specstone/reports').existsSync(),
        isFalse,
      );
    });
  });

  group('--target', () {
    test("--target jaspr keeps the name to jaspr's docs and the "
        'shared docs, a path whatever the target', () async {
      final (:runner, :out, :err) = readRunner(await writeTargetedProject());
      expect(
        await runner.run([
          'get',
          'architecture:feedback/toast',
          '--target',
          'jaspr',
        ]),
        0,
      );
      expect(
        out.toString(),
        startsWith(
          '==> feedback/toast (architecture) · '
          'specs/jaspr/f02_feedback/f03_toast/ARCHITECTURE.md · base ',
        ),
      );
      out.clear();
      expect(
        await runner.run([
          'get',
          'feedback/toast',
          '--target',
          'jaspr',
          '--json',
        ]),
        0,
      );
      expect(
        [
          for (final doc
              in (jsonDecode(out.toString()) as Map)['docs']! as List)
            (doc as Map)['path'],
        ],
        [
          'prds/features/f02_feedback/f03_toast/FEATURE.md',
          'specs/jaspr/f02_feedback/f03_toast/ARCHITECTURE.md',
        ],
      );
      out.clear();
      expect(
        await runner.run([
          'get',
          'specs/flutter/f02_feedback/f03_toast/DOMAIN.md',
          '--target',
          'jaspr',
        ]),
        0,
      );
      expect(
        out.toString(),
        contains(
          'specs/flutter/f02_feedback/f03_toast/'
          'DOMAIN.md',
        ),
      );
    });
    test('--paths and --code refuse a target targets: holds none of, '
        'argument_invalid, exit 64', () async {
      for (final option in ['--paths', '--code']) {
        final (:runner, :out, :err) = readRunner(
          await writeTargetedProject(
            extra: {
              'docs/prds/journeys/sign_in/JOURNEY.md':
                  '# Sign in\n\n## Goal\nReach home.\n\n## Flow\n\n## Steps\n'
                  '### 1. Open the page\nstep: feedback/toast S1\n',
            },
          ),
        );
        expect(
          await runner.run([
            'get',
            'sign_in',
            option,
            '--target',
            'web',
            '--json',
          ]),
          64,
          reason: option,
        );
        expect((jsonDecode(err.toString()) as Map)['error'], {
          'code': 'argument_invalid',
          'message': '--target web: the code targets are flutter, jaspr',
        }, reason: option);
      }
    });
    test('--paths resolves its address under the given target', () async {
      final project = await writeTargetedProject(
        extra: {
          '.specstone/templates/user_story.yaml':
              'id: user_story\nper_target: true\n'
              'path: specs/f{nn}_{slug}/us{nn}_{slug}/USER_STORY.md\n',
          'docs/prds/journeys/sign_in/JOURNEY.md':
              '# Sign in\n\n## Goal\nReach home.\n\n## Flow\n\n## Steps\n'
              '### 1. Open the page\nstep: feedback/toast/show S1\n',
          'docs/specs/flutter/f02_feedback/f03_toast/us01_show/USER_STORY.md':
              '# Show toast\n\n## Acceptance Criteria\n'
              '### Scenario 1 — [happy] Show\n- **Then** the Agent sees it '
              'on flutter\n',
          'docs/specs/jaspr/f02_feedback/f03_toast/us01_show/USER_STORY.md':
              '# Show toast\n\n## Acceptance Criteria\n'
              '### Scenario 1 — [happy] Show\n- **Then** the Agent sees it '
              'on jaspr\n',
        },
      );
      final (:runner, :out, :err) = readRunner(project);
      expect(
        await runner.run(['get', 'sign_in', '--paths', '--target', 'jaspr']),
        0,
      );
      expect(err.toString(), isEmpty);
      expect(
        out.toString(),
        allOf(
          contains('1. Open the page — feedback/toast/show S1'),
          contains('- **Then** the Agent sees it on jaspr'),
          isNot(contains('on flutter')),
        ),
      );
    });
    test('--paths with no --target resolves the step in a two-target '
        'project', () async {
      final project = await writeTargetedProject(
        extra: {
          '.specstone/templates/user_story.yaml':
              'id: user_story\nper_target: true\n'
              'path: specs/f{nn}_{slug}/us{nn}_{slug}/USER_STORY.md\n',
          'docs/prds/journeys/sign_in/JOURNEY.md':
              '# Sign in\n\n## Goal\nReach home.\n\n## Flow\n\n## Steps\n'
              '### 1. Open the page\nstep: feedback/toast/show S1\n',
          'docs/specs/flutter/f02_feedback/f03_toast/us01_show/USER_STORY.md':
              '# Show toast\n\n## Acceptance Criteria\n'
              '### Scenario 1 — [happy] Show\n- **Then** the Agent sees it '
              'on flutter\n',
          'docs/specs/jaspr/f02_feedback/f03_toast/us01_show/USER_STORY.md':
              '# Show toast\n\n## Acceptance Criteria\n'
              '### Scenario 1 — [happy] Show\n- **Then** the Agent sees it '
              'on jaspr\n',
        },
      );
      final (:runner, :out, :err) = readRunner(project);
      expect(await runner.run(['get', 'sign_in', '--paths']), 0);
      expect(err.toString(), isEmpty);
      expect(
        out.toString(),
        allOf(
          contains('1. Open the page — feedback/toast/show S1'),
          contains('- **Then** the Agent sees it on flutter'),
        ),
      );
    });
  });
}
