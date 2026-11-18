import 'package:specstone_core/src/doc_model/check_sentences.dart';
import 'package:specstone_core/src/doc_model/code_spans.dart';
import 'package:specstone_core/src/doc_model/inline_holders.dart';
import 'package:specstone_core/src/doc_model/markdown_lines.dart'
    show tableCellRanges;
import 'package:specstone_core/src/doc_model/models/id_read.dart';
import 'package:specstone_core/src/doc_model/models/item_trace_notes.dart';
import 'package:specstone_core/src/doc_model/models/text_range.dart';
import 'package:specstone_core/src/doc_model/models/trace_note.dart';
import 'package:specstone_core/src/doc_model/reference_grammar.dart';
import 'package:specstone_core/src/doc_model/sentences.dart'
    show collapseWhitespace;

const _openBracket = 0x5B;
const _openParen = 0x28;
const _closeParen = 0x29;
const _period = 0x2E;
const _space = 0x20;
const _tab = 0x09;
const _lineFeed = 0x0A;

final _partSeparator = RegExp(r'(?:[,;]\s+|\s+(?:and|to)\s+)');
final _ownershipWord = RegExp(
  r'\s+(?:owns|cites)(?![\p{L}\p{N}])',
  unicode: true,
);
final _wordSeparator = RegExp(r'[\s>]+');
final _wrapMarks = RegExp(r'(?<=\n)[ \t]*(?:>[ \t]?)+');
final _nestedLine = RegExp(r'^[ \t]+(?:[-+*]|\d{1,9}[.)])[ \t]');

/// Returns the trace notes of [lfItemText] and its text without the closing
/// ones.
///
/// A note is a group of item references or a clause whose first word is an
/// item reference and whose second is `owns` or `cites`. A reference is an
/// item or scenario link, or a bare ID of one of [idPrefixes]. An item closes
/// with its last note; a table row ([isTableRow], read as the table reader
/// cuts it) closes each cell with that cell's last.
ItemTraceNotes traceNotesOf(
  String lfItemText,
  Set<String> idPrefixes, {
  required bool isTableRow,
}) {
  final prefixes = idPrefixes.toList()..sort((a, b) => b.length - a.length);
  final own = lfItemText.substring(0, _ownTextEnd(lfItemText)).trimRight();
  final notes = <TextRange>[];
  final closings = <TextRange>[];
  for (final scope in _scopesOf(own, isTableRow: isTableRow)) {
    final found = _notesIn(own, scope, prefixes);
    notes.addAll(found);
    if (found.isEmpty) continue;
    final end = _closeEnd(own, found.last.end, scope.end);
    if (end != null) {
      closings.add(TextRange(start: found.last.start, end: end));
    }
  }
  return ItemTraceNotes(
    notes: [
      for (final note in notes)
        TraceNote(
          text: _noteText(own.substring(note.start, note.end)),
          closes: closings.any((closing) => closing.start == note.start),
        ),
    ],
    counted: _withoutSpans(lfItemText, closings),
  );
}

/// Returns the ranges of the item's own text that close a note apart: a table
/// row's cells, else the whole text.
List<TextRange> _scopesOf(String own, {required bool isTableRow}) =>
    isTableRow ? tableCellRanges(own) : [TextRange(start: 0, end: own.length)];

/// Returns the notes of [scope] of [own], as offsets into [own]; a note that
/// overlaps an earlier one is dropped.
List<TextRange> _notesIn(String own, TextRange scope, List<String> prefixes) {
  final text = own.substring(scope.start, scope.end);
  final spans = [
    if (text.contains('(')) ..._groupSpans(text, prefixes),
    if (_mayHoldClause(text)) ..._clauseSpans(text, prefixes),
  ]..sort((a, b) => a.start - b.start);
  final merged = <TextRange>[];
  for (final span in spans) {
    if (merged.isEmpty || span.start >= merged.last.end) merged.add(span);
  }
  return [
    for (final span in merged)
      TextRange(start: span.start + scope.start, end: span.end + scope.start),
  ];
}

/// Whether [text] holds a word an ownership clause needs, so a text with none
/// is never cut into sentences.
bool _mayHoldClause(String text) =>
    text.contains('owns') || text.contains('cites');

/// Returns [text] without each of [spans], the blanks before each dropped.
String _withoutSpans(String text, List<TextRange> spans) {
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

List<TextRange> _groupSpans(String text, List<String> prefixes) {
  final spans = _heldRuns(text);
  final found = <TextRange>[];
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
    found.add(TextRange(start: i, end: end));
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

List<TextRange> _clauseSpans(String text, List<String> prefixes) {
  final found = <TextRange>[];
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
///
/// Each space of [sentence] stands for a run of blanks and `>` marks in [text],
/// as the sentence cut drops the marks of a wrapped quote. No pattern is
/// built, so a sentence of any length is found.
TextRange? _locate(String text, String sentence, int from) {
  final words = sentence.split(' ');
  var start = text.indexOf(words.first, from);
  while (start >= 0) {
    final end = _wordsEnd(text, start, words);
    if (end != null) return TextRange(start: start, end: end);
    start = text.indexOf(words.first, start + 1);
  }
  return null;
}

/// Returns where [words] end in [text] when they begin at [start], each pair
/// apart by a run of blanks and `>` marks, else null.
///
/// A word that opens with `>` takes the last `>` of its run that it fits.
int? _wordsEnd(String text, int start, List<String> words) {
  var at = start + words.first.length;
  for (final word in words.skip(1)) {
    var wordStart = _separatorEnd(text, at);
    if (word.startsWith('>')) {
      while (wordStart > at && !text.startsWith(word, wordStart)) {
        wordStart--;
      }
    }
    if (wordStart == at || !text.startsWith(word, wordStart)) return null;
    at = wordStart + word.length;
  }
  return at;
}

int _separatorEnd(String text, int from) =>
    _wordSeparator.matchAsPrefix(text, from)?.end ?? from;
