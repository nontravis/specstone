// The expected values are plan literals kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/consistency_check/code_fingerprint.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import '../../../../specstone_core/test/helpers/check_fixture.dart';
import '../../../../specstone_core/test/helpers/record_fixture.dart'
    show recordsRootTemplates;
import '../../../../specstone_core/test/helpers/shipped_pins.dart'
    show shippedPinsConfig;
import '../../../../specstone_core/test/helpers/target_fixture.dart';
import '../../../../specstone_core/test/helpers/write_fixture.dart'
    show getDoc, testHome;
import '../../helpers/built_cli.dart';
import '../../helpers/read_fixture.dart';
import '../../helpers/temp_tree.dart';
import '../../helpers/write_runner.dart';

Map<String, String> frWith(String line) => fr('verify_method: test', line);

const _parsingDiagram = 'sequenceDiagram\n  A->>B: ok';
const _refusedDiagram = 'sequenceDiagram\n  A->>B: ok\n  A->>B: x;y';
const _noNodeWarning = 'Mermaid parse skipped: node not found';

/// The doc line of the refused block's third line in [_architectureWith].
const _refusedDocLine = 19;

/// Returns the architecture doc with one parsing and one refused block.
Map<String, String> _architectureWith() => {
  'docs/$loginArchitecture':
      '---\ncovers:\n  - app/lib/\n---\n\n# Login architecture\n\n'
      '## Component diagram\n\n```mermaid\n$_parsingDiagram\n```\n\n'
      '```mermaid\n$_refusedDiagram\n```\n\n## Components\n\n'
      '| Component | Responsibility |\n|---|---|\n| Sign-in page | Takes the form |\n\n'
      '## Concerns\n\n- Integration: N/A — no outside call\n- Errors: see Components\n'
      '- Auth: N/A — one local user\n- Lifecycle: N/A — no states\n- Events: N/A — no events\n'
      '- Rollout: N/A — one release\n- Observability: N/A — no telemetry\n',
};

/// Reports whether a `node` starts on this machine's `PATH`.
bool _nodeStarts() {
  try {
    return Process.runSync('node', ['--version']).exitCode == 0;
  } on ProcessException {
    return false;
  }
}

