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
        '${'> ' * 100000}x',
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
