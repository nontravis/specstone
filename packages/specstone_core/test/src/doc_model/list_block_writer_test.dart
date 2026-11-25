import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/list_block_writer.dart';
import 'package:test/test.dart';

KeyBlock _block(String text, {String key = 'tests'}) => KeyBlock(key, text);

void main() {
  group('entries that stay', () {
    test('one entry added to a 92-entry block changes one line', () {
      final held = [for (var i = 0; i < 92; i++) 'item$i:test/t$i.dart'];
      final text = "tests:\n${[for (final e in held) "  - '$e'\n"].join()}";

      final written = listBlockOf('tests', [
        ...held,
        'item92:test/t92.dart',
      ], onDisk: _block(text));

      expect(written, "$text  - 'item92:test/t92.dart'\n");
    });

    test('a removed entry takes its lines and every other line stays', () {
      const text = "tests:\n  - 'a:x'\n  - 'b:y'\n  - 'c:z'\n";

      final written = listBlockOf('tests', [
        'a:x',
        'c:z',
      ], onDisk: _block(text));

      expect(written, "tests:\n  - 'a:x'\n  - 'c:z'\n");
    });

    test('a comment above an entry moves with it and a trailing one stays', () {
      const text =
          'tests:\n'
          '  # first\n'
          '  - a # one\n'
          '\n'
          '  # second\n'
          '  - b   # two\n'
          '  # tail\n';

      final written = listBlockOf('tests', ['b'], onDisk: _block(text));

      expect(written, 'tests:\n\n  # second\n  - b   # two\n  # tail\n');
    });

    test('an entry equal by YAML value keeps its lines, quoted or not', () {
      const text = 'tests:\n  - "a"\n  - b\n';

      final written = listBlockOf('tests', ['a', 'b'], onDisk: _block(text));

      expect(written, text);
    });

    test('the entries stand in the order given', () {
      const text = 'tests:\n  - a\n  - b\n  - c\n';

      final written = listBlockOf('tests', [
        'c',
        'a',
        'b',
      ], onDisk: _block(text));

      expect(written, 'tests:\n  - c\n  - a\n  - b\n');
    });

    test('a key spelled with quotes keeps its spelling', () {
      final held = _block("'tests':\n  - a\n", key: "'tests'");

      final written = listBlockOf('tests', ['a', 'b'], onDisk: held);

      expect(written, "'tests':\n  - a\n  - b\n");
    });
  });

  group('comment lines above an entry', () {
    test('go with a changed entry', () {
      const text = 'tests:\n  # why a\n  - a\n  - b\n';

      final written = listBlockOf('tests', ['x', 'b'], onDisk: _block(text));

      expect(written, 'tests:\n  - x\n  - b\n');
    });

    test('go with a removed entry', () {
      const text = 'tests:\n  - a\n  # why b\n  - b\n';

      final written = listBlockOf('tests', ['a'], onDisk: _block(text));

      expect(written, 'tests:\n  - a\n');
    });
  });

  group('new and changed entries', () {
    test(
      'a changed entry takes the indent and quotes of the first kept entry',
      () {
        const text = "tests:\n    - 'a:x'\n    - 'b:y'\n";

        final written = listBlockOf('tests', [
          'a:x',
          'b:z',
        ], onDisk: _block(text));

        expect(written, "tests:\n    - 'a:x'\n    - 'b:z'\n");
      },
    );

    test('a double-quoted first kept entry gives double quotes', () {
      const text = 'tests:\n  - "a"\n  - "b"\n';

      final written = listBlockOf('tests', ['a', 'c'], onDisk: _block(text));

      expect(written, 'tests:\n  - "a"\n  - "c"\n');
    });

    test('no entry kept: the first entry on disk gives the style', () {
      const text = "tests:\n  - 'a'\n  - b\n";

      final written = listBlockOf('tests', ['x', 'y'], onDisk: _block(text));

      expect(written, "tests:\n  - 'x'\n  - 'y'\n");
    });

    test('a new entry that plain text cannot hold is single-quoted', () {
      const text = 'tests:\n  - a\n';

      final written = listBlockOf('tests', [
        'a',
        'S1: x',
        'true',
        "it's # not",
      ], onDisk: _block(text));

      expect(
        written,
        "tests:\n  - a\n  - 'S1: x'\n  - 'true'\n  - 'it''s # not'\n",
      );
    });

    test('a non-string entry is written as its YAML value', () {
      final written = listBlockOf('ids', [
        1,
        true,
      ], onDisk: _block("ids:\n  - '1'\n", key: 'ids'));

      expect(written, 'ids:\n  - 1\n  - true\n');
    });
  });

  group('an empty or absent block', () {
    test('writes each entry plain, indented two spaces', () {
      final written = listBlockOf('tests', ['a:x', 'b y']);

      expect(written, 'tests:\n  - a:x\n  - b y\n');
    });

    test('writes an entry YAML would read as another value single-quoted', () {
      final written = listBlockOf('tests', ['S1: x', 'true', '12', '- a', '']);

      expect(
        written,
        "tests:\n  - 'S1: x'\n  - 'true'\n  - '12'\n  - '- a'\n  - ''\n",
      );
    });

    test('a key line alone takes the entries below it', () {
      final written = listBlockOf('tests', ['a'], onDisk: _block('tests:\n'));

      expect(written, 'tests:\n  - a\n');
    });

    test('an empty entry list writes an empty YAML list', () {
      expect(listBlockOf('tests', const []), 'tests: []\n');
    });

    test('a multi-line string is written double-quoted on one line', () {
      expect(listBlockOf('tests', ['a\nb']), 'tests:\n  - "a\\nb"\n');
    });
  });

  group('a block that is not a plain one-line-item list', () {
    test('a flow list is written anew as a block list', () {
      final written = listBlockOf('tests', [
        'a',
        'b',
      ], onDisk: _block("tests: ['a', 'b']\n"));

      expect(written, 'tests:\n  - a\n  - b\n');
    });

    test('a folded item is written anew as a block list', () {
      const text = 'tests:\n  - >-\n    a\n';

      final written = listBlockOf('tests', ['a'], onDisk: _block(text));

      expect(written, 'tests:\n  - a\n');
    });

    test('a scalar block is written anew as a block list', () {
      final written = listBlockOf('tests', [
        'a',
        'b',
      ], onDisk: _block('tests: a\n'));

      expect(written, 'tests:\n  - a\n  - b\n');
    });
  });

  group('the entries of a block', () {
    test('a list gives its items', () {
      expect(listEntriesOf(_block("tests:\n  - 'a'\n  - 1\n")), ['a', 1]);
    });

    test('a scalar gives itself, an empty value none', () {
      expect(listEntriesOf(_block('tests: a\n')), ['a']);
      expect(listEntriesOf(_block('tests:\n')), isEmpty);
    });

    test('invalid YAML gives null', () {
      expect(listEntriesOf(_block('tests: [a\n')), isNull);
    });

    test('what it reads, the writer keeps byte for byte', () {
      const text = "tests:\n  - 'a'\n  # c\n  - b\n";
      final block = _block(text);

      expect(listBlockOf('tests', listEntriesOf(block)!, onDisk: block), text);
    });
  });
}
