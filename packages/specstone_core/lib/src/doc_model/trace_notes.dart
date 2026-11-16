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
const _space = 0x20;
const _tab = 0x09;
const _lineFeed = 0x0A;

final _partSeparator = RegExp(r'(?:[,;]\s+|\s+(?:and|to)\s+)');
final _ownershipWord = RegExp(
  r'\s+(?:owns|cites)(?![\p{L}\p{N}])',
  unicode: true,
);
final _wrapMarks = RegExp(r'(?<=\n)[ \t]*(?:>[ \t]?)+');
final _nestedLine = RegExp(r'^[ \t]+(?:[-+*]|\d{1,9}[.)])[ \t]');

typedef _Span = ({int start, int end});

/// Returns every trace note of [lfItemText] in file order, and the text with
/// its closing notes removed.
///
/// A note is a group of item references or a clause whose first word is an
/// item reference and whose second is `owns` or `cites`. A reference is an
/// item or scenario link, or a bare ID of one of [idPrefixes]. An item closes
/// with its last note; a table row closes each cell with that cell's last.
({List<TraceNote> notes, String counted}) traceNotesOf(
  String lfItemText,
  Set<String> idPrefixes,
) {
  final prefixes = idPrefixes.toList()..sort((a, b) => b.length - a.length);
  final own = lfItemText.substring(0, _ownTextEnd(lfItemText)).trimRight();
  final notes = <_Span>[];
  final closings = <_Span>[];
  for (final scope in _scopesOf(own)) {
    final found = _notesIn(own, scope, prefixes);
    notes.addAll(found);
    if (found.isEmpty) continue;
    final end = _closeEnd(own, found.last.end, scope.end);
    if (end != null) closings.add((start: found.last.start, end: end));
  }
  return (
    notes: [
      for (final note in notes)
        (
          text: _noteText(own.substring(note.start, note.end)),
          closes: closings.any((closing) => closing.start == note.start),
        ),
    ],
    counted: _withoutSpans(lfItemText, closings),
  );
}

/// Returns the item's own text range: a table row's cells, else the whole.
List<_Span> _scopesOf(String own) {
  if (own.contains('\n') || !own.trimLeft().startsWith('|')) {
    return [(start: 0, end: own.length)];
  }
  final scopes = <_Span>[];
  var start = own.indexOf('|') + 1;
  for (var i = start; i < own.length; i++) {
    if (own.codeUnitAt(i) != _pipe || isEscaped(own, i)) continue;
    scopes.add((start: start, end: i));
    start = i + 1;
  }
  if (own.substring(start).trim().isNotEmpty) {
    scopes.add((start: start, end: own.length));
  }
  return scopes;
}

/// Returns the notes of [scope] of [own], as offsets into [own]; a note that
/// overlaps an earlier one is dropped.
List<_Span> _notesIn(String own, _Span scope, List<String> prefixes) {
  final text = own.substring(scope.start, scope.end);
  final spans = [
    ..._groupSpans(text, prefixes),
    ..._clauseSpans(text, prefixes),
  ]..sort((a, b) => a.start - b.start);
  final merged = <_Span>[];
  for (final span in spans) {
    if (merged.isEmpty || span.start >= merged.last.end) merged.add(span);
  }
  return [
    for (final span in merged)
      (start: span.start + scope.start, end: span.end + scope.start),
  ];
}

/// Returns [text] without each of [spans], the blanks before each dropped.
String _withoutSpans(String text, List<_Span> spans) {
  var result = text;
  for (final span in spans.reversed) {
    result =
        result.substring(0, span.start).trimRight() +
        result.substring(span.end);
  }
  return result;
}

/// Returns a note's text as written: wrapped lines joined, quote marks and
/// the closing `.` dropped.
String _noteText(String raw) {
  final joined = collapseWhitespace(raw.replaceAll(_wrapMarks, ' '));
  return joined.endsWith('.') ? joined.substring(0, joined.length - 1) : joined;
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

/// Returns where the text removed with a note ends when the note closes its
/// scope ending at [limit], else null: only blanks and one `.` follow it.
int? _closeEnd(String own, int noteEnd, int limit) {
  var end = noteEnd;
  var sawStop = own.codeUnitAt(noteEnd - 1) == _period;
  for (var i = noteEnd; i < limit; i++) {
    final unit = own.codeUnitAt(i);
    if (unit == _period && !sawStop) {
      sawStop = true;
      end = i + 1;
    } else if (!_isBlank(unit)) {
      return null;
    }
  }
  return end;
}

bool _isBlank(int unit) => unit == _space || unit == _tab || unit == _lineFeed;

List<_Span> _groupSpans(String text, List<String> prefixes) {
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
        _isItemId(label, prefixes) || readScenarioRef(label)?.number is ItemId;
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

List<_Span> _clauseSpans(String text, List<String> prefixes) {
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
_Span? _locate(String text, String sentence, int from) {
  final pattern = RegExp(
    sentence.split(' ').map(RegExp.escape).join(r'(?:\s|>)+'),
  );
  final match = pattern.allMatches(text, from).firstOrNull;
  return match == null ? null : (start: match.start, end: match.end);
}
