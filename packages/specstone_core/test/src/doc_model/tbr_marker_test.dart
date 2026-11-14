import 'package:specstone_core/src/doc_model/tbr_marker.dart';
import 'package:specstone_core/src/rendering/line_ending.dart';
import 'package:test/test.dart';

void main() {
  group('tbrMarkerLinesIn', () {
    test('E02: a '
        'marker in a paragraph and in a table cell is read at its line', () {
      const body =
          '# T\n'
          '\n'
          'The timeout is TBR — the benchmark has not run.\n'
          '\n'
          '| Field | Note |\n'
          '|---|---|\n'
          '| limit | TBR — pick a value |\n';
      expect(tbrMarkerLinesIn(body), [
        (line: 2, rest: 'the benchmark has not run.'),
        (line: 6, rest: 'pick a value |'),
      ]);
    });

    test('E02: the '
        'text of a marker ends at the next marker on its line', () {
      expect(tbrMarkerLinesIn('TBR — pick one TBR — and two\n'), [
        (line: 0, rest: 'pick one'),
        (line: 0, rest: 'and two'),
      ]);
    });

    test('E02: a '
        'line of 5,000 markers stores no text between them', () {
      final found = tbrMarkerLinesIn('${'TBR — ' * 5000}\n');

      expect(found, hasLength(5000));
      expect(found.every((marker) => marker.rest.isEmpty), isTrue);
    });

    test('E03: a '
        'marker inside a code span is no marker', () {
      expect(tbrMarkerLinesIn('The form is `TBR — <why>` here.\n'), isEmpty);
      expect(tbrMarkerLinesIn('A ``TBR — x`` and `TBR — y`.\n'), isEmpty);
    });

    test('E03: a '
        'marker inside fenced code is no marker, and one after it is', () {
      const body =
          'Before.\n'
          '```\n'
          'TBR — in a backtick fence\n'
          '```\n'
          '~~~md\n'
          'TBR — in a tilde fence\n'
          '~~~\n'
          'TBR — after the fences\n';
      expect(tbrMarkerLinesIn(body), [(line: 7, rest: 'after the fences')]);
    });

    test('E03: a '
        'longer fence holds a shorter fence line and its marker', () {
      const body =
          '````md\n'
          '```\n'
          'TBR \u2014 in the long backtick fence\n'
          '````\n'
          '~~~~\n'
          '~~~\n'
          'TBR \u2014 in the long tilde fence\n'
          '~~~~\n'
          'TBR \u2014 after both\n';
      expect(tbrMarkerLinesIn(body), [(line: 8, rest: 'after both')]);
    });

    test('E03: a '
        'marker after a code span on the same line is still read', () {
      expect(tbrMarkerLinesIn('See `x` then TBR — later.\n'), [
        (line: 0, rest: 'later.'),
      ]);
    });

    test('E07: a '
        'hyphen, a missing dash, or a missing space is no marker', () {
      const body =
          'TBR - hyphen\n'
          'TBR no dash\n'
          'TBR: colon\n'
          'TBR —no space\n'
          'TBR – en dash\n';
      expect(tbrMarkerLinesIn(body), isEmpty);
    });

    test('E02: a '
        'marker at the end of its line has an empty text', () {
      expect(tbrMarkerLinesIn('TBR —\nTBR — \nA gap TBR —\n'), [
        (line: 0, rest: ''),
        (line: 1, rest: ''),
        (line: 2, rest: ''),
      ]);
      expect(tbrMarkerLinesIn('TBR — a TBR —\n'), [
        (line: 0, rest: 'a'),
        (line: 0, rest: ''),
      ]);
    });

    test('E07: a '
        'dash with no space after it, or a hyphen, is no marker even at a '
        'line end', () {
      expect(tbrMarkerLinesIn('TBR—x\nTBR -\nTBR —x TBR - y\n'), isEmpty);
      expect(tbrMarkerLinesIn('TBR —x TBR — y\n'), [(line: 0, rest: 'y')]);
    });

    test('a marker '
        'at the start of a line and after a bold label is read', () {
      const body =
          'TBR — first\n'
          '**Consistency:** TBR — legacy states none\n';
      expect(tbrMarkerLinesIn(body), [
        (line: 0, rest: 'first'),
        (line: 1, rest: 'legacy states none'),
      ]);
    });

    test('two '
        'markers on one line give two places at that line', () {
      expect(tbrMarkerLinesIn('TBR — a and TBR — b\n'), [
        (line: 0, rest: 'a and'),
        (line: 0, rest: 'b'),
      ]);
    });

    test('a CRLF '
        'body reads as its LF text, with no carriage return in the rest', () {
      const lf = '# T\n\nTBR — gap\n```\nTBR — code\n```\nTBR — more\n';
      final crlf = lf.replaceAll('\n', '\r\n');
      expect(tbrMarkerLinesIn(toLf(crlf)), tbrMarkerLinesIn(lf));
      expect(tbrMarkerLinesIn(lf), [
        (line: 2, rest: 'gap'),
        (line: 6, rest: 'more'),
      ]);
    });

    test('a body '
        'with no marker, or an empty one, gives none', () {
      expect(tbrMarkerLinesIn(''), isEmpty);
      expect(tbrMarkerLinesIn('# T\n\nplain\n'), isEmpty);
    });
  });
}
