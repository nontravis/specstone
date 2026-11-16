import 'package:specstone_core/src/document_writing/replace_passage.dart';
import 'package:specstone_core/src/document_writing/write_fault.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:test/test.dart';

Matcher throwsInvalid() => throwsA(
  isA<IndexFault>().having(
    (f) => f.code,
    'code',
    IndexFaultCode.argumentInvalid,
  ),
);

WriteFault writeFaultOf(void Function() run) {
  try {
    run();
  } on WriteFault catch (fault) {
    return fault;
  }
  throw StateError('no WriteFault thrown');
}

void main() {
  group('parseReplaceStdin', () {
    test('reads the old and the new passage between two marker lines', () {
      final read = parseReplaceStdin(
        '==> old <==\nSign in.\n==> new <==\nSign in fast.\n',
      );
      expect(read.oldPassage, 'Sign in.');
      expect(read.newPassage, 'Sign in fast.');
    });

    test('drops only the last LF of each passage', () {
      final read = parseReplaceStdin(
        '==> old <==\none\ntwo\n\n==> new <==\nthree\n\nfour\n\n',
      );
      expect(read.oldPassage, 'one\ntwo\n');
      expect(read.newPassage, 'three\n\nfour\n');
    });

    test('keeps a new passage that has no final LF', () {
      final read = parseReplaceStdin('==> old <==\na\n==> new <==\nb');
      expect(read.newPassage, 'b');
    });

    test('reads an empty new passage', () {
      expect(parseReplaceStdin('==> old <==\na\n==> new <==\n').newPassage, '');
      expect(parseReplaceStdin('==> old <==\na\n==> new <==').newPassage, '');
    });

    test('keeps an old passage that holds trailing spaces', () {
      final read = parseReplaceStdin('==> old <==\na  \n==> new <==\nb\n');
      expect(read.oldPassage, 'a  ');
    });

    test('reads a CRLF stdin, markers and both passages, as LF', () {
      final read = parseReplaceStdin(
        '==> old <==\r\none\r\ntwo\r\n==> new <==\r\nthree\r\nfour\r\n',
      );
      expect(read.oldPassage, 'one\ntwo');
      expect(read.newPassage, 'three\nfour');
    });

    test('keeps a lone CR inside the old passage', () {
      final read = parseReplaceStdin('==> old <==\na\rb\n==> new <==\nc\n');
      expect(read.oldPassage, 'a\rb');
    });

    test('refuses stdin whose first line is not the old marker', () {
      expect(
        () => parseReplaceStdin('a\n==> old <==\nb\n==> new <==\nc\n'),
        throwsInvalid(),
      );
      expect(
        () => parseReplaceStdin('\n==> old <==\nb\n==> new <==\nc\n'),
        throwsInvalid(),
      );
      expect(() => parseReplaceStdin(''), throwsInvalid());
    });

    test('refuses stdin with no new marker', () {
      expect(() => parseReplaceStdin('==> old <==\nb\n'), throwsInvalid());
    });

    test('refuses a second marker line', () {
      expect(
        () => parseReplaceStdin(
          '==> old <==\na\n==> new <==\nb\n==> new <==\nc\n',
        ),
        throwsInvalid(),
      );
      expect(
        () => parseReplaceStdin(
          '==> old <==\na\n==> old <==\nb\n==> new <==\nc\n',
        ),
        throwsInvalid(),
      );
      expect(
        () => parseReplaceStdin(
          '==> old <==\na\n==> new <==\nb\n==> old <==\nc\n',
        ),
        throwsInvalid(),
      );
    });

    test('refuses an empty old passage', () {
      expect(
        () => parseReplaceStdin('==> old <==\n==> new <==\nc\n'),
        throwsInvalid(),
      );
      expect(
        () => parseReplaceStdin('==> old <==\n\n==> new <==\nc\n'),
        throwsInvalid(),
      );
    });
  });

  group('replacedBody', () {
    const body = '\nOne fish.\nTwo fish.\n';

    test('replaces the one match and keeps every other byte', () {
      expect(
        replacedBody(body, 'One fish.', 'Red fish.', docPath: 'a.md'),
        '\nRed fish.\nTwo fish.\n',
      );
    });

    test('takes a new passage that holds dollar signs as written', () {
      expect(
        replacedBody(body, 'One fish.', r'$1 and \1', docPath: 'a.md'),
        '\n\$1 and \\1\nTwo fish.\n',
      );
    });

    test('removes the old passage for an empty new passage', () {
      expect(
        replacedBody(body, 'One fish.\n', '', docPath: 'a.md'),
        '\nTwo fish.\n',
      );
    });

    test('throws replace_unmatched when the old passage is not there', () {
      final fault = writeFaultOf(
        () => replacedBody(body, 'Blue fish.', 'x', docPath: 'a.md'),
      );
      expect(fault.code, WriteFaultCode.replaceUnmatched);
      expect(fault.exitStatus, 75);
      expect(fault.file, 'a.md');
    });

    test('never trims, folds case, or folds whitespace', () {
      for (final old in [
        'one fish.',
        'One fish. ',
        ' One fish.',
        'One  fish.',
      ]) {
        expect(
          writeFaultOf(() => replacedBody(body, old, 'x', docPath: 'a.md'))
              .code,
          WriteFaultCode.replaceUnmatched,
          reason: old,
        );
      }
    });

    test('throws replace_ambiguous with the count for two matches', () {
      final fault = writeFaultOf(
        () => replacedBody(body, 'fish.', 'x', docPath: 'a.md'),
      );
      expect(fault.code, WriteFaultCode.replaceAmbiguous);
      expect(fault.exitStatus, 64);
      expect(
        fault.message,
        'the old passage occurs 2 times in the section; send a longer '
        'passage that occurs once',
      );
    });

    test('counts non-overlapping occurrences', () {
      final fault = writeFaultOf(
        () => replacedBody('aaaa', 'aa', 'x', docPath: 'a.md'),
      );
      expect(fault.code, WriteFaultCode.replaceAmbiguous);
      expect(fault.message, contains('2 times'));
      expect(replacedBody('aaa', 'aa', 'x', docPath: 'a.md'), 'xa');
    });
  });
}
