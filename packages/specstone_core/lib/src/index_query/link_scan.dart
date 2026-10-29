import 'dart:typed_data';

import 'package:markdown/markdown.dart'
    show
        AutolinkExtensionSyntax,
        AutolinkSyntax,
        EmailAutolinkSyntax,
        InlineHtmlSyntax;
import 'package:specstone_core/src/index_query/link_blocks.dart';

/// A source of an `a` element markdown makes: the body offset of its first
/// character, its file line, and, for an inline or reference link, its
/// destination as written (null for an autolink, an email autolink, or a GFM
/// bare URL or email).
typedef LinkSource = ({int offset, int line, String? shown});

/// Returns the sources of the links in [lfBody], in source order.
///
/// [lfBody] is the doc text after the frontmatter, with LF line ends, and
/// [firstLine] is its first file line. Each leaf block (see [leafTextOf]) is
/// read left to right by CommonMark's bracket procedure, as `markdown` 7.3.1
/// runs it (`InlineParser.parse`): an escape, a code span, raw HTML, an
/// autolink, and a GFM bare URL or email bind tighter than brackets, so each is
/// skipped whole; a `[` or `![` pushes an opener, and a `]` closes the last
/// opener as an inline link, a full, collapsed, or shortcut reference, or is
/// text. A link turns off every link opener pushed before it, so a link inside
/// link text leaves the outer brackets as text; a link in an image description
/// is dropped with the image. Each autolink, email autolink, and bare URL or
/// email is a source with no destination. Where `markdown` differs from the
/// CommonMark text, the scan reads as `markdown` does: a tab stays in a bare
/// destination, a title after an open paren keeps the destination open, and a
/// bare URL runs through the brackets after it.
///
/// The scan stays linear in the size of [lfBody]. Each `]` is decided once,
/// and each repeated attempt is decided from a table one pass fills per leaf:
/// the end of a blank run, the escape-aware partner of a `(`, and the next
/// unescaped space, `>`, `"`, `'`, or `)`. An atom pattern runs only where its
/// closer exists in the leaf: the next backtick run of the same length, the
/// next `>`, `-->`, `?>`, or `]]>`, and the end of a run of email code units.
/// A link opener is off when a link closed after its push, a count the opener
/// stores. The text between an opener and its `]` is looked up as a label only
/// when no opener was pushed after it, so the spans looked up are disjoint. A
/// reference link shares its definition's string, and the destinations of
/// distinct links are disjoint. The one chain left is a title after an open
/// paren, which takes no more steps than `markdown`'s own walk.
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
  late final _Next _angleClose = _Next(text, '>');
  late final _Next _angleOrSpace = _Next(text, _angleOrSpacePattern);
  late final _Next _commentClose = _Next(text, '-->');
  late final _Next _instructionClose = _Next(text, '?>');
  late final _Next _cdataClose = _Next(text, ']]>');

  // The leaf [read] is reading, and what the atoms in it share.
  int _start = 0;
  int _end = 0;
  String? _leaf;
  Map<int, int>? _closers;
  int _emailRunEnd = -1;
  bool _emailRunDead = true;

  /// Reads the leaf [start] to [end], adding its links to [found].
  void read(int start, int end) {
    _start = start;
    _end = end;
    _leaf = null;
    _closers = null;
    _emailRunEnd = -1;
    _emailRunDead = true;
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
      } else if (unit == _backtick) {
        i = _codeSpan(i);
      } else if (unit == _lessThan) {
        i = _angle(i);
      } else if (_isEmailUnit(unit)) {
        i = _extensionAutolink(i, unit);
      } else {
        i++;
      }
    }
  }

  /// Returns the leaf as a string, which the patterns of `markdown` match
  /// against as they match the inline text of a paragraph.
  String get _leafText => _leaf ??= text.substring(_start, _end);

  /// Returns the offset after the code span that opens with the backtick run at
  /// [at], or after the run when no closing run follows (`CodeSyntax`).
  ///
  /// A run opens a span when the code unit before it is no backtick; the span
  /// ends at the next run of the same length. One pass over the leaf finds the
  /// closing run of every run, so a run that never closes costs no rescan.
  int _codeSpan(int at) {
    if (at > _start && text.codeUnitAt(at - 1) == _backtick) return at + 1;
    var runEnd = at + 1;
    while (runEnd < _end && text.codeUnitAt(runEnd) == _backtick) {
      runEnd++;
    }
    final closer = (_closers ??= _closingRuns())[at];
    return closer == null ? runEnd : closer + (runEnd - at);
  }

  /// Returns the offset of the next run of the same length for each backtick
  /// run in the leaf that has one.
  ///
  /// The content of a code span holds no CR, U+2028, or U+2029 but its last
  /// code unit, which `.` does not match (`CodeSyntax`'s pattern). Such a code
  /// unit ends the search of every run before it, except for a run right after
  /// it.
  Map<int, int> _closingRuns() {
    final closers = <int, int>{};
    var lastOfLength = <int, int>{};
    var beforeSeparator = <int, int>{};
    var separatorAt = -2;
    var i = _start;
    while (i < _end) {
      final unit = text.codeUnitAt(i);
      if (unit == _backtick) {
        var runEnd = i + 1;
        while (runEnd < _end && text.codeUnitAt(runEnd) == _backtick) {
          runEnd++;
        }
        final length = runEnd - i;
        final previous = separatorAt == i - 1
            ? beforeSeparator[length]
            : lastOfLength[length];
        if (previous != null) closers[previous] = i;
        lastOfLength[length] = i;
        i = runEnd;
      } else {
        if (unit == _carriageReturn ||
            unit == _lineSeparator ||
            unit == _paragraphSeparator) {
          separatorAt = i;
          beforeSeparator = lastOfLength;
          lastOfLength = <int, int>{};
        }
        i++;
      }
    }
    return closers;
  }

  /// Returns the offset after the raw HTML, email autolink, or autolink that
  /// opens with the `<` at [at], or `at + 1` when none does.
  ///
  /// `markdown` tries them in that order, and a `<` opens at most one. A
  /// pattern runs only when its closer exists in the leaf, so a `<` that never
  /// closes costs no scan.
  int _angle(int at) {
    final html = _htmlEnd(at);
    if (html > 0) return html;
    final close = _angleOrSpace.from(at + 1);
    if (close >= _end || text.codeUnitAt(close) != _greaterThan) return at + 1;
    final from = at - _start;
    final match =
        _emailAutolinkPattern.matchAsPrefix(_leafText, from) ??
        _autolinkPattern.matchAsPrefix(_leafText, from);
    if (match == null) return at + 1;
    found.add((offset: at, shown: null));
    return at + (match.end - from);
  }

  /// Returns the offset after the raw HTML that opens with the `<` at [at], or
  /// -1 when none does (`InlineHtmlSyntax`).
  int _htmlEnd(int at) {
    final next = at + 1 < _end ? text.codeUnitAt(at + 1) : -1;
    final bool closes;
    if (next == _bang) {
      final third = at + 2 < _end ? text.codeUnitAt(at + 2) : -1;
      closes = switch (third) {
        _dash => _closesBy(_commentClose, at + 4, 3),
        _openBracket => _closesBy(_cdataClose, at + 9, 3),
        _ => _isAsciiLetter(third) && _closesBy(_angleClose, at + 3, 1),
      };
    } else if (next == _question) {
      closes = _closesBy(_instructionClose, at + 2, 2);
    } else {
      closes =
          (next == _slash || _isAsciiLetter(next)) &&
          _closesBy(_angleClose, at + 2, 1);
    }
    if (!closes) return -1;
    final from = at - _start;
    final match = _htmlPattern.matchAsPrefix(_leafText, from);
    return match == null ? -1 : at + (match.end - from);
  }

  /// Returns whether [closer], [length] code units long, ends in the leaf at or
  /// after [from].
  bool _closesBy(_Next closer, int from, int length) =>
      closer.from(from) + length <= _end;

  /// Returns the offset after the GFM bare URL or email that starts at [at], or
  /// `at + 1` when none does (`AutolinkExtensionSyntax`).
  ///
  /// [unit] is the code unit at [at], one an email can hold. The pattern runs
  /// at a URL scheme, or in a run of email code units that ends in `@`. Every
  /// start in a run shares the text after the `@`, so once the pattern finds
  /// no email in a run, the run is dead for the rest of its starts.
  int _extensionAutolink(int at, int unit) {
    final startsUrl = _startsUrl(at, unit);
    if (at >= _emailRunEnd) {
      var runEnd = at + 1;
      while (runEnd < _end && _isEmailUnit(text.codeUnitAt(runEnd))) {
        runEnd++;
      }
      _emailRunEnd = runEnd;
      _emailRunDead = runEnd >= _end || text.codeUnitAt(runEnd) != _atSign;
    }
    if (!startsUrl && _emailRunDead) return at + 1;
    final leaf = _leafText;
    final from = at - _start;
    final match = _extensionPattern.matchAsPrefix(leaf, from);
    if (match == null) {
      _emailRunDead = true;
      return at + 1;
    }
    if (match[1] != null) {
      if (from > 0 && !_urlPrecedents.contains(text.codeUnitAt(at - 1))) {
        return at + 1;
      }
      found.add((offset: at, shown: null));
      return at + _urlLength(match[0]!);
    }
    final after = match.end < leaf.length ? leaf.codeUnitAt(match.end) : -1;
    if (after == _underscore || after == _dash) {
      _emailRunDead = true;
      return at + 1;
    }
    found.add((offset: at, shown: null));
    return at + (match.end - from);
  }

  /// Returns whether a URL scheme or `www.` starts at [at], where [unit] is the
  /// code unit there.
  bool _startsUrl(int at, int unit) {
    final lower = unit | 0x20;
    if (lower != 0x68 && lower != 0x66 && lower != 0x77) return false;
    return _urlStart.matchAsPrefix(text, at) != null;
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
const _backtick = 0x60;
const _dash = 0x2D;
const _question = 0x3F;
const _slash = 0x2F;
const _atSign = 0x40;
const _underscore = 0x5F;
const _carriageReturn = 0x0D;
const _lineSeparator = 0x2028;
const _paragraphSeparator = 0x2029;

final _blankOnly = RegExp(r'^\s*$');

// The patterns of the atoms `markdown` 7.3.1 reads before it reads a bracket.
final RegExp _htmlPattern = InlineHtmlSyntax().pattern;
final RegExp _extensionPattern = AutolinkExtensionSyntax().pattern;
final RegExp _emailAutolinkPattern = EmailAutolinkSyntax().pattern;
final RegExp _autolinkPattern = AutolinkSyntax().pattern;

final _angleOrSpacePattern = RegExp(r'[>\s]');
final _urlStart = RegExp(r'(?:https?|ftp)://|www\.', caseSensitive: false);
final _entityTail = RegExp(r'&[0-9a-z]+;$');

/// The code units a GFM bare URL may follow, besides the start of the text
/// (`AutolinkExtensionSyntax.tryMatch`): LF, space, `*`, `_`, `~`, `(`, `>`.
const _urlPrecedents = {0x0A, 0x20, 0x2A, 0x5F, 0x7E, 0x28, 0x3E};

/// Returns how many code units of the matched bare URL [url] belong to the
/// link: a closing paren with no opening one, or an entity, stays text
/// (`AutolinkExtensionSyntax._getConsumeLength`).
int _urlLength(String url) {
  var excluded = 0;
  if (url.endsWith(')')) {
    if (url.contains('(')) {
      var balance = 0;
      for (var i = 0; i < url.length; i++) {
        final unit = url.codeUnitAt(i);
        if (unit == _openParen) {
          balance++;
        } else if (unit == _closeParen) {
          balance--;
        }
      }
      if (balance < 0) excluded = -balance;
    } else {
      var i = url.length;
      while (i > 0 && url.codeUnitAt(i - 1) == _closeParen) {
        i--;
      }
      excluded = url.length - i;
    }
  } else if (url.endsWith(';')) {
    excluded = _entityTail.firstMatch(url)?[0]!.length ?? 0;
  }
  return url.length - excluded;
}

/// Returns whether [unit] is an ASCII letter.
bool _isAsciiLetter(int unit) => (unit | 0x20) >= 0x61 && (unit | 0x20) <= 0x7A;

/// Returns whether [unit] can be in the local part of a GFM bare email: a
/// letter, a digit, `-`, `_`, `.`, or `+`.
bool _isEmailUnit(int unit) =>
    _isAsciiLetter(unit) ||
    (unit >= 0x30 && unit <= 0x39) ||
    unit == _dash ||
    unit == _underscore ||
    unit == 0x2E ||
    unit == 0x2B;

/// Finds the next occurrence of a pattern at or after an offset, searching
/// forward once.
///
/// The offsets passed to [from] do not decrease, so an occurrence found stays
/// the answer until the offset passes it, and a pattern with no more
/// occurrences is searched for no more.
final class _Next {
  new(this._text, this._pattern);

  static const _none = 0x3FFFFFFF;

  final String _text;
  final Pattern _pattern;
  int _found = -1;

  /// Returns the offset of the first occurrence at or after [offset], or a
  /// number past every offset of the text when none follows.
  int from(int offset) {
    if (_found >= offset) return _found;
    final found = offset > _text.length ? -1 : _text.indexOf(_pattern, offset);
    return _found = found < 0 ? _none : found;
  }
}

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
