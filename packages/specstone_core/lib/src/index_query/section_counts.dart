import 'package:specstone_core/src/doc_model/text_scan.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';

const _lf = 0x0A;

/// The line count and code point count of a held section's text.
typedef SectionCounts = ({int lines, int chars});

/// Returns the sizes of `section.text` without building that text.
///
/// `lines` is what `text.split('\n').length` gives and `chars` is what
/// `text.runes.length` gives: a surrogate pair counts once, and the one line
/// break that ends the section is not part of the text.
SectionCounts sectionCountsOf(IndexedSection section) {
  final header = scanText(section.headerLine);
  final body = scanText(section.body);
  // The text is header, a line break, then the body; a body that is empty or
  // ends in a line break leaves that final break out.
  final endsInBreak =
      section.body.isEmpty ||
      section.body.codeUnitAt(section.body.length - 1) == _lf;
  final breaks = header.breaks + 1 + body.breaks - (endsInBreak ? 1 : 0);
  final units =
      section.headerLine.length +
      1 +
      section.body.length -
      (endsInBreak ? 1 : 0);
  return (lines: breaks + 1, chars: units - header.pairs - body.pairs);
}
