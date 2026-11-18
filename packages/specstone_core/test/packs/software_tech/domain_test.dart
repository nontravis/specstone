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

  test('domain sits under '
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

  test('an eventual invariant with no nested corrective policy gets '
      'item_field_missing for Corrective policy', () async {
    final report = await checkOf(
      await writeCheckProject(
        extra: {
          'docs/specs/f01_login/DOMAIN.md':
              '$draft# Login domain\n\n## Entities\n'
              '| Entity | Kind | Description |\n|---|---|---|\n'
              '| Account | Aggregate root | A login |\n\n'
              '## Invariants\n'
              '- **INV-1** An account mails its owner after a lock.\n'
              '  - **Enforcer:** Account\n'
              '  - **Consistency:** eventual\n',
        },
      ),
    );

    final json = report.findings
        .singleWhere((f) => f.kind == FindingKind.itemFieldMissing)
        .toJson();
    expect(json, containsPair('field', 'Corrective policy'));
  });

  test('a bullet under the Components table of an ARCHITECTURE.md gets '
      'pattern_banned at that bullet', () async {
    final report = await checkOf(
      await writeCheckProject(
        extra: {
          'docs/specs/f01_login/ARCHITECTURE.md':
              '$draft# Login architecture\n\n## Components\n'
              '| Component | Responsibility |\n|---|---|\n'
              '| Gate | Checks the password |\n\n'
              '- Gate also logs each attempt\n',
        },
      ),
    );

    final finding = report.findings.singleWhere(
      (f) => f.kind == FindingKind.patternBanned,
    );
    expect(finding.path, 'specs/f01_login/ARCHITECTURE.md');
    expect(finding.toJson(), containsPair('line', 12));
  });

  test('the invariants description states the bullet shape with the '
      'enforcer, consistency, and corrective policy bullets', () {
    final description = domain.sections
        .singleWhere((s) => s.id == 'invariants')
        .description;

    expect(
      description,
      allOf(
        contains('- **INV-<N>** <one sentence>'),
        contains('- **Enforcer:** <aggregate root>'),
        contains('- **Consistency:** immediate'),
        contains('- **Corrective policy:** <how the system restores the rule>'),
      ),
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
