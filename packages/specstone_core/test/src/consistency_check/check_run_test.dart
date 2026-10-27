import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/templates/template_fault.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';

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
}
