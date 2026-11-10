import 'package:specstone_core/src/doc_model/code_spans.dart';
import 'package:specstone_core/src/doc_model/doc.dart' show fenceScan;

/// The one TBR marker: `TBR`, a space, an em dash (U+2014), then a space or
/// the end of the line; a write strips a trailing space, so `TBR — ` is stored
/// as `TBR —`.
const _marker = 'TBR —';
const _space = 0x20;

/// Returns each TBR marker of [lfBody], the text after the frontmatter, with
/// its 0-based body line and the text after it on that line, up to the next
/// marker and trimmed.
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
  var at = _markerAt(line, 0);
  if (at < 0) return const [];
  final spans = codeSpansOf(line);
  final markers = <({int line, String rest})>[];
  while (at >= 0) {
    final textStart = at + _marker.length;
    final next = _markerAt(line, textStart);
    if (!spans.any((s) => at >= s.start && at < s.end)) {
      markers.add((
        line: number,
        rest: line.substring(textStart, next < 0 ? line.length : next).trim(),
      ));
    }
    at = next;
  }
  return markers;
}

/// Returns the index of the first marker of [line] at or after [from], or -1.
int _markerAt(String line, int from) {
  var at = line.indexOf(_marker, from);
  while (at >= 0) {
    final end = at + _marker.length;
    if (end == line.length || line.codeUnitAt(end) == _space) return at;
    at = line.indexOf(_marker, end);
  }
  return -1;
}
