import 'package:specstone_core/src/doc_model/code_spans.dart';
import 'package:specstone_core/src/doc_model/doc.dart' show blockScan;
import 'package:specstone_core/src/doc_model/reference_grammar.dart';

/// A doc-name mention: a code span whose whole text, less an optional
/// `#<section key>`, reads as a DocAddress of the no-lookup class (RULE-11).
///
/// `line` is 1-based and `column` the 0-based offset of the first character
/// of `text` in its line, after the opening backticks.
typedef NameMention = ({int line, int column, String text, DocAddress address});

/// The doc-name mentions of [lf], a doc body or a markdown file, read from its
/// code spans outside fenced code, each line alone.
List<NameMention> nameMentionsInMarkdown(String lf) {
  if (!lf.contains('`')) return const [];
  final lines = lf.split('\n');
  final fenced = blockScan(lines).fenced;
  return [
    for (var i = 0; i < lines.length; i++)
      if (!fenced[i]) ..._mentionsOnLine(lines[i], i + 1),
  ];
}

Iterable<NameMention> _mentionsOnLine(String line, int number) sync* {
  for (final (:start, :end, :ticks) in codeSpansOf(line)) {
    final text = line.substring(start + ticks, end - ticks);
    final address = readDocAddress(text);
    if (!address.isReferenceWithoutLookup) continue;
    yield (line: number, column: start + ticks, text: text, address: address);
  }
}
