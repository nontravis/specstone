import 'package:specstone_core/src/rendering/line_ending.dart';
import 'package:test/test.dart';

void main() {
  group('LineEnding.of', () {
    test('f05/us01/fr07/e01: the first line break decides: CRLF', () {
      expect(LineEnding.of('# T\r\n\r\nbody\r\n'), LineEnding.crlf);
    });

    test('f05/us01/fr07: the first line break decides: LF', () {
      expect(LineEnding.of('# T\n\nbody\r\n'), LineEnding.lf);
    });

    test('f05/us01/fr07/e02: no line break is LF', () {
      expect(LineEnding.of('# T'), LineEnding.lf);
      expect(LineEnding.of(''), LineEnding.lf);
    });

    test('f05/us01/fr07: a text that starts with a line break is LF', () {
      expect(LineEnding.of('\n\r\n'), LineEnding.lf);
    });
  });

  group('LineEnding.apply', () {
    test('f05/us01/fr07/e01: crlf turns every LF into CRLF', () {
      expect(LineEnding.crlf.apply('a\n\nb\n'), 'a\r\n\r\nb\r\n');
    });

    test('f05/us01/fr07: lf leaves the text as is', () {
      expect(LineEnding.lf.apply('a\n\nb\n'), 'a\n\nb\n');
    });
  });

  group('toLf', () {
    test('f05/us01/fr06/e01: turns CRLF into LF', () {
      expect(toLf('a\r\n\r\nb\r\n'), 'a\n\nb\n');
    });

    test('f05/us01/fr06/e01: leaves LF text and a lone CR alone', () {
      expect(toLf('a\nb\rc'), 'a\nb\rc');
    });
  });
}
