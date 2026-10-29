import 'dart:typed_data';

import 'package:specstone_core/src/index_query/link_blocks.dart';

/// A source of an `a` element markdown makes: the body offset of its first
/// character, its file line, and, for an inline or reference link, its
/// destination as written (null for an autolink, Task 2).
typedef LinkSource = ({int offset, int line, String? shown});

/// Returns the sources of the links in [lfBody], in source order.
///
/// [lfBody] is the doc text after the frontmatter, with LF line ends, and
/// [firstLine] is its first file line. Each leaf block (see [leafTextOf]) is
/// read left to right by CommonMark's bracket procedure, as `markdown` 7.3.1
/// runs it (`InlineParser.parse`): an escape is skipped whole, a `[` or `![`
/// pushes an opener, and a `]` closes the last opener as an inline link, a
/// full, collapsed, or shortcut reference, or is text. A link turns off every
/// link opener pushed before it, so a link inside link text leaves the outer
/// brackets as text; a link in an image description is dropped with the image.
/// Where `markdown` differs from the CommonMark text, the scan reads as
/// `markdown` does: a tab stays in a bare destination, and a title after an
/// open paren keeps the destination open.
///
/// The scan stays linear in the size of [lfBody]. Each `]` is decided once,
/// and each repeated attempt is decided from a table one pass fills per leaf:
/// the end of a blank run, the escape-aware partner of a `(`, and the next
/// unescaped space, `>`, `"`, `'`, or `)`. A link opener is off when a link
/// closed after its push, a count the opener stores. The text between an
/// opener and its `]` is looked up as a label only when no opener was pushed
/// after it, so the spans looked up are disjoint. A reference link shares its
/// definition's string, and the destinations of distinct links are disjoint.
/// The one chain left is a title after an open paren, which takes no more
/// steps than `markdown`'s own walk.
List<LinkSource> linkSourcesOf(String lfBody, {required int firstLine}) {
  final (:text, :leaves, :definitions) = leafTextOf(lfBody);
  final reader = _Reader(text, definitions);
  for (final (:start, :end) in leaves) {
    reader.read(start, end);
  }
  final found = reader.found..sort((a, b) => a.offset - b.offset);
  final sources = <LinkSource>[];
  var line = firstLine;
  var counted = 0;
  for (final (:offset, :shown) in found) {
    for (; counted < offset; counted++) {
      if (text.codeUnitAt(counted) == 0x0A) line++;
    }
    sources.add((offset: offset, line: line, shown: shown));
  }
  return sources;
}

/// A link the reader found: the offset of its first character and its
/// destination.
typedef _Found = ({int offset, String? shown});

/// Where a `]` ends the link it closes, and the link's destination.
typedef _Close = ({int end, String? shown});

/// An open `[` or `![` of the bracket procedure.
final class _Opener {
  new({
    required this.offset,
    required this.image,
    required this.linksClosed,
    required this.found,
  });

  final int offset;
  final bool image;

  /// The links closed before this opener was pushed; a link opener is off
  /// once more links have closed.
  final int linksClosed;

  /// The number of sources found before this opener was pushed; an image that
  /// closes drops the sources after it.
  final int found;

  /// Whether another opener was pushed after this one.
  bool pushedAfter = false;
}

/// Reads the leaves of a text by the bracket procedure.
final class _Reader {
  new(this.text, this.definitions);

  final String text;
  final Map<String, String> definitions;
  final found = <_Found>[];
  late final _Tables _tables = _Tables(text);