/// Returns an environment whose own `PATH` key holds no `node`.
Future<Map<String, String>> _environmentWithoutNode() async {
  final empty = await Directory.systemTemp.createTemp('specstone_no_node_');
  addTearDown(() => empty.delete(recursive: true));
  final key = Platform.environment.keys.firstWhere(
    (k) => k.toUpperCase() == 'PATH',
    orElse: () => 'PATH',
  );
  if (!Platform.isWindows) return {key: empty.path};
  final system32 = '${Platform.environment['SystemRoot']}\\System32';
  return {key: '${empty.path};$system32'};
}

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

  test('each finding prints on its own line before the count, and the check exits 1', () async {
    final (:runner, :out, :err) = readRunner(
      await writeCheckProject(extra: frWith('verify_method: maybe')),
    );
    expect(await runner.run(['check']), 1);
    expect(
      out.toString(),
      '$loginFr:5: field_value_mismatch: verify_method is maybe; it takes test, analysis, inspection, or '
      'demonstration\n1 finding\n',
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
      'line': 5,
      'message': 'verify_method is maybe; it takes test, analysis, inspection, or demonstration',
      'waitsFor': 'agent',
      'field': 'verify_method',
      'value': 'maybe',
    });
  });

  test('a file at a project spec doc path is typed and reports its template breaks', () async {
    const docPath = 'specs/DOMAIN.md';
    final (:runner, :out, :err) = readRunner(
      await writeCheckProject(
        extra: {'docs/$docPath': '# Project domain\n'},
        unstamped: {'docs/$docPath'},
      ),
    );
    expect(await runner.run(['check', '--json']), 1);
    final json = jsonDecode(out.toString()) as Map<String, Object?>;
    final ofDoc = [
      for (final f in (json['findings']! as List).cast<Map<String, Object?>>())
        if (f['docPath'] == docPath) f['kind'],
    ];
    expect(
      ofDoc.where((kind) => kind == 'required_section_missing'),
      hasLength(2),
    );
    expect(err.toString(), isEmpty);
  });

  group('code link', () {
    final current = fileCodeFingerprint(
      utf8.encode(checkProjectFiles()['app/lib/login.dart']!),
      path: 'app/lib/login.dart',
    );

    // The record's other entry records its fingerprint, so the entry with
    // none is the project's one code finding.
    Future<Directory> project() => writeCheckProject(
      extra: edit(loginRecord, [
        (
          "email_login:app/lib/login.dart:SignInPage'",
          "email_login:app/lib/login.dart:SignInPage $current'",
        ),
      ]),
      unfingerprinted: {loginRecord},
    );

    test(
      'with no fingerprint counts toward no doc of list --suspect',
      () async {
        final (:runner, :out, :err) = readRunner(await project());

        expect(await runner.run(['list', 'fr', '--suspect']), 0);
        expect(out.toString(), isEmpty);
      },
    );
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

  test(
    'a warning no finding states goes to stderr, and to warnings under --json',
    () async {
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
      expect(
        (jsonDecode(json.out.toString()) as Map)['warnings'],
        hasLength(1),
      );
    },
  );

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

  test(
    'a write lock held past the busy timeout exits 75 with the JSON envelope',
    () async {
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
    },
  );

  test('S12: check names the drifted file and its fix, and format clears it', () async {
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

  test('check names an approved story edited outside the commands; padded table cells draw format_drift only', () async {
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
      "$loginStory:2: approval_stale: the doc changed since the Owner approved it; it waits for the Owner's specstone approve (waits for the Owner)\n"
      '$loginApi:1: format_drift: the file differs from what `specstone format` writes; run '
      '`specstone format docs/$loginApi`\n'
      '2 findings\n',
    );
  });

  test('S13, consistency_check/find_broken_pointers/resolve_doc_links: check '
      'prints the anchor, self, and doc_ref findings with their keys', () async {
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
      '5 findings\n',
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
    const kept = 'depends_on:\n  - login\n  - login\n';
    final file = File('${project.path}/docs/$loginFeature');
    expect(file.readAsStringSync(), contains(kept));

    final formatted = readRunner(project);
    expect(await formatted.runner.run(['format', 'docs/$loginFeature']), 0);
    expect(file.readAsStringSync(), contains(kept));
  });

  group('consistency_check/find_template_breaks/check_target, --target', () {
    // The shared API doc stays out, so only the feature and the twins speak.
    Future<Directory> twinProject() =>
        writeTwinProject(without: {'docs/$loginApi'});

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
          {loginFeature, jasprArchitecture},
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

    /// Writes the twin project with the flutter and jaspr records.
    Future<Directory> project({
      required String flutter,
      required String jaspr,
    }) => writeTwinProject(
      extra: {
        '.specstone/templates/implementation.yaml': layer,
        'docs/$flutterRecord': flutter,
        'docs/$jasprRecord': jaspr,
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
  });

  group('--repeats', () {
    const clause =
        'a bundle over the budget prints no doc text and exits with status zero';
    const frEdge = 'An empty password → refused.';
    const nfStatement = 'The system shall sign in within 1 s.';

    Future<Directory> repeating() => writeCheckProject(
      extra: {
        ...doc(
          loginFr,
          frEdge,
          'When the Agent runs it → it shows $clause for the Agent.',
        ),
        ...doc(
          loginNf,
          nfStatement,
          'The system shall hold, with $clause, within 1 s.',
        ),
      },
    );

    Future<ProcessResult> spawn(Directory project, List<String> args) =>
        Process.run(binary, ['check', ...args], workingDirectory: project.path);

    int lineOf(Directory project, String docPath, String needle) =>
        File('${project.path}/docs/$docPath')
            .readAsLinesSync()
            .indexWhere((line) => line.contains(needle)) +
        1;

    test('--repeats prints the group, one line per item, then the count line, and exits 0', () async {
      final project = await repeating();
      final result = await spawn(project, ['--repeats']);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(
        result.stdout,
        'repeat: "$clause"\n'
        '$loginFr:${lineOf(project, loginFr, 'E01')}: login/email_login/check_password E01\n'
        '$loginNf:${lineOf(project, loginNf, 'The system shall hold')}: login/email_login/sign_in_time —\n'
        '1 repeat group\n',
      );
    });

    test('--json prints the repeats and the count', () async {
      final project = await repeating();
      final result = await spawn(project, ['--repeats', '--json']);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(jsonDecode(result.stdout as String), {
        'repeats': [
          {
            'run': clause,
            'items': [
              {
                'docPath': loginFr,
                'name': 'login/email_login/check_password',
                'line': lineOf(project, loginFr, 'E01'),
                'item': 'E01',
              },
              {
                'docPath': loginNf,
                'name': 'login/email_login/sign_in_time',
                'line': lineOf(project, loginNf, 'The system shall hold'),
                'item': null,
              },
            ],
          },
        ],
        'count': 1,
      });
    });

    test('no repeat prints 0 repeat groups and exits 0', () async {
      final result = await spawn(await writeCheckProject(), ['--repeats']);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(result.stdout, '0 repeat groups\n');
    });

    test(
      'a plain check prints no repeat group and no finding for the repeat',
      () async {
        final result = await spawn(await repeating(), []);
        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
        expect(result.stdout, '0 findings\n');
      },
    );

    test('--repeats prints no finding of the other rules', () async {
      final project = await writeCheckProject(
        extra: frWith('verify_method: maybe'),
      );
      final result = await spawn(project, ['--repeats']);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(result.stdout, '0 repeat groups\n');
    });

    test('a read-session warning goes to stderr, and to warnings under --json, as for a plain check', () async {
      Future<Directory> damaged() async {
        final project = await repeating();
        File('${project.path}/.specstone/index.sqlite')
            .writeAsStringSync('not a database');
        return project;
      }

      final text = readRunner(await damaged());
      expect(await text.runner.run(['check', '--repeats']), 0);
      expect(text.err.toString(), startsWith('⚠️ WARNING: '));
      expect(text.out.toString(), startsWith('repeat: "$clause"\n'));
      final json = readRunner(await damaged());
      expect(await json.runner.run(['check', '--repeats', '--json']), 0);
      final printed = jsonDecode(json.out.toString()) as Map;
      expect(printed['warnings'], hasLength(1));
      expect(printed['count'], 1);
    });

    test('--target jaspr keeps the shared docs and the jaspr twin, and drops the flutter twin', () async {
      const invariant =
          '# Login domain\n\n## Entities\n\n- Account\n\n## Invariants\n\n';
      final project = await writeTwinProject(
        extra: {
          ...doc(
            loginFr,
            frEdge,
            'When the Agent runs it → it shows $clause for the Agent.',
          ),
          'docs/specs/flutter/f01_login/DOMAIN.md':
              '$invariant- **INV-6** Every run: $clause, in short.\n',
          'docs/specs/jaspr/f01_login/DOMAIN.md':
              '$invariant- **INV-6** Every run: $clause, in short.\n',
        },
      );
      final (:runner, :out, :err) = readRunner(project);
      expect(
        await runner.run(['check', '--repeats', '--target', 'jaspr', '--json']),
        0,
        reason: err.toString(),
      );
      final repeats = (jsonDecode(out.toString()) as Map)['repeats']! as List;
      expect(
        [
          for (final i in (repeats.single as Map)['items']! as List)
            (i as Map)['docPath'],
        ],
        [loginFr, 'specs/jaspr/f01_login/DOMAIN.md'],
      );
    });

    test('a config pin fault and a template fault exit as the plain check does, with nothing on stdout', () async {
      final faults = <Map<String, String>>[
        {'.specstone/config.yaml': 'packs:\n  prd-core: 9.9.9\n'},
        {'.specstone/templates/fr.yaml': 'sections: [unclosed\n'},
      ];
      for (final fault in faults) {
        final project = await writeCheckProject(extra: fault);
        final plain = readRunner(project);
        final plainStatus = await plain.runner.run(['check']);
        final repeats = readRunner(project);
        expect(
          await repeats.runner.run(['check', '--repeats']),
          plainStatus,
          reason: '$fault',
        );
        expect(plainStatus, isNot(0), reason: '$fault');
        expect(repeats.out.toString(), isEmpty);
        expect(repeats.err.toString(), plain.err.toString());
      }
    });

    test(
      'outside a project it exits 78 and prints no project was found',
      () async {
        final result = await spawn(await writeTree({}), ['--repeats']);
        expect(result.exitCode, 78);
        expect(result.stderr, startsWith('no Specstone project'));
        expect(result.stdout, isEmpty);
      },
    );
  });

  group('skill and agent files', () {
    Future<ProcessResult> run(Directory root, List<String> args) => Process.run(
      binary,
      args,
      workingDirectory: root.path,
      environment: {'HOME': testHome().path, 'USERPROFILE': testHome().path},
    );

    /// Returns a project `init` set up, in a new temp folder.
    Future<Directory> initProject() async {
      final root = await Directory.systemTemp.createTemp('specstone_check_');
      addTearDown(() => root.delete(recursive: true));
      final init = await run(root, ['init']);
      expect(init.exitCode, 0, reason: '${init.stdout}\n${init.stderr}');
      return root;
    }

    /// Returns the `agent_block_stale` lines of a whole-project check.
    Future<List<String>> staleLines(
      Directory root, [
      List<String> target = const [],
    ]) async {
      final result = await run(root, ['check', ...target]);
      expect(result.exitCode, anyOf(0, 1), reason: '${result.stderr}');
      return [
        for (final line in (result.stdout as String).split('\n'))
          if (line.contains(': agent_block_stale: ')) line,
      ];
    }

    test('a fresh init project has no finding', () async {
      expect(await staleLines(await initProject()), isEmpty);
    });
  });

  group('--out', () {
    Future<Directory> oneFinding() =>
        writeCheckProject(extra: frWith('verify_method: maybe'));

    test('writes the report to .specstone/reports/check.all.txt, prints one header line, and exits 1', () async {
      final project = await oneFinding();
      final run = readRunner(project);
      expect(
        await run.runner.run(['check', '--out']),
        1,
        reason: run.err.toString(),
      );
      final file = File('${project.path}/.specstone/reports/check.all.txt');
      expect(file.readAsStringSync(), endsWith('1 finding\n'));
      expect(file.readAsStringSync(), contains('field_value_mismatch'));
      final lines = run.out.toString().trimRight().split('\n');
      expect(lines, hasLength(1));
      expect(lines.single, startsWith('==> check: '));
      expect(lines.single, contains(file.resolveSymbolicLinksSync()));
    });

    test('--repeats --out names its file check-repeats.all.txt', () async {
      final project = await oneFinding();
      final run = readRunner(project);
      expect(
        await run.runner.run(['check', '--repeats', '--out']),
        0,
        reason: run.err.toString(),
      );
      expect(
        File('${project.path}/.specstone/reports/check-repeats.all.txt')
            .existsSync(),
        isTrue,
      );
      expect(run.out.toString(), startsWith('==> check: '));
    });

    test('a target with --json --out writes the JSON report and prints out, lines, and tokens', () async {
      final project = await oneFinding();
      final run = readRunner(project);
      expect(
        await run.runner.run(['check', 'feature:login', '--json', '--out']),
        1,
        reason: run.err.toString(),
      );
      final file = File(
        '${project.path}/.specstone/reports/check.feature-login.json',
      );
      final report =
          jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
      expect(report['count'], 1);
      final printed = jsonDecode(run.out.toString()) as Map<String, Object?>;
      expect(printed['out'], file.resolveSymbolicLinksSync());
      expect(printed['lines'], isA<int>());
      expect(printed['tokens'], isA<int>());
    });

    test('--out "" is argument_invalid, exit 64, and writes no file', () async {
      final project = await oneFinding();
      final run = readRunner(project);
      expect(await run.runner.run(['check', '--out', '']), 64);
      expect(run.out.toString(), isEmpty);
      expect(
        Directory('${project.path}/.specstone/reports').existsSync(),
        isFalse,
      );
    });

    test('a relative --out path writes there and exits 1', () async {
      final project = await oneFinding();
      final run = readRunner(project);
      final relative = ['out', 'check.txt'].join(Platform.pathSeparator);
      expect(
        await run.runner.run(['check', '--out', relative]),
        1,
        reason: run.err.toString(),
      );
      final file = File(
        [project.path, 'out', 'check.txt'].join(Platform.pathSeparator),
      );
      expect(file.readAsStringSync(), endsWith('1 finding\n'));
      expect(run.out.toString(), contains(file.resolveSymbolicLinksSync()));
    });

    test('--out into the docs root exits 73 and writes nothing', () async {
      final project = await oneFinding();
      final run = readRunner(project);
      final relative = ['docs', 'check.txt'].join(Platform.pathSeparator);
      expect(await run.runner.run(['check', '--out', relative]), 73);
      expect(run.out.toString(), isEmpty);
      expect(
        File([project.path, 'docs', 'check.txt'].join(Platform.pathSeparator))
            .existsSync(),
        isFalse,
      );
    });

    test('--repeats --out writes the repeats text', () async {
      final project = await oneFinding();
      final stdout = readRunner(project);
      expect(await stdout.runner.run(['check', '--repeats']), 0);
      final run = readRunner(project);
      expect(await run.runner.run(['check', '--repeats', '--out']), 0);
      final file = File(
        [
          project.path,
          '.specstone',
          'reports',
          'check-repeats.all.txt',
        ].join(Platform.pathSeparator),
      );
      expect(file.readAsStringSync(), stdout.out.toString());
    });

    test('a warning still goes to stderr', () async {
      final project = await writeCheckProject();
      File('${project.path}/.specstone/index.sqlite')
          .writeAsStringSync('not a database');
      final run = readRunner(project);
      expect(await run.runner.run(['check', '--out']), 0);
      expect(run.err.toString(), startsWith('⚠️ WARNING: '));
    });
  });

  group('a record under .specstone/records/', () {
    const record = '.specstone/records/f01_login/IMPLEMENTATION.md';

    Future<Directory> recordProject() => writeCheckProject(
      extra: {
        ...recordsRootTemplates,
        record: checkProjectFiles()[loginRecord]!,
      },
    );

    test('check reads the record: a clean record is 0 findings, a broken one names its DocPath', () async {
      final clean = await recordProject();
      final ok = await Process.run(binary, [
        'check',
      ], workingDirectory: clean.path);
      expect(ok.exitCode, 0, reason: '${ok.stdout}\n${ok.stderr}');
      expect(ok.stdout, '0 findings\n');

      final broken = await writeCheckProject(
        extra: {
          ...recordsRootTemplates,
          record: checkProjectFiles()[loginRecord]!.replaceFirst(
            'email_login/check_password:implemented',
            'email_login/check_pasword:implemented',
          ),
        },
      );
      final bad = await Process.run(binary, [
        'check',
      ], workingDirectory: broken.path);
      expect(bad.exitCode, 1, reason: '${bad.stdout}\n${bad.stderr}');
      expect(bad.stdout, contains('$record:'));
    });

    test('context and get reach the record by its address', () async {
      final project = await recordProject();
      final got = await Process.run(binary, [
        'get',
        'implementation:login',
        '--json',
      ], workingDirectory: project.path);
      expect(got.exitCode, 0, reason: '${got.stdout}\n${got.stderr}');
      final doc = (jsonDecode(got.stdout as String) as Map)['docs']! as List;
      expect((doc.single as Map)['path'], record);

      final context = await Process.run(binary, [
        'context',
        'implementation:login',
        '--for',
        'implement',
      ], workingDirectory: project.path);
      expect(
        context.exitCode,
        0,
        reason: '${context.stdout}\n${context.stderr}',
      );
      expect(context.stdout, contains('Login implementation'));
    });

    test(
      'set --field statuses writes the record under .specstone/records/',
      () async {
        final project = await recordProject();
        final bases = getDoc(project, 'implementation:login')['bases']! as Map;
        final base = (bases['fields']! as Map)['statuses']! as String;
        final (:runner, :out, :err) = writeRunner(
          project,
          console: FakeConsole(input: '["email_login:planned"]\n'),
        );
        expect(
          await runner.run([
            'set',
            'implementation:login',
            '--field',
            'statuses',
            '--base',
            base,
          ]),
          0,
          reason: err.toString(),
        );
        final file = File(
          [
            project.path,
            '.specstone',
            'records',
            'f01_login',
            'IMPLEMENTATION.md',
          ].join(Platform.pathSeparator),
        );
        expect(file.readAsStringSync(), contains('email_login:planned'));
        expect(
          Directory('${project.path}/docs/.specstone').existsSync(),
          isFalse,
        );
      },
    );

    test('delete --dry-run lists the record by its DocPath', () async {
      final project = await recordProject();
      final run = await Process.run(binary, [
        'delete',
        'implementation:login',
        '--dry-run',
      ], workingDirectory: project.path);
      expect(run.exitCode, 0, reason: '${run.stdout}\n${run.stderr}');
      expect(run.stdout, contains(record));
      expect(run.stdout, isNot(contains('docs/$record')));
    });

    test('format reaches the record in a whole-tree run', () async {
      final project = await writeCheckProject(
        extra: {
          ...recordsRootTemplates,
          record: checkProjectFiles()[loginRecord]!.replaceFirst(
            '# Login implementation\n',
            '# Login implementation\n\n\n\nText.\n',
          ),
        },
      );
      final run = await Process.run(binary, [
        'format',
        '--check',
      ], workingDirectory: project.path);
      expect(run.exitCode, isNot(0), reason: '${run.stdout}\n${run.stderr}');
      expect(run.stdout, contains(record));
    });

    test('with two targets the record sits in its target folder after .specstone/records/', () async {
      const flutterRecord =
          '.specstone/records/flutter/f01_login/IMPLEMENTATION.md';
      final project = await writeTwinProject(
        extra: {
          ...recordsRootTemplates,
          flutterRecord: '---\nstatuses:\n  - "email_login:planned"\n---\n\n# Login implementation\n',
        },
      );
      final got = await Process.run(binary, [
        'get',
        'implementation:login',
        '--target',
        'flutter',
        '--json',
      ], workingDirectory: project.path);
      expect(got.exitCode, 0, reason: '${got.stdout}\n${got.stderr}');
      final docs = (jsonDecode(got.stdout as String) as Map)['docs']! as List;
      expect((docs.single as Map)['path'], flutterRecord);

      final misplaced = await writeTwinProject(
        extra: {
          ...recordsRootTemplates,
          '.specstone/records/f01_login/IMPLEMENTATION.md':
              '# Login implementation\n',
        },
      );
      final check = await Process.run(binary, [
        'check',
      ], workingDirectory: misplaced.path);
      expect(
        check.stdout,
        contains(
          '.specstone/records/f01_login/IMPLEMENTATION.md:1: untyped_doc',
        ),
      );
    });
  });

  group('verification matrix rows', () {
    const item = 'email_login/check_password';
    const testFile = 'app/test/login_test.dart';
    // The first row sits on file line 12, under the matrix header on line 10.
    const rows = [
      '- $item E01: `refuses a blank password`',
      '- $item E01 skipped: no clock on CI',
      'A paragraph in the section.',
    ];

    Future<Directory> matrixProject() => writeCheckProject(
      extra: {
        loginRecord:
            "---\nstatuses:\n  - '$item:implemented'\ntests:\n  - '$item:$testFile'\n---\n\n"
            '# Login implementation\n\n## Verification matrix\n\n${rows.join('\n')}\n',
        testFile:
            "void main() {\n  test('refuses an empty password', () {});\n}\n",
      },
      // A stamp would add an `approved:` line and move every line below it.
      unstamped: {loginRecord},
    );

    test('check prints matrix findings on the record, each waiting for the Agent', () async {
      final project = await matrixProject();

      final text = readRunner(project);
      expect(await text.runner.run(['check']), 1);
      expect(text.out.toString().split('\n').where((l) => l.contains(': matrix_')), [
        '$loginRecord:12: matrix_test_unresolved: refuses a blank password occurs in no test file of $item',
        '$loginRecord:13: matrix_skip_conflict: $item#E01 has a skip row beside another row; line 12 holds the other',
        '$loginRecord:14: matrix_row_malformed: ${rows[2]} is no matrix row; write "- <item> <edge case>: `<test name>`" or "- <item> <edge case> skipped: <reason>"',
      ]);

      final json = readRunner(project);
      expect(await json.runner.run(['check', '--json']), 1);
      final all =
          (jsonDecode(json.out.toString()) as Map<String, Object?>)['findings']!
              as List;
      final findings = [
        for (final f in all.cast<Map<String, Object?>>())
          if ((f['kind']! as String).startsWith('matrix_')) f,
      ];
      expect(
        [
          for (final f in findings) [f['kind'], f['line'], f['waitsFor']],
        ],
        [
          ['matrix_test_unresolved', 12, 'agent'],
          ['matrix_skip_conflict', 13, 'agent'],
          ['matrix_row_malformed', 14, 'agent'],
        ],
      );
      expect(
        [
          for (final f in findings)
            {
              for (final MapEntry(:key, :value) in f.entries)
                if (!const [
                  'kind',
                  'docPath',
                  'line',
                  'message',
                  'waitsFor',
                ].contains(key))
                  key: value,
            },
        ],
        [
          // The `name` key of this kind replaces the doc's name, as it does for `tests_unresolved`.
          {'name': 'refuses a blank password', 'item': item},
          {'name': 'login', 'first': 12},
          {'name': 'login', 'row': rows[2]},
        ],
      );
      expect({for (final f in findings) f['docPath']}, {loginRecord});
    });

    test('check on the requirement alone prints none of them', () async {
      final (:runner, :out, :err) = readRunner(await matrixProject());

      expect(await runner.run(['check', loginFr]), 0, reason: out.toString());
      expect(out.toString(), '0 findings\n');
    });

    test('the config key turns on the edge case coverage finding', () async {
      Future<Directory> coverageProject(String config) => writeCheckProject(
        extra: {
          '.specstone/config.yaml': config,
          loginRecord:
              "---\nstatuses:\n  - '$item:implemented'\ntests:\n  - '$item:$testFile'\n---\n\n"
              '# Login implementation\n\n## Verification matrix\n',
          testFile:
              "void main() {\n  test('refuses an empty password', () {});\n}\n",
        },
        unstamped: {loginRecord},
      );
      List<String> missing(String out) => [
        for (final line in out.split('\n'))
          if (line.contains(': matrix_row_missing')) line,
      ];

      final on = readRunner(
        await coverageProject(
          '${shippedPinsConfig()}verification_coverage: true\n',
        ),
      );
      expect(await on.runner.run(['check']), 1, reason: on.out.toString());
      expect(missing(on.out.toString()), [
        '$loginRecord:3: matrix_row_missing: $item#E01 is implemented and no matrix row names it',
      ]);

      final off = readRunner(await coverageProject(shippedPinsConfig()));
      await off.runner.run(['check']);
      expect(missing(off.out.toString()), isEmpty);
    });

    group('a row tracked against its edge case', () {
      const edgeCase = '1. E01 — An empty password → refused.';
      const older = '3f9a1c0b7e2d';
      const draftFr = (
        'verify_method: test',
        'verify_method: test\ndraft: true',
      );
      final current = fingerprintFor(edgeCase);

      Future<Directory> stampedProject({
        String fingerprint = ' $older',
        Map<String, String> extra = const {},
      }) => writeCheckProject(
        extra: {
          loginRecord:
              "---\nstatuses:\n  - '$item:implemented'\ntests:\n  - '$item:$testFile'\n---\n\n"
              '# Login implementation\n\n## Verification matrix\n\n'
              '- $item E01: `refuses an empty password`$fingerprint\n',
          testFile:
              "void main() {\n  test('refuses an empty password', () {});\n}\n",
          ...extra,
        },
        unstamped: {loginRecord},
      );

      // The record's suspect and unconfirmed lines, each with the block lines
      // that follow it.
      List<String> suspectLines(String out) {
        final lines = <String>[];
        var isRecordFinding = false;
        for (final line in out.split('\n')) {
          if (!line.startsWith('    ')) {
            isRecordFinding =
                line.startsWith('$loginRecord:') &&
                (line.contains(': suspect: ') ||
                    line.contains(': unconfirmed: '));
          }
          if (isRecordFinding) lines.add(line);
        }
        return lines;
      }

      test('a suspect row prints its block before its fingerprint', () async {
        final (:runner, :out, :err) = readRunner(await stampedProject());

        expect(await runner.run(['check']), 1, reason: out.toString());

        const message =
            '$item#E01 changed after it was confirmed, recorded $older; '
            'read E01 of $loginFr below, then record $item#E01 with the fingerprint after it';
        expect(suspectLines(out.toString()), [
          '$loginRecord:12: suspect: $message',
          '    $edgeCase',
          '    fingerprint $current',
        ]);
        expect(suspectLines(out.toString()).first, isNot(endsWith('Owner)')));
      });

      test('a row of a draft FR ends with the Owner tag', () async {
        final (:runner, :out, :err) = readRunner(
          await stampedProject(extra: fr(draftFr.$1, draftFr.$2)),
        );

        expect(await runner.run(['check']), 1, reason: out.toString());

        const message =
            '$item#E01 changed after it was confirmed, recorded $older; '
            "it waits for the Owner's approve of $loginFr (waits for the Owner)";
        expect(suspectLines(out.toString()), [
          '$loginRecord:12: suspect: $message',
          '    $edgeCase',
          '    fingerprint $current',
        ]);
      });

      test('an unstamped row of a draft FR ends with the Owner tag and prints '
          'no block', () async {
        final (:runner, :out, :err) = readRunner(
          await stampedProject(
            fingerprint: '',
            extra: fr(draftFr.$1, draftFr.$2),
          ),
        );

        expect(await runner.run(['check']), 1, reason: out.toString());

        const message =
            "$item#E01 waits for the Owner's approve of $loginFr (waits for the Owner)";
        expect(suspectLines(out.toString()), [
          '$loginRecord:12: unconfirmed: $message',
        ]);
      });
    });
  });

  group('mermaid parse through the built binary', () {
    final hasNode = _nodeStarts();
    final noNode = hasNode ? null : 'node is not on PATH';

    Future<ProcessResult> check(
      Directory project, {
      Map<String, String>? environment,
      bool json = false,
    }) => Process.run(
      binary,
      ['check', if (json) '--json'],
      workingDirectory: project.path,
      environment: environment,
    );

    test('a refused block is one finding at its error line, a block that parses gets none, and it exits 1', () async {
      final project = await writeCheckProject(extra: _architectureWith());

      final run = await check(project, json: true);

      expect(run.exitCode, 1, reason: '${run.stdout}\n${run.stderr}');
      final findings = [
        for (final f
            in (jsonDecode(run.stdout as String) as Map)['findings']! as List)
          if ((f as Map)['kind'] == 'diagram_parse_failed') f,
      ];
      expect(findings, hasLength(1), reason: '${run.stdout}');
      final finding = findings.single;
      expect(finding['docPath'], loginArchitecture);
      expect(finding['line'], _refusedDocLine);
      expect(finding['diagram'], 'sequence');
      expect(finding['waitsFor'], 'agent');
      expect(finding['message'], startsWith('Parse error on line 3:'));
    }, skip: noNode);

    test('a rerun with no Node on PATH reports the same finding from its stored row', () async {
      final project = await writeCheckProject(extra: _architectureWith());
      final first = await check(project);

      final rerun = await check(
        project,
        environment: await _environmentWithoutNode(),
      );

      expect(
        first.stdout,
        contains(
          '$loginArchitecture:$_refusedDocLine: diagram_parse_failed: Parse error on line 3:',
        ),
      );
      expect(rerun.exitCode, 1, reason: '${rerun.stdout}\n${rerun.stderr}');
      expect(rerun.stdout, first.stdout);
      expect(rerun.stderr, isEmpty);
    }, skip: noNode);

    test(
      'with no Node and no stored row the run warns and keeps its status',
      () async {
        final project = await writeCheckProject(extra: _architectureWith());
        final environment = await _environmentWithoutNode();

        final run = await check(project, environment: environment);

        expect(run.exitCode, 0, reason: '${run.stdout}\n${run.stderr}');
        expect(run.stdout, '0 findings\n');
        expect(run.stderr, '⚠️ WARNING: $_noNodeWarning\n');
      },
    );

    test('the warning run stores nothing, so the next run with Node parses the block', () async {
      final project = await writeCheckProject(extra: _architectureWith());
      await check(project, environment: await _environmentWithoutNode());

      final next = await check(project);

      expect(next.exitCode, 1, reason: '${next.stdout}\n${next.stderr}');
      expect(
        next.stdout,
        contains('$loginArchitecture:$_refusedDocLine: diagram_parse_failed:'),
      );
    }, skip: noNode);

    test('--json carries the skip warning in warnings', () async {
      final project = await writeCheckProject(extra: _architectureWith());

      final run = await check(
        project,
        environment: await _environmentWithoutNode(),
        json: true,
      );

      expect(run.exitCode, 0, reason: '${run.stdout}\n${run.stderr}');
      final printed = jsonDecode(run.stdout as String) as Map;
      expect(printed['warnings'], [_noNodeWarning]);
      expect(printed['findings'], isEmpty);
    });
  });
}
