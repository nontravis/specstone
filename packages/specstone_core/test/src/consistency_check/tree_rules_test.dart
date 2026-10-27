// The expected texts are plan literals kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/consistency_check/check_run.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/index_query/read_session.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/fixture_doc_types.dart';
import '../../helpers/posix_modes.dart';

void main() {
  test('f04/us01/s5, f04/us01/fr06/e01, f04/us01/fr06/e02: a file in a checked folder no pattern matches is '
      'untyped; a file outside them gets no check', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: {
          'docs/notes/2026-10-27-ideas.md':
              '---\npriority: high\n---\n\nNo title.\n',
          'docs/prds/features/f01_login/us02_Reset_Password/USER_STORY.md':
              '# Capitals\n',
        },
      ),
    );
    expect(spots(report), [
      'prds/features/f01_login/us02_Reset_Password/USER_STORY.md:1: untyped_doc',
    ]);
  });

  test('f04/us01/fr06/e05, f04/us01/fr06/e06: a project path pattern adds its folder; two matching patterns are '
      'doc_type_ambiguous, and its warning is not printed', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: {
          '.specstone/templates/runbook.yaml': 'id: runbook\ndescription: Run steps.\npath: ops/{slug}/runbook.md\n',
          '.specstone/templates/playbook.yaml':
              'id: playbook\ndescription: Plays.\npath: ops/deploy/{slug}.md\n',
          'docs/ops/deploy/runbook.md': '# Deploy\n',
          'docs/ops/other.md': '# Other\n',
        },
      ),
    );
    expect(spots(report), [
      'ops/deploy/runbook.md:1: doc_type_ambiguous',
      'ops/other.md:1: untyped_doc',
    ]);
    expect(
      report.findings.first.toJson()['docTypes'],
      unorderedEquals(['runbook', 'playbook']),
    );
    expect(report.warnings, isEmpty);
  });

  test('f04/us01/fr07/e01, f04/us01/fr07/e02: two stories numbered us01 under one feature are reported on each; '
      'an fr01 and an nf01 are no siblings', () async {
    const reset = 'prds/features/f01_login/us01_reset_password/USER_STORY.md';
    final report = checkOf(
      await writeCheckProject(extra: {'docs/$reset': '# Reset\n'}),
    );
    expect(spots(report, FindingKind.orderNumberDuplicate), [
      '$loginStory:1: order_number_duplicate',
      '$reset:1: order_number_duplicate',
    ]);
    expect(
      report.findings
          .firstWhere((f) => f.kind == FindingKind.orderNumberDuplicate)
          .toJson()['siblings'],
      [reset],
    );
  });

  test('f04/us01/s7, f04/us01/fr07/e03, f04/us04/fr01/e09, cc-s03/inv13: a requirement whose story is gone has no '
      'parent and no trace or suspect finding', () async {
    final report = checkOf(
      await writeCheckProject(without: {'docs/$loginStory'}),
    );
    expect(
      [
        for (final f in report.findings)
          if (f.path == loginFr) f.kind,
      ],
      [FindingKind.parentMissing],
    );
    expect(
      [
        for (final f in report.findings)
          if (f.path == loginNf) f.kind,
      ],
      [FindingKind.parentMissing],
    );
  });

  test('f04/us01/fr07/e04: a spec doc whose feature does not exist is parent_missing', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: {
          'docs/specs/f03_billing/API.md':
              '# Billing API\n\n## FR trace\n| FR | Operation |\n|----|-----------|\n\n'
              '## Operations\nNone.\n',
        },
      ),
    );
    expect(spots(report), ['specs/f03_billing/API.md:1: parent_missing']);
  });

  test('f04/us01/fr07/e05: two features named login make their children parent_ambiguous, warning not printed', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: {
          'docs/prds/features/f02_login/FEATURE.md':
              checkProjectFiles()['docs/$loginFeature']!,
        },
      ),
    );
    expect(spots(report, FindingKind.parentAmbiguous), [
      '$loginStory:1: parent_ambiguous',
      '$loginApi:1: parent_ambiguous',
      '$loginArchitecture:1: parent_ambiguous',
    ]);
    expect(report.warnings, isEmpty);
  });

  test('f04/us01/fr07/e06: a Latin-1 file is file_not_utf8, its warning not printed', () async {
    final project = await writeCheckProject();
    const reset = 'prds/features/f01_login/us02_reset/USER_STORY.md';
    File('${project.path}/docs/$reset')
      ..createSync(recursive: true)
      ..writeAsBytesSync(
        latin1.encode('---\nstatus: planned\n---\n\n# Reset at the café\n'),
      );
    final report = checkOf(project);
    expect(spots(report, FindingKind.fileNotUtf8), ['$reset:1: file_not_utf8']);
    expect(report.warnings, isEmpty);
  });

  test(
    'f04/us01/fr07/e07: a doc whose mode refuses reading is file_unreadable',
    skip: unreadablePathSkipReason(),
    () async {
      final project = await writeCheckProject();
      final path = '${project.path}/docs/$loginNf';
      Process.runSync('chmod', ['000', path]);
      addTearDown(() => Process.runSync('chmod', ['644', path]));
      final report = checkOf(project);
      expect(spots(report, FindingKind.fileUnreadable), [
        '$loginNf:1: file_unreadable',
      ]);
      expect(
        report.findings
            .firstWhere((f) => f.kind == FindingKind.fileUnreadable)
            .name,
        isNull,
      );
      expect(report.warnings, isEmpty);
      final targeted = checkOf(project, target: 'login');
      expect(spots(targeted, FindingKind.fileUnreadable), [
        '$loginNf:1: file_unreadable',
      ]);
      expect(targeted.warnings, isEmpty);
    },
  );

  test(
    'f04/us01/fr07/e08: a doc type with no parent is never parent_missing',
    () async {
      final report = checkOf(
        await writeCheckProject(
          extra: {
            '.specstone/templates/runbook.yaml': 'id: runbook\ndescription: Run steps.\npath: ops/{slug}/runbook.md\n',
            'docs/ops/deploy/runbook.md': '# Deploy\n',
          },
        ),
      );
      expect(spots(report, FindingKind.parentMissing), isEmpty);
    },
  );

  test('f04/us01/fr04/e08: a merged set with no project doc type runs no vision quote rule', () async {
    final project = await fixtureProject({
      'docs/prds/d01_context.md':
          '# Context\n\n## Project vision\n### PV-01 — X\nNo quote line.\n',
    });
    final session = ReadSession.open(
      templates: TemplateResolver(shippedFiles: fixturePackFiles()),
      workingDirectory: project,
      homeDirectory: null,
    );
    addTearDown(session.close);
    expect(spots(runCheck(session), FindingKind.visionQuoteMissing), isEmpty);
  });
}
