import 'package:specstone_core/src/doc_model/text_scan.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';

const _lf = 0x0A;

/// The non-blank line count and code point count of a held section's text.
typedef SectionCounts = ({int lines, int chars});

/// Returns the sizes of `section.text` without building that text.
///
/// `lines` counts the non-blank lines of the header line and the body, and
/// `chars` is what `text.runes.length` gives: a surrogate pair counts once, and
/// the one line break that ends the section is not part of the text.
SectionCounts sectionCountsOf(IndexedSection section) {
  final header = scanText(section.headerLine);
  final body = scanText(section.body);
  // The text is header, a line break, then the body; a body that is empty or
  // ends in a line break leaves that final break out.
  final endsInBreak =
      section.body.isEmpty ||
      section.body.codeUnitAt(section.body.length - 1) == _lf;
  final units =
      section.headerLine.length +
      1 +
      section.body.length -
      (endsInBreak ? 1 : 0);
  return (
    lines:
        _nonBlankLines(section.headerLine) +
        _nonBlankLines(
          endsInBreak && section.body.isNotEmpty
              ? section.body.substring(0, section.body.length - 1)
              : section.body,
        ),
    chars: units - header.pairs - body.pairs,
  );
}

/// Returns the non-blank lines of [text], split on `\n`, a final empty line
/// never counted.
int _nonBlankLines(String text) {
  if (text.isEmpty) return 0;
  var count = 0;
  var start = 0;
  while (start <= text.length) {
    final end = text.indexOf('\n', start);
    final stop = end < 0 ? text.length : end;
    if (_holdsText(text, start, stop)) count++;
    if (end < 0) break;
    start = end + 1;
  }
  return count;
}

/// Whether the line of [text] from [start] to [stop] holds any non-space
/// character.
bool _holdsText(String text, int start, int stop) {
  for (var i = start; i < stop; i++) {
    final unit = text.codeUnitAt(i);
    if (unit != 0x09 && unit != 0x20 && unit != 0x0D) return true;
  }
  return false;
}
