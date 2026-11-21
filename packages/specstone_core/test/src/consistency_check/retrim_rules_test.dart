// The expected texts are plan literals kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';

const _layer = '.specstone/templates/fr.yaml';
const _disableRationale = 'sections:\n  - id: rationale\n    disabled: true\n';

/// The fixture FR with [retrimLines] under `retrim:`, its Verification section
/// emptied when [emptyVerification], under a project layer that disables
/// `rationale` when [disableRationale].
Map<String, String> _retrimProject(
  String retrimLines, {
  bool emptyVerification = false,
  bool disableRationale = false,
}) => {
  if (disableRationale) _layer: _disableRationale,
  ...edit(loginFr, [
    (
      '${fingerprintFor(loginScenario2)}\n---',
      '${fingerprintFor(loginScenario2)}\nretrim:\n$retrimLines\n---',
    ),
    if (emptyVerification) (loginFrVerification, '## Verification\n'),
  ]),
};

void main() {
  test(
    'a marked section the doc holds gives one finding at its header',
    () async {
      final project = await writeCheckProject(
        extra: _retrimProject('  - edge_cases'),
      );
      final report = await checkOf(project);
      final finding = report.findings.singleWhere(
        (f) => f.kind == FindingKind.retrimDue,
      );
      expect(
        '${finding.path}:${finding.line}',
        '$loginFr:${lineOfFirst(project, loginFr, '## Edge cases')}',
      );
      expect(finding.message, 'edge_cases waits for a trim against its guide');
      expect(finding.toJson()['section'], 'edge_cases');
      expect(finding.waitsFor, WaitsFor.agent);
    },
  );

  for (final (label, id, extra) in [
    ('absent', 'input_output', _retrimProject('  - input_output')),
    (
      'empty',
      'verification',
      _retrimProject('  - verification', emptyVerification: true),
    ),
    (
      'disabled',
      'rationale',
      _retrimProject('  - rationale', disableRationale: true),
    ),
  ]) {
    test(
      '$label: a marked section that is absent, empty, or disabled gives one finding at the retrim line',
      () async {
        final project = await writeCheckProject(extra: extra);
        final report = await checkOf(project);
        final finding = report.findings.singleWhere(
          (f) => f.kind == FindingKind.retrimDue,
        );
        expect(
          '${finding.path}:${finding.line}',
          '$loginFr:${lineOfFirst(project, loginFr, 'retrim:')}',
        );
        expect(finding.message, '$id is absent; drop the mark');
        expect(finding.toJson()['section'], id);
        expect(finding.waitsFor, WaitsFor.agent);
      },
    );
  }

  test('an id listed twice gives one finding', () async {
    final report = await checkOf(
      await writeCheckProject(
        extra: _retrimProject('  - edge_cases\n  - edge_cases'),
      ),
    );
    expect(spots(report, FindingKind.retrimDue), hasLength(1));
  });

  test('an undefined id or a scalar retrim gives no retrim finding', () async {
    for (final (label, extra) in [
      ('an undefined id', _retrimProject('  - no_such_section')),
      (
        'a scalar retrim',
        fr(
          '${fingerprintFor(loginScenario2)}\n---',
          '${fingerprintFor(loginScenario2)}\nretrim: edge_cases\n---',
        ),
      ),
      (
        'a list with a non-string item',
        fr(
          '${fingerprintFor(loginScenario2)}\n---',
          '${fingerprintFor(loginScenario2)}\nretrim:\n  - edge_cases\n  - a: b\n---',
        ),
      ),
    ]) {
      final report = await checkOf(await writeCheckProject(extra: extra));
      expect(spots(report, FindingKind.retrimDue), isEmpty, reason: label);
      expect(
        spots(report, FindingKind.fieldValueMismatch),
        isNotEmpty,
        reason: label,
      );
    }
  });

  test(
    'a header written with other case or trailing spaces still counts as held',
    () async {
      final project = await writeCheckProject(
        extra: edit(loginFr, [
          (
            '${fingerprintFor(loginScenario2)}\n---',
            '${fingerprintFor(loginScenario2)}\nretrim:\n  - edge_cases\n---',
          ),
          ('## Edge cases', '##  edge cases '),
        ]),
      );
      final report = await checkOf(project);
      final finding = report.findings.singleWhere(
        (f) => f.kind == FindingKind.retrimDue,
      );
      expect(
        '${finding.path}:${finding.line}',
        '$loginFr:${lineOfFirst(project, loginFr, 'edge cases')}',
      );
      expect(finding.message, 'edge_cases waits for a trim against its guide');
    },
  );

  test('a doc with no retrim gives none', () async {
    final report = await checkOf(
      await writeCheckProject(extra: {_layer: _disableRationale}),
    );
    expect(spots(report, FindingKind.retrimDue), isEmpty);
  });
}
