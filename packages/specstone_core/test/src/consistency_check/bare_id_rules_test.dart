import 'dart:io';

import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/target_fixture.dart';

const _domain = 'specs/f01_login/DOMAIN.md';

/// The login domain, whose `## Invariants` holds INV-6.
const _domainFile = {
  'docs/$_domain':
      '# Login domain\n\n## Entities\n\n- Account\n\n'
      '## Invariants\n\n- **INV-6** An account holds one email.\n',
};

/// The path from the login feature to the login domain.
const _domainFromFeature = '../../../specs/f01_login/DOMAIN.md';

/// The path from the login FR to the login domain.
const _domainFromFr = '../../../../specs/f01_login/DOMAIN.md';

/// The body line of the login feature that the tests replace.
const _featureLine = 'Users forget passwords.';

/// The body line of the login FR that the tests replace.
const _frLine = 'A wrong password must not sign in.';

const Set<FindingKind> _judged = {
  FindingKind.itemMentionMissing,
  FindingKind.linkItemMissing,
  FindingKind.linkUnresolved,
};

Future<List<Finding>> _judgedIn(
  Directory project, [
  Set<FindingKind> kinds = _judged,
]) async => [
  for (final finding in (await checkOf(project)).findings)
    if (kinds.contains(finding.kind)) finding,
];

Future<Directory> _projectWith(Map<String, String> edit) =>
    writeCheckProject(extra: {..._domainFile, ...edit});

Future<Directory> _featureWith(String text) =>
    _projectWith(doc(loginFeature, _featureLine, text));

Future<Directory> _frWith(String text) =>
    _projectWith(doc(loginFr, _frLine, text));

/// The owner DocPath each finding names, by the item ID it names.
Map<String, String> _targetsOf(List<Finding> findings) => {
  for (final finding in findings)
    finding.keys['item']! as String: finding.keys['target']! as String,
};

