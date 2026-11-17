import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/prd_core.dart';
import '../../helpers/software_tech.dart';

void main() {
  late MergedDocType domain;
  setUpAll(() async {
    domain = prdCoreDocType(await resolveSoftwareTech(), 'domain');
  });

  test('f03/us07/fr01, f03/us07/fr01/e06: domain sits under '
      'specs/f{nn}_{slug}/ with parent feature, the overrides and tasks '
      'fields, and eight sections', () {
    expect(domain.path, 'specs/f{nn}_{slug}/DOMAIN.md');
    expect(domain.parent, 'feature');
    expectOwnFields(domain, const [
      FieldSpec('overrides', FieldType.string, list: true),
      FieldSpec('tasks', FieldType.taskRef, list: true),
    ]);
    expectSections(domain, const [
      SectionSpec('entities', 'Entities', required: true),
      SectionSpec('value_objects', 'Value objects'),
      SectionSpec('invariants', 'Invariants', prefixId: 'INV-', required: true),
      SectionSpec('known_limits', 'Known limits'),
      SectionSpec('lifecycle', 'Lifecycle'),
      SectionSpec('data_touch', 'Data touch'),
      SectionSpec('commands_and_events', 'Commands and events'),
      SectionSpec('terms', 'Terms'),
    ]);
  });

  test('the invariants require a corrective policy on an eventual invariant '
      'only', () {
    final fields = domain.sections
        .singleWhere((s) => s.id == 'invariants')
        .itemFields!;
    expect(
      [for (final f in fields) f.field],
      ['Enforcer', 'Consistency', 'Corrective policy'],
    );
    final policy = fields.last;
    expect(policy.when!.field, 'Consistency');
    expect(policy.when!.value, 'eventual');
    expect(policy.values, isNull);
  });

  test('domain holds no corrective policies section', () {
    expect(
      domain.sections.map((s) => s.id),
      isNot(contains('corrective_policies')),
    );
  });

  // A draft takes no approval stamp, so the counts stay exact.
  const draft = '---\ndraft: true\n---\n\n';

  Future<Map<String, Object?>> overLimit(
    String docPath,
    String text,
    FindingKind kind,
  ) async {
    final report = await checkOf(
      await writeCheckProject(extra: {docPath: text}),
    );
    final finding = report.findings.singleWhere((f) => f.kind == kind);
    expect(finding.path, docPath.substring('docs/'.length));
    return finding.toJson();
  }

  test('a 50001-character DOMAIN.md gets '
      'chars_over_limit, limit 50000, actual 50001', () async {
    // The index counts the laid-out text: a blank line under the title and a
    // final line break.
    const title = '# Login domain\n';
    final json = await overLimit(
      'docs/specs/f01_login/DOMAIN.md',
      '$draft$title${'x' * (50001 - draft.length - title.length - 2)}',
      FindingKind.charsOverLimit,
    );
    expect(
      json,
      allOf(containsPair('limit', 50000), containsPair('actual', 50001)),
    );
  });

  test('a DOMAIN.md body of 301 non-blank lines gets '
      'lines_over_limit, limit 300', () async {
    final json = await overLimit(
      'docs/specs/f01_login/DOMAIN.md',
      '$draft# Login domain\n\n${List.filled(300, 'x').join('\n')}\n',
      FindingKind.linesOverLimit,
    );
    expect(
      json,
      allOf(containsPair('limit', 300), containsPair('actual', 301)),
    );
  });

  test(
    'a 50001-character project DOMAIN.md gets '
    'chars_over_limit, limit 50000, the limit it inherits from domain',
    () async {
      const title = '# Project domain\n';
      final json = await overLimit(
        'docs/specs/DOMAIN.md',
        '$draft$title${'x' * (50001 - draft.length - title.length - 2)}',
        FindingKind.charsOverLimit,
      );
      expect(
        json,
        allOf(containsPair('limit', 50000), containsPair('actual', 50001)),
      );
    },
  );
}
