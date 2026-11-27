import 'dart:io';

import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/document_writing/move_doc.dart'
    show answerMove;
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/nested_fixture.dart' show shopDomain, writeNestedProject;
import '../../helpers/no_generators.dart';
import '../../helpers/target_fixture.dart';
import '../../helpers/write_fixture.dart' show writeIn;

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
    finding.keys['item']! as String: finding.keys['targetPath']! as String,
};

void main() {
  test('check and move agree on the sure owner of a bare id', () async {
    const payDomain = 'specs/f02_shop/f02_pay/DOMAIN.md';
    String domainOf(String item) =>
        '# Domain\n\n## Invariants\n\n- **INV-1** Rule 1 holds.\n$item\n';
    final project = await writeNestedProject(
      extra: {
        'docs/$shopDomain': domainOf('- **INV-3** Rule 3 follows INV-1.'),
        'docs/$payDomain': domainOf(
          '- **INV-2** Rule 2 follows [rulebook:shop](../DOMAIN.md) INV-1, '
          'unlike INV-3.',
        ),
      },
    );
    Future<List<String>> missing() async => [
      for (final finding in await _judgedIn(project, {
        FindingKind.itemMentionMissing,
      }))
        '${finding.path} ${finding.keys['item']} ${finding.keys['targetPath']}',
    ];
    final before = await missing();
    expect(before, ['$payDomain INV-3 docs/$payDomain']);
    final answer = writeIn(
      project,
      (session) => answerMove(
        session,
        ['rulebook:shop#INV-1'],
        under: 'rulebook:shop/cart',
        generators: noGenerators,
      ),
    );
    expect(answer.json['mentions'], isEmpty);
    expect(await missing(), before);
  });

  test('a bare ID its own doc lacks is item_mention_missing with item and '
      'targetPath', () async {
    final project = await _frWith('$_frLine See E07.');
    final findings = await _judgedIn(project);
    expect(findings, hasLength(1));
    final finding = findings.single;
    expect(finding.kind, FindingKind.itemMentionMissing);
    expect(finding.path, loginFr);
    expect(finding.line, lineOfFirst(project, loginFr, 'See E07.'));
    expect(finding.waitsFor, WaitsFor.agent);
    expect(finding.keys, {'item': 'E07', 'targetPath': 'docs/$loginFr'});
    expect(finding.message, 'bare ID E07 is no item of docs/$loginFr');
  });

  test('a bare ID after a doc link names that doc as target when it lacks '
      'the ID', () async {
    final project = await _featureWith(
      '$_featureLine [rulebook:login]($_domainFromFeature) INV-9.',
    );
    final findings = await _judgedIn(project);
    expect(findings, hasLength(1));
    expect(findings.single.kind, FindingKind.itemMentionMissing);
    expect(findings.single.path, loginFeature);
    expect(findings.single.line, lineOfFirst(project, loginFeature, 'INV-9'));
    expect(findings.single.keys, {
      'item': 'INV-9',
      'targetPath': 'docs/$_domain',
    });
    expect(findings.single.keys, isNot(contains('target')));
    expect(
      findings.single.message,
      'bare ID INV-9 is no item of docs/$_domain',
    );
  });

  test('only the missing ID of a run gives a finding', () async {
    final findings = await _judgedIn(
      await _featureWith(
        '$_featureLine [rulebook:login]($_domainFromFeature) INV-6 and INV-9.',
      ),
    );
    expect(_targetsOf(findings), {'INV-9': 'docs/$_domain'});
  });

  test('an ID after a section link is judged against the whole doc', () async {
    final held = await _featureWith(
      '$_featureLine [entities]($_domainFromFeature#entities) INV-6.',
    );
    expect(await _judgedIn(held), isEmpty);

    final missing = await _featureWith(
      '$_featureLine [entities]($_domainFromFeature#entities) INV-9.',
    );
    expect(_targetsOf(await _judgedIn(missing)), {'INV-9': 'docs/$_domain'});
  });

  test('an ID whose cited doc type lacks its prefix is judged in its own '
      'doc', () async {
    final project = await _frWith(
      '$_frLine [rulebook:login]($_domainFromFr) E01 and E07.',
    );
    expect(_targetsOf(await _judgedIn(project)), {'E07': 'docs/$loginFr'});
  });

  test("a bare ID its owner doc holds gives no finding, an item's own "
      'leading ID included', () async {
    final project = await _projectWith({
      ...doc(loginFr, _frLine, '$_frLine E01 holds.'),
      ...doc(
        loginFeature,
        _featureLine,
        '$_featureLine [rulebook:login]($_domainFromFeature) INV-6.',
      ),
    });
    expect(await _judgedIn(project), isEmpty);
  });

  test('a range in a run judges its two ends', () async {
    Future<Map<String, String>> targetsOf(String run) async => _targetsOf(
      await _judgedIn(
        await _featureWith(
          '$_featureLine [rulebook:login]($_domainFromFeature) $run.',
        ),
      ),
    );

    expect(await targetsOf('INV-6 to INV-9'), {'INV-9': 'docs/$_domain'});
    expect(await targetsOf('INV-8 to INV-9'), {
      'INV-8': 'docs/$_domain',
      'INV-9': 'docs/$_domain',
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

  test('an ID after a link spanning two lines is judged against the cited '
      'doc', () async {
    final findings = await _judgedIn(
      await _featureWith(
        '$_featureLine [domain\nlogin]($_domainFromFeature) INV-9.',
      ),
    );
    expect(_targetsOf(findings), {'INV-9': 'docs/$_domain'});
  });

  test('an ID after a link that is no doc link is judged in its own '
      'doc', () async {
    for (final destination in [
      'https://example.com/rfc',
      '../../../../diagram.png',
    ]) {
      final findings = await _judgedIn(
        await _frWith('$_frLine See [it]($destination) E07.'),
      );
      expect(_targetsOf(findings), {
        'E07': 'docs/$loginFr',
      }, reason: destination);
    }
  });

  test('an ID after a code-span cite gives no item_mention_missing', () async {
    final project = await _featureWith('$_featureLine `rulebook:login` INV-9.');
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

  test(
    'a bare ID behind an outside-docs link gives no item_mention_missing',
    () async {
      // A doc type whose path opens with a placeholder types a doc under no
      // checked folder, so the link leaves the docs and still has an owner doc.
      final project = await _projectWith({
        ...doc(
          loginFeature,
          _featureLine,
          '$_featureLine [design](../../../superpowers/specs/design.md) INV-9.',
        ),
        '.specstone/templates/design.yaml':
            'id: design\n'
            'description: A design document.\n'
            'path: "{slug}/specs/{slug}.md"\n'
            'sections:\n'
            '  - id: invariants\n'
            '    header: Invariants\n'
            '    prefix_id: INV-\n',
        'docs/superpowers/specs/design.md':
            '# Design\n\n## Invariants\n\n- **INV-1** Holds.\n',
      });
      final kinds = [
        for (final finding in (await checkOf(project)).findings) finding.kind,
      ];
      expect(kinds, contains(FindingKind.linkOutsideDocs));
      expect(kinds, isNot(contains(FindingKind.itemMentionMissing)));
    },
  );

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
      {
        for (final finding in findings)
          finding.path: finding.keys['targetPath'],
      },
      {flutterDomain: 'docs/$flutterDomain', jasprDomain: 'docs/$jasprDomain'},
    );
    expect(_targetsOf(findings), {
      'INV-8': 'docs/$flutterDomain',
      'INV-9': 'docs/$jasprDomain',
    });
  });
}
