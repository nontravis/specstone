import 'package:specstone_core/src/doc_model/trace_notes.dart';
import 'package:test/test.dart';

const _prefixes = {'INV-', 'RULE-', 'FR-'};

void main() {
  test('closing group of item links is stripped', () {
    final read = traceNotesOf(
      'A rule holds ([INV-74](DOMAIN.md#invariants), '
      '[INV-75](DOMAIN.md#invariants)).',
      _prefixes,
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
    );
    expect(read.notes, [(text: '(RULE-10)', closes: false)]);
    expect(read.counted, 'First clause (RULE-10) and more words.');
  });

  test('semicolon-joined group is one note', () {
    final read = traceNotesOf('A rule (RULE-1; RULE-2 and RULE-3).', _prefixes);
    expect(read.notes, [(text: '(RULE-1; RULE-2 and RULE-3)', closes: true)]);
    expect(read.counted, 'A rule');
  });

  test('ownership clause last closes', () {
    final read = traceNotesOf(
      'The recipe is fixed. INV-4 owns the recipe, and every other doc '
      'cites it.',
      _prefixes,
    );
    expect(read.notes.single.closes, isTrue);
    expect(read.counted, 'The recipe is fixed.');
    final before = traceNotesOf(
      'INV-4 owns the recipe. Another clause follows.',
      _prefixes,
    );
    expect(before.notes.single.closes, isFalse);
  });

  test('group then ownership clause', () {
    final read = traceNotesOf('A rule (RULE-1). INV-4 cites it.', _prefixes);
    expect(read.notes, [
      (text: '(RULE-1)', closes: false),
      (text: 'INV-4 cites it.', closes: true),
    ]);
    expect(read.counted, 'A rule (RULE-1).');
  });

  test('see parenthesis and grammar link are no note', () {
    const text = 'Read (see INV-4) and [INV-4](DOMAIN.md#invariants) today.';
    final read = traceNotesOf(text, _prefixes);
    expect(read.notes, isEmpty);
    expect(read.counted, text);
  });

  test('note before nested items closes', () {
    final read = traceNotesOf(
      '- A rule holds (RULE-5).\n  - nested one\n  - nested two',
      _prefixes,
    );
    expect(read.notes.single.closes, isTrue);
    expect(read.counted, '- A rule holds\n  - nested one\n  - nested two');
  });

  test('note closes its table cell', () {
    final read = traceNotesOf('| A rule (RULE-5) | next cell |', _prefixes);
    expect(read.notes, [(text: '(RULE-5)', closes: true)]);
    expect(read.counted, '| A rule | next cell |');
  });

  test('each table cell closes its own note', () {
    final read = traceNotesOf('| A (RULE-1) | B (RULE-2). |', _prefixes);
    expect(read.notes.every((note) => note.closes), isTrue);
    expect(read.counted, '| A | B |');
  });

  test('ownership note in thai is no note', () {
    final read = traceNotesOf('INV-4 เป็นเจ้าของสูตรนี้', _prefixes);
    expect(read.notes, isEmpty);
    expect(read.counted, 'INV-4 เป็นเจ้าของสูตรนี้');
    expect(traceNotesOf('สูตร (INV-4)', _prefixes).notes.single.closes, isTrue);
  });

  test('item of only a trace group closes', () {
    final read = traceNotesOf('(RULE-1, RULE-2)', _prefixes);
    expect(read.notes.single.closes, isTrue);
    expect(read.counted, '');
  });
}
