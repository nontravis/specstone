// The expected texts are plan literals kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/shipped_pins.dart';

void main() {
  const rules = 'prds/references/login_rules/REFERENCE.md';
  const ruleDoc =
      '---\nsource: Team wiki\nfiles:\n  - spec.pdf\n  - notes.md\n---\n\n# Login rules\n\n'
      '## Summary\nThe rules.\n';
  const template =
      'reference:\n  add:\n    - title: Login rules\n      doc: login_rules\n';

  test('f04/us02/fr05/e01, f04/us02/fr05/e02: a template reference doc no doc carries is reported at the template, '
      'on a whole-project run only', () async {
    final project = await writeCheckProject(
      extra: {'.specstone/templates/fr.yaml': template},
    );
    expect(spots(checkOf(project)), [
      '.specstone/templates/fr.yaml:3: reference_doc_unresolved',
    ]);
    expect(checkOf(project).findings.single.name, isNull);
    expect(spots(checkOf(project, target: 'login')), isEmpty);
    final found = await writeCheckProject(
      extra: {
        '.specstone/templates/fr.yaml': template,
        'docs/$rules': ruleDoc.replaceFirst('  - notes.md\n', ''),
        'docs/prds/references/login_rules/spec.pdf': 'pdf',
      },
    );
    expect(spots(checkOf(found)), isEmpty);
  });

  test('f04/us02/s9, f04/us02/fr05/e03, f04/us02/fr05/e05: a listed file missing beside its reference doc, and a '
      'Concerns line pointing nowhere, are one finding each', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: {
          'docs/$rules': ruleDoc,
          'docs/prds/references/login_rules/spec.pdf': 'pdf',
          ...doc(
            loginArchitecture,
            '- Errors: see Components\n',
            '- Errors: see Components\n- Auth: see AUTH.md\n',
          ),
        },
      ),
    );
    expect(spots(report), [
      '$rules:5: listed_file_missing',
      '$loginArchitecture:16: concerns_target_unresolved',
    ]);
    expect(report.findings.last.toJson()['target'], 'AUTH.md');
  });

  test('f04/us02/fr05/e04, f04/us02/fr05/e06: a sibling file, a section of the doc, or N/A resolves', () async {
    final report = checkOf(
      await writeCheckProject(
        extra:
            {
              ...doc(
                loginArchitecture,
                '- Errors: see Components\n',
                '- Errors: see ERROR.md\n- Events: N/A — one request, one reply\n- Observability: see observability\n',
              ),
              'docs/specs/f01_login/ERROR.md': '# Login errors\n',
            }..update(
              'docs/$loginArchitecture',
              (text) => '$text\n## Observability\nLogs.\n',
            ),
      ),
    );
    expect(spots(report, FindingKind.concernsTargetUnresolved), isEmpty);
  });

  test('f04/us02/fr05/e07, cc-s03/inv2: a merged set with no architecture doc type runs no Concerns rule', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: {
          '.specstone/config.yaml': shippedPinsConfig(['prd-core']),
          ...doc(
            loginArchitecture,
            '- Errors: see Components\n',
            '- Auth: see AUTH.md\n',
          ),
        },
      ),
    );
    expect(spots(report, FindingKind.concernsTargetUnresolved), isEmpty);
  });
}
