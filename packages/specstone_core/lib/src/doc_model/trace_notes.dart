import 'package:specstone_core/src/doc_model/check_sentences.dart';
import 'package:specstone_core/src/doc_model/code_spans.dart';
import 'package:specstone_core/src/doc_model/inline_holders.dart';
import 'package:specstone_core/src/doc_model/reference_grammar.dart';
import 'package:specstone_core/src/doc_model/sentences.dart'
    show collapseWhitespace;

/// A trace note of an item, and whether it closes the item or its table cell.
typedef TraceNote = ({String text, bool closes});

const _openBracket = 0x5B;
const _openParen = 0x28;
const _closeParen = 0x29;
const _pipe = 0x7C;
const _period = 0x2E;

final _partSeparator = RegExp(r'(?:[,;]\s+|\s+(?:and|to)\s+)');
final _ownershipWord = RegExp(
  r'\s+(?:owns|cites)(?![\p{L}\p{N}])',
  unicode: true,
);
final _nestedLine = RegExp(r'^[ \t]+(?:[-+*]|\d{1,9}[.)])[ \t]');

/// Returns every trace note of [lfItemText] in file order, and the text with
/// its one closing note removed.
///
/// A note is a group of item references or a clause whose first word is an
/// item reference and whose second is `owns` or `cites`. A reference is an
/// item or scenario link, or a bare ID of one of [idPrefixes].
({List<TraceNote> notes, String counted}) traceNotesOf(
  String lfItemText,
  Set<String> idPrefixes,
) {
  final prefixes = idPrefixes.toList()..sort((a, b) => b.length - a.length);
  final ownEnd = _ownTextEnd(lfItemText);
  final own = lfItemText.substring(0, ownEnd);
  final spans = [..._groupSpans(own, prefixes), ..._clauseSpans(own, prefixes)]
    ..sort((a, b) => a.start - b.start);
  final notes = <({int start, int end})>[];
  for (final span in spans) {
    if (notes.isEmpty || span.start >= notes.last.end) notes.add(span);
  }
  final isRow = _isTableRow(own);
  // A row's cells each end an item part, so each cell closes its own note.
  final candidates = isRow ? notes : [if (notes.isNotEmpty) notes.last];
  final closeEnds = <({int start, int end})>[];
  for (final note in candidates) {
    final end = _closeEnd(own, note.end, isRow);
    if (end != null) closeEnds.add((start: note.start, end: end));
  }
  var counted = lfItemText;
  for (final removal in closeEnds.reversed) {
    counted =
        counted.substring(0, removal.start).trimRight() +
        counted.substring(removal.end);
  }
  return (
    notes: [
      for (final note in notes)
        (
          text: collapseWhitespace(own.substring(note.start, note.end)),
          closes: closeEnds.any((removal) => removal.start == note.start),
        ),
    ],
    counted: counted,
  );
}

/// Returns the offset where the item's nested list lines begin, else its end.
int _ownTextEnd(String text) {
  var at = text.indexOf('\n');
  while (at >= 0) {
    final lineStart = at + 1;
    final lineEnd = text.indexOf('\n', lineStart);
    final line = text.substring(lineStart, lineEnd < 0 ? text.length : lineEnd);
    if (_nestedLine.hasMatch(line)) return at;
    at = lineEnd;
  }
  return text.length;
}

bool _isTableRow(String own) =>
    !own.contains('\n') && own.trimLeft().startsWith('|');

/// Returns where the text removed with a note ends when the note closes, else
/// null: only blanks and one `.` follow it, up to the cell's end in a row.
int? _closeEnd(String own, int noteEnd, bool isRow) {
  var end = noteEnd;
  final limit = isRow ? _nextPipe(own, noteEnd) : own.length;
  var i = noteEnd;
  var sawStop = own.codeUnitAt(noteEnd - 1) == _period;
  while (i < limit) {
    final unit = own.codeUnitAt(i);
    if (unit == _period && !sawStop) {
      sawStop = true;
      end = i + 1;
    } else if (!_isBlank(unit)) {
      return null;
    }
    i++;
  }
  return isRow ? end : limit;
}

int _nextPipe(String text, int from) {
  for (var i = from; i < text.length; i++) {
    if (text.codeUnitAt(i) == _pipe && !isEscaped(text, i)) return i;
  }
  return text.length;
}

bool _isBlank(int unit) => unit == 0x20 || unit == 0x09 || unit == 0x0A;

List<({int start, int end})> _groupSpans(String text, List<String> prefixes) {
  final spans = _heldRuns(text);
  final found = <({int start, int end})>[];
  var i = 0;
  while (i < text.length) {
    final held = spans[i];
    if (held != null) {
      i = held;
      continue;
    }
    final unit = text.codeUnitAt(i);
    final end = unit == _openParen && !isEscaped(text, i)
        ? _groupEnd(text, i, prefixes, spans)
        : null;
    if (end == null) {
      i++;
      continue;
    }
    found.add((start: i, end: end));
    i = end;
  }
  return found;
}

/// Returns the offset of each code span's start mapped to its end.
Map<int, int> _heldRuns(String text) => {
  for (final span in codeSpansOf(text)) span.start: span.end,
};

int? _groupEnd(
  String text,
  int open,
  List<String> prefixes,
  Map<int, int> skips,
) {
  var at = open + 1;
  while (true) {
    final partEnd = _referenceEnd(text, at, prefixes, skips);
    if (partEnd == null) return null;
    at = partEnd;
    if (at < text.length && text.codeUnitAt(at) == _closeParen) return at + 1;
    final separator = _partSeparator.matchAsPrefix(text, at);
    if (separator == null) return null;
    at = separator.end;
  }
}

/// Returns where the item or scenario reference at [at] ends, or null.
int? _referenceEnd(
  String text,
  int at,
  List<String> prefixes,
  Map<int, int> skips,
) {
  if (at >= text.length) return null;
  if (text.codeUnitAt(at) == _openBracket) {
    final link = linkAt(text, at, skips: skips);
    if (link == null) return null;
    final label = text.substring(at + 1, link.textEnd);
    final isReference =
        _isItemId(label, prefixes) || readScenarioRef(label) != null;
    return isReference ? link.end : null;
  }
  for (final prefix in prefixes) {
    if (readItemIdAt(text, at, prefix) case final ItemId id) {
      return at + id.written.length;
    }
  }
  return null;
}

bool _isItemId(String label, List<String> prefixes) {
  for (final prefix in prefixes) {
    final id = readItemIdAt(label, 0, prefix);
    if (id is ItemId && id.written.length == label.length) return true;
  }
  return false;
}

List<({int start, int end})> _clauseSpans(String text, List<String> prefixes) {
  final found = <({int start, int end})>[];
  final skips = _heldRuns(text);
  var cursor = 0;
  for (final sentence in checkSentencesOf(text)) {
    final span = _locate(text, sentence.text, cursor);
    if (span == null) continue;
    cursor = span.end;
    final refEnd = _referenceEnd(text, span.start, prefixes, skips);
    if (refEnd == null || refEnd > span.end) continue;
    if (_ownershipWord.matchAsPrefix(text, refEnd) != null) found.add(span);
  }
  return found;
}

/// Finds [sentence], cut from whitespace-collapsed text, in [text] from [from].
({int start, int end})? _locate(String text, String sentence, int from) {
  final pattern = RegExp(
    sentence.split(' ').map(RegExp.escape).join(r'(?:\s|>)+'),
  );
  final match = pattern.allMatches(text, from).firstOrNull;
  return match == null ? null : (start: match.start, end: match.end);
}
