import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/pattern_findings.dart';
import '../../helpers/prd_core.dart';
import '../../helpers/software_tech.dart';

const _securityPath = 'specs/f01_login/SECURITY.md';

const _threatsHeader =
    '| Element | STRIDE | Threat | Response | Residual risk | Proved by |\n'
    '|---|---|---|---|---|---|\n';

/// Returns the lines of a `security` doc's Threats [rows] that [pattern]
/// flags.
Future<List<String>> _flaggedThreats(String rows, String pattern) =>
    bannedLines(
      {
        'docs/$_securityPath':
            '---\ndraft: true\n---\n\n# Login security\n\n'
            '## Threats\n\n$_threatsHeader$rows',
      },
      _securityPath,
      pattern,
    );

void main() {
  late MergedDocType security;
  setUpAll(() async {
    security = prdCoreDocType(await resolveSoftwareTech(), 'security');
  });

  test('security sits under specs/f{nn}_{slug}/ with parent feature, the '
      'overrides and tasks fields, and the five sections of its row', () {
    expect(security.path, 'specs/f{nn}_{slug}/SECURITY.md');
    expect(security.parent, 'feature');
    expect(security.isPerTarget, isTrue);
    expectOwnFields(security, const [
      FieldSpec('overrides', FieldType.string, list: true),
      FieldSpec('tasks', FieldType.taskRef, list: true),
    ]);
    expectSections(security, const [
      SectionSpec('system_model', 'System model', required: true),
      SectionSpec('threats', 'Threats', required: true),
      SectionSpec('out_of_scope', 'Out of scope'),
      SectionSpec('enforcement', 'Enforcement', required: true),
      SectionSpec('audit', 'Audit', required: true),
    ]);
  });

  test('enforcement carries its one-line cap', () {
    expect(sectionOf(security, 'enforcement').maxLines, 1);
  });

  test('a threats row off the six STRIDE categories is stride_value, and '
      'each category passes', () async {
    const off = '| Login form | Phishing | Fake page | mitigate | low | t1 |';
    expect(
      await _flaggedThreats(
        '| Login form | Spoofing | Stolen password | mitigate | low | t1 |\n'
            '| Session | Tampering | Edited cookie | mitigate | low | t2 |\n'
            '| Audit | Repudiation | Denied sign-in | mitigate | low | t3 |\n'
            '| Token | Information disclosure | Leak | mitigate | low | t4 |\n'
            '| Gate | Denial of service | Flood | transfer | low | t5 |\n'
            '| Admin | Elevation of privilege | Edit | eliminate | low | t6 |\n'
            '$off\n',
        'stride_value',
      ),
      [off],
    );
  });

  test('a threats row whose Response reads ignore is response_value', () async {
    const ignored =
        '| Login form | Spoofing | Stolen password | ignore | high | t1 |';
    expect(
      await _flaggedThreats(
        '| Session | Tampering | Edited cookie | accept | low | t2 |\n'
            '$ignored\n',
        'response_value',
      ),
      [ignored],
    );
    expect(
      {
        for (final p in sectionOf(security, 'threats').bannedPatterns!)
          p.id: p.message,
      },
      {
        'stride_value': endsWith(
          'guide line: Write STRIDE as one of the six categories',
        ),
        'response_value': endsWith(
          'guide line: Write Response as mitigate, eliminate, transfer, or '
          'accept',
        ),
      },
    );
  });

  test('a SECURITY.md body of 301 non-blank lines gets lines_over_limit, '
      'limit 300', () async {
    const docPath = 'docs/$_securityPath';
    final report = await checkOf(
      await writeCheckProject(
        extra: {
          docPath:
              '---\ndraft: true\n---\n\n# Login security\n\n'
              '${List.filled(300, 'x').join('\n')}\n',
        },
      ),
    );

    final finding = report.findings.singleWhere(
      (f) => f.kind == FindingKind.linesOverLimit,
    );
    expect(finding.path, _securityPath);
    expect(
      finding.toJson(),
      allOf(containsPair('limit', 300), containsPair('actual', 301)),
    );
  });

  test('security lists its four sources in table order', () {
    for (final r in security.reference!) {
      expect(r.url, startsWith('https://'), reason: r.title);
      expect(r.locator, isNotEmpty, reason: r.title);
    }
  });
}