  /// Reads the leaf [start] to [end], adding its links to [found].
  void read(int start, int end) {
    final openers = <_Opener>[];
    var linksClosed = 0;
    var filled = false;
    var i = start;
    while (i < end) {
      final unit = text.codeUnitAt(i);
      if (unit == _backslash) {
        i += i + 1 < end && _isPunctuation(text.codeUnitAt(i + 1)) ? 2 : 1;
      } else if (unit == _openBracket ||
          (unit == _bang &&
              i + 1 < end &&
              text.codeUnitAt(i + 1) == _openBracket)) {
        if (openers.isNotEmpty) openers.last.pushedAfter = true;
        final image = unit == _bang;
        openers.add(
          _Opener(
            offset: i,
            image: image,
            linksClosed: linksClosed,
            found: found.length,
          ),
        );
        i += image ? 2 : 1;
      } else if (unit == _closeBracket) {
        if (openers.isEmpty) {
          i++;
          continue;
        }
        final opener = openers.removeLast();
        if (!opener.image && opener.linksClosed < linksClosed) {
          i++;
          continue;
        }
        if (!filled && text.startsWith('(', i + 1)) {
          _tables.fill(start, end);
          filled = true;
        }
        final close = _close(opener, i, end);
        if (close == null) {
          i++;
          continue;
        }
        if (opener.image) {
          found.length = opener.found;
        } else {
          found.add((offset: opener.offset, shown: close.shown));
          linksClosed++;
        }
        i = close.end;
      } else {
        i++;
      }
    }
  }

  /// Returns what the `]` at [close] makes of [opener], or null when it makes
  /// no link: an inline link, then, as `LinkSyntax.close` tries them, a full,
  /// collapsed, or shortcut reference.
  _Close? _close(_Opener opener, int close, int end) {
    final next = close + 1;
    final nextUnit = next < end ? text.codeUnitAt(next) : -1;
    if (nextUnit == _openParen) {
      return _inlineLink(next, end) ?? _shortcut(opener, close);
    }
    if (nextUnit == _openBracket) {
      if (next + 1 < end && text.codeUnitAt(next + 1) == _closeBracket) {
        final collapsed = _shortcut(opener, close);
        return collapsed == null
            ? null
            : (end: next + 2, shown: collapsed.shown);
      }
      return _fullReference(next, end);
    }
    return _shortcut(opener, close);
  }

  /// Returns the reference [opener]'s text names, or null when the text is
  /// not a definition label or an opener was pushed after [opener], which
  /// makes the text hold a bracket no label holds.
  _Close? _shortcut(_Opener opener, int close) {
    if (opener.pushedAfter) return null;
    final from = opener.offset + (opener.image ? 2 : 1);
    final dest = definitions[linkLabel(text.substring(from, close))];
    return dest == null ? null : (end: close + 1, shown: dest);
  }

  /// Returns the full reference whose label opens at [open], or null when it
  /// is no valid label or names no definition (`_parseReferenceLinkLabel`).
  _Close? _fullReference(int open, int end) {
    var pos = open + 1;
    if (pos >= end) return null;
    final label = StringBuffer();
    while (true) {
      final unit = text.codeUnitAt(pos);
      if (unit == _backslash) {
        pos++;
        if (pos >= end) return null;
        final escaped = text.codeUnitAt(pos);
        if (escaped != _backslash && escaped != _closeBracket) {
          label.writeCharCode(unit);
        }
        label.writeCharCode(escaped);
      } else if (unit == _openBracket) {
        return null;
      } else if (unit == _closeBracket) {
        break;
      } else {
        label.writeCharCode(unit);
      }
      pos++;
      if (pos >= end) return null;
    }
    final name = label.toString();
    if (_blankOnly.hasMatch(name)) return null;
    final dest = definitions[linkLabel(name)];
    return dest == null ? null : (end: pos + 1, shown: dest);
  }

  /// Returns the inline link whose `(` is at [open], or null when the parens
  /// hold no link (`_parseInlineLink`).
  _Close? _inlineLink(int open, int end) {
    final start = _tables.blankEnd[open + 1];
    if (start >= end) return null;
    return text.codeUnitAt(start) == _lessThan
        ? _angleLink(start, end)
        : _bareLink(open, start, end);
  }

