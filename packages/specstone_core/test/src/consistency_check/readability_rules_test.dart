import 'dart:io';

import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/consistency_check/readability_rules.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';

const _readabilityKinds = <FindingKind>{
  FindingKind.wordsOverLimit,
  FindingKind.sentenceCharsOverLimit,
  FindingKind.traceNoteNotLast,
  FindingKind.sentencesOverLimit,
};
const _domainDoc = 'specs/f01_login/DOMAIN.md';
const _domainLayer = '.specstone/templates/domain.yaml';
const _noGuideTail = '; guide line: ';

late Directory _project;

Future<List<Finding>> _found(
  Map<String, String> extra, {
  String? docPath,
}) async {
  _project = await writeCheckProject(extra: extra);
  return [
    for (final f in (await checkOf(_project, docPath: docPath)).findings)
      if (_readabilityKinds.contains(f.kind)) f,
  ];
}

/// Returns a sentence of [count] words, ended by a full stop.
String _sentenceOf(int count, [String word = 'word']) =>
    '${List.filled(count, word).join(' ')}.';

Map<String, String> _edgeCase(String text) =>
    fr('1. E01 — An empty password → refused.', '1. E01 — $text');

Map<String, String> _domainWith(String invariants) => {
  'docs/$_domainDoc':
      '# Login domain\n\n## Entities\n\n- Account\n\n'
      '## Invariants\n\n$invariants\n',
};

