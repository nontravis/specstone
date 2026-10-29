import 'package:markdown/markdown.dart';
import 'package:specstone_core/src/doc_model/markdown_body.dart';
import 'package:test/test.dart';

void main() {
  group('parseMarkdown', () {
    test('doc_model/s03/inv8, LP2: a body the parser throws on gives null, '
        'whatever it throws', () {
      final inputs = [
        r'[a]:<b\',
        '[a]: <',
        '[a]: /b (c\n| :--- | ---: |\n',
        '[^1]\n\n[^1]: - note\n',
        '${'>' * 20000}x',
      ];

      for (final input in inputs) {
        expect(
          () =>
              Document(extensionSet: ExtensionSet.gitHubFlavored).parse(input),
          throwsA(anything),
          reason: 'the input still reaches the boundary: $input',
        );
        expect(parseMarkdown(input), isNull, reason: input);
      }
    });

    test('doc_model/s03/inv8, LP2: a tree deeper than 1,000 levels gives '
        'null; one within the bound gives its nodes', () {
      final tooDeep = '${'*' * 2400}a${'*' * 2400}';
      final withinBound = '${'*' * 1900}a${'*' * 1900}';

      expect(
        () =>
            Document(extensionSet: ExtensionSet.gitHubFlavored).parse(tooDeep),
        returnsNormally,
        reason: 'the parser itself builds the deep tree',
      );
      expect(parseMarkdown(tooDeep), isNull);
      expect(parseMarkdown(withinBound), isNotNull);
      expect(
        parseMarkdown('${'>' * 1500} a [y](other.md)'),
        isNull,
        reason:
            'a blockquote the parser still reads is cut at the same bound, '
            'so the answer no longer depends on the stack depth of the caller',
      );
    });

    test(
      'doc_model/s03/inv8, LP2: a body the parser reads gives its nodes',
      () {
        final nodes = parseMarkdown('[a](b.md)')!;

        expect(nodes, hasLength(1));
        expect((nodes.single as Element).tag, 'p');
      },
    );
  });
}
