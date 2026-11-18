import 'package:specstone_core/src/doc_model/text_scan.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';

const _lf = 0x0A;

/// The non-blank line count and code point count of a held section's body.
typedef SectionCounts = ({int lines, int chars});

/// Returns the sizes of `section.body`.
///
/// `lines` counts the non-blank body lines, and `chars` is what `runes.length`
/// gives: a surrogate pair counts once. The header line, and the one line break
/// that ends the body, are not counted.
SectionCounts sectionCountsOf(IndexedSection section) {
  final body = section.body;
  final endsInBreak =
      body.isNotEmpty && body.codeUnitAt(body.length - 1) == _lf;
  final units = body.length - (endsInBreak ? 1 : 0);
  return (lines: _nonBlankLines(body), chars: units - scanText(body).pairs);
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
