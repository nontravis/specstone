import 'dart:typed_data';

import 'package:specstone_core/src/doc_model/doc.dart';

/// The inline text of a body and the definitions its links resolve against.
///
/// `text` is the body with every code unit markdown never reads as inline text
/// blanked to a space, line ends and length kept; `leaves` are the inline text
/// ranges in source order; `definitions` maps `linkLabel(label)` to the
/// destination as written, angle brackets dropped, the first definition of a
/// label winning.
typedef LeafText = ({
  String text,
  List<({int start, int end})> leaves,
  Map<String, String> definitions,
});

final _definitionStart = RegExp(r'^ {0,3}\[', multiLine: true);
final _bareDest = RegExp(r'\S+');
final _span = RegExp('`[^`\n]*`');
final _blankRun = RegExp(r'\s+');

/// Returns the [LeafText] of [lfBody], a doc text with LF line ends.
///
/// A leaf is a run of lines between blank lines. Fenced code lines, one-line
/// code spans, and each definition (`[label]: dest`, from its `[` to the end of
/// its destination) are blanked, so an offset in the text is an offset in
/// [lfBody].
LeafText leafTextOf(String lfBody) {
  final lines = lfBody.split('\n');
  final fenced = fencedLines(lines);
  final masked = <String>[];
  final leaves = <({int start, int end})>[];
  var offset = 0;
  var leafStart = -1;
  var leafEnd = 0;
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    masked.add(
      fenced[i]
          ? ' ' * line.length
          : line.replaceAllMapped(_span, (m) => ' ' * m[0]!.length),
    );
    if (fenced[i] || _isBlankLine(line)) {
      if (leafStart >= 0) leaves.add((start: leafStart, end: leafEnd));
      leafStart = -1;
    } else {
      if (leafStart < 0) leafStart = offset;
      leafEnd = offset + line.length;
    }
    offset += line.length + 1;
  }
  if (leafStart >= 0) leaves.add((start: leafStart, end: leafEnd));

  final text = masked.join('\n');
  final definitions = <String, String>{};
  final spans = <({int start, int end})>[];
  _scanDefinitions(text, (start, label, dest, end) {
    definitions.putIfAbsent(linkLabel(label), () => _bare(dest));
    spans.add((start: start, end: end));
  });
  if (spans.isEmpty) {
    return (text: text, leaves: leaves, definitions: definitions);
  }
  final units = Uint16List.fromList(text.codeUnits);
  for (final (:start, :end) in spans) {
    for (var i = start; i < end; i++) {
      if (units[i] != 0x0A) units[i] = 0x20;
    }
  }
  return (
    text: String.fromCharCodes(units),
    leaves: leaves,
    definitions: definitions,
  );
}

/// Returns whether [line] holds nothing but spaces and tabs.
bool _isBlankLine(String line) {
  for (var i = 0; i < line.length; i++) {
    final unit = line.codeUnitAt(i);
    if (unit != 0x20 && unit != 0x09) return false;
  }
  return true;
}

/// Returns [text] as a definition label: trimmed, each run of blanks one
/// space, lowercased.
String linkLabel(String text) =>
    text.trim().replaceAll(_blankRun, ' ').toLowerCase();

String _bare(String dest) => dest.startsWith('<') && dest.endsWith('>')
    ? dest.substring(1, dest.length - 1)
    : dest;

/// Calls [found] with the offset, label, destination, and end offset of each
/// definition (`[label]: dest`) in [text], in order.
///
/// A label runs to the first `]`, over line ends, and a `<` destination to the
/// first `>`. Each is looked up once for all the starts before it, so a bracket
/// or `<` that never closes costs no rescan.
void _scanDefinitions(
  String text,
  void Function(int start, String label, String dest, int end) found,
) {
  var resume = 0;
  var close = -1;
  var angleClose = -1;
  var noAngleClose = false;
  for (final candidate in _definitionStart.allMatches(text)) {
    final at = candidate.end - 1;
    if (at < resume) continue;
    if (close <= at) close = text.indexOf(']', at + 1);
    if (close < 0) return;
    if (close == at + 1 || !text.startsWith(':', close + 1)) continue;
    var destAt = close + 2;
    while (destAt < text.length &&
        (text[destAt] == ' ' || text[destAt] == '\t')) {
      destAt++;
    }
    var destEnd = -1;
    if (text.startsWith('<', destAt)) {
      if (!noAngleClose && angleClose <= destAt) {
        angleClose = text.indexOf('>', destAt + 1);
        noAngleClose = angleClose < 0;
      }
      if (!noAngleClose) destEnd = angleClose + 1;
    }
    if (destEnd < 0) {
      destEnd = _bareDest.matchAsPrefix(text, destAt)?.end ?? -1;
      if (destEnd < 0) continue;
    }
    found(
      at,
      text.substring(at + 1, close),
      text.substring(destAt, destEnd),
      destEnd,
    );
    resume = destEnd;
  }
}
