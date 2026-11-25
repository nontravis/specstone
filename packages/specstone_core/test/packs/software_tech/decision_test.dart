import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:test/test.dart';

import '../../helpers/prd_core.dart';
import '../../helpers/software_tech.dart';

void main() {
  late MergedDocType decision;
  setUpAll(() async {
    decision = prdCoreDocType(await resolveSoftwareTech(), 'decision');
  });

  test('decision sits in the one specs/decisions/ folder with no parent, no '
      'per-target key, fixed numbers, and the six sections of its row', () {
    expect(decision.path, 'specs/decisions/d{nn}_{slug}.md');
    expect(decision.parent, isNull);
    expect(decision.isPerTarget, isFalse);
    expect(decision.fixedNumbers, isTrue);
    expect(decision.bundle, isNull);
    expectSections(decision, const [
      SectionSpec('context', 'Context', required: true),
      SectionSpec('drivers', 'Drivers'),
      SectionSpec('options', 'Options', required: true),
      SectionSpec('outcome', 'Outcome', required: true),
      SectionSpec('consequences', 'Consequences', required: true),
      SectionSpec('confirmation', 'Confirmation'),
    ]);
  });

  test('superseded_by is an optional link to the decision that replaces '
      'it, then the shared tasks field', () {
    expectOwnFields(decision, const [
      FieldSpec('superseded_by', FieldType.docRef, docTypes: ['decision']),
      FieldSpec('tasks', FieldType.taskRef, list: true),
    ]);
  });

  test('decision lists its four sources in table order', () {
    expect(
      [for (final r in decision.reference!) r.title],
      [
        'Michael Nygard, Documenting Architecture Decisions',
        'MADR template',
        'arc42 section 9, Architecture Decisions',
        'ISO/IEC/IEEE 42010 conceptual model',
      ],
    );
    for (final r in decision.reference!) {
      expect(r.url, startsWith('http'), reason: r.title);
      expect(r.locator, isNotEmpty, reason: r.title);
    }
  });
}
