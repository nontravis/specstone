import 'package:markdown/markdown.dart';
import 'package:specstone_core/src/doc_model/doc_anchors.dart';
import 'package:specstone_core/src/doc_model/markdown_body.dart';
import 'package:specstone_core/src/index_query/link_places.dart';
import 'package:test/test.dart';

const _prose =
    'Plain words with no mark that opens a link, repeated so that the block '
    'is long. ';

String _longProse() => List.filled(40, _prose).join();

/// The links and anchors of [body] read from [tree], as one comparable text.
String _readOf(String body, MarkdownTree tree) {
  final links = linkPlacesOf(
    body,
    docPath: 'a/doc.md',
    firstLine: 1,
    tree: tree,
  );
  return '$links\n${anchorsOf(tree.nodes).toJson()}';
}

void _expectSameAsFullParse(String body) {
  final full = parseMarkdownTree(body);
  final byBlock = parseMarkdownTreeByBlock(body);
  expect(full, isNotNull, reason: body);
  expect(byBlock, isNotNull, reason: body);
  expect(_readOf(body, byBlock!), _readOf(body, full!), reason: body);
}

void main() {
  group('parseMarkdownTreeByBlock reads what the full parse reads', () {
    final byBlockKind = <String, String>{
      'a paragraph': 'See [a](b.md#top) here.\n\n${_longProse()}\n',
      'a heading': '# Title [x](y.md)\n\n## Plain heading\n\n## Other_Name\n',
      'a heading with no gate character': '# Plain\n\n## Second\n\n## Second\n',
      'a list item': '- item [a](b.md)\n- ${_longProse()}\n- last [c](d.md)\n',
      'a block quote': '> quote [a](b.md)\n>\n> ${_longProse()}\n',
      'a fenced code block':
          '```\n[a](b.md)\n```\n\n${_longProse()}\n\ntext [c](d.md)\n',
      'an indented code block':
          '    [a](b.md)\n\n${_longProse()}\n\ntext [c](d.md)\n',
      'a table': '| a | b |\n|---|---|\n| [x](y.md) | z |\n| w | v |\n',
      'an HTML block':
          '<div id="top">\n[a](b.md)\n</div>\n\n<a name="n"></a>\n\n'
          '${_longProse()}\n',
      'a link reference definition used in a later block':
          '[a][ref]\n\n${_longProse()}\n\n[b][ref]\n\n[ref]: b.md\n',
      'a link reference definition after its use':
          '${_longProse()}\n\n[used][ref]\n\n[ref]: other.md "Title"\n',
      'a footnote': 'Text[^1] and more.\n\n[^1]: note [a](b.md)\n',
      'a footnote no reference names':
          'Text.\n\n[^1]: <span id="lost"></span>\n\n# Kept\n',
    };
    for (final MapEntry(:key, :value) in byBlockKind.entries) {
      test('$key gives the links and anchors of the full parse', () {
        _expectSameAsFullParse(value);
      });
    }

    final byStartCharacter = <String, String>{
      '[': '${_longProse()}\n\n[a](b.md)\n',
      '<': '<https://example.com> and <a id="x"></a> and <span id="y">z</span>\n',
      '@': 'mail me@example.com or see ${_longProse()}\n',
      '://': '${_longProse()}\n\nsee https://example.com/x and more\n',
      'WWW.': 'Visit WWW.EXAMPLE.COM today.\n\nSee [a](b.md).\n',
      'Www.': 'Visit Www.example.com today.\n\nSee [a](b.md).\n',
      'www.': 'visit www.example.com now\n\n${_longProse()}\n',
    };
    for (final MapEntry(:key, :value) in byStartCharacter.entries) {
      test('a block holding "$key" gives the links and anchors of the full '
          'parse', () {
        _expectSameAsFullParse(value);
      });
    }

    test('a doc whose only link sits in its last block gives its link', () {
      final body =
          '${List.filled(30, '${_longProse()}\n\n').join()}[a](b.md)\n';

      _expectSameAsFullParse(body);
      final tree = parseMarkdownTreeByBlock(body)!;
      final links = linkPlacesOf(
        body,
        docPath: 'a/doc.md',
        firstLine: 1,
        tree: tree,
      )!;
      expect(links.docLinks.single.target, 'a/b.md');
    });

    test('a block with a colon and no link keeps its unparsed content', () {
      final tree = parseMarkdownTreeByBlock('**Statement:** plain words\n')!;

      final block = tree.nodes.single as Element;
      expect(block.children!.single, isA<UnparsedContent>());
    });

    test('a body that fails to parse gives null from both', () {
      final inputs = [
        r'[a]:<b\',
        '[a]: <',
        '[a]: /b (c\n| :--- | ---: |\n',
        '[^1]\n\n[^1]: - note\n',
        '${'>' * 20000}x',
        '${'>' * 1500} a [y](other.md)',
      ];

      for (final input in inputs) {
        expect(parseMarkdownTree(input), isNull, reason: input);
        expect(parseMarkdownTreeByBlock(input), isNull, reason: input);
      }
    });
  });
}
