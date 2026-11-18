// The expected values are plan literals kept as written.
// ignore_for_file: lines_longer_than_80_chars, avoid_escaping_inner_quotes

import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import '../../../../specstone_core/test/helpers/check_fixture.dart';
import '../../../../specstone_core/test/helpers/override_link_fixture.dart';
import '../../../../specstone_core/test/helpers/shipped_pins.dart';
import '../../helpers/built_cli.dart';
import '../../helpers/read_fixture.dart';
import '../../helpers/temp_tree.dart';

final String edited = loginScenario2.replaceFirst(
  'wrong password',
  'wrong pass',
);

Map<String, String> _extraFr(String name, String confirmed) => {
  'docs/prds/features/f01_login/us01_email_login/$name.md':
      '---\nstatus: planned\ntraced_from:\n  - S1\nverify_method: test\n$confirmed---\n\n'
      '# Remember the device\n\n## Statement\nThe system shall remember a device.\n\n'
      '## Edge cases\n1. E01 — A new device → asked again.\n\n## Rationale\nFewer sign-ins.\n\n'
      '## Verification\nTest: a remembered device.\n',
};

Future<Directory> suspectProject() => writeCheckProject(
  extra: {
    ...doc(loginStory, loginScenario2, edited),
    ..._extraFr('fr02_remember_device', ''),
    ..._extraFr(
      'fr03_keep_session',
      'confirmed:\n  - S1 ${fingerprintFor(loginScenario1)}\n',
    ),
  },
);

