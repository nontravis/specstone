import 'package:specstone_core/src/index_query/doc_parse.dart';
import 'package:test/test.dart';

void main() {
  group('DocParse.approvalMarkChars', () {
    // Each count is the one the two `withKeyBlock` reparses gave the text.
    const cases = {
      'a draft block': ('---\nstatus: planned\ndraft: true\n---\n\n# T\n', 12),
      'an approved block': ('---\napproved: "abc123"\n---\n\n# T\n', 19),
      'both blocks, each holding a YAML comment': (
        '---\nstatus: planned\n# held until review \u{1F600}\ndraft: true\n'
            'approved: "abc123" # hash\n# trailing note\n---\n\n# T\n\nBody.\n',
        76,
      ),
      'neither block': (
        '---\nstatus: planned\n---\n\n# T\n\nThe draft is approved.\n',
        0,
      ),
      'no frontmatter': ('# T\n\ndraft: true\napproved: x\n', 0),
    };
    for (final MapEntry(key: name, value: (text, chars)) in cases.entries) {
      test('$name counts $chars', () {
        expect(DocParse.of(text).approvalMarkChars, chars);
      });
    }
  });
}