  /// Returns the inline link whose destination opens with the `<` at [open]
  /// (`_parseInlineBracketedLink`).
  _Close? _angleLink(int open, int end) {
    final close = _tables.nextAngle[open + 1];
    if (close >= end || text.codeUnitAt(close) != _greaterThan) return null;
    final after = close + 1;
    if (after >= end) return null;
    final unit = text.codeUnitAt(after);
    final int paren;
    if (_isDestinationSpace(unit)) {
      paren = _titleEnd(after, end);
      if (paren < 0) return null;
    } else if (unit == _closeParen) {
      paren = after;
    } else {
      return null;
    }
    return (end: paren + 1, shown: text.substring(open + 1, close));
  }

  /// Returns the inline link whose bare destination opens at [start], inside
  /// the `(` at [open] (`_parseInlineBareDestinationLink`).
  ///
  /// With no space before the paren that balances [open], the destination
  /// runs to it. Otherwise a space ends the destination, a title may follow,
  /// and the `)` after them closes one level of parens, so a level left open
  /// keeps the destination open.
  _Close? _bareLink(int open, int start, int end) {
    final tables = _tables;
    final match = tables.partner[open];
    final space = tables.nextSpace[start];
    if (match >= 0 && (space >= end || match < space)) {
      return (end: match + 1, shown: text.substring(start, match));
    }
    if (space >= end) return null;
    var depth = 1 + tables.parenDepth[space] - tables.parenDepth[start];
    final shown = StringBuffer();
    var pieceStart = start;
    var pos = space;
    while (true) {
      final paren = _titleEnd(pos, end);
      if (paren < 0) return null;
      shown.write(text.substring(pieceStart, pos));
      depth--;
      if (depth == 0) return (end: paren + 1, shown: shown.toString());
      pieceStart = pos = paren + 1;
      while (true) {
        if (pos >= end) return null;
        final unit = text.codeUnitAt(pos);
        if (tables.escaped[pos] == 0) {
          if (unit == _openParen) {
            depth++;
          } else if (unit == _closeParen) {
            depth--;
            if (depth == 0) {
              shown.write(text.substring(pieceStart, pos));
              return (end: pos + 1, shown: shown.toString());
            }
          } else if (_isDestinationSpace(unit)) {
            break;
          }
        }
        pos++;
      }
    }
  }

  /// Returns the offset of the `)` that closes an optional title after the
  /// blank at [blank], or -1 when the parens are no link (`_parseTitle`).
  int _titleEnd(int blank, int end) {
    final tables = _tables;
    var pos = tables.blankEnd[blank];
    if (pos >= end) return -1;
    final delimiter = text.codeUnitAt(pos);
    if (delimiter != _apostrophe &&
        delimiter != _quote &&
        delimiter != _openParen) {
      return delimiter == _closeParen ? pos : -1;
    }
    final from = pos + 1;
    if (from >= end) return -1;
    final close = switch (delimiter) {
      _openParen => tables.nextCloseParen[from],
      _quote => tables.nextQuote[from],
      _ => tables.nextApostrophe[from],
    };
    if (close >= end) return -1;
    pos = close + 1;
    if (pos >= end) return -1;
    pos = tables.blankEnd[pos];
    if (pos >= end) return -1;
    return text.codeUnitAt(pos) == _closeParen ? pos : -1;
  }
}

/// The tables of the leaves of a text, each filled by [fill] on first need.
///
/// Every `next` table maps an offset to the offset of the first matching
/// unescaped code unit at or after it, or to the leaf's end when none follows;
/// a backslash escapes the code unit after it whatever that is, as the
/// destination, title, and label scans of `markdown` read it.
final class _Tables {
  new(String text)
    : _text = text,
      escaped = Uint8List(text.length + 1),
      blankEnd = Int32List(text.length + 1),
      nextSpace = Int32List(text.length + 1),
      nextAngle = Int32List(text.length + 1),
      nextQuote = Int32List(text.length + 1),
      nextApostrophe = Int32List(text.length + 1),
      nextCloseParen = Int32List(text.length + 1),
      partner = Int32List(text.length + 1),
      parenDepth = Int32List(text.length + 1);

  final String _text;