void main() {
  test('list feature prints the feature line and exits 0', () async {
    final (:runner, :out, :err) = readRunner(await writeReadProject());
    expect(await runner.run(['list', 'feature']), 0);
    expect(out.toString(), startsWith('login (feature) — Login · planned · '));
    expect(err.toString(), isEmpty);
  });
  test('--json prints docs and warnings', () async {
    final (:runner, :out, :err) = readRunner(await writeReadProject());
    expect(await runner.run(['list', 'feature', '--json']), 0);
    expect((jsonDecode(out.toString()) as Map).keys.toList(), [
      'docs',
      'warnings',
    ]);
  });
  group('through the built CLI', () {
    late String binary;
    setUpAll(() async => binary = await buildSpecstone());

    Future<ProcessResult> listFeature(List<String> extraArgs) async {
      final root = await writeReadProject(
        extra: {
          'docs/prds/features/f01_login/FEATURE.md':
              '---\nsummary: Grounds a task in one call.\n---\n\n# Login\n',
        },
      );
      return Process.run(binary, [
        'list',
        'feature',
        ...extraArgs,
      ], workingDirectory: root.path);
    }

    test('list ends a feature line with its summary', () async {
      final result = await listFeature([]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(
        (result.stdout as String).trimRight(),
        allOf(
          startsWith('login (feature) — Login · '),
          endsWith(' — Grounds a task in one call.'),
        ),
      );
    });

    test('--json gives the summary key', () async {
      final result = await listFeature(['--json']);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      final docs =
          (jsonDecode(result.stdout as String) as Map)['docs']! as List;
      expect(
        docs.single,
        containsPair('summary', 'Grounds a task in one call.'),
      );
    });
  });
  test('no doc type is argument_missing, exit 64', () async {
    final (:runner, :out, :err) = readRunner(await writeReadProject());
    expect(await runner.run(['list']), 64);
    expect(
      err.toString(),
      'list needs a doc type, such as specstone list feature\n',
    );
    expect(out.toString(), isEmpty);
  });
  test('list fr --suspect keeps the suspect FR only', () async {
    for (final args in [
      ['list', 'fr', '--suspect'],
      ['list', 'fr', '--suspect', '--under', 'login/email_login'],
    ]) {
      final (:runner, :out, :err) = readRunner(await suspectProject());
      expect(await runner.run(args), 0);
      expect(
        out.toString(),
        startsWith(
          'login/email_login/check_password (fr) — Check the password',
        ),
      );
      expect(
        out.toString().split('\n').where((l) => l.isNotEmpty),
        hasLength(1),
      );
    }
  });

  test('list journey --suspect keeps a journey with a suspect step', () async {
    final (:runner, :out, :err) = readRunner(
      await writeCheckProject(
        extra: {
          ...doc(
            loginStory,
            loginScenario1,
            loginScenario1.replaceFirst('home page', 'dashboard'),
          ),
          'docs/prds/journeys/sign_in/JOURNEY.md':
              '---\nconfirmed:\n  - login/email_login#S1 ${fingerprintFor(loginScenario1)}\n---\n\n'
              '# Sign in\n\n## Goal\nGet in.\n\n## Flow\n\n## Steps\n### 1. Open\nstep: login/email_login S1\n',
        },
      ),
    );
    expect(await runner.run(['list', 'journey', '--suspect']), 0);
    expect(out.toString(), startsWith('sign_in (journey)'));
    expect(out.toString().split('\n').where((l) => l.isNotEmpty), hasLength(1));
  });

  test(
    'list --suspect lists a doc whose only suspect link is an override',
    () async {
      final files = overrideFiles(
        root: rootRule.replaceFirst('7 days', '14 days'),
        extra: {
          'docs/$loginDomain': domainDoc(
            [overrideOfRoot],
            entries: ['$rootAddress $rootFingerprint'],
          ),
        },
      );
      final (:runner, :out, :err) = readRunner(
        await writeCheckProject(extra: files, unstamped: files.keys.toSet()),
      );
      expect(await runner.run(['list', 'domain', '--suspect']), 0);
      expect(out.toString(), startsWith('login (domain)'));
      expect(
        out.toString().split('\n').where((l) => l.isNotEmpty),
        hasLength(1),
      );
      expect(err.toString(), isEmpty);
    },
  );

  test('list api --suspect keeps an API doc with a suspect row; a type with no '
      'tracked link lists nothing', () async {
    final api = readRunner(
      await writeCheckProject(
        extra: fr(
          checkPasswordStatement,
          'The system shall refuse a wrong password within 2 s.',
        ),
      ),
    );
    expect(await api.runner.run(['list', 'api', '--suspect']), 0);
    expect(api.out.toString(), startsWith('login (api)'));
    final feature = readRunner(await suspectProject());
    expect(await feature.runner.run(['list', 'feature', '--suspect']), 0);
    expect(feature.out.toString(), isEmpty);
  });

  test('an unconfirmed link, a draft\'s included, does not count', () async {
    final (:runner, :out, :err) = readRunner(
      await writeCheckProject(
        extra: edit(loginFr, [
          ('traced_from:\n', 'draft: true\ntraced_from:\n'),
          ('  - S2 ${fingerprintFor(loginScenario2)}', '  - S2 000000000000'),
        ]),
      ),
    );
    expect(await runner.run(['list', 'fr', '--suspect']), 0);
    expect(out.toString(), isEmpty);
  });

  test('--json gives the docs object', () async {
    final (:runner, :out, :err) = readRunner(await suspectProject());
    expect(await runner.run(['list', 'fr', '--suspect', '--json']), 0);
    final docs = (jsonDecode(out.toString()) as Map)['docs']! as List;
    expect(
      docs.single,
      containsPair('name', 'login/email_login/check_password'),
    );
  });

  test('list\'s faults come before any link state', () async {
    final unknown = readRunner(await suspectProject());
    expect(await unknown.runner.run(['list', 'nope', '--suspect']), 64);
    final under = readRunner(await suspectProject());
    expect(
      await under.runner.run([
        'list',
        'fr',
        '--suspect',
        '--under',
        'login/emial_login',
      ]),
      64,
    );
    final outside = readRunner(await writeTree({}));
    expect(await outside.runner.run(['list', 'fr', '--suspect']), 78);
  });
  test('outside a project, or under a 9.9.9 pin, exits 78', () async {
    final outside = readRunner(await writeTree({}));
    expect(await outside.runner.run(['list', 'feature']), 78);
    final pinned = readRunner(
      await writeReadProject(
        extra: {'.specstone/config.yaml': 'packs:\n  prd-core: 9.9.9\n'},
      ),
    );
    expect(await pinned.runner.run(['list', 'feature']), 78);
  });

  test(
    'list user_story --unwalked --json adds unwalked to each doc, exit 0',
    () async {
      final (:runner, :out, :err) = readRunner(await writeCheckProject());
      expect(
        await runner.run(['list', 'user_story', '--unwalked', '--json']),
        0,
      );
      final docs = (jsonDecode(out.toString()) as Map)['docs']! as List;
      expect(docs.single, containsPair('unwalked', ['S1', 'S2']));
    },
  );

  test('list user_story --suspect --unwalked exits 0', () async {
    final (:runner, :out, :err) = readRunner(await suspectProject());
    expect(
      await runner.run(['list', 'user_story', '--suspect', '--unwalked']),
      0,
    );
    expect(err.toString(), isEmpty);
  });

  Map<String, Object?> errorOf(StringBuffer err) =>
      (jsonDecode(err.toString()) as Map<String, Object?>)['error']!
          as Map<String, Object?>;

  test(
    'list with no doc type under --json gives the code argument_missing',
    () async {
      final (:runner, :out, :err) = readRunner(await writeReadProject());
      expect(await runner.run(['list', '--json']), 64);
      expect(errorOf(err)['code'], 'argument_missing');
      expect(out.toString(), isEmpty);
    },
  );

  test(
    'list outside a project gives project_not_found, a bad pin its code',
    () async {
      final outside = readRunner(await writeTree({}));
      expect(await outside.runner.run(['list', 'feature', '--json']), 78);
      expect(errorOf(outside.err)['code'], 'project_not_found');
      final pinned = readRunner(
        await writeReadProject(
          extra: {'.specstone/config.yaml': 'packs:\n  prd-core: 9.9.9\n'},
        ),
      );
      expect(await pinned.runner.run(['list', 'feature', '--json']), 78);
      expect(errorOf(pinned.err)['code'], 'pack_pin_newer');
    },
  );

  test('list feature --unwalked is argument_invalid, exit 64', () async {
    final (:runner, :out, :err) = readRunner(await writeCheckProject());
    expect(await runner.run(['list', 'feature', '--unwalked', '--json']), 64);
    expect(errorOf(err)['code'], 'argument_invalid');
    expect(out.toString(), isEmpty);
  });

  test(
    'list fr --suspect --under another story leaves a suspect FR out',
    () async {
      const reset =
          'docs/prds/features/f01_login/us02_reset_password/USER_STORY.md';
      final project = await writeCheckProject(
        extra: {
          ...doc(loginStory, loginScenario2, edited),
          reset: '# Agent resets a password\n\n## Use Case\nReset it.\n',
        },
      );
      final everywhere = readRunner(project);
      expect(await everywhere.runner.run(['list', 'fr', '--suspect']), 0);
      expect(
        everywhere.out.toString(),
        startsWith('login/email_login/check_password (fr)'),
      );
      final scoped = readRunner(project);
      expect(
        await scoped.runner.run([
          'list',
          'fr',
          '--suspect',
          '--under',
          'login/reset_password',
        ]),
        0,
      );
      expect(scoped.out.toString(), isEmpty);
    },
  );

  test('list --suspect on a bad pin gives the list fault, exit 78', () async {
    final project = await suspectProject();
    File('${project.path}/.specstone/config.yaml')
        .writeAsStringSync('packs:\n  prd-core: 9.9.9\n');
    final (:runner, :out, :err) = readRunner(project);
    expect(await runner.run(['list', 'fr', '--suspect', '--json']), 78);
    expect(errorOf(err)['code'], 'pack_pin_newer');
    expect(out.toString(), isEmpty);
  });

  test('list --suspect on a busy index gives index_busy, exit 75', () async {
    final project = await suspectProject();
    expect(await readRunner(project).runner.run(['list', 'fr']), 0);
    final holder = sqlite3.open('${project.path}/.specstone/index.sqlite')
      ..execute('BEGIN IMMEDIATE');
    addTearDown(
      () => holder
        ..execute('ROLLBACK')
        ..close(),
    );
    File('${project.path}/docs/$loginFeature')
        .writeAsStringSync('# Login v2\n');
    final (:runner, :out, :err) = readRunner(
      project,
      busyTimeout: const Duration(milliseconds: 200),
    );
    expect(await runner.run(['list', 'fr', '--suspect', '--json']), 75);
    expect(errorOf(err)['code'], 'index_busy');
    expect(out.toString(), isEmpty);
  });

  test(
    'a code_unconfirmed link counts toward no doc under --suspect',
    () async {
      final project = await writeCheckProject(unfingerprinted: {loginRecord});
      final check = readRunner(project);
      await check.runner.run(['check', '--json']);
      expect(check.out.toString(), contains('"kind": "code_unconfirmed"'));
      for (final type in ['fr', 'user_story', 'implementation']) {
        final (:runner, :out, :err) = readRunner(project);
        expect(await runner.run(['list', type, '--suspect']), 0, reason: type);
        expect(out.toString(), isEmpty, reason: type);
      }
    },
  );

  group('per code target', () {
    /// Writes a two-target project: the feature `login` with two stories and
    /// their FRs, and each target's record; `flutter` names code for both
    /// FRs, `jaspr` for `show/open` alone.
    Future<Directory> twoTargets() => writeTree({
      '.specstone/templates/implementation.yaml':
          'id: implementation\n'
          'description: One feature record per target.\n'
          'path: specs/f{nn}_{slug}/IMPLEMENTATION.md\n'
          'parent: feature\n'
          'per_target: true\n'
          'fields:\n'
          '  - id: statuses\n'
          '    type: record_status\n'
          '    list: true\n'
          '  - id: implements\n'
          '    type: output_ref\n'
          '    list: true\n'
          '    pointer: item_exact\n',
      '.specstone/config.yaml':
          '${shippedPinsConfig()}targets:\n'
          '  flutter:\n    code_root: flutter_lib\n'
          '  jaspr:\n    code_root: jaspr_lib\n',
      'flutter_lib/.keep': '',
      'jaspr_lib/.keep': '',
      'docs/prds/features/f01_login/FEATURE.md': '# Login\n\n## Problem\n.\n',
      'docs/prds/features/f01_login/us01_show/USER_STORY.md': '---\nstatus: implemented\n---\n\n# Agent sees it\n\n## Use Case\n.\n',
      'docs/prds/features/f01_login/us01_show/fr01_open.md':
          '---\nstatus: implemented\n---\n\n# Open it\n',
      'docs/prds/features/f01_login/us02_hide/USER_STORY.md': '---\nstatus: implemented\n---\n\n# Agent hides it\n\n## Use Case\n.\n',
      'docs/prds/features/f01_login/us02_hide/fr01_close.md':
          '---\nstatus: implemented\n---\n\n# Close it\n',
      'docs/specs/flutter/f01_login/IMPLEMENTATION.md':
          '---\nimplements:\n'
          '  - show/open:flutter/lib/open.dart\n'
          '  - show:flutter/lib/show.dart\n'
          '  - hide/close:flutter/lib/close.dart\n'
          '  - hide:flutter/lib/hide.dart\n---\n\n# Record\n',
      'docs/specs/jaspr/f01_login/IMPLEMENTATION.md':
          '---\nimplements:\n  - show/open:jaspr/lib/open.dart\n---\n\n'
          '# Record\n',
    });

    test('list fr --no-implements --target jaspr keeps the FR with no code in jaspr', () async {
      final (:runner, :out, :err) = readRunner(await twoTargets());
      expect(
        await runner.run([
          'list',
          'fr',
          '--no-implements',
          '--target',
          'jaspr',
        ]),
        0,
      );
      expect(
        out.toString().split('\n').where((l) => l.isNotEmpty),
        hasLength(1),
      );
      expect(out.toString(), startsWith('login/hide/close (fr) — Close it'));
      expect(out.toString(), contains(' · planned · '));
    });

    test(
      'list user_story --status skipped --target jaspr keeps the skipped story',
      () async {
        final (:runner, :out, :err) = readRunner(
          await writeTree({
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
                '${shippedPinsConfig()}targets:\n'
                '  flutter:\n    code_root: flutter_lib\n'
                '  jaspr:\n    code_root: jaspr_lib\n',
            'flutter_lib/.keep': '',
            'jaspr_lib/.keep': '',
            'docs/prds/features/f01_login/FEATURE.md':
                '# Login\n\n## Problem\n.\n',
            'docs/prds/features/f01_login/us01_show/USER_STORY.md': '---\nstatus: implemented\n---\n\n# Agent sees it\n\n## Use Case\n.\n',
            'docs/prds/features/f01_login/us02_hide/USER_STORY.md': '---\nstatus: implemented\n---\n\n# Agent hides it\n\n## Use Case\n.\n',
            'docs/specs/flutter/f01_login/IMPLEMENTATION.md': '---\nstatuses:\n  - show:implemented\n  - hide:implemented\n---\n\n# Record\n',
            'docs/specs/jaspr/f01_login/IMPLEMENTATION.md': '---\nstatuses:\n  - hide:skipped:no hide on the web\n---\n\n# Record\n',
          }),
        );
        expect(
          await runner.run([
            'list',
            'user_story',
            '--status',
            'skipped',
            '--target',
            'jaspr',
          ]),
          0,
        );
        expect(out.toString().split('\n').where((l) => l.isNotEmpty), [
          startsWith('login/hide (user_story) — Agent hides it · skipped · '),
        ]);
      },
    );
  });
}
