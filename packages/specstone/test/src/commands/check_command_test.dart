// The expected values are plan literals kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/document_writing/approval.dart'
    show withApprovalHash;
import 'package:specstone_core/src/rendering/line_ending.dart' show toLf;
import 'package:specstone_core/src/setup_migration/agent_files.dart';
import 'package:specstone_core/src/version.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import '../../../../specstone_core/test/helpers/check_fixture.dart';
import '../../../../specstone_core/test/helpers/nested_fixture.dart';
import '../../../../specstone_core/test/helpers/target_fixture.dart';
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
          'waitsFor': 'agent',
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
      'waitsFor': 'agent',
      'field': 'verify_method',
      'value': 'maybe',
    });
  });

  group('user_story:consistency_check/find_template_breaks S8', () {
    // Two findings: the story edited since the Owner approved it, and a
    // requirement with a bad field value.
    Future<Directory> project() => writeCheckProject(
      extra: {
        ...editedAfterApproval(loginStory, [('Sign in', 'Sign in again')]),
        ...frWith('verify_method: maybe'),
      },
    );

    test(
      '--json gives each finding who clears it, and the count of two',
      () async {
        final (:runner, :out, :err) = readRunner(await project());
        expect(await runner.run(['check', '--json']), 1);
        final json = jsonDecode(out.toString()) as Map<String, Object?>;
        expect(json['count'], 2);
        final waits = {
          for (final f
              in (json['findings']! as List).cast<Map<String, Object?>>())
            f['kind']: f['waitsFor'],
        };
        expect(waits, {
          'approval_stale': 'owner',
          'field_value_mismatch': 'agent',
        });
        final stale = (json['findings']! as List)
            .cast<Map<String, Object?>>()
            .firstWhere((f) => f['kind'] == 'approval_stale');
        expect(stale.keys.take(6), [
          'kind',
          'docPath',
          'name',
          'line',
          'message',
          'waitsFor',
        ]);
        expect(stale['message'], isNot(contains('(waits for the Owner)')));
      },
    );

    test('text ends the edited doc line with the tag and no other', () async {
      final (:runner, :out, :err) = readRunner(await project());
      expect(await runner.run(['check']), 1);
      final lines = out.toString().trimRight().split('\n');
      expect(lines.last, '2 findings');
      final tagged = lines.where((l) => l.endsWith(' (waits for the Owner)'));
      expect(tagged, hasLength(1));
      expect(tagged.single, startsWith('$loginStory:3: approval_stale: '));
    });
  });

  test('consistency_check/find_template_breaks/print_findings E08: an '
      'approval_stale finding ends its line with the tag, and its JSON holds '
      'waitsFor owner with a message that carries no tag', () async {
    final project = await writeCheckProject(
      extra: editedAfterApproval(loginStory, [('Sign in', 'Sign in again')]),
    );
    final text = readRunner(project);
    expect(await text.runner.run(['check']), 1);
    expect(
      text.out.toString(),
      endsWith(' (waits for the Owner)\n1 finding\n'),
    );

    final json = readRunner(project);
    expect(await json.runner.run(['check', '--json']), 1);
    final finding =
        ((jsonDecode(json.out.toString()) as Map)['findings']! as List).single
            as Map;
    expect(finding['waitsFor'], 'owner');
    expect(finding['message'], isNot(contains('waits for the Owner)')));
  });

  group('user_story:consistency_check/find_template_breaks S16', () {
    const reason = 'legacy states none';
    // The marker is built from parts so this file holds none outside a value.
    const marker = 'TBR \u2014 ';

    Future<Directory> project() => writeCheckProject(
      extra: fr(
        'A wrong password must not sign in.',
        'A wrong password must not sign in.\n\n- **Consistency:** $marker$reason',
      ),
    );

    test('text prints one tbr_open line at the marker with the tag', () async {
      final dir = await project();
      final line = File('${dir.path}/docs/$loginFr')
          .readAsLinesSync()
          .indexWhere((l) => l.contains(marker));
      final (:runner, :out, :err) = readRunner(dir);

      expect(await runner.run(['check']), 1);
      expect(
        out.toString(),
        '$loginFr:${line + 1}: tbr_open: the value is still to be resolved: '
        '$reason (waits for the Owner)\n1 finding\n',
      );
    });

    test('--json gives form marker and waitsFor owner, no tag', () async {
      final (:runner, :out, :err) = readRunner(await project());

      expect(await runner.run(['check', '--json']), 1);
      final finding =
          ((jsonDecode(out.toString()) as Map)['findings']! as List).single
              as Map;
      expect(finding['kind'], 'tbr_open');
      expect(finding['waitsFor'], 'owner');
      expect(finding['form'], 'marker');
      expect(finding['message'], 'the value is still to be resolved: $reason');
    });

    test(
      'after the Owner writes the value, the check reports nothing',
      () async {
        final (:runner, :out, :err) = readRunner(
          await writeCheckProject(
            extra: fr(
              'A wrong password must not sign in.',
              'A wrong password must not sign in.\n\n- **Consistency:** immediate',
            ),
          ),
        );

        expect(await runner.run(['check']), 0);
        expect(out.toString(), '0 findings\n');
      },
    );
  });

  group('consistency_check/find_template_breaks/print_findings upstream block', () {
    final edited = loginScenario2.replaceFirst('wrong password', 'wrong pass');
    final fingerprint = fingerprintFor(edited);
    final block = printedBlockOf(edited);

    Future<Directory> project() =>
        writeCheckProject(extra: doc(loginStory, loginScenario2, edited));

    test('text prints the finding line, the block indented 4 spaces, then '
        'the fingerprint line, then the count', () async {
      final (:runner, :out, :err) = readRunner(await project());
      expect(await runner.run(['check']), 1);
      expect(
        out.toString(),
        '$loginFr:8: suspect: S2 changed after it was confirmed, recorded ${fingerprintFor(loginScenario2)}; '
        'read Scenario 2 of $loginStory below, then record S2 with the fingerprint after it\n'
        '${block.split('\n').map((l) => '    $l\n').join()}'
        '    fingerprint $fingerprint\n'
        '1 finding\n',
      );
    });

    test('--json puts text before fingerprint', () async {
      final (:runner, :out, :err) = readRunner(await project());
      expect(await runner.run(['check', '--json']), 1);
      final finding =
          ((jsonDecode(out.toString()) as Map)['findings']! as List).single
              as Map<String, Object?>;
      expect(finding['text'], block);
      final keys = finding.keys.toList();
      expect(keys.indexOf('text'), lessThan(keys.indexOf('fingerprint')));
      expect(finding['fingerprint'], fingerprint);
      expect(finding['message'], isNot(contains(fingerprint)));
    });
  });

  test('consistency_check/find_template_breaks/print_findings E12: an owner '
      'finding counts and exits 1 as any other', () async {
    final (:runner, :out, :err) = readRunner(
      await writeCheckProject(
        extra: editedAfterApproval(loginStory, [('Sign in', 'Sign in again')]),
      ),
    );
    expect(await runner.run(['check']), 1);
    expect(out.toString(), contains('\n1 finding\n'));
  });

  group('consistency_check/find_template_breaks/print_findings E11, E12: item_over_limit', () {
    final overlong = 'A long rationale'.padRight(700, '.');

    Future<Directory> project() => writeCheckProject(
      extra: fr('A wrong password must not sign in.', overlong),
    );

    test('text ends its line with the tag and the run exits 1', () async {
      final dir = await project();
      final line =
          File('${dir.path}/docs/$loginFr')
              .readAsLinesSync()
              .indexWhere((l) => l.startsWith('A long rationale')) +
          1;
      final (:runner, :out, :err) = readRunner(dir);

      expect(await runner.run(['check']), 1);
      expect(
        out.toString(),
        '$loginFr:$line: item_over_limit: the item at line $line of section '
        'rationale has 700 characters; the limit is 600 '
        '(waits for the Owner)\n1 finding\n',
      );
    });

    test('--json carries waitsFor owner and the four keys, no tag', () async {
      final (:runner, :out, :err) = readRunner(
        await writeCheckProject(
          extra: fr(
            '1. E01 — An empty password → refused.',
            '1. E01 — ${'An empty password'.padRight(700, '.')}',
          ),
        ),
      );

      expect(await runner.run(['check', '--json']), 1);
      final finding =
          ((jsonDecode(out.toString()) as Map)['findings']! as List).single
              as Map;
      expect(finding['kind'], 'item_over_limit');
      expect(finding['waitsFor'], 'owner');
      expect(finding, containsPair('section', 'edge_cases'));
      expect(finding, containsPair('id', 'E01'));
      expect(finding, containsPair('limit', 600));
      expect(finding, containsPair('actual', 709));
      expect(finding['message'], isNot(contains('waits for the Owner)')));
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
      'AGENTS.md:2: agent_block_stale: $message (waits for the Owner)\n'
      '1 finding\n',
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
        'waitsFor': 'owner',
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
      "$loginStory:3: approval_stale: the doc changed since the Owner approved it; it waits for the Owner's specstone approve (waits for the Owner)\n"
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
      "$loginFr:1: approval_stale: the doc carries no approval; it waits for the Owner's specstone approve (waits for the Owner)\n"
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
        'waitsFor': 'owner',
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
    const shared = {'docPath', 'name', 'line', 'message', 'waitsFor'};
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

  group('consistency_check/find_template_breaks/check_target, --target', () {
    const flutterArch = flutterArchitecture;
    const jasprArch = jasprArchitecture;
    // The shared API doc stays out, so only the feature and the twins speak.
    Future<Directory> twinProject() =>
        writeTwinProject(without: {'docs/$loginApi'});

    test('E20: check feature:login lists the feature and each target spec folder; --target jaspr drops the flutter folder', () async {
      final project = await twinProject();
      final both = readRunner(project);
      expect(await both.runner.run(['check', 'feature:login']), 1);
      expect(
        both.out.toString(),
        allOf(
          contains(loginFeature),
          contains(flutterArch),
          contains(jasprArch),
        ),
      );
      final one = readRunner(project);
      expect(
        await one.runner.run(['check', 'feature:login', '--target', 'jaspr']),
        1,
      );
      expect(
        one.out.toString(),
        allOf(
          contains(loginFeature),
          contains(jasprArch),
          isNot(contains(flutterArch)),
        ),
      );
      expect(one.out.toString(), endsWith('2 findings\n'));
    });

    test(
      'E21: check --target jaspr keeps the shared docs and jaspr, --json too',
      () async {
        final (:runner, :out, :err) = readRunner(await twinProject());
        expect(await runner.run(['check', '--target', 'jaspr', '--json']), 1);
        final findings =
            (jsonDecode(out.toString()) as Map<String, Object?>)['findings']!
                as List;
        expect(
          {for (final f in findings) (f as Map<String, Object?>)['docPath']},
          {loginFeature, jasprArch},
        );
        expect(err.toString(), isEmpty);
      },
    );

    test('E22: a --target name targets: lacks is argument_invalid, exit 64, no finding', () async {
      final (:runner, :out, :err) = readRunner(await twinProject());
      expect(await runner.run(['check', '--target', 'web']), 64);
      expect(
        err.toString(),
        '--target web: the code targets are flutter, jaspr\n',
      );
      expect(out.toString(), isEmpty);
    });

    const missing =
        '--target needs a code target name: the code targets are flutter, jaspr';

    test('E22: --target with no value is argument_missing naming the targets, exit 64, no finding', () async {
      for (final args in [
        ['check', '--target'],
        ['check', '--target', '--json'],
      ]) {
        final (:runner, :out, :err) = readRunner(await twinProject());
        expect(await runner.run(args), 64, reason: '$args');
        expect(out.toString(), isEmpty, reason: '$args');
        if (args.contains('--json')) {
          expect((jsonDecode(err.toString()) as Map)['error'], {
            'code': 'argument_missing',
            'message': missing,
          });
        } else {
          expect(err.toString(), '$missing\n');
        }
      }
    });

    test(
      'E22: another command with --target and no value answers the same',
      () async {
        final (:runner, :out, :err) = readRunner(await twinProject());
        expect(await runner.run(['structure', '--target']), 64);
        expect(err.toString(), '$missing\n');
        expect(out.toString(), isEmpty);
      },
    );
  });

  group('consistency_check/find_prd_spec_disagreements, two targets', () {
    const layer =
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
        '    pointer: item_exact\n';
    const flutterRecord = 'specs/flutter/f01_login/IMPLEMENTATION.md';
    const jasprRecord = 'specs/jaspr/f01_login/IMPLEMENTATION.md';
    const item = 'email_login/check_password';
    const story = 'email_login';
    const code = '$item:app/lib/login.dart:checkPassword';

    String record(List<String> statuses, [List<String> paths = const []]) =>
        '---\nstatuses:\n${[for (final s in statuses) "  - '$s'\n"].join()}'
        '${paths.isEmpty ? '' : 'implements:\n${[for (final p in paths) "  - '$p'\n"].join()}'}'
        '---\n\n# Record\n';

    /// The login architecture doc with [covers] as its covers entry and
    /// [sentence] after its box, carrying its approval hash.
    String architecture({String covers = 'app/lib/', String sentence = ''}) =>
        withApprovalHash(
          toLf(
            checkProjectFiles()['docs/$loginArchitecture']!
                .replaceFirst('  - app/lib/\n', '  - $covers\n')
                .replaceFirst('One box.', 'One box. $sentence'),
          ),
          fixtureDocTypeOf(loginArchitecture),
        );

    /// Writes the twin project with the two records; no jaspr record when
    /// [jaspr] is null.
    Future<Directory> project({
      required String flutter,
      String? jaspr,
      Map<String, String> extra = const {},
    }) => writeTwinProject(
      extra: {
        '.specstone/templates/implementation.yaml': layer,
        'docs/$flutterRecord': flutter,
        'docs/$jasprRecord': ?jaspr,
        ...extra,
      },
    );

    /// Runs `check --json` and returns the findings of [kinds].
    Future<List<Map<String, Object?>>> checked(
      Directory dir,
      Set<String> kinds,
    ) async {
      final (:runner, :out, :err) = readRunner(dir);
      await runner.run(['check', '--json']);
      final all =
          (jsonDecode(out.toString()) as Map<String, Object?>)['findings']!
              as List;
      return [
        for (final f in all)
          if (kinds.contains((f as Map<String, Object?>)['kind'])) f,
      ];
    }

    final flutterDone = record(['$item:implemented'], [code]);

    test('user_story:consistency_check/find_prd_spec_disagreements S8: work implemented in jaspr with no code is one finding naming jaspr', () async {
      final findings = await checked(
        await project(
          flutter: flutterDone,
          jaspr: record(['$item:implemented']),
        ),
        {'implements_missing'},
      );

      expect(findings, hasLength(1));
      expect(findings.single['docPath'], jasprRecord);
      expect(
        findings.single['message'],
        contains('implemented in target jaspr'),
      );
      expect(findings.single['message'], contains('names no code path'));
    });

    test('user_story:consistency_check/find_prd_spec_disagreements S9: a record entry for work the feature lacks names the record and the entry', () async {
      final findings = await checked(
        await project(
          flutter: flutterDone,
          jaspr: record(['$item:planned', '$story/pin_toast:planned']),
        ),
        {'record_entry_unresolved'},
      );

      expect(findings, hasLength(1));
      expect(findings.single['docPath'], jasprRecord);
      expect(findings.single['entry'], '$story/pin_toast');
    });

    test('user_story:consistency_check/find_prd_spec_disagreements S10: a story a target skips with a reason has no finding, and the tree shows it skipped', () async {
      final dir = await project(
        flutter: flutterDone,
        jaspr: record(['$story:skipped:no jaspr sign-in']),
      );
      final findings = await checked(dir, {
        'implements_missing',
        'record_entry_unresolved',
        'record_entry_duplicate',
        'skip_reason_missing',
        'skip_with_code',
        'entry_under_skip',
        'feature_status_written',
        'architecture_missing',
      });
      expect(findings, isEmpty);

      final (:runner, :out, :err) = readRunner(dir);
      expect(await runner.run(['structure', 'login', '--target', 'jaspr']), 0);
      final storyLine = out
          .toString()
          .split('\n')
          .singleWhere((l) => l.contains('(user_story)'));
      expect(storyLine, contains(' · skipped · '));
      expect(storyLine, isNot(contains('planned')));
    });

    test('user_story:consistency_check/find_prd_spec_disagreements S11: a skip with no reason, or with code, is a finding naming the entry', () async {
      final noReason = await checked(
        await project(flutter: flutterDone, jaspr: record(['$item:skipped'])),
        {'skip_reason_missing'},
      );
      expect(noReason, hasLength(1));
      expect(noReason.single['docPath'], jasprRecord);
      expect(noReason.single['entry'], item);

      final withCode = await checked(
        await project(
          flutter: flutterDone,
          jaspr: record(['$item:skipped:no jaspr'], [code]),
        ),
        {'skip_with_code'},
      );
      expect(withCode, hasLength(1));
      expect(withCode.single['docPath'], jasprRecord);
      expect(withCode.single['entry'], item);
    });

    test('user_story:consistency_check/find_broken_pointers S16: a planned requirement naming code not written yet has no pointer finding, and an implemented one does', () async {
      const later = '$item:app/lib/later.dart:later';
      const kinds = {
        'implements_path_unresolved',
        'implements_symbol_unresolved',
      };
      final planned = await checked(
        await project(
          flutter: flutterDone,
          jaspr: record(['$item:planned'], [later]),
        ),
        kinds,
      );
      expect(planned, isEmpty);

      final implemented = await checked(
        await project(
          flutter: flutterDone,
          jaspr: record(['$item:implemented'], [later]),
        ),
        kinds,
      );
      expect(implemented, hasLength(1));
      expect(implemented.single['docPath'], jasprRecord);
      expect(implemented.single['kind'], 'implements_path_unresolved');
    });

    test("user_story:consistency_check/find_broken_pointers S17: a target's coverage path that does not exist gives no finding until the target implements work of the feature", () async {
      final missing = {
        'docs/$jasprArchitecture': architecture(covers: 'app/lib/web/'),
      };
      final before = await checked(
        await project(
          flutter: flutterDone,
          jaspr: record(['$item:planned']),
          extra: missing,
        ),
        {'covers_path_missing'},
      );
      expect(before, isEmpty);

      final after = await checked(
        await project(
          flutter: flutterDone,
          jaspr: record(['$item:implemented'], [code]),
          extra: missing,
        ),
        {'covers_path_missing'},
      );
      expect(after, hasLength(1));
      expect(after.single['docPath'], jasprArchitecture);
    });

    test('user_story:consistency_check/find_broken_pointers S18: a spec doc of one target naming a doc only the other target holds is doc_name_unresolved at its line', () async {
      final dir = await project(
        flutter: flutterDone,
        extra: {
          'docs/$jasprArchitecture': architecture(
            sentence: 'See `implementation:login`.',
          ),
        },
      );
      final findings = await checked(dir, {'doc_name_unresolved'});

      expect(findings, hasLength(1));
      expect(findings.single['docPath'], jasprArchitecture);
      expect(findings.single['message'], contains('implementation:login'));
      final line =
          File('${dir.path}/docs/$jasprArchitecture')
              .readAsLinesSync()
              .indexWhere((l) => l.contains('implementation:login')) +
          1;
      expect(findings.single['line'], line);
    });

    test('user_story:consistency_check/find_broken_pointers S19: a requirement naming a spec doc of one target is per_target_reference', () async {
      final dir = await project(
        flutter: flutterDone,
        jaspr: record(['$item:planned']),
        extra: doc(
          loginNf,
          'Users wait.',
          'Users wait. See `architecture:login`.',
        ),
      );
      final findings = await checked(dir, {'per_target_reference'});

      expect(findings, hasLength(1));
      expect(findings.single['docPath'], loginNf);
      expect(findings.single['reference'], 'architecture:login');
    });
  });
}
