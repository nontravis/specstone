import 'package:specstone_core/src/consistency_check/fingerprint.dart';
import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_type_matcher.dart';
import 'package:specstone_core/src/setup_migration/renumber_pass.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';

const _fr = 'setup_migration/upgrade_pack_pins/apply_steps_and_pins';

const _topicPath = 'specs/topics/doc_model.md';
const _otherTopicPath = 'specs/topics/other_topic.md';
const _domainPath = 'specs/f01_a/DOMAIN.md';
const _storyPath = 'prds/features/f01_a/us01_b/USER_STORY.md';
const _siblingPath = 'prds/features/f01_a/us02_e/USER_STORY.md';
const _frPath = 'prds/features/f01_a/us01_b/fr01_c.md';
const _siblingFrPath = 'prds/features/f01_a/us02_e/fr01_f.md';
const _journeyPath = 'prds/journeys/onboard/JOURNEY.md';
const _gnfrPath = 'prds/GNFR.md';
const _nfPath = 'prds/features/f01_a/us01_b/nf01_d.md';

const _topic = '''
---
covers:
  - lib/RULE-7a.dart
---
# Doc model

## Rules

- **RULE-1** — One.
- **RULE-7a** — Lettered, as RULE-7a says; `RULE-7a` stays.
- **RULE-12** — Twelve.
- **RULE-30** — Thirty.

```text
RULE-7a in a fence
```
''';

const _otherTopic = '''
# Other topic

## Rules

- **RULE-1** — One.
''';

const _lettered = '### Scenario 6a — [edge] lettered\n- **Given** g\n';
const _renumbered = '### Scenario 9 — [edge] lettered\n\n- **Given** g';

const _story = '''
# B

## Acceptance Criteria

### Scenario 1 — [happy] one

- **Given** g

### Scenario 8 — [error] eight

- **Given** g

$_lettered''';

const _frCitations = '''
`doc_model` RULE-7a
`topic:doc_model` RULE-7a
`doc_model` RULE-12 and RULE-7a
`RULE-7a` in a code span
RULE-7a on a line that cites no doc
`other_topic` RULE-7a
`doc_model` see `other_topic` RULE-7a
[rules](../topics/doc_model.md) RULE-7a
''';

const _fenced = '```text\n`doc_model` RULE-7a\n```\n';

String _frDoc(String confirmedFingerprint) =>
    '''
---
traced_from:
  - S1
  - S6a
confirmed:
  - S6a $confirmedFingerprint
---
# C

## Statement

$_frCitations
$_fenced''';

late MergedSet _set;

MergedDocType _typeAt(String docPath) =>
    switch (DocTypeMatcher(_set).match(docPath)) {
      MatchedDocType(:final docType) => docType,
      _ => throw StateError('no doc type at $docPath'),
    };

RenumberPass _planOf(Map<String, String> docs) => RenumberPass.plan([
  for (final MapEntry(key: docPath, value: lf) in docs.entries)
    (docPath: docPath, lf: lf, type: _typeAt(docPath)),
]);

/// The pass over [docs] applied to each of them, keyed by DocPath.
Map<String, String> _applied(Map<String, String> docs) {
  final pass = _planOf(docs);
  return {
    for (final MapEntry(key: docPath, value: lf) in docs.entries)
      docPath: pass.apply(docPath, lf),
  };
}