void main() {
  test('long default sentence gives words_over_limit', () async {
    final found = await _found(_edgeCase(_sentenceOf(30)));
    expect(found, hasLength(1));
    expect(found.single.kind, FindingKind.wordsOverLimit);
    expect(found.single.path, loginFr);
    expect(found.single.line, lineOfFirst(_project, loginFr, 'E01'));
    expect(found.single.waitsFor, WaitsFor.agent);
    expect(
      found.single.toJson(),
      allOf(
        containsPair('section', 'edge_cases'),
        containsPair('id', 'E01'),
        containsPair('language', 'default'),
        containsPair('limit', 25),
        containsPair('actual', 30),
        containsPair('sentences', 1),
      ),
    );
  });

  test('a sentence at its cap gives none', () async {
    expect(await _found(_edgeCase(_sentenceOf(25))), isEmpty);
  });

  test('two long sentences give one finding', () async {
    final found = await _found(
      _edgeCase('${_sentenceOf(26)} ${_sentenceOf(31)}'),
    );
    expect(found, hasLength(1));
    expect(
      found.single.toJson(),
      allOf(containsPair('actual', 31), containsPair('sentences', 2)),
    );
  });

  test('two sentences report the kind and the default language', () async {
    final found = await _found(
      _edgeCase('${_sentenceOf(26)} ${_sentenceOf(31)}'),
    );
    expect(found.single.kind, FindingKind.wordsOverLimit);
    expect(found.single.toJson(), containsPair('language', 'default'));
  });

  test('a closing group of two item links gives none', () async {
    final found = await _found(
      _domainWith(
        '- **INV-1** — ${_sentenceOf(25).replaceFirst('.', '')} '
        '([INV-74](DOMAIN.md#invariants), [INV-75](DOMAIN.md#invariants)).',
      ),
    );
    expect(found, isEmpty);
  });

  test('a group joined by semicolons gives one finding at most', () async {
    final found = await _found(
      _edgeCase('An empty password (INV-4; INV-5) is refused.'),
    );
    expect(found, hasLength(1));
    expect(found.single.kind, FindingKind.traceNoteNotLast);
    expect(found.single.toJson(), containsPair('note', '(INV-4; INV-5)'));
  });

  group('an ownership clause', () {
    test('as the last clause gives none', () async {
      final found = await _found(
        _edgeCase(
          'A password is hashed. INV-4 owns the recipe, '
          'and every other doc cites it.',
        ),
      );
      expect(found, isEmpty);
    });

    test('before another clause gives trace_note_not_last', () async {
      final found = await _found(
        _edgeCase('A password is hashed. INV-4 owns the recipe. It is kept.'),
      );
      expect(found, hasLength(1));
      expect(found.single.kind, FindingKind.traceNoteNotLast);
      expect(found.single.line, lineOfFirst(_project, loginFr, 'E01'));
    });

    test('after a group leaves the group misplaced', () async {
      final found = await _found(
        _edgeCase('A password is hashed (INV-4). INV-5 owns the recipe.'),
      );
      expect(found, hasLength(1));
      expect(found.single.kind, FindingKind.traceNoteNotLast);
      expect(found.single.toJson(), containsPair('note', '(INV-4)'));
    });
  });

  test('a note before nested items gives none', () async {
    final found = await _found(
      _domainWith('- **INV-1** — A password is hashed (INV-4).\n  - Nested.'),
    );
    expect(found, isEmpty);
  });

  test(
    'a note closing a cell before text in the next cell gives none',
    () async {
      final found = await _found(
        fr(
          'A wrong password must not sign in.',
          '| Part | Responsibility | Owner |\n|---|---|---|\n'
              '| Form | Takes it (INV-4) | Keeps it. |',
        ),
      );
      expect(found, isEmpty);
    },
  );

  test('a default-only layer leaves the korean cap merged', () async {
    final found = await _found({
      ..._domainWith('- **INV-1** — ${_sentenceOf(18, '가')}'),
      _domainLayer: 'lint:\n  max_sentence_words:\n    default: 30\n',
    });
    expect(found, hasLength(1));
    expect(found.single.kind, FindingKind.wordsOverLimit);
    expect(
      found.single.toJson(),
      allOf(
        containsPair('language', 'ko'),
        containsPair('limit', 17),
        containsPair('actual', 18),
      ),
    );
  });

  test('english terms never outvote a korean sentence', () async {
    final found = await _found(
      _edgeCase('${List.filled(17, '가').join(' ')} API CLI JSON.'),
    );
    expect(found, hasLength(1));
    expect(found.single.kind, FindingKind.wordsOverLimit);
    expect(
      found.single.toJson(),
      allOf(
        containsPair('language', 'ko'),
        containsPair('limit', 17),
        containsPair('actual', 20),
      ),
    );
  });

  test('long cell gives finding at row line', () async {
    final found = await _found(
      fr(
        'A wrong password must not sign in.',
        '| Part | Responsibility |\n|---|---|\n'
            '| Form | ${_sentenceOf(30)} |\n| Store | Keeps it. |',
      ),
    );
    expect(found, hasLength(1));
    expect(found.single.kind, FindingKind.wordsOverLimit);
    expect(found.single.line, lineOfFirst(_project, loginFr, '| Form |'));
    expect(
      found.single.toJson(),
      allOf(containsPair('language', 'default'), containsPair('actual', 30)),
    );
  });

  group('generated block copy gives none', () {
    final body =
        '### Group\n\n1. E01 — one.\n'
        '<!-- specstone:generated scenario_copy (do not edit) -->\n'
        '- **Given** ${_sentenceOf(30)}\n'
        '<!-- specstone:generated end -->\n';

    test('when the doc type lists the generator', () async {
      final found = await _found({
        ..._edgeCaseBlock(body),
        '.specstone/templates/fr.yaml': 'generators: [scenario_copy]\n',
      });
      expect(found, isEmpty);
    });

    test('and is read as an item when it lists none', () async {
      final found = await _found(_edgeCaseBlock(body));
      expect(found.map((f) => f.kind), [FindingKind.wordsOverLimit]);
    });
  });

  test('project layer cap applies to its doc type', () async {
    final layer = {
      _domainLayer: 'lint:\n  max_sentence_words:\n    default: 30\n',
    };
    final inside = await _found({
      ..._domainWith('- **INV-1** — ${_sentenceOf(28)}'),
      ...layer,
    });
    expect(inside, isEmpty);
    final over = await _found({
      ..._domainWith('- **INV-1** — ${_sentenceOf(31)}'),
      ...layer,
    });
    expect(over, hasLength(1));
    expect(over.single.path, _domainDoc);
    expect(
      over.single.toJson(),
      allOf(
        containsPair('section', 'invariants'),
        containsPair('id', 'INV-1'),
        containsPair('limit', 30),
        containsPair('actual', 31),
      ),
    );
  });

  test('trace_note_last false turns notes off', () async {
    final item = '- **INV-1** — An email (INV-4) is unique ${_sentenceOf(30)}';
    final on = await _found(_domainWith(item));
    expect(
      on.map((f) => f.kind),
      unorderedEquals([
        FindingKind.wordsOverLimit,
        FindingKind.traceNoteNotLast,
      ]),
    );
    final off = await _found({
      ..._domainWith(item),
      _domainLayer: 'lint:\n  trace_note_last: false\n',
    });
    expect(off.map((f) => f.kind), [FindingKind.wordsOverLimit]);
  });

  test('long thai sentence gives sentence_chars_over_limit', () async {
    final found = await _found(_edgeCase('${'ก' * 120}.'));
    expect(found, hasLength(1));
    expect(found.single.kind, FindingKind.sentenceCharsOverLimit);
    expect(found.single.line, lineOfFirst(_project, loginFr, 'E01'));
    expect(
      found.single.toJson(),
      allOf(
        containsPair('section', 'edge_cases'),
        containsPair('id', 'E01'),
        containsPair('language', 'th'),
        containsPair('limit', 100),
        containsPair('actual', 120),
        containsPair('sentences', 1),
      ),
    );
  });

  test('a thai sentence weighs its english run at the cap over 25', () async {
    final found = await _found(_edgeCase('${'ก' * 98} check.'));
    expect(found, hasLength(1));
    expect(found.single.toJson(), containsPair('actual', 102));
  });

  test('en line under thai heading takes default', () async {
    final found = await _found(
      doc(
        projectDoc,
        '### PV-01 — One sign-in\n\n> en: One sign-in for every app.',
        '### PV-01 — ระบบล็อกอินเดียว\n\n> en: ${_sentenceOf(30)}',
      ),
    );
    expect(found, hasLength(1));
    expect(found.single.kind, FindingKind.wordsOverLimit);
    expect(found.single.path, projectDoc);
    expect(
      found.single.toJson(),
      allOf(
        containsPair('section', 'vision'),
        containsPair('language', 'default'),
        containsPair('limit', 25),
      ),
    );
  });

  test('en marker line of 25 words passes and 26 words fails', () async {
    String vision(int count) =>
        '### PV-01 — One sign-in\n\n> en: ${_sentenceOf(count)}';
    final project = doc(
      projectDoc,
      '### PV-01 — One sign-in\n\n> en: One sign-in for every app.',
      vision(25),
    );
    expect(await _found(project), isEmpty);

    final found = await _found(
      doc(
        projectDoc,
        '### PV-01 — One sign-in\n\n> en: One sign-in for every app.',
        vision(26),
      ),
    );
    expect(found, hasLength(1));
    expect(found.single.toJson(), containsPair('actual', 26));
  });

  test('two languages give two findings', () async {
    final found = await _found(_edgeCase('${'ก' * 110}. ${_sentenceOf(26)}'));
    expect(
      found.map((f) => f.kind),
      unorderedEquals([
        FindingKind.sentenceCharsOverLimit,
        FindingKind.wordsOverLimit,
      ]),
    );
    expect(
      found.map((f) => f.toJson()['language']),
      unorderedEquals(['th', 'default']),
    );
    expect(found.map((f) => f.line).toSet(), {
      lineOfFirst(_project, loginFr, 'E01'),
    });
  });

  test('misplaced note gives trace_note_not_last with note', () async {
    final found = await _found(
      _edgeCase('An empty password (INV-4) is refused.'),
    );
    expect(found, hasLength(1));
    expect(found.single.kind, FindingKind.traceNoteNotLast);
    expect(found.single.line, lineOfFirst(_project, loginFr, 'E01'));
    expect(found.single.waitsFor, WaitsFor.agent);
    expect(
      found.single.toJson(),
      allOf(
        containsPair('section', 'edge_cases'),
        containsPair('id', 'E01'),
        containsPair('note', '(INV-4)'),
      ),
    );
    expect(found.single.message, endsWith('$_noGuideTail$citeNoteGuideLine'));
  });

  test('a note that closes its item gives none', () async {
    final found = await _found(
      _edgeCase('An empty password is refused (INV-4).'),
    );
    expect(found, isEmpty);
  });

  test('a length message carries no guide sentence', () async {
    final words = await _found(_edgeCase(_sentenceOf(31)));
    expect(
      words.single.message,
      'the longest sentence holds 31 words; '
      'the limit is 25 words for language default',
    );
    final thai = await _found(_edgeCase('${'ก' * 120}.'));
    expect(
      thai.single.message,
      'the longest sentence holds 120 characters; '
      'the limit is 100 characters for language th',
    );
    final raised = await _found({
      ..._domainWith('- **INV-1** — ${_sentenceOf(31)}'),
      _domainLayer: 'lint:\n  max_sentence_words:\n    default: 30\n',
    });
    expect(
      raised.single.message,
      'the longest sentence holds 31 words; '
      'the limit is 30 words for language default',
    );
  });

  test('a korean sentence takes the ko word cap', () async {
    final found = await _found(_edgeCase(_sentenceOf(18, '가')));
    expect(found, hasLength(1));
    expect(found.single.kind, FindingKind.wordsOverLimit);
    expect(
      found.single.toJson(),
      allOf(
        containsPair('language', 'ko'),
        containsPair('limit', 17),
        containsPair('actual', 18),
      ),
    );
  });

  test('a long lead item gives a finding under the lead key', () async {
    final found = await _found({
      'docs/$_domainDoc':
          '# Login domain\n\n${_sentenceOf(30)}\n\n'
          '## Entities\n\n- Account\n\n## Invariants\n\n- **INV-1** — Ok.\n',
    });
    expect(found, hasLength(1));
    expect(found.single.kind, FindingKind.wordsOverLimit);
    expect(found.single.path, _domainDoc);
    expect(
      found.single.toJson(),
      allOf(
        containsPair('section', '_lead'),
        isNot(contains('id')),
        containsPair('actual', 30),
      ),
    );
  });

  test(
    'a misplaced note in a table row gives trace_note_not_last at the row',
    () async {
      final found = await _found(
        fr(
          'A wrong password must not sign in.',
          '| Part | Responsibility |\n|---|---|\n'
              '| Form | Takes it (INV-4) now. |',
        ),
      );
      expect(found, hasLength(1));
      expect(found.single.kind, FindingKind.traceNoteNotLast);
      expect(found.single.line, lineOfFirst(_project, loginFr, '| Form |'));
      expect(
        found.single.toJson(),
        allOf(
          containsPair('section', 'rationale'),
          containsPair('note', '(INV-4)'),
        ),
      );
    },
  );

  group('a prose field value', () {
    const summaryLine = 'summary: Lets an agent sign in.';
    const noteLayer = '.specstone/templates/feature.yaml';

    Map<String, String> summary(String text) =>
        doc(loginFeature, summaryLine, 'summary: $text');

    Map<String, String> note(String text) => {
      ...doc(loginFeature, summaryLine, '$summaryLine\nnote: $text'),
      noteLayer:
          'fields:\n  - id: note\n    type: string\n'
          '    lint: {max_sentences: 1}\n',
    };

    test('over its word cap gives words_over_limit on the key line', () async {
      final found = await _found(summary(_sentenceOf(18)));
      expect(found, hasLength(1));
      expect(found.single.kind, FindingKind.wordsOverLimit);
      expect(found.single.path, loginFeature);
      expect(
        found.single.line,
        lineOfFirst(_project, loginFeature, 'summary:'),
      );
      expect(found.single.waitsFor, WaitsFor.agent);
      expect(
        found.single.toJson(),
        allOf(
          containsPair('field', 'summary'),
          containsPair('language', 'default'),
          containsPair('limit', 15),
          containsPair('actual', 18),
          containsPair('sentences', 1),
          isNot(contains('section')),
          isNot(contains('id')),
        ),
      );
    });

    test('of two sentences gives sentences_over_limit', () async {
      final found = await _found(summary('One short one. Another short one.'));
      expect(found, hasLength(1));
      expect(found.single.kind, FindingKind.sentencesOverLimit);
      expect(
        found.single.line,
        lineOfFirst(_project, loginFeature, 'summary:'),
      );
      expect(
        found.single.toJson(),
        allOf(
          containsPair('field', 'summary'),
          containsPair('limit', 1),
          containsPair('actual', 2),
        ),
      );
    });

    test('takes the Korean cap from the field alone', () async {
      final found = await _found(
        summary('${List.filled(12, '단어').join(' ')}.'),
      );
      expect(found, hasLength(1));
      expect(found.single.kind, FindingKind.wordsOverLimit);
      expect(
        found.single.toJson(),
        allOf(
          containsPair('language', 'ko'),
          containsPair('limit', 10),
          containsPair('actual', 12),
        ),
      );
    });

    test('weighs an English word in a Thai value by its own caps', () async {
      final found = await _found(summary('${'ก' * 57} check.'));
      expect(found, hasLength(1));
      expect(found.single.kind, FindingKind.sentenceCharsOverLimit);
      expect(
        found.single.toJson(),
        allOf(
          containsPair('field', 'summary'),
          containsPair('language', 'th'),
          containsPair('limit', 60),
          containsPair('actual', 61),
        ),
      );
    });

    test('of a field with no lint is never read', () async {
      final found = await _found(
        doc(
          loginFeature,
          summaryLine,
          '$summaryLine\nsystem: ${_sentenceOf(40)}',
        ),
      );
      expect(found, isEmpty);
    });

    test('of a field capping sentences alone ignores its length', () async {
      expect(await _found(note(_sentenceOf(40))), isEmpty);
      final found = await _found(note('One short one. Another short one.'));
      expect(found, hasLength(1));
      expect(found.single.kind, FindingKind.sentencesOverLimit);
      expect(found.single.toJson(), containsPair('field', 'note'));
    });
  });

  test('the cite-note guide line matches every shipped guide', () async {
    final project = await writeCheckProject();
    final types = TemplateResolver()
        .resolve(workingDirectory: project, homeDirectory: null)
        .docTypes
        .where(
          (type) => type.pack == 'prd-core' || type.pack == 'software-tech',
        )
        .toList();
    expect(types.map((type) => type.pack).toSet(), {
      'prd-core',
      'software-tech',
    });
    for (final type in types) {
      final lines = type.description!.split('\n');
      expect(lines, contains(citeNoteGuideLine), reason: type.id);
    }
  });
}

Map<String, String> _edgeCaseBlock(String body) =>
    fr('1. E01 — An empty password → refused.', body);
