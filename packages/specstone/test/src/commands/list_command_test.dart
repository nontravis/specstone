// The expected values are plan literals kept as written.
// ignore_for_file: lines_longer_than_80_chars, avoid_escaping_inner_quotes

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../../../specstone_core/test/helpers/check_fixture.dart';
import '../../../../specstone_core/test/helpers/shipped_pins.dart';
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
  test('f01/us03/s1, f01/us03/fr01: list feature prints the feature line and exits 0', () async {
    final (:runner, :out, :err) = readRunner(await writeReadProject());
    expect(await runner.run(['list', 'feature']), 0);
    expect(out.toString(), startsWith('login (feature) — Login · planned · '));
    expect(err.toString(), isEmpty);
  });
  test('f01/us03/fr01: --json prints docs and warnings', () async {
    final (:runner, :out, :err) = readRunner(await writeReadProject());
    expect(await runner.run(['list', 'feature', '--json']), 0);
    expect((jsonDecode(out.toString()) as Map).keys.toList(), [
      'docs',
      'warnings',
    ]);
  });
  test('f01/us03/fr01/e04: no doc type is argument_missing, exit 64', () async {
    final (:runner, :out, :err) = readRunner(await writeReadProject());
    expect(await runner.run(['list']), 64);
    expect(
      err.toString(),
      'list needs a doc type, such as specstone list feature\n',
    );
    expect(out.toString(), isEmpty);
  });
  test('f04/us04/s8, f04/us04/fr04/e01, f04/us04/fr04/e02: list fr --suspect keeps the suspect FR only', () async {
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

  test('f04/us04/fr04: list journey --suspect keeps a journey with a suspect step', () async {
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

  test('f04/us04/fr04/e03, f04/us04/fr04/e05: list api --suspect keeps an API doc with a suspect row; a type with no '
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

  test('f04/us04/fr04/e04, f04/us04/fr02/e06: an unconfirmed link, a draft\'s included, does not count', () async {
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

  test('f04/us04/fr04/e06: --json gives F-01\'s docs object', () async {
    final (:runner, :out, :err) = readRunner(await suspectProject());
    expect(await runner.run(['list', 'fr', '--suspect', '--json']), 0);
    final docs = (jsonDecode(out.toString()) as Map)['docs']! as List;
    expect(
      docs.single,
      containsPair('name', 'login/email_login/check_password'),
    );
  });

  test(
    'f04/us04/fr04/e07: list\'s faults come before any link state',
    () async {
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
    },
  );
  test('f01/us03/s10, f01/us03/fr01/e06: outside a project, or under a 9.9.9 pin, exits 78', () async {
    final outside = readRunner(await writeTree({}));
    expect(await outside.runner.run(['list', 'feature']), 78);
    final pinned = readRunner(
      await writeReadProject(
        extra: {'.specstone/config.yaml': 'packs:\n  prd-core: 9.9.9\n'},
      ),
    );
    expect(await pinned.runner.run(['list', 'feature']), 78);
  });

  test('f10/us04/fr01: list user_story --unwalked --json adds unwalked to each doc, exit 0', () async {
    final (:runner, :out, :err) = readRunner(await writeCheckProject());
    expect(await runner.run(['list', 'user_story', '--unwalked', '--json']), 0);
    final docs = (jsonDecode(out.toString()) as Map)['docs']! as List;
    expect(docs.single, containsPair('unwalked', ['S1', 'S2']));
  });

  test('f10/us04/s4, f10/us04/fr01/e05: list feature --unwalked exits 64 with the refusal', () async {
    final (:runner, :out, :err) = readRunner(await writeCheckProject());
    expect(await runner.run(['list', 'feature', '--unwalked']), 64);
    expect(
      err.toString(),
      contains('--unwalked lists user_story docs only, not feature'),
    );
    expect(out.toString(), isEmpty);
  });

  test('f10/us04/fr01: list user_story --suspect --unwalked exits 0', () async {
    final (:runner, :out, :err) = readRunner(await suspectProject());
    expect(
      await runner.run(['list', 'user_story', '--suspect', '--unwalked']),
      0,
    );
    expect(err.toString(), isEmpty);
  });

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

    test('f01/us03/fr02/e09: list fr --no-implements --target jaspr keeps the FR with no code in jaspr', () async {
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

    test('f01/us03/fr02/e10: --status or --no-implements with two targets and no --target is argument_missing, exit 64', () async {
      for (final args in [
        ['list', 'user_story', '--status', 'planned'],
        ['list', 'fr', '--no-implements'],
      ]) {
        final (:runner, :out, :err) = readRunner(await twoTargets());
        expect(await runner.run(args), 64);
        expect(
          err.toString(),
          '--status and --no-implements need --target with two or more code '
          'targets; the targets are flutter, jaspr\n',
        );
        expect(out.toString(), isEmpty);
      }
    });

    test('f01/us03/fr02/e11: list user_story --status skipped --target jaspr keeps the skipped story', () async {
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
    });

    test(
      'f01/us03/fr02/e12: one target judges its status with no --target',
      () async {
        final (:runner, :out, :err) = readRunner(await writeReadProject());
        expect(
          await runner.run(['list', 'user_story', '--status', 'planned']),
          0,
        );
        expect(
          out
              .toString()
              .split('\n')
              .where((l) => l.isNotEmpty)
              .map((l) => l.split(' (').first),
          ['login/email_login'],
        );
      },
    );
  });
}
