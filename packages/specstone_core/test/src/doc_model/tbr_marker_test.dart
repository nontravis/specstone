import 'package:specstone_core/src/doc_model/tbr_marker.dart';
import 'package:specstone_core/src/rendering/line_ending.dart';
import 'package:test/test.dart';

void main() {
  group('tbrMarkerLinesIn', () {
    test('consistency_check/find_template_breaks/report_open_tbrs E02: a '
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

    test('consistency_check/find_template_breaks/report_open_tbrs E03: a '
        'marker inside a code span is no marker', () {
      expect(tbrMarkerLinesIn('The form is `TBR — <why>` here.\n'), isEmpty);
      expect(tbrMarkerLinesIn('A ``TBR — x`` and `TBR — y`.\n'), isEmpty);
    });

    test('consistency_check/find_template_breaks/report_open_tbrs E03: a '
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

    test('consistency_check/find_template_breaks/report_open_tbrs E03: a '
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

    test('consistency_check/find_template_breaks/report_open_tbrs E03: a '
        'marker after a code span on the same line is still read', () {
      expect(tbrMarkerLinesIn('See `x` then TBR — later.\n'), [
        (line: 0, rest: 'later.'),
      ]);
    });

    test('consistency_check/find_template_breaks/report_open_tbrs E07: a '
        'hyphen, a missing dash, or a missing space is no marker', () {
      const body =
          'TBR - hyphen\n'
          'TBR no dash\n'
          'TBR: colon\n'
          'TBR —no space\n'
          'TBR – en dash\n';
      expect(tbrMarkerLinesIn(body), isEmpty);
    });

    test('consistency_check/find_template_breaks/report_open_tbrs: a marker '
        'at the start of a line and after a bold label is read', () {
      const body =
          'TBR — first\n'
          '**Consistency:** TBR — legacy states none\n';
      expect(tbrMarkerLinesIn(body), [
        (line: 0, rest: 'first'),
        (line: 1, rest: 'legacy states none'),
      ]);
    });

    test('consistency_check/find_template_breaks/report_open_tbrs: two '
        'markers on one line give two places at that line', () {
      expect(tbrMarkerLinesIn('TBR — a and TBR — b\n'), [
        (line: 0, rest: 'a and TBR — b'),
        (line: 0, rest: 'b'),
      ]);
    });

    test('consistency_check/find_template_breaks/report_open_tbrs: a CRLF '
        'body reads as its LF text, with no carriage return in the rest', () {
      const lf = '# T\n\nTBR — gap\n```\nTBR — code\n```\nTBR — more\n';
      final crlf = lf.replaceAll('\n', '\r\n');
      expect(tbrMarkerLinesIn(toLf(crlf)), tbrMarkerLinesIn(lf));
      expect(tbrMarkerLinesIn(lf), [
        (line: 2, rest: 'gap'),
        (line: 6, rest: 'more'),
      ]);
    });

    test('consistency_check/find_template_breaks/report_open_tbrs: a body '
        'with no marker, or an empty one, gives none', () {
      expect(tbrMarkerLinesIn(''), isEmpty);
      expect(tbrMarkerLinesIn('# T\n\nplain\n'), isEmpty);
    });
  });
}
