import 'package:specstone_core/src/doc_model/code_spans.dart';
import 'package:specstone_core/src/doc_model/doc.dart' show fenceScan;

/// The one TBR marker: `TBR`, a space, an em dash (U+2014), a space.
const _marker = 'TBR — ';

/// Returns each TBR marker of [lfBody], the text after the frontmatter, with
/// its 0-based body line and the text after it on that line, trimmed.
///
/// Fenced code and code spans hold no marker. A line with two markers gives
/// two places. Spans are read per line, so a marker inside a span wrapped over
/// two lines is still read, as for number labels.
List<({int line, String rest})> tbrMarkerLinesIn(String lfBody) {
  if (!lfBody.contains(_marker)) return const [];
  final lines = lfBody.split('\n');
  final fenced = fenceScan(lines).fenced;
  final markers = <({int line, String rest})>[];
  for (var i = 0; i < lines.length; i++) {
    if (fenced[i]) continue;
    markers.addAll(_markersOf(lines[i], i));
  }
  return markers;
}

/// Returns the markers of [line], read as body line [number], outside its code
/// spans.
List<({int line, String rest})> _markersOf(String line, int number) {
  var at = line.indexOf(_marker);
  if (at < 0) return const [];
  final spans = codeSpansOf(line);
  final markers = <({int line, String rest})>[];
  while (at >= 0) {
    if (!spans.any((s) => at >= s.start && at < s.end)) {
      markers.add((
        line: number,
        rest: line.substring(at + _marker.length).trim(),
      ));
    }
    at = line.indexOf(_marker, at + _marker.length);
  }
  return markers;
}
