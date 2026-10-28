import 'package:specstone_core/src/consistency_check/doc_lines.dart';
import 'package:test/test.dart';

void main() {
  const text =
      '---\nstatus: planned\ntraced_from:\n  - S1\n  - S2\nowner: x\n---\n\n'
      '# Title\n\n'
      '## Statement\nBody.\n';

  test(
    'cc-s03/inv14: key, entry, and section lines are 1-based in the file',
    () {
      final lines = DocLines.of(text);
      expect(lines.keyLine('status'), 2);
      expect(lines.keyLine('missing'), isNull);
      expect(lines.entriesOf('traced_from'), [
        (value: 'S1', line: 4, text: 'S1'),
        (value: 'S2', line: 5, text: 'S2'),
      ]);
      expect(lines.entriesOf('owner'), [(value: 'x', line: 6, text: 'x')]);
      expect(lines.sectionLines, [11]);
      expect(lines.lines, hasLength(12));
      expect(lines.frontmatterErrorLine, isNull);
    },
  );

  test(
    'review focus 1: a CRLF file has the lines and counts of its LF twin',
    () {
      final lf = DocLines.of(text);
      final crlf = DocLines.of(text.replaceAll('\n', '\r\n'));
      expect(crlf.lines, lf.lines);
      expect(crlf.charCount, lf.charCount);
      expect(crlf.sectionLines, lf.sectionLines);
      expect(crlf.entriesOf('traced_from'), lf.entriesOf('traced_from'));
    },
  );

  test(
    'review focus 2: a ## line inside a fenced code block is no section',
    () {
      final lines = DocLines.of(
        '# T\n\n```\n## not a section\n```\n\n## Real\nx\n',
      );
      expect(lines.sectionLines, [7]);
    },
  );

  test('f04/us01/fr03/e07: frontmatter YAML with an unclosed quote names the parser line', () {
    expect(
      DocLines.of('---\ntitle: "open\n---\n\n# T\n').frontmatterErrorLine,
      3,
    );
    expect(DocLines.of('---\n- a list\n---\n').frontmatterErrorLine, 1);
    expect(DocLines.of('# No frontmatter\n').keyLine('status'), isNull);
  });

  test('review: a backtick fence with a backtick in its info string is no '
      'fence', () {
    final lines = DocLines.of('# T\n\n```x``` inline\n\n## Real\nx\n');
    expect(lines.sectionLines, [5]);
  });

  test('review: empty frontmatter is valid and holds no keys', () {
    final lines = DocLines.of('---\n---\n');
    expect(lines.frontmatterErrorLine, isNull);
    expect(lines.keyLine('status'), isNull);
  });

  test('a bare key, or a bare list item, has no entry', () {
    final lines = DocLines.of(
      '---\nconfirmed:\nimplements:\n  - \n  - a\n---\n',
    );
    expect(lines.entriesOf('confirmed'), isEmpty);
    expect([for (final e in lines.entriesOf('implements')) e.value], ['a']);
  });

  test(
    'isFenced is true for a fence line and its content, and false elsewhere',
    () {
      final lines = DocLines.of(
        '---\nk: v\n---\n# T\n```\n### x\n```\nafter\n',
      );
      expect(
        [for (var line = 1; line <= 9; line++) lines.isFenced(line)],
        [false, false, false, false, true, true, true, false, false],
      );
    },
  );
}
