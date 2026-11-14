import 'package:specstone_core/src/rendering/line_ending.dart';
import 'package:test/test.dart';

void main() {
  group('LineEnding.of', () {
    test('the first line break decides: CRLF', () {
      expect(LineEnding.of('# T\r\n\r\nbody\r\n'), LineEnding.crlf);
    });

    test('the first line break decides: LF', () {
      expect(LineEnding.of('# T\n\nbody\r\n'), LineEnding.lf);
    });

    test('no line break is LF', () {
      expect(LineEnding.of('# T'), LineEnding.lf);
      expect(LineEnding.of(''), LineEnding.lf);
    });

    test('a text that starts with a line break is LF', () {
      expect(LineEnding.of('\n\r\n'), LineEnding.lf);
    });
  });

  group('LineEnding.apply', () {
    test('crlf turns every LF into CRLF', () {
      expect(LineEnding.crlf.apply('a\n\nb\n'), 'a\r\n\r\nb\r\n');
    });

    test('lf leaves the text as is', () {
      expect(LineEnding.lf.apply('a\n\nb\n'), 'a\n\nb\n');
    });
  });

  group('toLf', () {
    test('turns CRLF into LF', () {
      expect(toLf('a\r\n\r\nb\r\n'), 'a\n\nb\n');
    });

    test('leaves LF text and a lone CR alone', () {
      expect(toLf('a\nb\rc'), 'a\nb\rc');
    });
  });
}