void main() {
  setUpAll(() {
    _set = TemplateResolver().resolveCarried(
      packNames: const ['prd-core', 'software-tech'],
      homeDirectory: null,
    );
  });

  test('$_fr E19: two lettered scenarios take the next free numbers in '
      'document order; another prefix counts only its own numbers', () {
    const story = '''
# B

## Rules

- **BR-01** — One.
- **BR-2a** — Lettered.
- **BR-03** — Three.

## Acceptance Criteria

### Scenario 7 — [happy] seven

- **Given** g

### Scenario 6a — [edge] a

- **Given** g

### Scenario 6b — [error] b (BR-2a)

- **Given** g
''';

    final pass = _planOf({_storyPath: story});

    expect(pass.renumberings, [
      (docPath: _storyPath, from: 'BR-2a', to: 'BR-04'),
      (docPath: _storyPath, from: 'Scenario 6a', to: 'Scenario 8'),
      (docPath: _storyPath, from: 'Scenario 6b', to: 'Scenario 9'),
    ]);
    final applied = pass.apply(_storyPath, story);
    expect(applied, contains('- **BR-04** — Lettered.\n'));
    expect(applied, contains('### Scenario 8 — [edge] a\n'));
    expect(applied, contains('### Scenario 9 — [error] b (BR-04)\n'));
    expect(
      pass.planLine,
      'renumber ids: $_storyPath BR-2a -> BR-04, '
      '$_storyPath Scenario 6a -> Scenario 8, '
      '$_storyPath Scenario 6b -> Scenario 9',
    );
  });

  test('$_fr E18: the renumbered doc rewrites its own item and prose mention, '
      'and keeps its code span, fence, and frontmatter byte-equal', () {
    final applied = _applied({_topicPath: _topic})[_topicPath]!;

    expect(
      applied,
      _topic.replaceFirst(
        '- **RULE-7a** — Lettered, as RULE-7a says;',
        '- **RULE-31** — Lettered, as RULE-31 says;',
      ),
    );
  });

  test('$_fr E18: a line of another doc rewrites the token its nearest '
      'citation names the renumbered doc for, outside code spans and '
      'fences', () {
    final applied = _applied({
      _topicPath: _topic,
      _otherTopicPath: _otherTopic,
      _frPath: _frDoc('000000000000'),
    })[_frPath]!;

    expect(
      applied,
      contains('''
`doc_model` RULE-31
`topic:doc_model` RULE-31
`doc_model` RULE-12 and RULE-31
`RULE-7a` in a code span
RULE-7a on a line that cites no doc
`other_topic` RULE-7a
`doc_model` see `other_topic` RULE-7a
[rules](../topics/doc_model.md) RULE-7a
'''),
    );
    expect(applied, contains(_fenced));
  });

  test('$_fr E18: a spec doc whose link or code-span path resolves to the '
      'renumbered doc cites it', () {
    const domain = '''
# A

## Invariants

[rules](../topics/doc_model.md) RULE-7a
`../topics/doc_model.md` RULE-7a
`specs/topics/doc_model.md` RULE-7a
`../topics/missing.md` RULE-7a
''';

    final applied = _applied({
      _topicPath: _topic,
      _domainPath: domain,
    })[_domainPath]!;

    expect(
      applied,
      domain
          .replaceFirst('.md) RULE-7a', '.md) RULE-31')
          .replaceFirst('/doc_model.md` RULE-7a', '/doc_model.md` RULE-31')
          .replaceFirst(
            'specs/topics/doc_model.md` RULE-7a',
            'specs/topics/doc_model.md` RULE-31',
          ),
    );
  });

  test('$_fr E18: the plan line lists each renumbering in tree order, then '
      'each other doc it rewrites for them after ; references:', () {
    final pass = _planOf({
      _topicPath: _topic,
      _otherTopicPath: _otherTopic,
      _storyPath: _story,
      _frPath: _frDoc('000000000000'),
    });

    expect(
      pass.planLine,
      'renumber ids: $_storyPath Scenario 6a -> Scenario 9, '
      '$_topicPath RULE-7a -> RULE-31; references: $_frPath',
    );
  });

  test('$_fr E18: a matched confirmed entry records the renumbered block '
      'fingerprint after layout; a suspect one keeps its fingerprint', () {
    final matched = fingerprintOf(_lettered);
    final docs = {
      _storyPath: _story,
      _frPath: _frDoc(matched),
      _siblingPath: '# E\n\n## Acceptance Criteria\n\n### Scenario 1 — x\n',
      _siblingFrPath:
          '---\ntraced_from:\n  - a/b#S6a\nconfirmed:\n'
          '  - a/b#S6a 000000000000\n---\n# F\n',
    };

    final applied = _applied(docs);

    expect(
      applied[_frPath],
      startsWith(
        '---\ntraced_from:\n  - S1\n  - S9\nconfirmed:\n'
        '  - S9 ${fingerprintOf(_renumbered)}\n---\n',
      ),
    );
    expect(
      applied[_siblingFrPath],
      startsWith(
        '---\ntraced_from:\n  - a/b#S9\nconfirmed:\n'
        '  - a/b#S9 000000000000\n---\n',
      ),
    );
  });

  test('$_fr E18: a journey step value and its confirmed label take the new '
      'number; a step heading number 3x stays', () {
    final matched = fingerprintOf(_lettered);
    final journey =
        '''
---
confirmed:
  - a/b#S6a $matched
---
# Get onboarded

## Steps

### 1. Start
step: a/b S6a

### 3x. Detour
step: a/b S1
''';

    final applied = _applied({
      _storyPath: _story,
      _journeyPath: journey,
    })[_journeyPath]!;

    expect(
      applied,
      journey
          .replaceFirst(
            'a/b#S6a $matched',
            'a/b#S9 ${fingerprintOf(_renumbered)}',
          )
          .replaceFirst('step: a/b S6a', 'step: a/b S9'),
    );
  });

  test('$_fr E18: a lettered gnfr NFR ID renames the overrides value and the '
      'confirmed label, the statement fingerprint carried over', () {
    const statement = '- **Statement:** The tool shall answer in 1 s.';
    const gnfr =
        '''
# GNFR

## Performance

### NFR-P01 — First
- **Statement:** The tool shall start in 2 s.

### NFR-P01a — Lettered
$statement
''';
    final nf =
        '''
---
kind: tighten
overrides: NFR-P01a
confirmed:
  - NFR-P01a ${fingerprintOf(statement)}
---
# D
''';

    final pass = _planOf({_gnfrPath: gnfr, _nfPath: nf});

    expect(pass.renumberings, [
      (docPath: _gnfrPath, from: 'NFR-P01a', to: 'NFR-P02'),
    ]);
    expect(
      pass.apply(_nfPath, nf),
      nf
          .replaceFirst('overrides: NFR-P01a', 'overrides: NFR-P02')
          .replaceFirst('  - NFR-P01a ', '  - NFR-P02 '),
    );
  });

  test('$_fr E18: a tree with no lettered ID plans nothing, and the pass '
      'over its own output renumbers nothing', () {
    final docs = {
      _topicPath: _topic,
      _storyPath: _story,
      _frPath: _frDoc(fingerprintOf(_lettered)),
    };

    final applied = _applied(docs);
    final again = _planOf(applied);

    expect(again.renumberings, isEmpty);
    expect(again.planLine, isNull);
    for (final MapEntry(key: docPath, value: lf) in applied.entries) {
      expect(again.apply(docPath, lf), lf, reason: docPath);
    }
    expect(_planOf({_otherTopicPath: _otherTopic}).planLine, isNull);
  });

  test('$_fr E18: a doc the pass was not planned over comes back '
      'unchanged', () {
    final pass = _planOf({_topicPath: _topic});

    expect(pass.apply(_frPath, _frDoc('000000000000')), _frDoc('000000000000'));
  });

  test('$_fr E19: two items lettered alike take two numbers, each at its own '
      'start; a mention elsewhere takes the first', () {
    const topic = '''
# Doc model

## Rules

- **RULE-1** — One, unlike RULE-7a.
- **RULE-7a** — A.
- **RULE-7a** — B.
''';

    final pass = _planOf({_topicPath: topic});

    expect(pass.renumberings, [
      (docPath: _topicPath, from: 'RULE-7a', to: 'RULE-2'),
      (docPath: _topicPath, from: 'RULE-7a', to: 'RULE-3'),
    ]);
    expect(
      pass.apply(_topicPath, topic),
      topic
          .replaceFirst('unlike RULE-7a', 'unlike RULE-2')
          .replaceFirst('**RULE-7a** — A', '**RULE-2** — A')
          .replaceFirst('**RULE-7a** — B', '**RULE-3** — B'),
    );
  });

  test('$_fr E18: a quoted confirmed entry takes the new label and the '
      'renumbered block fingerprint in its quotes', () {
    final fr =
        '---\ntraced_from: [S6a]\nconfirmed:\n'
        '  - "S6a ${fingerprintOf(_lettered)}"\n---\n# C\n';

    final applied = _applied({_storyPath: _story, _frPath: fr})[_frPath];

    expect(
      applied,
      '---\ntraced_from: [S9]\nconfirmed:\n'
      '  - "S9 ${fingerprintOf(_renumbered)}"\n---\n# C\n',
    );
  });

  test('$_fr E18: a scenario whose prose the pass rewrites keeps a current '
      'link; an entry already suspect stays suspect', () {
    const eight = '### Scenario 8 — [error] eight\n\n- **Given** g';
    const mentioning = '$eight, unlike Scenario 6a';
    final story = _story.replaceFirst(eight, mentioning);
    String tracing(String fingerprint) =>
        '---\ntraced_from: [S8]\nconfirmed:\n  - S8 $fingerprint\n---\n# C\n';

    final applied = _applied({
      _storyPath: story,
      _frPath: tracing(fingerprintOf(mentioning)),
      _siblingFrPath: tracing('000000000000'),
    });

    expect(
      applied[_frPath],
      tracing(fingerprintOf('$eight, unlike Scenario 9')),
    );
    expect(applied[_siblingFrPath], tracing('000000000000'));
  });

  test('$_fr E18: an FR Statement the pass rewrites keeps the api FR trace '
      'link current', () {
    final fr = _frDoc('000000000000');
    String api(String fingerprint) =>
        '---\nconfirmed:\n  - b/c $fingerprint\n---\n# A\n\n## FR trace\n\n'
        '| FR | Operation |\n|----|-----------|\n| b/c | get |\n';
    final docs = {
      _topicPath: _topic,
      'prds/features/f01_a/FEATURE.md': '# A\n',
      _frPath: fr,
      'specs/f01_a/API.md': api(fingerprintOf(_statementOf(fr))),
    };

    final applied = _applied(docs);

    expect(
      applied['specs/f01_a/API.md'],
      api(fingerprintOf(_statementOf(applied[_frPath]!))),
    );
    expect(_statementOf(applied[_frPath]!), isNot(_statementOf(fr)));
  });

  test('$_fr E18: a lettered project goal cited in an nf traced_from takes '
      'the new number', () {
    const project = '''
# P

## Project goals

- **PG-01** — One.
- **PG-2a** — Lettered.
''';
    const nf = '---\nkind: add\ntraced_from:\n  - PG-2a\n---\n# D\n';

    final pass = _planOf({'prds/PROJECT.md': project, _nfPath: nf});

    expect(pass.apply(_nfPath, nf), nf.replaceFirst('PG-2a', 'PG-02'));
    expect(pass.planLine, endsWith('; references: $_nfPath'));
  });
}

/// The body of the `## Statement` section of [lf], as `check` fingerprints an
/// FR's statement.
String _statementOf(String lf) =>
    Doc.parse(lf).sections
        .firstWhere((section) => section.headerText == 'Statement')
        .body;
