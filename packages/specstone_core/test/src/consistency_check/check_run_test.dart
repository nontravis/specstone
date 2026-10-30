// The test names and expected texts are plan literals kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/templates/template_fault.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/posix_modes.dart';

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
      ['$loginFr:5: field_undeclared'],
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
}
