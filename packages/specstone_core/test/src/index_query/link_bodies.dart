import 'dart:convert';
import 'dart:math';

import 'package:markdown/markdown.dart';
import 'package:specstone_core/src/doc_model/markdown_body.dart';
import 'package:specstone_core/src/index_query/link_places.dart';
import 'package:specstone_core/src/index_query/link_scan.dart';
import 'package:test/test.dart';

/// Makes one random body from [random].
typedef Grammar = String Function(Random random);

const _tokens = <String>[
  '[',
  ']',
  '![',
  '(',
  ')',
  r'\',
  r'\[',
  r'\]',
  r'\!',
  r'\(',
  r'\)',
  'b.md',
  'c.md',
  'x',
  ' ',
  '\t',
  '"t"',
  "'t'",
  '(<b.md>)',
  '(<c d.md>)',
  '[r]',
  '[s]',
  '[]',
  '*',
  '_',
];

const _definitions = <String>['[r]: b.md', '[s]: <c d.md> "t"', '[r]: c.md'];

String _line(Random random) {
  final count = 1 + random.nextInt(8);
  final tokens = [
    for (var i = 0; i < count; i++) _tokens[random.nextInt(_tokens.length)],
  ];
  return 'x ${tokens.join()}';
}

String _paragraph(Random random) {
  final count = 1 + random.nextInt(3);
  return [for (var i = 0; i < count; i++) _line(random)].join('\n');
}

String _inlineBody(Random random) {
  final count = 1 + random.nextInt(4);
  final separators = [
    for (var i = 1; i < count; i++)
      if (random.nextBool()) '\n' else '\n\n',
  ];
  final body = StringBuffer();
  for (var i = 0; i < count; i++) {
    final afterBlank = i == 0 || separators[i - 1] == '\n\n';
    final beforeBlank = i < count - 1 && separators[i] == '\n\n';
    final isDefinition = afterBlank && beforeBlank && random.nextInt(3) == 0;
    body.write(
      isDefinition
          ? _definitions[random.nextInt(_definitions.length)]
          : _paragraph(random),
    );
    if (i < count - 1) body.write(separators[i]);
  }
  body.write('\n');
  return body.toString();
}

/// Bodies of one to four blocks: paragraphs of inline bracket syntax, and
/// definition lines that stand alone between blank lines.
const Grammar inlineGrammar = _inlineBody;

/// Returns every `a` href of `parseMarkdown(body)`, in tree order.
List<String> markdownHrefs(String body) {
  final nodes =
      parseMarkdown(body) ??
      (throw StateError('markdown failed on ${jsonEncode(body)}'));
  final hrefs = <String>[];
  void visit(List<Node> nodes) {
    for (final node in nodes) {
      if (node is! Element) continue;
      final href = node.attributes['href'];
      if (node.tag == 'a' && href != null) hrefs.add(href);
      final children = node.children;
      if (children != null) visit(children);
    }
  }

  visit(nodes);
  return hrefs;
}

/// Fails on the first body of [grammar], over the seeds 1, 2, and 3 and 3,000
/// bodies each, whose scanned sources and `markdown` hrefs disagree.
void expectReadersAgree(Grammar grammar) {
  for (final seed in const [1, 2, 3]) {
    final random = Random(seed);
    for (var index = 0; index < 3000; index++) {
      final body = grammar(random);
      final sources = linkSourcesOf(body, firstLine: 1);
      final hrefs = markdownHrefs(body);
      if (!readersAgree(sources, hrefs)) {
        fail(
          'seed $seed, index $index, body ${jsonEncode(body)}\n'
          'scan: ${[for (final s in sources) (s.offset, s.shown)]}\n'
          'markdown: $hrefs',
        );
      }
    }
  }
}
