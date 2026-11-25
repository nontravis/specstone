// The expected values are plan literals kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/templates/shipped_pack_files.dart'
    show shippedPackVersions;
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import '../../../../specstone_core/test/helpers/shipped_pins.dart';

import '../../helpers/built_cli.dart';
import '../../helpers/read_fixture.dart';
import '../../helpers/temp_tree.dart';

const legacyFr = {
  '.specstone/templates/legacy_fr.yaml':
      'id: legacy_fr\n'
      'description: Old FRs.\npath: prds/features/f{nn}_{slug}/us{nn}_{slug}/{slug}.md\n',
};
const frWarning =
    'prds/features/f01_login/us01_email_login/fr01_validate_credentials.md matches two doc types: fr, legacy_fr';

const frKey =
    'docs/prds/features/f01_login/us01_email_login/fr01_validate_credentials.md';
const frTarget = 'fr:login/email_login/validate_credentials';

// A requirement whose sections count 166, 229 chars and whose items 165, 106, 121.
String frWithSizes() =>
    '---\nstatus: implemented\ntraced_from:\n  - S1\n  - S2\n'
    'implements:\n  - app/lib/src/login/credential_validator.dart:CredentialValidator\n---\n\n'
    '# Validate credentials\n\n## Statement\n'
    '${'The system shall check the email and the password.'.padRight(165, '.')}\n\n'
    '## Edge cases\n${'1. E01 — A wrong password → refused'.padRight(106, '.')}\n'
    '${'2. E02 — An unknown email → refused'.padRight(121, '.')}\n';

Map<String, Object?> errorOf(StringBuffer err) =>
    (jsonDecode(err.toString()) as Map)['error'] as Map<String, Object?>;

/// Writes the two-target fixture of `index_query/view_docs_tree/print_docs_tree`
/// E15: the feature `feedback/toast`, its two stories, its architecture doc in
/// both targets, and each target's record.
Future<Directory> writeTargetedTree() {
  const feature =
      '---\nstatus: implemented\n---\n\n# Toast\n\n## Problem\nBurnt toast.\n';
  const show =
      '---\nstatus: implemented\n---\n\n# Agent sees a toast\n\n## Use Case\n'
      'Use it.\n';
  const swipe =
      '---\nstatus: implemented\n---\n\n# Agent swipes a toast away\n\n'
      '## Use Case\nUse it.\n';
  String record(String statuses) => statuses.isEmpty
      ? '# Record\n'
      : '---\nstatuses:\n$statuses---\n\n# Record\n';
  return writeReadProject(
    extra: {
      '.specstone/templates/architecture.yaml':
          'id: architecture\nper_target: true\n',
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
      '.specstone/config.yaml':
          'packs:\n'
          '  prd-core: ${shippedPackVersions()['prd-core']}\n'
          '  software-tech: ${shippedPackVersions()['software-tech']}\n'
          'targets:\n'
          '  flutter:\n    code_root: flutter_lib\n'
          '  jaspr:\n    code_root: jaspr_lib\n',
      'flutter_lib/.keep': '',
      'jaspr_lib/.keep': '',
      'docs/prds/features/f02_feedback/f03_toast/FEATURE.md': feature,
      'docs/prds/features/f02_feedback/FEATURE.md': feature,
      'docs/prds/features/f02_feedback/f03_toast/us01_show/USER_STORY.md': show,
      'docs/prds/features/f02_feedback/f03_toast/us02_swipe/USER_STORY.md':
          swipe,
      'docs/specs/flutter/f02_feedback/f03_toast/ARCHITECTURE.md':
          '# Toast architecture\n',
      'docs/specs/jaspr/f02_feedback/f03_toast/ARCHITECTURE.md':
          '# Toast architecture\n',
      'docs/specs/flutter/f02_feedback/f03_toast/IMPLEMENTATION.md': record(
        '  - show:implemented\n  - swipe:implemented\n',
      ),
      'docs/specs/jaspr/f02_feedback/f03_toast/IMPLEMENTATION.md': record(
        '  - show:planned\n  - swipe:skipped:no jaspr\n',
      ),
    },
  );
}

