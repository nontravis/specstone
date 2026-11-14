// The doc texts are plan literals kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:io';

import 'package:specstone_core/src/consistency_check/check_run.dart';
import 'package:specstone_core/src/consistency_check/repeat_listing.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/index_fixture.dart';

/// The DocPath of the login domain the tests add.
const _domain = 'specs/f01_login/DOMAIN.md';

/// A 14-word clause no template or guide holds.
const _clause =
    'a bundle over the budget prints no doc text and exits with status zero';

/// [_clause] as the listing prints it.
const String _run = _clause;

const _frEdge = 'An empty password → refused.';
const _nfStatement = 'The system shall sign in within 1 s.';

Map<String, String> _edge(String text) => doc(loginFr, _frEdge, text);

Map<String, String> _statement(String text) => doc(loginNf, _nfStatement, text);

Map<String, String> _invariant(String text) => {
  'docs/$_domain':
      '# Login domain\n\n## Entities\n\n- Account\n\n'
      '## Invariants\n\n- **INV-6** $text\n',
};

List<RepeatGroup> _groupsOf(
  Directory project, {
  String? target,
  String? codeTarget,
}) {
  final session = openSession(project);
  try {
    return runRepeats(session, target: target, codeTarget: codeTarget).groups;
  } finally {
    session.close();
  }
}

int _lineOf(Directory project, String docPath, String needle) =>
    File('${project.path}/docs/$docPath')
        .readAsLinesSync()
        .indexWhere((line) => line.contains(needle)) +
    1;

