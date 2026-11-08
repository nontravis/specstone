// The expected values are plan literals kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/setup_migration/agent_files.dart';
import 'package:specstone_core/src/version.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import '../../../../specstone_core/test/helpers/check_fixture.dart';
import '../../../../specstone_core/test/helpers/nested_fixture.dart';
import '../../../../specstone_core/test/helpers/write_fixture.dart' show getDoc;
import '../../helpers/built_cli.dart';
import '../../helpers/read_fixture.dart';
import '../../helpers/temp_tree.dart';
import '../../helpers/write_runner.dart';

Map<String, String> frWith(String line) => fr('verify_method: test', line);

void main() {
  late String binary;

  setUpAll(() async {
    binary = await buildSpecstone();
  });

  test('f04/us01/s1, f04/us01/fr02/e01: a clean project prints 0 findings and exits 0', () async {
    final (:runner, :out, :err) = readRunner(await writeCheckProject());
    expect(await runner.run(['check']), 0);
    expect(out.toString(), '0 findings\n');
    expect(err.toString(), isEmpty);
  });

  test('f04/us01/fr02: each finding prints on its own line before the count, and the check exits 1', () async {
    final (:runner, :out, :err) = readRunner(
      await writeCheckProject(extra: frWith('verify_method: maybe')),
    );
    expect(await runner.run(['check']), 1);
    expect(
      out.toString(),
      '$loginFr:6: field_value_mismatch: verify_method is maybe; it takes test, analysis, inspection, or '
      'demonstration\n1 finding\n',
    );
  });

  test('f04/us01/fr01/e15: check architecture:login prints the finding of ARCHITECTURE.md only, not API.md beside it', () async {
    final (:runner, :out, :err) = readRunner(
      await writeCheckProject(
        extra: {
          ...doc(
            loginApi,
            'Signs the Agent in.',
            'Signs the Agent in. See [x](../../../nowhere.md).',
          ),
          ...doc(
            loginArchitecture,
            'One box.',
            'One box. See [y](../../../nowhere.md).',
          ),
        },
      ),
    );
    expect(await runner.run(['check', 'architecture:login']), 1);
    expect(
      out.toString(),
      allOf(contains(loginArchitecture), isNot(contains(loginApi))),
    );
    expect(out.toString(), endsWith('1 finding\n'));
  });

  test('f04/us01/fr10/e01: check --json on a feature that holds a story and sub-features lists feature_mixed_children and exits 1', () async {
    final (:runner, :out, :err) = readRunner(
      await writeNestedProject(
        extra: {
          'docs/prds/features/f02_shop/us01_extra/USER_STORY.md':
              nestedFiles()['docs/$cartDrop']!,
        },
      ),
    );
    expect(await runner.run(['check', '--json']), 1);
    final json = jsonDecode(out.toString()) as Map<String, Object?>;
    expect(
      [
        for (final finding in json['findings']! as List)
          if ((finding as Map)['kind'] == 'feature_mixed_children') finding,
      ],
      [
        {
          'kind': 'feature_mixed_children',
          'docPath': shopFeature,
          'name': 'shop',
          'line': 1,
          'message': 'holds both feature and user_story children',
          'docTypes': ['feature', 'user_story'],
        },
      ],
    );
  });

  test("f04/us01/s8, f04/us01/fr02: --json gives each finding's kind, file, name, line, and message, and the count", () async {
    final (:runner, :out, :err) = readRunner(
      await writeCheckProject(extra: frWith('verify_method: maybe')),
    );
    expect(await runner.run(['check', '--json']), 1);
    final json = jsonDecode(out.toString()) as Map<String, Object?>;
    expect(json.keys, ['findings', 'count']);
    expect(json['count'], 1);
    expect((json['findings']! as List).single, {
      'kind': 'field_value_mismatch',
      'docPath': loginFr,
      'name': 'login/email_login/check_password',
      'line': 6,
      'message': 'verify_method is maybe; it takes test, analysis, inspection, or demonstration',
      'field': 'verify_method',
      'value': 'maybe',
    });
  });

  test('f04/us01/s9, f04/us01/fr01/e05, f04/us01/fr02/e07: a name no doc carries refuses, exit 64, no finding', () async {
    final (:runner, :out, :err) = readRunner(await writeCheckProject());
    expect(await runner.run(['check', 'login/emial_login']), 64);
    expect(err.toString(), 'no doc carries the name login/emial_login\n');
    expect(out.toString(), isEmpty);
  });

  test('f04/us01/fr01/e06, f04/us01/fr01/e07: an unknown doc type exits 64; outside a project exits 78', () async {
    final inside = readRunner(await writeCheckProject());
    expect(await inside.runner.run(['check', 'nope:login']), 64);
    final outside = readRunner(await writeTree({}));
    expect(await outside.runner.run(['check']), 78);
    expect(outside.err.toString(), startsWith('no Specstone project'));
    expect(outside.out.toString(), isEmpty);
  });

  test('f04/us01/fr02/e05: a warning no finding states goes to stderr, and to warnings under --json', () async {
    Future<Directory> damaged() async {
      final project = await writeCheckProject();
      File('${project.path}/.specstone/index.sqlite')
          .writeAsStringSync('not a database');
      return project;
    }

    final text = readRunner(await damaged());
    expect(await text.runner.run(['check']), 0);
    expect(text.err.toString(), startsWith('⚠️ WARNING: '));
    final json = readRunner(await damaged());
    expect(await json.runner.run(['check', '--json']), 0);
    expect((jsonDecode(json.out.toString()) as Map)['warnings'], hasLength(1));
  });

  test('f04/us01/fr01/e08, f04/us01/fr01/e19: a pin fault exits 78 before any rule; an unknown option or two targets '
      'exit 64', () async {
    final pinned = readRunner(
      await writeCheckProject(
        extra: {'.specstone/config.yaml': 'packs:\n  prd-core: 9.9.9\n'},
      ),
    );
    expect(await pinned.runner.run(['check']), 78);
    expect(pinned.out.toString(), isEmpty);
    for (final args in [
      ['check', '--fix'],
      ['check', 'a', 'b'],
    ]) {
      expect(await readRunner(await writeCheckProject()).runner.run(args), 64);
    }
  });

  test('f04/us01/fr01/e09: a write lock held past the busy timeout exits 75 with the JSON envelope', () async {
    final project = await writeCheckProject();
    expect(await readRunner(project).runner.run(['check']), 0);
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
    expect(await runner.run(['check', '--json']), 75);
    expect(
      (jsonDecode(err.toString()) as Map)['error'],
      containsPair('code', 'index_busy'),
    );
    expect(out.toString(), isEmpty);
  });
  test('user_story:consistency_check/find_template_breaks S13: check names a stale agent block and its fix, and --json holds no name', () async {
    final project = await writeCheckProject(
      extra: {
        'AGENTS.md':
            'top\n${inlineBlock(cliVersion: specstoneVersion).replaceFirst('Rules', 'Rule')}',
        '.specstone/AGENT.md': agentMdText,
      },
    );
    const message =
        'the Specstone block differs from what the running CLI writes; run `specstone migrate`';

    final text = await Process.run(binary, [
      'check',
    ], workingDirectory: project.path);
    final json = await Process.run(binary, [
      'check',
      '--json',
    ], workingDirectory: project.path);

    expect(text.exitCode, 1, reason: '${text.stdout}\n${text.stderr}');
    expect(
      text.stdout,
      'AGENTS.md:2: agent_block_stale: $message\n1 finding\n',
    );
    expect(json.exitCode, 1, reason: '${json.stdout}\n${json.stderr}');
    final findings =
        (jsonDecode(json.stdout as String) as Map)['findings']! as List;
    expect(findings, [
      {
        'kind': 'agent_block_stale',
        'docPath': 'AGENTS.md',
        'line': 2,
        'message': message,
      },
    ]);
  });

  test('consistency_check/find_template_breaks/report_format_drift S12: check names the drifted file and its fix, and format clears it', () async {
    final project = await writeCheckProject(
      extra: fr(
        'A wrong password must not sign in.\n',
        'A wrong password must not sign in.\n\n| Case       | Result  |\n|------------|---------|\n| wrong      | refused |\n',
      ),
    );
    final drifted = readRunner(project);
    expect(await drifted.runner.run(['check']), 1);
    expect(
      drifted.out.toString(),
      '$loginFr:1: format_drift: the file differs from what `specstone format` writes; run '
      '`specstone format docs/$loginFr`\n1 finding\n',
    );

    final formatted = readRunner(project);
    expect(await formatted.runner.run(['format', 'docs/$loginFr']), 0);

    final clean = readRunner(project);
    expect(await clean.runner.run(['check']), 0);
    expect(clean.out.toString(), '0 findings\n');
  });

  test('consistency_check/find_template_breaks: check names an approved story edited outside the commands; padded table cells draw format_drift only', () async {
    final project = await writeCheckProject(
      extra: {
        ...editedAfterApproval(loginStory, [('Sign in', 'Sign in again')]),
        ...editedAfterApproval(loginApi, [
          (
            '| FR | Operation |\n|---|---|\n',
            '| FR   | Operation |\n|------|-----------|\n',
          ),
        ]),
      },
    );
    final stale = readRunner(project);
    expect(await stale.runner.run(['check']), 1);
    expect(
      stale.out.toString(),
      "$loginStory:3: approval_stale: the doc changed since the Owner approved it; it waits for the Owner's specstone approve\n"
      '$loginApi:1: format_drift: the file differs from what `specstone format` writes; run '
      '`specstone format docs/$loginApi`\n'
      '2 findings\n',
    );
  });

  test('consistency_check/find_template_breaks: check names a doc made outside the commands in a project upgraded to 1.2.0', () async {
    final project = await writeCheckProject(
      extra: {'docs/$loginFr': checkProjectFiles()['docs/$loginFr']!},
      unstamped: {'docs/$loginFr'},
    );
    final text = readRunner(project);
    expect(await text.runner.run(['check']), 1);
    expect(
      text.out.toString(),
      "$loginFr:1: approval_stale: the doc carries no approval; it waits for the Owner's specstone approve\n"
      '1 finding\n',
    );

    final json = readRunner(project);
    expect(await json.runner.run(['check', '--json']), 1);
    final findings =
        (jsonDecode(json.out.toString()) as Map)['findings']! as List;
    expect(findings, [
      {
        'kind': 'approval_stale',
        'docPath': loginFr,
        'name': 'login/email_login/check_password',
        'line': 1,
        'message': "the doc carries no approval; it waits for the Owner's specstone approve",
      },
    ]);
  });

  test('consistency_check/find_broken_pointers S13, consistency_check/find_broken_pointers/resolve_doc_links: check '
      'prints the anchor, self, malformed, and doc_ref findings with their keys', () async {
    final project = await writeCheckProject(
      extra: edit(loginFeature, [
        ('  - PG-01\n---', '  - PG-01\ndepends_on:\n  - login\n  - login\n---'),
        (
          'Users forget passwords.',
          'Users forget passwords; [a](../../GNFR.md#speed), [b](FEATURE.md), and [c](http://h:abc/x.md).',
        ),
      ]),
    );
    final text = readRunner(project);
    expect(await text.runner.run(['check']), 1);
    expect(
      text.out.toString(),
      '$loginFeature:8: doc_ref_self: depends_on value login names the doc that holds it\n'
      '$loginFeature:9: doc_ref_duplicate: depends_on holds login a second time\n'
      '$loginFeature:9: doc_ref_self: depends_on value login names the doc that holds it\n'
      '$loginFeature:16: link_anchor_missing: link target ../../GNFR.md#speed names anchor speed, which '
      '$gnfrDoc does not hold\n'
      '$loginFeature:16: link_self: link target FEATURE.md names the doc that holds it\n'
      '$loginFeature:16: reference_malformed: link target http://h:abc/x.md cannot be read: the WHATWG URL '
      'parser fails on it\n'
      '6 findings\n',
    );

    final json = readRunner(project);
    expect(await json.runner.run(['check', '--json']), 1);
    final findings =
        ((jsonDecode(json.out.toString()) as Map)['findings']! as List)
            .cast<Map<String, Object?>>();
    const shared = {'docPath', 'name', 'line', 'message'};
    expect(
      [
        for (final finding in findings)
          {
            for (final MapEntry(:key, :value) in finding.entries)
              if (!shared.contains(key)) key: value,
          },
      ],
      [
        {'kind': 'doc_ref_self', 'field': 'depends_on', 'value': 'login'},
        {'kind': 'doc_ref_duplicate', 'field': 'depends_on', 'value': 'login'},
        {'kind': 'doc_ref_self', 'field': 'depends_on', 'value': 'login'},
        {
          'kind': 'link_anchor_missing',
          'target': '../../GNFR.md#speed',
          'anchor': 'speed',
        },
        {'kind': 'link_self', 'target': 'FEATURE.md'},
        {
          'kind': 'reference_malformed',
          'form': 'link_target',
          'text': 'http://h:abc/x.md',
        },
      ],
    );
  });

  test('document_writing INV-16: set --field and format keep a repeated doc_ref value and one naming its own doc', () async {
    final project = await writeCheckProject();
    final bases = getDoc(project, 'feature:login')['bases']! as Map;
    final base = (bases['fields']! as Map)['depends_on']! as String;
    final (:runner, :out, :err) = writeRunner(
      project,
      console: FakeConsole(input: '[login, login]\n'),
    );
    expect(
      await runner.run([
        'set',
        'feature:login',
        '--field',
        'depends_on',
        '--base',
        base,
      ]),
      0,
      reason: err.toString(),
    );
    const kept = 'depends_on: [login, login]\n';
    final file = File('${project.path}/docs/$loginFeature');
    expect(file.readAsStringSync(), contains(kept));

    final formatted = readRunner(project);
    expect(await formatted.runner.run(['format', 'docs/$loginFeature']), 0);
    expect(file.readAsStringSync(), contains(kept));
  });

  test('consistency_check/find_broken_pointers S15: check prints one number_label finding per label with its key, '
      'and none for a placeholder', () async {
    // The labels are built from parts so this file holds no number label.
    final run = ['F-${2}', 'US-${3}', 'FR-${4}'].join(' ');
    final project = await writeCheckProject(
      extra: edit(loginFeature, [
        (
          'Users forget passwords.',
          'Cite $run, or F-<nn> US-<nn> FR-<nn>, or ${'us01'}/${'fr02_x'}.',
        ),
      ]),
    );
    final text = readRunner(project);
    expect(await text.runner.run(['check']), 1);
    expect(
      text.out.toString(),
      '$loginFeature:13: number_label: $run is a number label; cite the doc by its name, such as `<feature>/<story>`\n'
      '$loginFeature:13: number_label: us01/fr02_x is a number label; cite the doc by its name, such as `<feature>/<story>`\n'
      '2 findings\n',
    );

    final json = readRunner(project);
    expect(await json.runner.run(['check', '--json']), 1);
    final findings =
        (jsonDecode(json.out.toString()) as Map<String, Object?>)['findings']!
            as List;
    expect(findings.map((f) => (f as Map<String, Object?>)['label']), [
      run,
      'us01/fr02_x',
    ]);
  });
}
