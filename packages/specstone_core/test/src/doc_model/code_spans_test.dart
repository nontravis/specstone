import 'package:specstone_core/src/doc_model/code_spans.dart';
import 'package:test/test.dart';

void main() {
  group('codeSpansOf', () {
    test('a backtick after an odd run of backslashes opens '
        'no span', () {
      expect(codeSpansOf(r'Write \`login/email_login\` as is.'), isEmpty);
      expect(codeSpansOf(r'\\\`a/b`'), isEmpty);
    });

    test('a backtick after an even run of backslashes '
        'still opens a span', () {
      expect(codeSpansOf(r'\\`a/b`').map((s) => s.start), [2]);
    });

    test('a backslash inside a span escapes nothing, so '
        'the next backtick closes it', () {
      expect(codeSpansOf(r'`a\` b`').map((s) => (s.start, s.end)), [(0, 4)]);
    });
  });
}
