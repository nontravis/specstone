// The doc texts are plan literals kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:io';

import 'package:specstone_core/src/consistency_check/check_run.dart';
import 'package:specstone_core/src/consistency_check/repeat_listing.dart';
import 'package:specstone_core/src/index_query/read_session.dart';
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

void main() {
  test('a link, bold, backticks, an item ID, and punctuation normalize away, so two wordings of one rule read alike', () async {
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
        (loginFr, lineOfFirst(project, loginFr, 'E01'), 'E01'),
        (_domain, lineOfFirst(project, _domain, 'INV-6'), 'INV-6'),
      ],
    );
  });

  test('two docs that share a clause give one group naming both items, sorted by DocPath then line', () async {
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

  test('one rule in three docs gives one group of three items', () async {
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

  test('overlapping 8-word windows the same items share merge into one maximal run', () async {
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

  test('a run of 7 words is no group', () async {
    final project = await writeCheckProject(
      extra: {
        ..._edge('Alpha opens one two three four five six seven closes.'),
        ..._statement('Beta begins one two three four five six seven ends.'),
      },
    );
    expect(_groupsOf(project), isEmpty);
  });

  test('two items of one doc that share a run give no group', () async {
    final project = await writeCheckProject(
      extra: {
        ..._edge(
          'When the Agent runs it, $_clause for the Agent.\n2. E02 — Also, $_clause, once more.',
        ),
      },
    );
    expect(_groupsOf(project), isEmpty);
  });

  test('a Given line, a table row, fenced code, a heading, and an HTML comment are not read', () async {
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

  test('a run the template text also holds is left out', () async {
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

  test('a run the guide text also holds is left out', () async {
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

  test('a pack change that adds the run to a section description drops its group on the same index, from the words the first run stored', () async {
    final project = await writeCheckProject(
      extra: {
        ..._edge('When the Agent runs it, $_clause for the Agent.'),
        ..._statement('The system shall hold that $_clause, always.'),
      },
    );
    List<(String, int, String)> stored(ReadSession session) => [
      for (final item in session.index.ruleItemWords())
        (item.docPath, item.line, item.words.join(' ')),
    ];
    final first = openSession(project);
    final before = (runRepeats(first).groups.length, stored(first));
    first.close();
    expect(before.$1, 1);
    File('${project.path}/.specstone/templates/fr.yaml')
      ..createSync(recursive: true)
      ..writeAsStringSync(
        'sections:\n  - id: edge_cases\n    description: "Write it as: $_clause."\n',
      );
    final second = openSession(project);
    try {
      expect(runRepeats(second).groups, isEmpty);
      expect(stored(second), before.$2);
    } finally {
      second.close();
    }
  });

  test('a run two docs share whole and a third holds the last part of prints beside the shorter run all three share', () async {
    const whole = 'w01 w02 w03 w04 w05 w06 w07 w08 w09 w10 w11 w12 w13 w14';
    const last = 'w05 w06 w07 w08 w09 w10 w11 w12 w13 w14';
    final project = await writeCheckProject(
      extra: {
        ..._edge('Alpha opens $whole closes.'),
        ..._statement('Beta begins $whole ends.'),
        ..._invariant('Gamma holds $last stops.'),
      },
    );
    final groups = {
      for (final g in _groupsOf(project))
        g.run: [for (final i in g.items) i.docPath],
    };
    expect(groups, {
      whole: [loginFr, loginNf],
      last: [loginFr, loginNf, _domain],
    });
  });

  test('a run longer than 8 words that another doc holds in two parts prints as the two parts it holds', () async {
    final project = await writeCheckProject(
      extra: {
        ..._edge('Alpha opens k0 k1 k2 k3 k4 k5 k6 k7 k8 k9 closes.'),
        ..._statement(
          'Beta begins k0 k1 k2 k3 k4 k5 k6 k7 k8 xx k1 k2 k3 k4 k5 k6 k7 k8 k9 ends.',
        ),
      },
    );
    final runs = [for (final g in _groupsOf(project)) g.run]..sort();
    expect(runs, ['k0 k1 k2 k3 k4 k5 k6 k7 k8', 'k1 k2 k3 k4 k5 k6 k7 k8 k9']);
  });

  test('a run that 14 docs hold gives one group of 14 items beside the longer run 13 of them hold', () async {
    final nf = checkProjectFiles()['docs/$loginNf']!.replaceFirst(
      _nfStatement,
      'The system shall hold that $_clause, always.',
    );
    final project = await writeCheckProject(
      extra: {
        ..._edge('When the Agent runs it, $_clause for the Agent.'),
        'docs/$loginNf': nf,
        for (var n = 2; n <= 13; n++)
          'docs/prds/features/f01_login/us01_email_login/nf${n.toString().padLeft(2, '0')}_t$n.md':
              nf.replaceAll('Sign-in time', 'Sign-in time $n'),
      },
    );
    final held = {for (final g in _groupsOf(project)) g.run: g.items.length};
    expect(held, {
      _clause: 14,
      'the system shall hold that $_clause always': 13,
    });
  });

  test(
    'windows another doc holds apart are not merged into one run for it',
    () async {
      final project = await writeCheckProject(
        extra: {
          ..._edge('Alpha opens p1 p2 p3 p4 p5 p6 p7 p8 p9 closes.'),
          ..._statement(
            'Beta begins p1 p2 p3 p4 p5 p6 p7 p8 qq p2 p3 p4 p5 p6 p7 p8 p9 ends.',
          ),
        },
      );
      final runs = [for (final g in _groupsOf(project)) g.run]..sort();
      expect(runs, ['p1 p2 p3 p4 p5 p6 p7 p8', 'p2 p3 p4 p5 p6 p7 p8 p9']);
    },
  );

  test('a target keeps only the groups that hold an item of its docs, each listing every item', () async {
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

  test('docs that share no run give no group', () async {
    expect(_groupsOf(await writeCheckProject()), isEmpty);
  });

  test(
    'a project template that renames a section header keeps its items in scope',
    () async {
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
    },
  );

  test('groups sort by their first item, then by run', () async {
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