  /// Whether the code unit is escaped by the backslash before it.
  final Uint8List escaped;

  /// The end of the run of the blanks `_moveThroughWhitespace` skips.
  final Int32List blankEnd;

  /// The next space, LF, CR, or FF, which ends a bare destination.
  final Int32List nextSpace;

  /// The next `>`, LF, CR, or FF, which ends an angle destination.
  final Int32List nextAngle;

  /// The next `"`, which ends a title.
  final Int32List nextQuote;

  /// The next `'`, which ends a title.
  final Int32List nextApostrophe;

  /// The next `)`, which ends a title.
  final Int32List nextCloseParen;

  /// For an unescaped `(`, the offset of the `)` that balances it, or -1.
  final Int32List partner;

  /// The unescaped `(` minus `)` from the leaf's start up to the offset.
  final Int32List parenDepth;

  /// Fills the tables for the leaf [start] to [end].
  void fill(int start, int end) {
    final opens = <int>[];
    var escapedNext = false;
    var depth = 0;
    parenDepth[start] = 0;
    for (var i = start; i < end; i++) {
      if (escapedNext) {
        escaped[i] = 1;
        escapedNext = false;
      } else {
        final unit = _text.codeUnitAt(i);
        if (unit == _backslash) {
          escapedNext = true;
        } else if (unit == _openParen) {
          partner[i] = -1;
          opens.add(i);
          depth++;
        } else if (unit == _closeParen) {
          depth--;
          if (opens.isNotEmpty) partner[opens.removeLast()] = i;
        }
      }
      parenDepth[i + 1] = depth;
    }
    blankEnd[end] = end;
    nextSpace[end] = end;
    nextAngle[end] = end;
    nextQuote[end] = end;
    nextApostrophe[end] = end;
    nextCloseParen[end] = end;
    for (var i = end - 1; i >= start; i--) {
      final unit = _text.codeUnitAt(i);
      final free = escaped[i] == 0;
      blankEnd[i] = _isBlank(unit) ? blankEnd[i + 1] : i;
      nextSpace[i] = free && _isDestinationSpace(unit) ? i : nextSpace[i + 1];
      nextAngle[i] = free && (unit == _greaterThan || _isLineEnd(unit))
          ? i
          : nextAngle[i + 1];
      nextQuote[i] = free && unit == _quote ? i : nextQuote[i + 1];
      nextApostrophe[i] = free && unit == _apostrophe
          ? i
          : nextApostrophe[i + 1];
      nextCloseParen[i] = free && unit == _closeParen
          ? i
          : nextCloseParen[i + 1];
    }
  }
}

const _backslash = 0x5C;
const _bang = 0x21;
const _openBracket = 0x5B;
const _closeBracket = 0x5D;
const _openParen = 0x28;
const _closeParen = 0x29;
const _lessThan = 0x3C;
const _greaterThan = 0x3E;
const _quote = 0x22;
const _apostrophe = 0x27;

final _blankOnly = RegExp(r'^\s*$');

/// Returns whether [unit] is ASCII punctuation, which a backslash escapes.
bool _isPunctuation(int unit) =>
    (unit >= 0x21 && unit <= 0x2F) ||
    (unit >= 0x3A && unit <= 0x40) ||
    (unit >= 0x5B && unit <= 0x60) ||
    (unit >= 0x7B && unit <= 0x7E);

/// Returns whether [unit] is LF, CR, or FF.
bool _isLineEnd(int unit) => unit == 0x0A || unit == 0x0D || unit == 0x0C;

/// Returns whether [unit] ends a bare destination: a space, LF, CR, or FF. A
/// tab does not, as `markdown` reads it.
bool _isDestinationSpace(int unit) => unit == 0x20 || _isLineEnd(unit);

/// Returns whether [unit] is a blank `_moveThroughWhitespace` skips: a space,
/// tab, LF, VT, CR, or FF.
bool _isBlank(int unit) =>
    unit == 0x20 || unit == 0x09 || unit == 0x0B || _isLineEnd(unit);
