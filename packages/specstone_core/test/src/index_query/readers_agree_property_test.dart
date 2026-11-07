import 'dart:convert';
import 'dart:math';

import 'package:specstone_core/src/doc_model/markdown_body.dart';
import 'package:specstone_core/src/index_query/link_places.dart';
import 'package:specstone_core/src/index_query/link_scan.dart';
import 'package:test/test.dart';

import 'link_bodies.dart' show renumberDestinations;

// The link scan and markdown list the same links in the same order on docs
// that mix footnotes, reference links with labels markdown folds or keeps,
// images, and code spans (R74).

/// Pairs of a reference label and a definition label: the first three fold
/// to each other in markdown, the rest do not.
final _labels = <(String, String)>[
  ('ẞ', 'ss'),
  ('ÄRGER', 'ärger'),
  ('ΣΑ', 'σα'),
  ('Œuvre', 'œuvre'),
  ('Ĳ', 'ĳ'),
  ('𐐨', '𐐀'),
  (String.fromCharCode(0x212A), 'k'),
];

const _footnotes = ['1', '2', '3'];

String _pick(Random random, List<String> from) =>
    from[random.nextInt(from.length)];

String _reference(Random random) {
  final (reference, definition) = _labels[random.nextInt(_labels.length)];
  return '[q][${random.nextBool() ? reference : definition}]';
}

String _token(Random random) {
  final footnote = '[^${_pick(random, _footnotes)}]';
  return switch (random.nextInt(12)) {
    0 => '[a](b.md)',
    1 => '![i](c.md)',
    2 => '`[c](b.md)`',
    3 || 4 => _reference(random),
    5 => footnote,
    6 => '[s $footnote](b.md)',
    7 => '[s !$footnote](b.md)',
    8 => '[r]$footnote',
    9 => '*',
    _ => 'x',
  };
}

String _line(Random random) => [
  'x',
  for (var i = random.nextInt(5); i >= 0; i--) _token(random),
].join(' ');

String _definition(Random random) {
  final (reference, definition) = _labels[random.nextInt(_labels.length)];
  return '[${random.nextBool() ? definition : reference}]: b.md';
}

/// A footnote definition: one line, a lazy line after it, a paragraph after a
/// blank line indented four spaces, or a definition as its content.
String _footnote(Random random) {
  final label = '[^${_pick(random, _footnotes)}]:';
  return switch (random.nextInt(4)) {
    0 => '$label ${_line(random)}\n${_line(random)}',
    1 => '$label ${_line(random)}\n\n    ${_line(random)}',
    2 => '$label ${_definition(random)}',
    _ => '$label ${_line(random)}',
  };
}

String _block(Random random) {
  switch (random.nextInt(4)) {
    case 0:
      return _definition(random);
    case 1:
      return _footnote(random);
    default:
      return [for (var i = random.nextInt(3); i >= 0; i--) _line(random)]
          .join('\n');
  }
}

String _body(Random random) {
  final blocks = [
    for (var i = 1 + random.nextInt(5); i >= 0; i--) _block(random),
  ];
  return '${blocks.join(random.nextBool() ? '\n\n' : '\n')}\n';
}

void main() {
  test('R74: the link scan and markdown read the same links on 6,000 bodies '
      'of footnotes, folded labels, images, and code spans', () {
    var parsed = 0;
    for (final seed in const [1, 2, 3]) {
      final random = Random(seed);
      for (var index = 0; index < 2000; index++) {
        final body = renumberDestinations(_body(random));
        if (parseMarkdownTree(body) == null) continue;
        parsed++;
        final scan = linkScanOf(body, firstLine: 1);
        final read = (
          sources: sourceHrefsOf(body, scan.sources) != null,
          destinations: hrefDestinationsOf(body, scan).linksRead,
        );
        expect(read, (
          sources: true,
          destinations: true,
        ), reason: 'seed $seed, index $index, body ${jsonEncode(body)}');
      }
    }
    expect(parsed, greaterThan(5900));
  });
}