void main() {
  test('structure prints the tree on stdout and exits 0', () async {
    final (:runner, :out, :err) = readRunner(await writeReadProject());
    expect(await runner.run(['structure']), 0);
    expect(out.toString(), contains('login (feature) — Login · planned · '));
    expect(err.toString(), isEmpty);
  });
  test(
    'structure --target jaspr prints jaspr alone, no flutter spec doc',
    () async {
      final (:runner, :out, :err) = readRunner(await writeTargetedTree());
      expect(
        await runner.run(['structure', 'feedback/toast', '--target', 'jaspr']),
        0,
      );
      final lines = out.toString().split('\n');
      expect(lines.first, contains(' · planned · '));
      expect(
        lines.where((l) => l.contains('(user_story)')).last,
        contains(' · skipped · '),
      );
      expect(
        lines.where((l) => l.contains('flutter')),
        isEmpty,
        reason: 'no flutter status and no flutter spec doc',
      );
      expect(err.toString(), isEmpty);
    },
  );
  test(
    '--json prints one object; a warning goes only to its warnings array',
    () async {
      final (:runner, :out, :err) = readRunner(
        await writeReadProject(extra: legacyFr),
      );
      expect(await runner.run(['structure', '--json']), 0);
      final json = jsonDecode(out.toString()) as Map<String, Object?>;
      expect(json.keys.toList(), ['docs', 'untyped', 'warnings']);
      expect(json['warnings'], [frWarning]);
      expect(err.toString(), isEmpty);
    },
  );
  test(
    'in text mode the warning prints on stderr with the warning prefix',
    () async {
      final (:runner, :out, :err) = readRunner(
        await writeReadProject(extra: legacyFr),
      );
      expect(await runner.run(['structure']), 0);
      expect(err.toString(), '⚠️ WARNING: $frWarning\n');
    },
  );
  test('a target no doc carries exits 64 and names it', () async {
    final (:runner, :out, :err) = readRunner(await writeReadProject());
    expect(await runner.run(['structure', 'logn']), 64);
    expect(err.toString(), 'no doc carries the name logn\n');
    expect(out.toString(), isEmpty);
  });
  test('two names of no doc exit 64 with one doc_not_found line each and print no tree', () async {
    final (:runner, :out, :err) = readRunner(await writeReadProject());
    expect(await runner.run(['structure', 'logn', 'resett']), 64);
    expect(
      err.toString(),
      'no doc carries the name logn\nno doc carries the name resett\n',
    );
    expect(out.toString(), isEmpty);
  });
  test('outside a project exits 78', () async {
    final (:runner, :out, :err) = readRunner(await writeTree({}));
    expect(await runner.run(['structure']), 78);
    expect(
      err.toString(),
      'no Specstone project: no folder from the working directory upward holds .specstone/config.yaml\n',
    );
  });
  test("a template fault exits 78 with the template fault's code", () async {
    final (:runner, :out, :err) = readRunner(
      await writeReadProject(
        extra: {'.specstone/config.yaml': 'packs:\n  prd-core: 9.9.9\n'},
      ),
    );
    expect(await runner.run(['structure', '--json']), 78);
    expect(errorOf(err)['code'], 'pack_pin_newer');
    expect(out.toString(), isEmpty);
  });
  test(
    'a read-only .specstone/ exits 73 with the JSON envelope',
    skip: readOnlySkipReason(),
    () async {
      final project = await writeReadProject();
      final dot = Directory('${project.path}/.specstone');
      Process.runSync('chmod', ['555', dot.path]);
      addTearDown(() => Process.runSync('chmod', ['755', dot.path]));
      final (:runner, :out, :err) = readRunner(project);
      expect(await runner.run(['structure', '--json']), 73);
      expect(errorOf(err), {
        'code': 'index_not_writable',
        'message': 'cannot write the index under .specstone/; make it writable and run the command again',
      });
      expect(out.toString(), isEmpty);
    },
  );
  test(
    'a write lock held past the timeout exits 75 with the JSON envelope',
    () async {
      final project = await writeReadProject();
      expect(await readRunner(project).runner.run(['structure']), 0);
      final holder = sqlite3.open('${project.path}/.specstone/index.sqlite')
        ..execute('BEGIN IMMEDIATE');
      addTearDown(
        () => holder
          ..execute('ROLLBACK')
          ..close(),
      );
      File('${project.path}/docs/prds/features/f01_login/FEATURE.md')
          .writeAsStringSync('# Login v2\n');
      final (:runner, :out, :err) = readRunner(
        project,
        busyTimeout: const Duration(milliseconds: 200),
      );
      expect(await runner.run(['structure', '--json']), 75);
      expect(errorOf(err), {
        'code': 'index_busy',
        'message': 'the index is busy; run the command again once the other call finishes',
      });
      expect(out.toString(), isEmpty);
    },
  );

  group('built binary', () {
    late String binary;

    setUpAll(() async {
      binary = await buildSpecstone();
    });

    test('structure prints a linked item at its visible count', () async {
      const item = '- See [the rule](a/b.md#rules).';
      final project = await writeReadProject(
        extra: {
          frKey: frWithSizes().replaceFirst(
            RegExp(r'The system shall check[^\n]*\n'),
            '$item\n',
          ),
        },
      );
      final run = await runSpecstone(binary, [
        'structure',
        frTarget,
      ], workingDirectory: project.path);

      expect(run.exitCode, 0, reason: '${run.stdout}\n${run.stderr}');
      expect((run.stdout as String).split('\n').skip(1).take(2), [
        '  statement · ${'\n$item'.length} chars',
        '    line 14 · 15 chars',
      ]);
    });
  });

  group('built binary on a doc the markdown parser fails on', () {
    late String binary;

    setUpAll(() async {
      binary = await buildSpecstone();
    });

    test('every read command answers with the title, frontmatter values, and '
        'sections, no links, and the warning', () async {
      const emptyHash = 'e3b0c44298fc';
      const unparsedWarning =
          'prds/features/f01_login/us01_email_login/'
          'fr01_validate_credentials.md: the markdown parser failed; '
          'its links are not indexed';
      final project = await writeReadProject(
        extra: {
          frKey:
              '---\nstatus: implemented\n---\n\n# Validate credentials\n\n'
              '## Statement\nSee [the story](USER_STORY.md).\n\n[a]:<b\\',
        },
      );
      Future<ProcessResult> run(List<String> args) =>
          runSpecstone(binary, args, workingDirectory: project.path);

      final get = await run(['get', frTarget, '--json']);
      final refs = await run(['refs', frTarget, '--json']);
      final structure = await run(['structure', frTarget]);
      final list = await run(['list', 'fr']);
      final search = await run(['search', 'Validate']);

      for (final result in [get, refs, structure, list, search]) {
        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
      }
      final doc =
          ((jsonDecode(get.stdout as String) as Map)['docs']! as List).single
              as Map;
      final bases = doc['bases'] as Map;
      final realHash = allOf(isA<String>(), isNotEmpty, isNot(emptyHash));
      expect(bases['title'], realHash);
      expect((bases['fields'] as Map)['status'], realHash);
      expect((bases['sections'] as Map)['statement'], realHash);
      expect((jsonDecode(get.stdout as String) as Map)['warnings'], [
        unparsedWarning,
      ]);
      expect(list.stdout, contains('Validate credentials'));
      expect(search.stdout, contains('validate_credentials#statement'));
      expect(structure.stdout, contains('statement'));
      final refsDoc =
          ((jsonDecode(refs.stdout as String) as Map)['docs']! as List).single
              as Map;
      expect(refsDoc['outbound'], isEmpty);
      for (final result in [list, search, structure]) {
        expect(result.stderr, contains(unparsedWarning));
      }
    });
  });

  group('on a project with no docs folder', () {
    const readCommands = [
      ['structure'],
      ['structure', '--json'],
      ['list', 'user_story'],
      ['list', 'user_story', '--json'],
      ['search', 'login'],
      ['search', 'login', '--json'],
      ['check'],
      ['check', '--json'],
      ['get', 'feature:login'],
      ['refs', 'feature:login'],
      ['context', 'feature:login', '--for', 'design'],
      ['structure', 'feature:login'],
    ];

    test('each read command answers as on an empty docs folder', () async {
      final bare = await writeTree({
        '.specstone/config.yaml': shippedPinsConfig(),
      });
      final empty = await writeTree({
        '.specstone/config.yaml': shippedPinsConfig(),
        'docs/.keep': '',
      });
      for (final args in readCommands) {
        final (runner: bareRunner, out: bareOut, err: bareErr) = readRunner(
          bare,
        );
        final (runner: emptyRunner, out: emptyOut, err: emptyErr) = readRunner(
          empty,
        );
        final bareStatus = await bareRunner.run(args);
        expect(await emptyRunner.run(args), bareStatus, reason: '$args');
        expect(bareOut.toString(), emptyOut.toString(), reason: '$args');
        expect(bareErr.toString(), emptyErr.toString(), reason: '$args');
      }
    });

    test('structure, list, and search print no doc and exit 0', () async {
      final bare = await writeTree({
        '.specstone/config.yaml': shippedPinsConfig(),
      });
      for (final args in [
        ['structure'],
        ['list', 'user_story'],
        ['search', 'login'],
      ]) {
        final (:runner, :out, :err) = readRunner(bare);
        expect(await runner.run(args), 0, reason: '$args');
        expect(out.toString(), isEmpty, reason: '$args');
        expect(err.toString(), isEmpty, reason: '$args');
      }
    });

    test('a read command naming a doc is doc_not_found, exit 64', () async {
      final bare = await writeTree({
        '.specstone/config.yaml': shippedPinsConfig(),
      });
      for (final args in [
        ['get', 'feature:login'],
        ['refs', 'feature:login'],
        ['context', 'feature:login', '--for', 'design'],
      ]) {
        final (:runner, :out, :err) = readRunner(bare);
        expect(await runner.run(args), 64, reason: '$args');
        expect(err.toString(), 'no feature doc carries the name login\n');
        expect(out.toString(), isEmpty);
      }
    });
  });

  test(
    'a target no doc carries is doc_not_found with --json, exit 64',
    () async {
      final (:runner, :out, :err) = readRunner(await writeReadProject());
      expect(await runner.run(['structure', 'logn', '--json']), 64);
      expect(errorOf(err), {
        'code': 'doc_not_found',
        'message': 'no doc carries the name logn',
      });
      expect(out.toString(), isEmpty);
    },
  );

  test('outside a project the --json error is project_not_found, and no index is made', () async {
    final folder = await writeTree({});
    final (:runner, :out, :err) = readRunner(folder);
    expect(await runner.run(['structure', '--json']), 78);
    expect(errorOf(err)['code'], 'project_not_found');
    expect(out.toString(), isEmpty);
    expect(folder.listSync(), isEmpty);
  });
  group('--out', () {
    test(
      'a bare --out saves the stdout text and prints only its header',
      () async {
        final project = await writeReadProject();
        final plain = readRunner(project);
        expect(await plain.runner.run(['structure']), 0);

        final (:runner, :out, :err) = readRunner(project);
        expect(
          await runner.run(['structure', '--out']),
          0,
          reason: err.toString(),
        );
        final file = File(
          '${project.path}/.specstone/reports/structure.all.txt',
        );
        expect(file.readAsStringSync(), plain.out.toString());
        final printed = out.toString();
        expect(printed.trimRight().split('\n'), hasLength(1));
        expect(
          printed,
          matches(RegExp(r'^==> structure: \d+ lines, \d+ tokens · .+ <==\n$')),
        );
        expect(printed, contains(file.resolveSymbolicLinksSync()));
        expect(err.toString(), isEmpty);
      },
    );

    test('--json --out saves the JSON reply and prints only {out, lines, tokens, warnings}', () async {
      final project = await writeReadProject(extra: legacyFr);
      final plain = readRunner(project);
      expect(
        await plain.runner.run(['structure', 'feature:login', '--json']),
        0,
      );

      final (:runner, :out, :err) = readRunner(project);
      expect(
        await runner.run(['structure', 'feature:login', '--json', '--out']),
        0,
        reason: err.toString(),
      );
      final file = File(
        '${project.path}/.specstone/reports/structure.feature-login.json',
      );
      expect(file.readAsStringSync(), plain.out.toString());
      final printed = jsonDecode(out.toString()) as Map<String, Object?>;
      expect(printed.keys.toList(), ['out', 'lines', 'tokens', 'warnings']);
      expect(printed['out'], file.resolveSymbolicLinksSync());
      expect(
        printed['warnings'],
        (jsonDecode(plain.out.toString()) as Map)['warnings'],
      );
      expect(err.toString(), isEmpty);
    });

    test(
      'a fault writes no file and keeps the bytes of the file already there',
      () async {
        final project = await writeReadProject();
        final file =
            File('${project.path}/.specstone/reports/structure.logn.json')
              ..createSync(recursive: true)
              ..writeAsStringSync('kept');
        final (:runner, :out, :err) = readRunner(project);
        expect(await runner.run(['structure', 'logn', '--json', '--out']), 64);
        expect(errorOf(err)['code'], 'doc_not_found');
        expect(out.toString(), isEmpty);
        expect(file.readAsStringSync(), 'kept');

        final text = readRunner(project);
        expect(await text.runner.run(['structure', 'logn', '--out']), 64);
        expect(text.out.toString(), isEmpty);
        expect(
          File('${project.path}/.specstone/reports/structure.logn.txt')
              .existsSync(),
          isFalse,
        );
      },
    );

    test('an empty path is argument_invalid; a path in the docs root or under .specstone/ is output_not_writable', () async {
      final project = await writeReadProject();
      for (final (path, status, code) in [
        ('', 64, 'argument_invalid'),
        ('docs/tree.txt', 73, 'output_not_writable'),
        ('.specstone/index.txt', 73, 'output_not_writable'),
      ]) {
        final (:runner, :out, :err) = readRunner(project);
        expect(
          await runner.run(['structure', '--json', '--out', path]),
          status,
          reason: path,
        );
        expect(errorOf(err)['code'], code, reason: path);
        expect(out.toString(), isEmpty);
      }
      expect(File('${project.path}/docs/tree.txt').existsSync(), isFalse);
      expect(
        File('${project.path}/.specstone/index.txt').existsSync(),
        isFalse,
      );
    });
  });
}
