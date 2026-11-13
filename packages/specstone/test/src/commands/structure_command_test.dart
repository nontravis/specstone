// The expected values are plan literals kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/templates/shipped_pack_files.dart'
    show shippedPackVersions;
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import '../../../../specstone_core/test/helpers/shipped_pins.dart';

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

// A requirement whose sections count 179, 243 chars and whose items 165, 106, 121.
String frWithSizes() =>
    '---\nstatus: implemented\ntraced_from:\n  - S1\n  - S2\n'
    'implements:\n  - app/lib/src/login/credential_validator.dart:CredentialValidator\n---\n\n'
    '# Validate credentials\n\n## Statement\n'
    '${'The system shall check the email and the password.'.padRight(165, '.')}\n\n'
    '## Edge cases\n${'1. E01 — A wrong password → refused'.padRight(106, '.')}\n'
    '${'2. E02 — An unknown email → refused'.padRight(121, '.')}\n';

// The same requirement with a lead of 681 chars after its title.
String frWithLead() => frWithSizes().replaceFirst(
  '# Validate credentials\n\n',
  '# Validate credentials\n\n'
      '${'The lead says what the check covers.'.padRight(681, '.')}\n\n',
);

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
  test('f01/us02/s1, f01/us02/fr01: structure prints the tree on stdout and exits 0', () async {
    final (:runner, :out, :err) = readRunner(await writeReadProject());
    expect(await runner.run(['structure']), 0);
    expect(out.toString(), contains('login (feature) — Login · planned · '));
    expect(err.toString(), isEmpty);
  });
  test('index_query/view_docs_tree s8, fr01/e15: structure names each target status, a skipped story skipped', () async {
    final (:runner, :out, :err) = readRunner(await writeTargetedTree());
    expect(await runner.run(['structure', 'feedback/toast']), 0);
    expect(out.toString().split('\n').take(3), [
      startsWith(
        'feedback/toast (feature) — Toast · '
        'flutter: implemented, jaspr: planned · ',
      ),
      isA<String>().having(
        (l) => l.trim().split(' · ').take(2).join(' · '),
        'statuses',
        'feedback/toast/show (user_story) — Agent sees a toast · '
            'flutter: implemented, jaspr: planned',
      ),
      isA<String>().having(
        (l) => l.trim().split(' · ').take(2).join(' · '),
        'statuses',
        'feedback/toast/swipe (user_story) — Agent swipes a toast away · '
            'flutter: implemented, jaspr: skipped',
      ),
    ]);
    expect(err.toString(), isEmpty);
  });
  test('index_query/view_docs_tree fr01/e16: structure --target jaspr prints jaspr alone, no flutter spec doc', () async {
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
  });
  test('read_doc_section/resolve_doc_name E22: an unknown --target with no '
      'positional target exits 64', () async {
    final (:runner, :out, :err) = readRunner(await writeTargetedTree());
    expect(await runner.run(['structure', '--target', 'web']), 64);
    expect(
      err.toString(),
      '--target web: the code targets are flutter, jaspr\n',
    );
    expect(out.toString(), isEmpty);
  });
  test('f01/us02/fr01/e17: one named target reads its records with no --target '
      'through list', () async {
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
            '  flutter:\n    code_root: flutter_lib\n',
        'flutter_lib/.keep': '',
        'docs/prds/features/f01_login/FEATURE.md': '# Login\n\n## Problem\n.\n',
        'docs/prds/features/f01_login/us01_show/USER_STORY.md':
            '---\nstatus: planned\n---\n\n# Agent sees it\n\n## Use Case\n.\n',
        'docs/specs/f01_login/IMPLEMENTATION.md':
            '---\nstatuses:\n  - show:implemented\n---\n\n# Record\n',
      }),
    );
    expect(
      await runner.run(['list', 'user_story', '--status', 'implemented']),
      0,
    );
    expect(out.toString(), startsWith('login/show (user_story)'));
    expect(err.toString(), isEmpty);
  });
  test('f01/us02/fr01/e06: --json prints one object; a warning goes only to its warnings array', () async {
    final (:runner, :out, :err) = readRunner(
      await writeReadProject(extra: legacyFr),
    );
    expect(await runner.run(['structure', '--json']), 0);
    final json = jsonDecode(out.toString()) as Map<String, Object?>;
    expect(json.keys.toList(), ['docs', 'untyped', 'warnings']);
    expect(json['warnings'], [frWarning]);
    expect(err.toString(), isEmpty);
  });
  test('f01/us02/fr01: in text mode the warning prints on stderr with the warning prefix', () async {
    final (:runner, :out, :err) = readRunner(
      await writeReadProject(extra: legacyFr),
    );
    expect(await runner.run(['structure']), 0);
    expect(err.toString(), '⚠️ WARNING: $frWarning\n');
  });
  test('index_query/view_docs_tree S7: a requirement prints each section and item with its characters', () async {
    final (:runner, :out, :err) = readRunner(
      await writeReadProject(extra: {frKey: frWithSizes()}),
    );
    expect(await runner.run(['structure', frTarget]), 0);
    expect(
      out.toString().split('\n').skip(1).join('\n'),
      '  statement · 179 chars\n'
      '    line 14 · 165 chars\n'
      '  edge_cases · 243 chars\n'
      '    E01 · 106 chars\n'
      '    E02 · 121 chars\n',
    );
    expect(err.toString(), isEmpty);
  });
  test(
    'index_query/view_docs_tree S7: --json gives the doc object its sections',
    () async {
      final (:runner, :out, :err) = readRunner(
        await writeReadProject(extra: {frKey: frWithSizes()}),
      );
      expect(await runner.run(['structure', frTarget, '--json']), 0);
      final doc =
          ((jsonDecode(out.toString()) as Map)['docs']! as List).single
              as Map<String, Object?>;
      expect(doc['sections'], [
        {
          'key': 'statement',
          'chars': 179,
          'items': [
            {'line': 14, 'chars': 165},
          ],
        },
        {
          'key': 'edge_cases',
          'chars': 243,
          'items': [
            {'id': 'E01', 'line': 18, 'chars': 106},
            {'id': 'E02', 'line': 19, 'chars': 121},
          ],
        },
      ]);
      expect(err.toString(), isEmpty);
    },
  );
  test('index_query/view_docs_tree S7: a requirement with a lead prints it first, as text', () async {
    final (:runner, :out, :err) = readRunner(
      await writeReadProject(extra: {frKey: frWithLead()}),
    );
    expect(await runner.run(['structure', frTarget]), 0);
    expect(
      out.toString().split('\n').skip(1).join('\n'),
      '  _lead · 681 chars\n'
      '    line 12 · 681 chars\n'
      '  statement · 179 chars\n'
      '    line 16 · 165 chars\n'
      '  edge_cases · 243 chars\n'
      '    E01 · 106 chars\n'
      '    E02 · 121 chars\n',
    );
    expect(err.toString(), isEmpty);
  });
  test('index_query/view_docs_tree S7: a requirement with a lead gives --json a _lead section first', () async {
    final (:runner, :out, :err) = readRunner(
      await writeReadProject(extra: {frKey: frWithLead()}),
    );
    expect(await runner.run(['structure', frTarget, '--json']), 0);
    final doc =
        ((jsonDecode(out.toString()) as Map)['docs']! as List).single
            as Map<String, Object?>;
    expect((doc['sections']! as List).first, {
      'key': '_lead',
      'chars': 681,
      'items': [
        {'line': 12, 'chars': 681},
      ],
    });
    expect(err.toString(), isEmpty);
  });
  test('f01/us02/s5, f01/us02/fr01/e03: a target no doc carries exits 64 and names it', () async {
    final (:runner, :out, :err) = readRunner(await writeReadProject());
    expect(await runner.run(['structure', 'logn']), 64);
    expect(err.toString(), 'no doc carries the name logn\n');
    expect(out.toString(), isEmpty);
  });
  test('f01/us02/s6, f01/us02/fr01/e07, f01/us01/s11, f01/us01/fr01/e01: outside a project exits 78', () async {
    final (:runner, :out, :err) = readRunner(await writeTree({}));
    expect(await runner.run(['structure']), 78);
    expect(
      err.toString(),
      'no Specstone project: no folder from the working directory upward holds .specstone/config.yaml\n',
    );
  });
  test("f01/us02/fr01/e07, f01/us01/fr01/e02: a template fault exits 78 with F-03's code", () async {
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
    'f01/us02/fr01: a surplus positional prints usage and exits 64',
    () async {
      final (:runner, :out, :err) = readRunner(await writeReadProject());
      expect(await runner.run(['structure', 'a', 'b']), 64);
      expect(err.toString(), contains('Usage: specstone structure'));
    },
  );
  test(
    'f01/us01/s12, f01/us01/fr02/e07, s05: a read-only .specstone/ exits 73 with the JSON envelope',
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
  test('f01/us01/s13, f01/us01/fr05/e05, s05: a write lock held past the timeout exits 75 with the JSON envelope', () async {
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
  });
}
