// The test names and expected texts are plan literals kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/check_report.dart';
import 'package:specstone_core/src/consistency_check/check_run.dart';
import 'package:specstone_core/src/consistency_check/check_scope.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/document_writing/approval.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/rendering/line_ending.dart';
import 'package:specstone_core/src/templates/code_target.dart';
import 'package:specstone_core/src/templates/template_fault.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/index_fixture.dart';
import '../../helpers/nested_fixture.dart';
import '../../helpers/posix_modes.dart';
import '../../helpers/shipped_pins.dart';

void main() {
  test(
    'f04/us01/s1, f04/us01/fr01/e01: the fixture project has zero findings',
    () async {
      final report = checkOf(await writeCheckProject());
      expect(report.findings, isEmpty);
      expect(report.exitStatus, 0);
    },
  );

  test('f04/us01/fr01/e02, cc-s03/inv12: check login keeps the feature and the docs under it', () async {
    final project = await writeCheckProject(
      extra: {
        'docs/$loginFr': checkProjectFiles()['docs/$loginFr']!.replaceFirst(
          'verify_method: test\n',
          '',
        ),
        'docs/prds/features/f02_signup/FEATURE.md': '# Sign up\n',
        'docs/prds/features/f02_signup/us01_create/fr01_store.md':
            '---\ntraced_from:\n  - S1\n---\n\n# Store\n',
      },
    );
    const missing = FindingKind.requiredFieldMissing;
    expect(spots(checkOf(project), missing), [
      '$loginFr:1: required_field_missing',
      'prds/features/f02_signup/us01_create/fr01_store.md:1: required_field_missing',
    ]);
    expect(spots(checkOf(project, target: 'login'), missing), [
      '$loginFr:1: required_field_missing',
    ]);
  });

  const orphanFr = 'prds/features/f01_login/us03_export/fr01_send_file.md';
  const siblingOrphanFr = 'prds/features/f02_signup/us01_create/fr01_store.md';
  const orphanText = '---\ntraced_from:\n  - S9\n---\n\n# Send file\n';

  test('f04/us01/fr01/e11, cc-s03/inv12, cc-s03/inv13: an orphan FR under the target feature folder is '
      'parent_missing and runs no trace rule; one under another feature stays out', () async {
    final project = await writeCheckProject(
      extra: {
        'docs/$orphanFr': orphanText,
        'docs/$siblingOrphanFr': orphanText,
      },
    );
    expect(spots(checkOf(project), FindingKind.parentMissing), [
      '$orphanFr:1: parent_missing',
      '$siblingOrphanFr:1: parent_missing',
    ]);
    final targeted = checkOf(project, target: 'login');
    expect(spots(targeted, FindingKind.parentMissing), [
      '$orphanFr:1: parent_missing',
    ]);
    expect(spots(targeted, FindingKind.scenarioTraceUnresolved), isEmpty);
  });

  test('f04/us01/fr01/e12: an untyped file and a file that is not UTF-8 under the target folder get their own findings', () async {
    const untyped = 'prds/features/f01_login/notes.md';
    const latin = 'prds/features/f01_login/us02_reset/USER_STORY.md';
    const outside = 'prds/features/f02_signup/notes.md';
    final project = await writeCheckProject(
      extra: {'docs/$untyped': '# Notes\n', 'docs/$outside': '# Notes\n'},
    );
    File('${project.path}/docs/$latin')
      ..createSync(recursive: true)
      ..writeAsBytesSync(
        latin1.encode('---\nstatus: planned\n---\n\n# Café\n'),
      );
    final report = checkOf(project, target: 'login');
    expect(spots(report, FindingKind.untypedDoc), ['$untyped:1: untyped_doc']);
    expect(spots(report, FindingKind.fileNotUtf8), ['$latin:1: file_not_utf8']);
    expect(report.warnings, isEmpty);
  });

  test(
    'f04/us01/fr01/e12, f04/us01/fr01/e14: an unreadable file under the target folder is file_unreadable; '
    'an fr target adds no folder, so the warning stays',
    skip: unreadablePathSkipReason(),
    () async {
      final project = await writeCheckProject();
      final path = '${project.path}/docs/$loginNf';
      Process.runSync('chmod', ['000', path]);
      addTearDown(() => Process.runSync('chmod', ['644', path]));
      final targeted = checkOf(project, target: 'login');
      expect(spots(targeted, FindingKind.fileUnreadable), [
        '$loginNf:1: file_unreadable',
      ]);
      expect(targeted.warnings, isEmpty);
      final fr = checkOf(
        project,
        target: 'fr:login/email_login/check_password',
      );
      expect(spots(fr, FindingKind.fileUnreadable), isEmpty);
      expect(fr.warnings, ['$loginNf: cannot be read; skipped']);
    },
  );

  test("f04/us01/fr01/e13: a story target reaches the files under its own folder, not the sibling story's", () async {
    const own = 'prds/features/f01_login/us01_email_login/notes.md';
    const sibling = 'prds/features/f01_login/us02_reset/notes.md';
    final project = await writeCheckProject(
      extra: {'docs/$own': '# Notes\n', 'docs/$sibling': '# Notes\n'},
    );
    expect(
      spots(
        checkOf(project, target: 'user_story:login/email_login'),
        FindingKind.untypedDoc,
      ),
      ['$own:1: untyped_doc'],
    );
    expect(spots(checkOf(project, target: 'login'), FindingKind.untypedDoc), [
      '$own:1: untyped_doc',
      '$sibling:1: untyped_doc',
    ]);
  });

  test('f04/us01/fr01/e14: an fr target adds no folder; a sibling file and a sibling FR stay out', () async {
    const notes = 'prds/features/f01_login/us01_email_login/notes.md';
    const sibling = 'prds/features/f01_login/us01_email_login/fr02_other.md';
    final project = await writeCheckProject(
      extra: {
        'docs/$notes': '# Notes\n',
        'docs/$sibling': checkProjectFiles()['docs/$loginFr']!.replaceFirst(
          'verify_method: test\n',
          '',
        ),
      },
    );
    final report = checkOf(
      project,
      target: 'fr:login/email_login/check_password',
    );
    expect(spots(report), isNot(contains('$notes:1: untyped_doc')));
    expect(spots(report, FindingKind.requiredFieldMissing), isEmpty);
    expect(
      spots(
        checkOf(project, target: 'login'),
        FindingKind.requiredFieldMissing,
      ),
      ['$sibling:1: required_field_missing'],
    );
  });

  test('f04/us01/fr01/e15, cc-s03/inv12: a spec doc target reports its own file, not the spec doc beside it', () async {
    final project = await writeCheckProject(
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
    );
    const missing = FindingKind.linkTargetMissing;
    expect(spots(checkOf(project, target: 'architecture:login'), missing), [
      '$loginArchitecture:11: link_target_missing',
    ]);
    expect(spots(checkOf(project, target: 'api:login'), missing), [
      '$loginApi:19: link_target_missing',
    ]);
  });

  test('f04/us01/fr01/e16, cc-s03/inv12: a feature target reports the feature folder and its spec folder', () async {
    final project = await writeCheckProject(
      extra: {
        ...doc(
          loginApi,
          'Signs the Agent in.',
          'Signs the Agent in. See [x](../../../nowhere.md).',
        ),
        'docs/specs/f02_signup/API.md':
            '# Sign up API\n\nSee [z](../../../nowhere.md).\n',
        'docs/prds/features/f01_login/notes.md': '# Notes\n',
        'docs/prds/features/f02_signup/notes.md': '# Notes\n',
      },
    );
    final report = checkOf(project, target: 'feature:login');
    expect(spots(report, FindingKind.linkTargetMissing), [
      '$loginApi:19: link_target_missing',
    ]);
    expect(spots(report, FindingKind.untypedDoc), [
      'prds/features/f01_login/notes.md:1: untyped_doc',
    ]);
  });

  test('f04/us01/fr01/e17, cc-s03/inv12: an untyped DocPath target reports that one file', () async {
    const notes = 'prds/features/f01_login/notes.md';
    const sibling = 'prds/features/f01_login/other.md';
    final project = await writeCheckProject(
      extra: {'docs/$notes': '# Notes\n', 'docs/$sibling': '# Other\n'},
    );
    expect(spots(checkOf(project, target: notes), FindingKind.untypedDoc), [
      '$notes:1: untyped_doc',
    ]);
  });

  test('f04/us01/fr01/e03: a typed name checks that doc only', () async {
    final project = await writeCheckProject(
      extra: {
        'docs/$loginStory': checkProjectFiles()['docs/$loginStory']!
            .replaceFirst('---\n\n', 'priority: high\n---\n\n'),
        'docs/$loginFr': checkProjectFiles()['docs/$loginFr']!.replaceFirst(
          'verify_method: test\n',
          'priority: high\nverify_method: test\n',
        ),
      },
    );
    expect(spots(checkOf(project), FindingKind.fieldUndeclared), hasLength(2));
    expect(
      spots(
        checkOf(project, target: 'fr:login/email_login/check_password'),
        FindingKind.fieldUndeclared,
      ),
      ['$loginFr:6: field_undeclared'],
    );
  });

  test('f04/us01/fr01/e05, f04/us01/fr01/e06: a name no doc carries, or an unknown doc type, is a fault', () async {
    final project = await writeCheckProject();
    expect(
      () => checkOf(project, target: 'login/emial_login'),
      throwsA(
        isA<IndexFault>().having(
          (f) => f.code,
          'code',
          IndexFaultCode.docNotFound,
        ),
      ),
    );
    expect(
      () => checkOf(project, target: 'nope:login'),
      throwsA(
        isA<TemplateFault>().having(
          (f) => f.code,
          'code',
          FaultCode.docTypeUnknown,
        ),
      ),
    );
  });

  test('cc-s03/inv1: a check writes no file of its own', () async {
    final project = await writeCheckProject();
    checkOf(project); // the first open builds the index
    Map<String, String> snapshot() => {
      for (final f in project.listSync(recursive: true).whereType<File>())
        if (!f.path.contains('index.sqlite'))
          f.path: base64.encode(f.readAsBytesSync()),
    };
    final before = snapshot();
    checkOf(project);
    expect(snapshot(), before);
  });

  test('the fixture edit helper names an anchor that does not occur', () {
    expect(
      () => fr('no such anchor', 'x'),
      throwsA(
        isA<ArgumentError>().having(
          (e) => e.toString(),
          'message',
          contains('no such anchor'),
        ),
      ),
    );
  });

  test("f08/us06/fr02, f08/us06/s3, f08/us06/fr02/e06: a doc check gives that doc's findings only", () async {
    final project = await writeCheckProject(
      extra: {
        ...doc(
          loginStory,
          'I reach my work',
          'I reach my work, see [gone](gone/USER_STORY.md)',
        ),
        ...fr('app/lib/login.dart:checkPassword', 'app/lib/gone.dart:X'),
      },
    );
    final story = checkOf(project, docPath: loginStory);
    expect(story.findings, isNotEmpty);
    expect(story.findings.map((f) => f.path).toSet(), {loginStory});
    expect(
      story.findings.map((f) => f.kind),
      contains(FindingKind.linkUnresolved),
    );
    final requirement = checkOf(project, docPath: loginFr);
    expect(requirement.findings, isNotEmpty);
    expect(requirement.findings.where((f) => f.path == loginStory), isEmpty);
  });

  test(
    'f08/us06/fr02/e06: a doc check gives no project-level finding',
    () async {
      final project = await writeCheckProject(
        extra: {
          ...doc(loginArchitecture, 'app/lib/', 'app/lib/login.dart'),
          'app/lib/extra.dart': 'class Extra {}\n',
        },
      );
      expect(spots(checkOf(project), FindingKind.codeUncovered), isNotEmpty);
      expect(
        spots(checkOf(project, docPath: projectDoc), FindingKind.codeUncovered),
        isEmpty,
      );
    },
  );

  test(
    'f08/us06/fr02: a feature doc check leaves out the docs under it',
    () async {
      final project = await writeCheckProject(
        extra: fr('app/lib/login.dart:checkPassword', 'app/lib/gone.dart:X'),
      );
      expect(
        checkOf(project, target: 'feature:login').findings.map((f) => f.path),
        contains(loginFr),
      );
      expect(
        checkOf(project, docPath: loginFeature).findings.map((f) => f.path),
        isNot(contains(loginFr)),
      );
    },
  );

  test('f08/us06/fr02/e07: an untyped .md file in prds/ gets its untyped_doc finding', () async {
    final project = await writeCheckProject(
      extra: {'docs/prds/notes.md': '# Notes\n'},
    );
    expect(
      spots(checkOf(project, docPath: 'prds/notes.md'), FindingKind.untypedDoc),
      ['prds/notes.md:1: untyped_doc'],
    );
  });

  test('f08/us06/fr02: runCheck with both a target and a docPath throws ArgumentError', () async {
    final project = await writeCheckProject();
    expect(
      () => checkOf(project, target: 'login', docPath: loginStory),
      throwsArgumentError,
    );
  });

  test('f08/us06/fr02, sf-c2: checking a sub-feature scopes to its subtree and its spec folder', () async {
    final project = await writeNestedProject(
      extra: {
        'docs/$cartAddFr': '# Check the stock\n',
        'docs/$payCard': '# Agent pays by card\n',
        'docs/$cartDomain': '# Cart domain\n',
        'docs/$shopDomain': '# Shop domain\n',
      },
    );
    final paths = {
      for (final f in checkOf(project, target: 'feature:shop/cart').findings)
        f.path,
    };
    expect(paths, isNotEmpty);
    expect(
      paths.where(
        (p) =>
            !p.startsWith('prds/features/f02_shop/f01_cart/') &&
            !p.startsWith('specs/f02_shop/f01_cart/'),
      ),
      isEmpty,
    );
  });
  test('consistency_check/find_template_breaks/report_stale_agent_blocks E08: a check with a target holds no agent_block_stale', () async {
    final project = await writeCheckProject(
      extra: {'.specstone/AGENT.md': 'hand edit\n'},
    );

    expect(spots(checkOf(project), FindingKind.agentBlockStale), [
      '.specstone/AGENT.md:1: agent_block_stale',
    ]);
    expect(
      spots(checkOf(project, target: 'login'), FindingKind.agentBlockStale),
      isEmpty,
    );
  });

  test('consistency_check/find_template_breaks/print_findings INV-14: an agent file finding sorts by path with the doc findings', () async {
    final project = await writeCheckProject(
      extra: {'.specstone/AGENT.md': 'hand edit\n'},
    );
    final paths = [for (final f in checkOf(project).findings) f.path];

    expect(paths, contains('.specstone/AGENT.md'));
    expect(paths, [...paths]..sort());
  });

  test('consistency_check/find_template_breaks/print_findings E12: an owner '
      'finding counts, sorts, and exits 1 beside an agent finding', () async {
    final project = await writeCheckProject(
      extra: {
        '.specstone/AGENT.md': 'hand edit\n',
        'docs/prds/d01_context.md': '# Context\n',
      },
    );
    final report = checkOf(project);

    expect(
      {for (final f in report.findings) f.kind: f.waitsFor},
      {
        FindingKind.agentBlockStale: WaitsFor.owner,
        FindingKind.untypedDoc: WaitsFor.agent,
      },
    );
    expect(report.exitStatus, 1);
    expect(report.json['count'], 2);
    expect(report.text, contains('2 findings\n'));
    expect(
      report.text
          .split('\n')
          .where((l) => l.endsWith(' (waits for the Owner)')),
      hasLength(1),
    );
  });

  test('consistency_check/find_template_breaks/report_open_tbrs: the run '
      'reports an open TBR of each typed doc in scope, counted and exit 1, '
      'and none outside the target', () async {
    const open = 'TBR \u2014 2 s';
    final project = await writeCheckProject(
      extra: {
        ...fr(checkPasswordStatement, '$checkPasswordStatement $open'),
        'docs/prds/features/f02_signup/FEATURE.md': '# Sign up\n',
      },
    );
    final whole = checkOf(project);
    final tbr = [
      for (final f in whole.findings)
        if (f.kind == FindingKind.tbrOpen) f,
    ];

    expect(tbr, hasLength(1));
    expect(tbr.single.path, loginFr);
    expect(tbr.single.waitsFor, WaitsFor.owner);
    expect(whole.exitStatus, 1);
    expect(
      whole.text,
      contains('${tbr.single.textLine} (waits for the Owner)\n'),
    );
    expect(spots(checkOf(project, target: 'login'), FindingKind.tbrOpen), [
      '$loginFr:${tbr.single.line}: tbr_open',
    ]);
    expect(
      spots(checkOf(project, target: 'feature:signup'), FindingKind.tbrOpen),
      isEmpty,
    );
  });

  group('consistency_check/find_template_breaks/check_target, code targets', () {
    const flutter = CodeTarget('flutter', codeRoot: 'flutter_ws');
    const jaspr = CodeTarget('jaspr', codeRoot: 'jaspr_ws');
    const flutterArch = 'specs/flutter/f01_login/ARCHITECTURE.md';
    const jasprArch = 'specs/jaspr/f01_login/ARCHITECTURE.md';
    const brokenLink = ' See [x](../../../nowhere.md).';

    // The two-target project: `architecture` is per-target, one twin per
    // target; the API doc stays shared. Every doc but the story holds one
    // broken link, so each finding names the doc it came from.
    Future<Directory> twinProject({Map<String, String> extra = const {}}) {
      final files = checkProjectFiles();
      // The twins read as approved: the helper's stamp skips a per-target path.
      final twin = withApprovalHash(
        toLf(
          files['docs/$loginArchitecture']!.replaceFirst(
            'One box.',
            'One box.$brokenLink',
          ),
        ),
        fixtureDocTypeOf(loginArchitecture),
      );
      return writeCheckProject(
        without: {'docs/$loginArchitecture', 'app/lib/login.dart'},
        extra: {
          '.specstone/config.yaml':
              '${shippedPinsConfig()}targets:\n'
              '  flutter:\n    code_root: flutter_ws\n'
              '  jaspr:\n    code_root: jaspr_ws\n',
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
          'docs/$flutterArch': twin,
          'docs/$jasprArch': twin,
          ...edit(loginApi, [
            ('Signs the Agent in.', 'Signs the Agent in.$brokenLink'),
          ]),
          ...edit(loginFeature, [
            ('Users forget passwords.', 'Users forget passwords.$brokenLink'),
          ]),
          'flutter_ws/app/lib/login.dart': 'class SignInPage {}\nclass FlutterSignIn {}\nbool checkPassword(String p) => p.isNotEmpty;\n',
          'jaspr_ws/app/lib/login.dart': 'class SignInPage {}\nclass JasprSignIn {}\nbool checkPassword(String p) => p.isNotEmpty;\n',
          ...extra,
        },
      );
    }

    CheckReport runTwin(
      Directory project, {
      String? target,
      String? codeTarget,
    }) {
      final session = openSession(project);
      addTearDown(session.close);
      return runCheck(session, target: target, codeTarget: codeTarget);
    }

    Set<String> pathsOf(CheckReport report) => {
      for (final finding in report.findings) finding.path,
    };

    test('the two-target fixture reads each doc once: only the planted links are findings', () async {
      final report = runTwin(await twinProject());
      expect(pathsOf(report), {loginFeature, loginApi, flutterArch, jasprArch});
      expect(spots(report).length, 4, reason: spots(report).join('\n'));
    });

    // `login` names the feature and each twin; `feature:login` names the
    // feature alone, so the spec folders come from its unit.
    for (final name in ['login', 'feature:login']) {
      test(
        'E20: check $name with two targets reports the feature folder and each target spec folder',
        () async {
          final project = await twinProject();
          expect(pathsOf(runTwin(project, target: name)), {
            loginFeature,
            loginApi,
            flutterArch,
            jasprArch,
          });
        },
      );

      test(
        'E20: check $name --target jaspr keeps the PRD files, the shared docs, and that target spec folder',
        () async {
          final project = await twinProject();
          expect(pathsOf(runTwin(project, target: name, codeTarget: 'jaspr')), {
            loginFeature,
            loginApi,
            jasprArch,
          });
          expect(
            pathsOf(runTwin(project, target: name, codeTarget: 'flutter')),
            {loginFeature, loginApi, flutterArch},
          );
        },
      );
    }

    test('E21: check with no target reports every target, each finding at the DocPath of its target', () async {
      final project = await twinProject(
        extra: {'.specstone/AGENT.md': 'hand edit\n'},
      );
      final report = runTwin(project);
      expect(pathsOf(report), containsAll([flutterArch, jasprArch]));
      expect(spots(report, FindingKind.agentBlockStale), [
        '.specstone/AGENT.md:1: agent_block_stale',
      ]);
    });

    test('E21: check --target jaspr keeps the shared docs and jaspr, the project-level findings too', () async {
      final project = await twinProject(
        extra: {'.specstone/AGENT.md': 'hand edit\n'},
      );
      final report = runTwin(project, codeTarget: 'jaspr');
      expect(pathsOf(report), containsAll([loginFeature, loginApi, jasprArch]));
      expect(pathsOf(report), isNot(contains(flutterArch)));
      expect(spots(report, FindingKind.agentBlockStale), [
        '.specstone/AGENT.md:1: agent_block_stale',
      ]);
    });

    test('E22: a --target name targets: lacks is argument_invalid naming the targets, alone or beside a doc target', () async {
      final project = await twinProject();
      for (final target in [null, 'login']) {
        expect(
          () => runTwin(project, target: target, codeTarget: 'web'),
          throwsA(
            isA<IndexFault>()
                .having((f) => f.code, 'code', IndexFaultCode.argumentInvalid)
                .having(
                  (f) => f.message,
                  'message',
                  '--target web: the code targets are flutter, jaspr',
                ),
          ),
          reason: 'target: $target',
        );
      }
    });

    test('E22: a --target name on a project with one unnamed target is argument_invalid', () async {
      final project = await writeCheckProject();
      expect(
        () => runTwin(project, codeTarget: 'web'),
        throwsA(
          isA<IndexFault>().having(
            (f) => f.message,
            'message',
            '--target web: this project names no code target',
          ),
        ),
      );
    });

    test(
      'INV-32: CheckScope.targets holds every target, or the one named',
      () async {
        final session = openSession(await twinProject());
        addTearDown(session.close);
        final context = CheckContext(session);
        expect(CheckScope.project(context).targets, [flutter, jaspr]);
        expect(CheckScope.project(context, codeTarget: 'jaspr').targets, [
          jaspr,
        ]);
        expect(CheckScope.of(context, 'login').targets, [flutter, jaspr]);
        expect(CheckScope.of(context, 'login', codeTarget: 'flutter').targets, [
          flutter,
        ]);
        expect(CheckScope.doc(context, loginFr).targets, [flutter, jaspr]);
        final plain = openSession(await writeCheckProject());
        addTearDown(plain.close);
        expect(CheckScope.project(CheckContext(plain)).targets, [
          const CodeTarget(null, codeRoot: '.'),
        ]);
      },
    );

    test(
      'INV-32: the context reads each target code root and code text apart',
      () async {
        final session = openSession(await twinProject());
        addTearDown(session.close);
        final context = CheckContext(session);
        expect(context.codeRootOf(flutter).path, endsWith('flutter_ws'));
        expect(context.codeRootOf(jaspr).path, endsWith('jaspr_ws'));
        expect(
          context.codeTextOf(flutter, 'app/lib/login.dart'),
          contains('FlutterSignIn'),
        );
        expect(
          context.codeTextOf(jaspr, 'app/lib/login.dart'),
          contains('JasprSignIn'),
        );
        expect(context.codeFilesRead, 2);
        expect(context.codeTextOf(jaspr, 'app/lib/gone.dart'), isNull);
        expect(context.unstatedWarnings, hasLength(1));
      },
    );
  });
}
