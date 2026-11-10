import 'dart:convert';
import 'dart:math';

// The pin reads the pattern of the pinned `markdown` itself, which its public
// library does not export.
import 'package:markdown/markdown.dart' show ExtensionSet, markdownToHtml;
import 'package:markdown/src/patterns.dart' show tablePattern;
import 'package:specstone_core/src/doc_model/markdown_lines.dart';
import 'package:specstone_core/src/templates/shipped_pack_files.dart';
import 'package:test/test.dart';

import '../../helpers/write_fixture.dart' show writeProject;

/// Every line of the fixture docs and of the shipped packs.
Iterable<String> _fixtureLines() sync* {
  for (final text in writeProject.values) {
    yield* const LineSplitter().convert(text);
  }
  for (final bytes in shippedPackFiles.values) {
    yield* const LineSplitter().convert(
      utf8.decode(bytes, allowMalformed: true),
    );
  }
}

/// Every string of up to [length] characters over the characters a delimiter
/// row is made of, so each shape of one is met, the near misses included.
Iterable<String> _shortRows(int length) sync* {
  const alphabet = [' ', '\t', '|', '-', ':', 'a'];
  var rows = [''];
  for (var n = 0; n < length; n++) {
    rows = [
      for (final row in rows)
        for (final char in alphabet) '$row$char',
    ];
    yield* rows;
  }
}

/// Returns rows of 1 to 12 cells with a random indent, edge pipes, spacing,
/// colons, and tail, most of them delimiter rows and some of them not.
Iterable<String> _wideRows() sync* {
  final random = Random(11);
  const tails = ['', ' ', '|', ' |', ' x', 'x', ' | n/a |', '-:', ':'];
  String pad() => ' ' * random.nextInt(3);
  for (var round = 0; round < 4000; round++) {
    final cells = [
      for (var i = 0, n = 1 + random.nextInt(12); i < n; i++)
        pad() +
            (random.nextBool() ? ':' : '') +
            '-' * (1 + random.nextInt(3)) +
            (random.nextBool() ? ':' : '') +
            pad(),
    ];
    yield '${' ' * random.nextInt(6)}${random.nextBool() ? '|' : ''}'
        '${cells.join('|')}${tails[random.nextInt(tails.length)]}';
  }
}

