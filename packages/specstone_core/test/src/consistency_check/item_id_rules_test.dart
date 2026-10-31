// The expected texts are plan literals kept as written.

import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';

Future<List<Finding>> _itemIdFindings(
  Map<String, String> edits, {
  FindingKind kind = FindingKind.itemIdMissing,
}) async {
  final report = checkOf(await writeCheckProject(extra: edits));
  return [
    for (final f in report.findings)
      if (f.kind == kind) f,
  ];
}

Map<String, String> _storyRules(String body) => doc(
  loginStory,
  '## Acceptance Criteria',
  '## Rules\n$body\n\n## Acceptance Criteria',
);

void main() {
  test('f04/us01/fr09/e01: an item with no prefix ID reports its line, message, and keys', () async {
    final found = await _itemIdFindings(
      _storyRules('- **BR-01** — a\n1. BR-02 — b\n- a rule with no ID'),
    );
    expect(found, hasLength(1));
    expect(
      found.single.path,
      'prds/features/f01_login/us01_email_login/USER_STORY.md',
    );
    expect(found.single.line, 19);
    expect(found.single.message, 'the item opens with no BR- ID');
    expect(
      found.single.toJson(),
      allOf(containsPair('section', 'rules'), containsPair('prefix', 'BR-')),
    );
  });

  test('f04/us01/fr09/e02: a heading item lacks its ID; quote and Serves lines are no items', () async {
    final found = await _itemIdFindings(
      doc(
        projectDoc,
        '### PV-01 — One sign-in\n> en: One sign-in for every app.',
        '### One sign-in\n> en: One sign-in for every app.\n**Serves:** x',
      ),
    );
    expect(found, hasLength(1));
    expect(found.single.toJson(), containsPair('section', 'vision'));
    expect(found.single.message, 'the item opens with no PV- ID');
  });

  test(
    'f04/us01/fr09/e03: N/A items and nested bullets are no items',
    () async {
      final found = await _itemIdFindings({
        ...doc(
          gnfrDoc,
          '## Security\nN/A — none applies.',
          '## Security\n- N/A — no target applies',
        ),
        ..._storyRules('- **BR-01** — a\n  - detail of the rule'),
      });
      expect(found, isEmpty);
    },
  );

  test('f04/us01/fr09/e04: a repeated ID reports the second item with the first line', () async {
    final found = await _itemIdFindings(
      doc(
        projectDoc,
        '## Project goals',
        '### PV-01 — Again\n\n## Project goals',
      ),
      kind: FindingKind.itemIdDuplicate,
    );
    expect(found, hasLength(1));
    expect(found.single.line, 14);
    expect(found.single.message, 'PV-01 is already held at line 11');
    expect(
      found.single.toJson(),
      allOf(containsPair('id', 'PV-01'), containsPair('section', 'vision')),
    );
  });

  test('f04/us01/fr09/e05: a domain invariant with a bold ID passes', () async {
    final found = await _itemIdFindings({
      'docs/specs/f01_login/DOMAIN.md':
          '# Login domain\n\n## Entities\n- Account\n\n'
          '## Invariants\n- **INV-1** — an email is unique\n',
    });
    expect(found, isEmpty);
  });
}