void main() {
  test('a bare ID its own doc lacks is item_mention_missing with item and '
      'target', () async {
    final project = await _frWith('$_frLine See E07.');
    final findings = await _judgedIn(project);
    expect(findings, hasLength(1));
    final finding = findings.single;
    expect(finding.kind, FindingKind.itemMentionMissing);
    expect(finding.path, loginFr);
    expect(finding.line, lineOfFirst(project, loginFr, 'See E07.'));
    expect(finding.waitsFor, WaitsFor.agent);
    expect(finding.keys, {'item': 'E07', 'target': loginFr});
    expect(finding.message, 'bare ID E07 is no item of $loginFr');
  });

  test('a bare ID after a doc link names that doc as target when it lacks '
      'the ID', () async {
    final project = await _featureWith(
      '$_featureLine [domain:login]($_domainFromFeature) INV-9.',
    );
    final findings = await _judgedIn(project);
    expect(findings, hasLength(1));
    expect(findings.single.kind, FindingKind.itemMentionMissing);
    expect(findings.single.path, loginFeature);
    expect(findings.single.line, lineOfFirst(project, loginFeature, 'INV-9'));
    expect(findings.single.keys, {'item': 'INV-9', 'target': _domain});
  });

  test('only the missing ID of a run gives a finding', () async {
    final findings = await _judgedIn(
      await _featureWith(
        '$_featureLine [domain:login]($_domainFromFeature) INV-6 and INV-9.',
      ),
    );
    expect(_targetsOf(findings), {'INV-9': _domain});
  });

  test('an ID after a section link is judged against the whole doc', () async {
    final held = await _featureWith(
      '$_featureLine [entities]($_domainFromFeature#entities) INV-6.',
    );
    expect(await _judgedIn(held), isEmpty);

    final missing = await _featureWith(
      '$_featureLine [entities]($_domainFromFeature#entities) INV-9.',
    );
    expect(_targetsOf(await _judgedIn(missing)), {'INV-9': _domain});
  });

  test('an ID whose cited doc type lacks its prefix is judged in its own '
      'doc', () async {
    final project = await _frWith(
      '$_frLine [domain:login]($_domainFromFr) E01 and E07.',
    );
    expect(_targetsOf(await _judgedIn(project)), {'E07': loginFr});
  });

  test("a bare ID its owner doc holds gives no finding, an item's own "
      'leading ID included', () async {
    final project = await _projectWith({
      ...doc(loginFr, _frLine, '$_frLine E01 holds.'),
      ...doc(
        loginFeature,
        _featureLine,
        '$_featureLine [domain:login]($_domainFromFeature) INV-6.',
      ),
    });
    expect(await _judgedIn(project), isEmpty);
  });

  test('a range in a run judges its two ends', () async {
    Future<Map<String, String>> targetsOf(String run) async => _targetsOf(
      await _judgedIn(
        await _featureWith(
          '$_featureLine [domain:login]($_domainFromFeature) $run.',
        ),
      ),
    );

    expect(await targetsOf('INV-6 to INV-9'), {'INV-9': _domain});
    expect(await targetsOf('INV-8 to INV-9'), {
      'INV-8': _domain,
      'INV-9': _domain,
    });
  });

  test('a run after a link to no doc gives link_unresolved and no '
      'item_mention_missing', () async {
    final findings = await _judgedIn(
      await _featureWith(
        '$_featureLine [gone](../../../specs/f01_login/NOPE.md) INV-9.',
      ),
    );
    expect(findings.map((f) => f.kind), [FindingKind.linkUnresolved]);
  });

  test('an ID after a code-span cite gives no item_mention_missing', () async {
    final project = await _featureWith('$_featureLine `domain:login` INV-9.');
    expect(await _judgedIn(project), isEmpty);
  });

  test(
    'an ID with no owner doc, or in an untyped doc, gives no finding',
    () async {
      final project = await _projectWith({
        ...doc(loginFeature, _featureLine, '$_featureLine INV-9 has no owner.'),
        'docs/NOTES.md': '# Notes\n\nINV-9 and E07 sit in an untyped doc.\n',
      });
      expect(await _judgedIn(project), isEmpty);
    },
  );

  test('a run after a link to an existing untyped doc gives no '
      'item_mention_missing', () async {
    final project = await _projectWith({
      ...doc(loginFr, _frLine, '$_frLine [notes](../../../../NOTES.md) E07.'),
      'docs/NOTES.md': '# Notes\n\nA doc of no type.\n',
    });
    expect(await _judgedIn(project), isEmpty);
  });

  test('an ID in a code span gives no finding', () async {
    final project = await _frWith('$_frLine Write `E07` as an example.');
    expect(await _judgedIn(project), isEmpty);
  });

  test(
    'an item link to a missing item gives link_item_missing alone',
    () async {
      final findings = await _judgedIn(
        await _featureWith(
          '$_featureLine [INV-9]($_domainFromFeature#invariants).',
        ),
      );
      expect(findings.map((f) => f.kind), [FindingKind.linkItemMissing]);
    },
  );

  test("a per-target doc's finding names its own target's DocPath", () async {
    const flutterDomain = 'specs/flutter/f01_login/DOMAIN.md';
    const jasprDomain = 'specs/jaspr/f01_login/DOMAIN.md';
    String domainMentioning(String id) =>
        '# Login domain\n\n## Entities\n\n- Account\n\n'
        '## Invariants\n\n- **INV-6** An account holds one email.\n\n'
        'See $id.\n';
    final project = await writeTwinProject(
      extra: {
        'docs/$flutterDomain': domainMentioning('INV-8'),
        'docs/$jasprDomain': domainMentioning('INV-9'),
      },
    );
    final findings = await _judgedIn(project, {FindingKind.itemMentionMissing});
    expect(
      {for (final finding in findings) finding.path: finding.keys['target']},
      {flutterDomain: flutterDomain, jasprDomain: jasprDomain},
    );
    expect(_targetsOf(findings), {
      'INV-8': flutterDomain,
      'INV-9': jasprDomain,
    });
  });
}