void main() {
  test('f04/us05/fr01/e01, f04/us05/s1: a link, bold, backticks, an item ID, and punctuation normalize away, so two wordings of one rule read alike', () async {
    final project = await writeCheckProject(
      extra: {
        ..._edge(
          'The **context** call [returns](../nowhere.md) `the bundle` within 500 ms for every target, always.',
        ),
        ..._invariant(
          'the context call returns the bundle within 500 ms for every target always',
        ),
      },
    );
    final groups = _groupsOf(project);
    expect(groups, hasLength(1));
    expect(
      groups.single.run,
      'the context call returns the bundle within 500 ms for every target always',
    );
    expect(
      [for (final i in groups.single.items) (i.docPath, i.line, i.item)],
      [
        (loginFr, _lineOf(project, loginFr, 'E01'), 'E01'),
        (_domain, _lineOf(project, _domain, 'INV-6'), 'INV-6'),
      ],
    );
  });

  test('f04/us05/fr01/e02, f04/us05/s1: two docs that share a clause give one group naming both items, sorted by DocPath then line', () async {
    final project = await writeCheckProject(
      extra: {
        ..._edge('When the Agent runs it, $_clause for the Agent.'),
        ..._statement('The system shall hold that $_clause, always.'),
      },
    );
    final groups = _groupsOf(project);
    expect(groups, hasLength(1));
    expect(groups.single.run, _run);
    expect(
      [for (final i in groups.single.items) (i.docPath, i.item, i.name)],
      [
        (loginFr, 'E01', 'login/email_login/check_password'),
        (loginNf, null, 'login/email_login/sign_in_time'),
      ],
    );
  });

  test('f04/us05/fr01/e03, f04/us05/s2: one rule in three docs gives one group of three items', () async {
    final project = await writeCheckProject(
      extra: {
        ..._edge('When the Agent runs it, $_clause for the Agent.'),
        ..._statement('The system shall hold that $_clause, always.'),
        ..._invariant('Every run: $_clause, in short.'),
      },
    );
    final groups = _groupsOf(project);
    expect(groups, hasLength(1));
    expect(
      [for (final i in groups.single.items) i.docPath],
      [loginFr, loginNf, _domain],
    );
  });

  test('f04/us05/fr01/e04: overlapping 8-word windows the same items share merge into one maximal run', () async {
    const twelve =
        'one two three four five six seven eight nine ten eleven twelve';
    final project = await writeCheckProject(
      extra: {
        ..._edge('Alpha opens $twelve closes.'),
        ..._statement('Beta begins $twelve ends.'),
      },
    );
    final groups = _groupsOf(project);
    expect(groups, hasLength(1));
    expect(groups.single.run, twelve);
  });

  test('f04/us05/fr01/e04: a run of 7 words is no group', () async {
    final project = await writeCheckProject(
      extra: {
        ..._edge('Alpha opens one two three four five six seven closes.'),
        ..._statement('Beta begins one two three four five six seven ends.'),
      },
    );
    expect(_groupsOf(project), isEmpty);
  });

  test('f04/us05/fr01/e05: two items of one doc that share a run give no group', () async {
    final project = await writeCheckProject(
      extra: {
        ..._edge(
          'When the Agent runs it, $_clause for the Agent.\n2. E02 — Also, $_clause, once more.',
        ),
      },
    );
    expect(_groupsOf(project), isEmpty);
  });

  test('f04/us05/fr01/e06, f04/us05/s3: a Given line, a table row, fenced code, a heading, and an HTML comment are not read', () async {
    final shapes = <String, String Function(String)>{
      'a Given line': (c) => '- **Given** $c',
      'a When line': (c) => '- **When** $c',
      'a Then line': (c) => '- **Then** $c',
      'an And line': (c) => '- **And** $c',
      'a table row': (c) => '| Rule | Note |\n|---|---|\n| $c | x |',
      'fenced code': (c) => '```text\n$c\n```',
      'an HTML comment': (c) => '<!-- $c -->',
      'a heading': (c) => '### $c',
    };
    for (final MapEntry(:key, :value) in shapes.entries) {
      final project = await writeCheckProject(
        extra: {
          ...doc(
            loginFr,
            '1. E01 — $_frEdge',
            value('Alpha opens $_clause closes.'),
          ),
          ..._statement(value('Beta begins $_clause ends.')),
        },
      );
      expect(_groupsOf(project), isEmpty, reason: key);
    }
  });

  test('f04/us05/fr01/e06, f04/us05/s3: a run the template text also holds is left out', () async {
    const template =
        'The <product> shall <verb> <object> <value ± tolerance> <condition>.';
    final project = await writeCheckProject(
      extra: {
        ...doc(
          loginFr,
          'The system shall refuse a wrong password within 1 s.',
          template,
        ),
        ..._statement(template),
      },
    );
    expect(_groupsOf(project), isEmpty);
  });

  test('f04/us05/fr01/e06, f04/us05/s3: a run the guide text also holds is left out', () async {
    const guide =
        'Use one "shall" and a positive form; rewrite "shall not" as the required behavior.';
    final project = await writeCheckProject(
      extra: {
        ...doc(
          loginFr,
          'The system shall refuse a wrong password within 1 s.',
          'The Agent notes: $guide Stops here.',
        ),
        ..._statement('The Owner studies: $guide Waits here.'),
      },
    );
    expect(_groupsOf(project), isEmpty);
  });

  test('f04/us05/fr01/e12: a template layer that adds the run to a section description drops its group, with no doc changed', () async {
    final extra = {
      ..._edge('When the Agent runs it, $_clause for the Agent.'),
      ..._statement('The system shall hold that $_clause, always.'),
    };
    expect(_groupsOf(await writeCheckProject(extra: extra)), hasLength(1));
    final layered = await writeCheckProject(
      extra: {
        ...extra,
        '.specstone/templates/fr.yaml':
            'sections:\n  - id: edge_cases\n    description: "Write it as: $_clause."\n',
      },
    );
    expect(_groupsOf(layered), isEmpty);
  });

  test('f04/us05/fr01/e07, f04/us05/s5: a target keeps only the groups that hold an item of its docs, each listing every item', () async {
    const other =
        'two docs agree on the second clause that the first target never reads aloud';
    final project = await writeCheckProject(
      extra: {
        ..._edge('When the Agent runs it, $_clause for the Agent.'),
        ..._statement(
          'The system shall hold that $_clause, and that $other, always.',
        ),
        ..._invariant('Every run: $other, in short.'),
      },
    );
    final all = _groupsOf(project);
    expect(all, hasLength(2));
    final kept = _groupsOf(project, target: 'login/email_login/check_password');
    expect(kept, hasLength(1));
    expect(kept.single.run, _run);
    expect([for (final i in kept.single.items) i.docPath], [loginFr, loginNf]);
  });

  test('f04/us05/fr01/e08: docs that share no run give no group', () async {
    expect(_groupsOf(await writeCheckProject()), isEmpty);
  });

  test('f04/us05/fr01/e09: a project template that renames a section header keeps its items in scope', () async {
    final project = await writeCheckProject(
      extra: {
        '.specstone/templates/fr.yaml':
            'sections:\n  - id: edge_cases\n    header: Corner cases\n',
        ...edit(loginFr, [
          ('## Edge cases', '## Corner cases'),
          (_frEdge, 'When the Agent runs it, $_clause for the Agent.'),
        ]),
        ..._invariant('Every run: $_clause, in short.'),
      },
    );
    final groups = _groupsOf(project);
    expect(groups, hasLength(1));
    expect(
      [for (final i in groups.single.items) i.docPath],
      [loginFr, _domain],
    );
  });

  test('f04/us05/fr01: groups sort by their first item, then by run', () async {
    const first = 'zeta one two three four five six seven eight nine ten';
    const second = 'alpha one two three four five six seven eight nine ten';
    final project = await writeCheckProject(
      extra: {
        ..._edge('$first, left, $second.'),
        ..._statement('$first, right, $second.'),
      },
    );
    expect([for (final g in _groupsOf(project)) g.run], [second, first]);
  });
}