void main() {
  group('atxHeadingOf', () {
    test('reads the level and the text of a heading', () {
      expect(atxHeadingOf('# Title'), (level: 1, text: 'Title'));
      expect(atxHeadingOf('## Section'), (level: 2, text: 'Section'));
      expect(atxHeadingOf('### Edge case. Two'), (
        level: 3,
        text: 'Edge case. Two',
      ));
      expect(atxHeadingOf('   ###### Deep'), (level: 6, text: 'Deep'));
    });

    test('drops a closing run of # and trailing spaces', () {
      expect(atxHeadingOf('#### Deeper ####'), (level: 4, text: 'Deeper'));
      expect(atxHeadingOf('### Foo  '), (level: 3, text: 'Foo'));
      expect(atxHeadingOf('### Foo#'), (level: 3, text: 'Foo#'));
    });

    test('reads a heading with no text as empty text', () {
      expect(atxHeadingOf('###'), (level: 3, text: ''));
      expect(atxHeadingOf('### ###'), (level: 3, text: ''));
      expect(atxHeadingOf('### ##'), (level: 3, text: ''));
    });

    test('reads no heading from a line that is none', () {
      expect(atxHeadingOf('#hashtag'), isNull);
      expect(atxHeadingOf('####### seven'), isNull);
      expect(atxHeadingOf('    ### indented code'), isNull);
      expect(atxHeadingOf('plain # text'), isNull);
    });
  });

  group('isTableDelimiterRow', () {
    test('accepts a delimiter row with or without edge pipes and colons', () {
      expect(isTableDelimiterRow('|---|---|'), isTrue);
      expect(isTableDelimiterRow('| :--- | :---: | ---: |'), isTrue);
      expect(isTableDelimiterRow('--- | ---'), isTrue);
      expect(isTableDelimiterRow('  |-|-|  '), isTrue);
    });

    test('rejects a row that holds text or no pipe', () {
      expect(isTableDelimiterRow('| a | b |'), isFalse);
      expect(isTableDelimiterRow('---'), isFalse);
      expect(isTableDelimiterRow('|---| text'), isFalse);
      expect(isTableDelimiterRow(''), isFalse);
    });

    test('rejects a one-column row with no closing pipe, as package:markdown '
        '7.3.1 renders it as a paragraph', () {
      expect(isTableDelimiterRow('|---'), isFalse);
      expect(isTableDelimiterRow('|:--:'), isFalse);
      expect(isTableDelimiterRow('| --- |'), isTrue);
    });

    test('rejects a row with a leading pipe indented 4 spaces or more', () {
      expect(isTableDelimiterRow('    |---|'), isFalse);
    });

    test('reads every line of the fixtures and of generated rows as '
        'package:markdown does', () {
      final lines = [..._fixtureLines(), ..._shortRows(7), ..._wideRows()];
      var delimiters = 0;
      for (final line in lines) {
        final expected = tablePattern.hasMatch(line);
        if (expected) delimiters++;
        expect(isTableDelimiterRow(line), expected, reason: '"$line"');
      }
      expect(delimiters, greaterThan(1000)); // the corpus holds real rows
    });

    test('answers a failing 26-cell row within 50 ms', () {
      final row = '| ${List.filled(26, '-').join(' | ')} | n/a x';
      final watch = Stopwatch()..start();

      expect(isTableDelimiterRow(row), isFalse);
      expect(watch.elapsedMilliseconds, lessThan(50));
    });
  });

  group('isThematicBreak', () {
    test('accepts three or more of one mark, spaced or not', () {
      for (final line in ['---', '***', '___', '* * *', ' - - - -', '----  ']) {
        expect(isThematicBreak(line), isTrue, reason: line);
      }
    });

    test('rejects two marks, mixed marks, text, and a 4-space indent', () {
      for (final line in ['--', '-*-', '--- x', '    ---', 'a---', '']) {
        expect(isThematicBreak(line), isFalse, reason: line);
      }
    });
  });

  group('startsTable', () {
    test('needs a delimiter row below the header and as many header cells as '
        'the delimiter row has columns, edge pipes optional', () {
      expect(startsTable('a | b', '--- | ---'), isTrue);
      expect(startsTable('| a | b |', '|---|---|'), isTrue);
      expect(startsTable('abc', '|---|'), isTrue);
      expect(startsTable('a | b | c', '--- | ---'), isFalse);
      expect(startsTable('a | b', 'c | d'), isFalse);
      expect(startsTable('a | b', '---'), isFalse);
    });

    test('agrees with markdown 7.3.1 on whether a header and a delimiter row '
        'make a table', () {
      const headers = [
        'a',
        'abc',
        'a | b',
        '| a | b |',
        'a | b | c',
        'a |',
        '| a',
        '|',
        r'a \| b',
        r'a \| b | c',
        '`a | b`',
        'a || b',
        ' a | b ',
        r'a \',
        r'a | \',
      ];
      const delimiters = [
        '---',
        '|---|',
        '--- | ---',
        '|---|---|',
        '|:--|--:|',
        '---|---|---',
        ':-:|:-:',
        '|---',
        '---|',
        '| - |  - |',
        '|---|---|---|',
        'x | y',
        '| --- | --- |',
        ' |-|-| ',
      ];
      var tables = 0;
      for (final header in headers) {
        for (final delimiter in delimiters) {
          final html = markdownToHtml(
            '$header\n$delimiter\nrow\n',
            extensionSet: ExtensionSet.gitHubFlavored,
          );
          final isTable = html.contains('<table>');
          if (isTable) tables++;
          expect(
            startsTable(header, delimiter),
            isTable,
            reason: 'header "$header", delimiter "$delimiter"',
          );
        }
      }
      expect(tables, greaterThan(20));
    });
  });
}
