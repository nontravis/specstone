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

  test('the invariants lint frees Enforcer by the entity default and '
      'Consistency by optional', () {
    final fields = sectionOf(domain, 'invariants').itemFields!;
    expect(
      [for (final f in fields) f.field],
      ['Enforcer', 'Consistency', 'Corrective policy'],
    );
    final [enforcer, consistency, policy] = fields;
    expect(enforcer.defaultFrom, 'entities');
    expect(enforcer.optional, isFalse);
    expect(enforcer.when, isNull);
    expect(consistency.values, ['eventual']);
    expect(consistency.optional, isTrue);
    expect(consistency.defaultFrom, isNull);
    expect(policy.when!.field, 'Consistency');
    expect(policy.when!.value, 'eventual');
    expect(policy.values, isNull);
    expect(policy.optional, isFalse);
  });

  test('the invariants guide asks a field line only off the default', () {
    final description = sectionOf(domain, 'invariants').description!;
    expect(
      description,
      allOf(
        contains('- **<field>:** <text>'),
        contains('- **Enforcer:** <entity>'),
        contains('only off it'),
        contains('- **Consistency:** eventual'),
        contains('- **Corrective policy:** <how the system restores the rule>'),
        contains('no Consistency line means immediate'),
        isNot(contains('- **Consistency:** immediate')),
      ),
    );
    expect(description, isNot(contains('<aggregate root>')));
  });

  test('the value objects and lifecycle guides follow their section '
      'points', () {
    final valueObjects = sectionOf(domain, 'value_objects').description!;
    expect(
      valueObjects,
      allOf(
        contains('Make each value object immutable'),
        contains('Validation'),
        contains('link an invariant for any rule on it'),
      ),
    );
    final lifecycle = sectionOf(domain, 'lifecycle').description!;
    expect(
      lifecycle,
      allOf(
        contains('`stateDiagram-v2` alone, no prose'),
        contains('4 or more states'),
      ),
    );
  });

  test('the invariant form states no sentence count', () {
    final invariants = sectionOf(domain, 'invariants');
    expect(invariants.description, isNot(contains('<one sentence>')));
    expect(
      invariants.description,
      contains('Write each invariant as `- **INV-<N>** <rule>`'),
    );
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
