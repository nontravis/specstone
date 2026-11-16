import 'dart:io';

import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/consistency_check/readability_rules.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';

const _readabilityKinds = <FindingKind>{
  FindingKind.wordsOverLimit,
  FindingKind.sentenceCharsOverLimit,
  FindingKind.traceNoteNotLast,
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
    for (final f in checkOf(_project, docPath: docPath).findings)
      if (_readabilityKinds.contains(f.kind)) f,
  ];
}

// The file line of the first line of [docPath] holding [needle], in the
// project the last _found call wrote.
int _lineOf(String docPath, String needle) =>
    File('${_project.path}/docs/$docPath')
        .readAsLinesSync()
        .indexWhere((line) => line.contains(needle)) +
    1;

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
    expect(found.single.line, _lineOf(loginFr, 'E01'));
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
    expect(found.single.line, _lineOf(loginFr, '| Form |'));
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
    expect(found.single.line, _lineOf(loginFr, 'E01'));
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
        '### PV-01 — ระบบล็อกอินเดียว\n\n> en: ${_sentenceOf(25)}',
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
        containsPair('actual', 26),
      ),
    );
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
    expect(found.map((f) => f.line).toSet(), {_lineOf(loginFr, 'E01')});
  });

  test('misplaced note gives trace_note_not_last with note', () async {
    final found = await _found(
      _edgeCase('An empty password (INV-4) is refused.'),
    );
    expect(found, hasLength(1));
    expect(found.single.kind, FindingKind.traceNoteNotLast);
    expect(found.single.line, _lineOf(loginFr, 'E01'));
    expect(found.single.waitsFor, WaitsFor.agent);
    expect(
      found.single.toJson(),
      allOf(
        containsPair('section', 'edge_cases'),
        containsPair('id', 'E01'),
        containsPair('note', '(INV-4)'),
      ),
    );
    expect(found.single.message, contains(_noGuideTail));
  });

  test('a note that closes its item gives none', () async {
    final found = await _found(
      _edgeCase('An empty password is refused (INV-4).'),
    );
    expect(found, isEmpty);
  });

  test('each message ends with the guide line of its kind', () async {
    final words = await _found(_edgeCase(_sentenceOf(30)));
    expect(
      words.single.message,
      endsWith('$_noGuideTail$sentenceLengthGuideLine'),
    );
    final note = await _found(_edgeCase('A (INV-4) b.'));
    expect(note.single.message, endsWith('$_noGuideTail$citeNoteGuideLine'));
  });

  test('guide line constants match the shipped guide', () {
    final lines = fixtureDocTypeOf(loginFr).description!.split('\n');
    expect(lines, contains(sentenceLengthGuideLine));
    expect(lines, contains(citeNoteGuideLine));
  });
}

Map<String, String> _edgeCaseBlock(String body) =>
    fr('1. E01 — An empty password → refused.', body);
