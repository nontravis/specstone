import 'package:specstone_core/src/doc_model/trace_notes.dart';
import 'package:test/test.dart';

const _prefixes = {'INV-', 'RULE-', 'FR-'};

void main() {
  test('closing group of item links is stripped', () {
    final read = traceNotesOf(
      'A rule holds ([INV-74](DOMAIN.md#invariants), '
      '[INV-75](DOMAIN.md#invariants)).',
      _prefixes,
      isTableRow: false,
    );
    expect(read.notes, [
      (
        text:
            '([INV-74](DOMAIN.md#invariants), [INV-75](DOMAIN.md#invariants))',
        closes: true,
      ),
    ]);
    expect(read.counted, 'A rule holds');
  });

  test('group after first clause is misplaced', () {
    final read = traceNotesOf(
      'First clause (RULE-10) and more words.',
      _prefixes,
      isTableRow: false,
    );
    expect(read.notes, [(text: '(RULE-10)', closes: false)]);
    expect(read.counted, 'First clause (RULE-10) and more words.');
  });

  test('semicolon-joined group is one note', () {
    final read = traceNotesOf(
      'A rule (RULE-1; RULE-2 and RULE-3).',
      _prefixes,
      isTableRow: false,
    );
    expect(read.notes, [(text: '(RULE-1; RULE-2 and RULE-3)', closes: true)]);
    expect(read.counted, 'A rule');
  });

  test('ownership clause last closes', () {
    final read = traceNotesOf(
      'The recipe is fixed. INV-4 owns the recipe, and every other doc '
      'cites it.',
      _prefixes,
      isTableRow: false,
    );
    expect(read.notes.single.closes, isTrue);
    expect(read.counted, 'The recipe is fixed.');
    final before = traceNotesOf(
      'INV-4 owns the recipe. Another clause follows.',
      _prefixes,
      isTableRow: false,
    );
    expect(before.notes.single.closes, isFalse);
  });

  test('group then ownership clause', () {
    final read = traceNotesOf(
      'A rule (RULE-1). INV-4 cites it.',
      _prefixes,
      isTableRow: false,
    );
    expect(read.notes, [
      (text: '(RULE-1)', closes: false),
      (text: 'INV-4 cites it', closes: true),
    ]);
    expect(read.counted, 'A rule (RULE-1).');
  });

  test('see parenthesis and grammar link are no note', () {
    const text = 'Read (see INV-4) and [INV-4](DOMAIN.md#invariants) today.';
    final read = traceNotesOf(text, _prefixes, isTableRow: false);
    expect(read.notes, isEmpty);
    expect(read.counted, text);
  });

  test('note before nested items closes', () {
    final read = traceNotesOf(
      '- A rule holds (RULE-5).\n  - nested one\n  - nested two',
      _prefixes,
      isTableRow: false,
    );
    expect(read.notes.single.closes, isTrue);
    expect(read.counted, '- A rule holds\n  - nested one\n  - nested two');
  });

  test('note closes its table cell', () {
    final read = traceNotesOf(
      '| A rule (RULE-5) | next cell |',
      _prefixes,
      isTableRow: true,
    );
    expect(read.notes, [(text: '(RULE-5)', closes: true)]);
    expect(read.counted, '| A rule | next cell |');
  });

  test('each table cell closes its own note', () {
    final read = traceNotesOf(
      '| A (RULE-1) | B (RULE-2). |',
      _prefixes,
      isTableRow: true,
    );
    expect(read.notes.every((note) => note.closes), isTrue);
    expect(read.counted, '| A | B |');
  });

  test('ownership note in thai is no note', () {
    final read = traceNotesOf(
      'INV-4 เป็นเจ้าของสูตรนี้',
      _prefixes,
      isTableRow: false,
    );
    expect(read.notes, isEmpty);
    expect(read.counted, 'INV-4 เป็นเจ้าของสูตรนี้');
    expect(
      traceNotesOf(
        'สูตร (INV-4)',
        _prefixes,
        isTableRow: false,
      ).notes.single.closes,
      isTrue,
    );
  });

  test('item of only a trace group closes', () {
    final read = traceNotesOf('(RULE-1, RULE-2)', _prefixes, isTableRow: false);
    expect(read.notes.single.closes, isTrue);
    expect(read.counted, '');
  });

  test('ownership clause closes its table cell', () {
    final read = traceNotesOf(
      '| A | INV-4 owns the recipe. | next |',
      _prefixes,
      isTableRow: true,
    );
    expect(read.notes, [(text: 'INV-4 owns the recipe', closes: true)]);
    expect(read.counted, '| A | | next |');
  });

  test('ownership clause before more cell text is misplaced', () {
    final read = traceNotesOf(
      '| INV-4 owns it. More words | next |',
      _prefixes,
      isTableRow: true,
    );
    expect(read.notes, [(text: 'INV-4 owns it', closes: false)]);
    expect(read.counted, '| INV-4 owns it. More words | next |');
  });

  test('row with a trailing line feed is still a row', () {
    final read = traceNotesOf(
      '| A (RULE-1) | B |\n',
      _prefixes,
      isTableRow: true,
    );
    expect(read.notes, [(text: '(RULE-1)', closes: true)]);
    expect(read.counted, '| A | B |\n');
  });

  test('lettered scenario link is no note part', () {
    expect(
      traceNotesOf('Rule ([S1a](x.md#a)).', _prefixes, isTableRow: false).notes,
      isEmpty,
    );
    final read = traceNotesOf(
      'Rule ([S1](x.md#a), [s/y#S2](x.md#a)).',
      _prefixes,
      isTableRow: false,
    );
    expect(read.notes.single.closes, isTrue);
  });

  test('to and comma separators join one group', () {
    expect(
      traceNotesOf(
        'Rule (RULE-1 to RULE-3).',
        _prefixes,
        isTableRow: false,
      ).notes.single.closes,
      isTrue,
    );
    expect(
      traceNotesOf(
        'Rule (RULE-1, RULE-3).',
        _prefixes,
        isTableRow: false,
      ).notes.single.closes,
      isTrue,
    );
  });

  test('paren held by a code span or escaped is no group', () {
    expect(
      traceNotesOf('Use `(RULE-1)` here.', _prefixes, isTableRow: false).notes,
      isEmpty,
    );
    expect(
      traceNotesOf(r'Use \(RULE-1) here.', _prefixes, isTableRow: false).notes,
      isEmpty,
    );
  });

  test('doc link inside a group is no note', () {
    expect(
      traceNotesOf(
        'Rule ([the doc](DOMAIN.md)).',
        _prefixes,
        isTableRow: false,
      ).notes,
      isEmpty,
    );
  });

  test('blank line before nested items keeps the note closing', () {
    final read = traceNotesOf(
      '- A rule (RULE-5).\n\n  - nested',
      _prefixes,
      isTableRow: false,
    );
    expect(read.notes.single.closes, isTrue);
    expect(read.counted, '- A rule\n\n  - nested');
  });

  test('wrapped clause drops quote marks and the stop', () {
    final read = traceNotesOf(
      '> A rule.\n> INV-4 owns\n> it.',
      _prefixes,
      isTableRow: false,
    );
    expect(read.notes, [(text: 'INV-4 owns it', closes: true)]);
  });

  test('row with no outer pipes closes each cell', () {
    final read = traceNotesOf('A (RULE-1) | B', _prefixes, isTableRow: true);
    expect(read.notes, [(text: '(RULE-1)', closes: true)]);
    expect(read.counted, 'A | B');
  });

  test('row with no outer pipes finds a clause in its last cell', () {
    final read = traceNotesOf('A | INV-4 owns x.', _prefixes, isTableRow: true);
    expect(read.notes, [(text: 'INV-4 owns x', closes: true)]);
  });

  test('paragraph holding a pipe stays one scope', () {
    final read = traceNotesOf('A (RULE-1) | B', _prefixes, isTableRow: false);
    expect(read.notes, [(text: '(RULE-1)', closes: false)]);
    expect(read.counted, 'A (RULE-1) | B');
  });

  test('a sentence of 70,000 characters is read, no regex built from it', () {
    final read = traceNotesOf(
      '${'a' * 70000}. INV-4 owns it.',
      _prefixes,
      isTableRow: false,
    );
    expect(read.notes, [(text: 'INV-4 owns it', closes: true)]);
  });

  test('clause holding a lone > word is found', () {
    final read = traceNotesOf(
      'A rule. INV-4 owns a > b here.',
      _prefixes,
      isTableRow: false,
    );
    expect(read.notes, [(text: 'INV-4 owns a > b here', closes: true)]);
  });
}
