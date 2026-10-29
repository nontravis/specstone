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

/// The tokens `atomGrammar` adds: code spans, autolinks, and raw HTML.
const _atomTokens = <String>[
  '`',
  '``',
  '<http://x.y/>',
  '<a@b.md>',
  'http://x.y/',
  'www.x.y',
  'a@b.md',
  '<span title="',
  '">',
  '</span>',
  '<!--',
  '-->',
  '<?',
  '?>',
  '<!X',
  '<',
  '>',
  '&#46;',
  '&amp;',
  '~',
];

const _definitions = <String>['[r]: b.md', '[s]: <c d.md> "t"', '[r]: c.md'];

String _tokenRun(Random random, List<String> vocabulary) {
  final count = 1 + random.nextInt(8);
  return [
    for (var i = 0; i < count; i++)
      vocabulary[random.nextInt(vocabulary.length)],
  ].join();
}

String _line(Random random, List<String> vocabulary) =>
    'x ${_tokenRun(random, vocabulary)}';

String _paragraph(Random random, List<String> vocabulary) {
  final count = 1 + random.nextInt(3);
  return [for (var i = 0; i < count; i++) _line(random, vocabulary)].join('\n');
}

String _inlineBody(Random random, List<String> vocabulary) {
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
          : _paragraph(random, vocabulary),
    );
    if (i < count - 1) body.write(separators[i]);
  }
  body.write('\n');
  return body.toString();
}

/// Bodies of one to four blocks: paragraphs of inline bracket syntax, and
/// definition lines that stand alone between blank lines.
String inlineGrammar(Random random) => _inlineBody(random, _tokens);

/// [inlineGrammar] with code spans, autolinks, and raw HTML added.
String atomGrammar(Random random) =>
    _inlineBody(random, [..._tokens, ..._atomTokens]);

/// [_definitions] and a definition whose title sits on the next line.
const _topDefinitions = <String>[..._definitions, '[s]: <c d.md>\n"t"'];

/// Returns zero to two token lines, each led by a line end.
String _tokenLines(Random random, List<String> vocabulary) => [
  for (var i = random.nextInt(3); i > 0; i--) '\n${_line(random, vocabulary)}',
].join();

const _delimiterCells = <String>['---', ':--', '--:', ':-:'];

String _pick(Random random, List<String> choices) =>
    choices[random.nextInt(choices.length)];

String _htmlBlock(Random random, List<String> vocabulary) {
  final lines = _tokenLines(random, vocabulary);
  return switch (random.nextInt(4)) {
    0 => '<!--$lines\n-->',
    1 => '<details>$lines\n</details>',
    2 => '<pre>${random.nextBool() ? '\n' : ''}$lines\n</pre>',
    _ => '<x-y>$lines',
  };
}

String _tableBlock(Random random, List<String> vocabulary) {
  final columns = 1 + random.nextInt(3);
  String row(int cells) {
    final texts = [
      for (var i = 0; i < cells; i++) _tokenRun(random, vocabulary),
    ];
    return '| ${texts.join(' | ')} |';
  }

  final delimiters = [
    for (var i = 0; i < columns; i++) _pick(random, _delimiterCells),
  ];
  return [
    row(columns),
    '|${delimiters.join('|')}|',
    for (var i = random.nextInt(3); i > 0; i--) row(1 + random.nextInt(3)),
  ].join('\n');
}

String _topBlock(
  Random random,
  List<String> vocabulary, {
  required bool afterBlank,
}) {
  final kind = random.nextInt(11);
  return switch (kind) {
    0 => '# ${_tokenRun(random, vocabulary)}',
    1 => '${_paragraph(random, vocabulary)}\n${_pick(random, ['===', '---'])}',
    2 => '***',
    3 =>
      '```${_tokenLines(random, vocabulary)}'
          '${_pick(random, ['', '\n```'])}',
    4 => _htmlBlock(random, vocabulary),
    5 when afterBlank => [
      '    ${_tokenRun(random, vocabulary)}',
      if (random.nextBool()) '    ${_tokenRun(random, vocabulary)}',
    ].join(_pick(random, ['\n', '\n\n'])),
    6 => _tableBlock(random, vocabulary),
    7 => _topDefinitions[random.nextInt(_topDefinitions.length)],
    8 =>
      '${_line(random, vocabulary)}\n'
          '${_topDefinitions[random.nextInt(_topDefinitions.length)]}',
    _ => _paragraph(random, vocabulary),
  };
}

/// Bodies of one to five blocks joined by a line end or a blank line:
/// paragraphs, headings, setext headings, thematic breaks, fences, HTML blocks,
/// indented code, tables, and definitions.
String topBlockGrammar(Random random) {
  final vocabulary = [..._tokens, ..._atomTokens];
  final count = 1 + random.nextInt(5);
  final body = StringBuffer();
  var afterBlank = true;
  for (var i = 0; i < count; i++) {
    body.write(_topBlock(random, vocabulary, afterBlank: afterBlank));
    if (i < count - 1) {
      afterBlank = random.nextBool();
      body.write(afterBlank ? '\n\n' : '\n');
    }
  }
  body.write('\n');
  return body.toString();
}

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
