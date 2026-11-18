import 'package:specstone_core/src/doc_model/doc_items.dart'
    show headingItemTextOf;
import 'package:specstone_core/src/doc_model/models/destination_parts.dart';
import 'package:specstone_core/src/doc_model/models/doc_address.dart';
import 'package:specstone_core/src/doc_model/models/id_read.dart';
import 'package:specstone_core/src/doc_model/models/item_id_at.dart';
import 'package:specstone_core/src/doc_model/percent_decode.dart';

/// The one-code-point letter test: a letter ends no ID.
final _letters = RegExp(r'\p{L}', unicode: true);

bool _isDigit(int code) => code >= 0x30 && code <= 0x39;

// The index of the first digit of [text]; -1 when it holds none.
int _firstDigitAt(String text) {
  for (var at = 0; at < text.length; at++) {
    if (_isDigit(text.codeUnitAt(at))) return at;
  }
  return -1;
}

final _docTypeId = RegExp(r'^[a-z][a-z0-9_]*$');

/// Whether all of [text] is shaped like a doc type id: `[a-z][a-z0-9_]*`.
bool isDocTypeIdShaped(String text) => _docTypeId.hasMatch(text);

/// Reads [text] as a doc address: an optional `<doc type>:` prefix, a Name
/// or path, and an optional `#<section key>`.
///
/// The text before the first `:` is a prefix only when it is one slug; any
/// other text reads whole as the body.
DocAddress readDocAddress(String text) {
  final hash = text.indexOf('#');
  final beforeHash = hash < 0 ? text : text.substring(0, hash);
  final sectionKey = hash < 0 ? null : text.substring(hash + 1);
  final colon = beforeHash.indexOf(':');
  if (colon <= 0 || !isDocTypeIdShaped(beforeHash.substring(0, colon))) {
    return DocAddress(body: beforeHash, sectionKey: sectionKey);
  }
  return DocAddress(
    typeId: beforeHash.substring(0, colon),
    body: beforeHash.substring(colon + 1),
    sectionKey: sectionKey,
  );
}

/// A run of the characters a Name or a doc type prefix is written in.
final _addressRun = RegExp('[a-z0-9_/:]+');

/// The `/` and `:` that open or close a run.
final _runEdge = RegExp(r'^[/:]+|[/:]+$');

/// A no-lookup address found in a line of text.
final class AddressToken {
  const new({required this.column, required this.text, required this.address});

  /// The 0-based offset of the first character of [text] in its line.
  final int column;
  final String text;
  final DocAddress address;
}

/// Returns the no-lookup addresses [text] holds, each a run of slug
/// characters, `/`, and `:` that any other text bounds, less the `/` and `:`
/// that open or close it, in order.
List<AddressToken> addressTokensIn(String text) => [
  for (final run in _addressRun.allMatches(text)) ?_tokenOf(run),
];

AddressToken? _tokenOf(Match run) {
  final written = run[0]!;
  final text = written.replaceAll(_runEdge, '');
  final address = readDocAddress(text);
  if (!address.isReferenceWithoutLookup) return null;
  return AddressToken(
    column: run.start + written.indexOf(text),
    text: text,
    address: address,
  );
}

/// A web address: a scheme, `://`, and the text to the next whitespace,
/// bracket, quote, `|`, or `<`.
final _webAddress = RegExp(
  '(?<![A-Za-z0-9.])[A-Za-z][A-Za-z0-9+\\-]*://[^\\s\\])"\'|<]*',
);

/// A Mermaid node-shape delimiter that holds a slash or a backslash.
final _nodeShape = RegExp(r'\[[/\\]|[/\\]\]');

/// A run that starts with `/` or follows a `.` after a letter or digit: part
/// of a path or a host.
final _pathRun = RegExp(
  r'(?<![a-z0-9_/:])/[a-z0-9_/:]*|(?<=[A-Za-z0-9]\.)[a-z0-9_/:]+',
);

/// A sequence-diagram message up to the `:` that opens its text: sender,
/// arrow, receiver; the first on its line, after any container marks.
final _sequenceMessage = RegExp(
  r'\w+\s*(?:<<-->>|<<->>|-->>|--\)|--x|->>|-\)|-x|-->|->)[+-]?\s*\w+\s*:',
);

String _blanked(Match match) => ' ' * match[0]!.length;

/// Returns the no-lookup tokens of [line], a line of a `mermaid` block: those
/// of [addressTokensIn], less any in a web address or a path, the shape marks
/// around a node's text, and, when [isSequence], the sender, arrow, and
/// receiver of a message, whose `:` is no type prefix.
List<AddressToken> mermaidTokensIn(String line, {bool isSequence = false}) {
  final message = isSequence
      ? line.replaceFirstMapped(_sequenceMessage, _blanked)
      : line;
  return addressTokensIn(
    message
        .replaceAllMapped(_webAddress, _blanked)
        .replaceAllMapped(_nodeShape, _blanked)
        .replaceAllMapped(_pathRun, _blanked),
  );
}

/// Returns the no-lookup addresses [text] holds, in order.
List<DocAddress> referencesWithoutLookupIn(String text) => [
  for (final token in addressTokensIn(text)) token.address,
];

/// A line suffix such as `:12` or `:12:5` after a path written in prose.
final _lineSuffix = RegExp(r'(?::\d+)+$');

/// A closing mark that prose adds after a path.
final _closingMark = RegExp(r'[.,;:]$');

/// Returns [path], a doc path written in prose, less the sentence mark and
/// the line suffix that follow it there.
///
/// [path] is the text of a [DocAddress] before any `#`.
String proseTrimmedPath(String path) =>
    path.replaceFirst(_closingMark, '').replaceFirst(_lineSuffix, '');

/// The prefix a `### Scenario <N>` heading's number carries in IDs:
/// `Scenario `.
const scenarioIdPrefix = 'Scenario ';

/// Id of the story section that holds the scenarios.
const acceptanceSectionId = 'acceptance_criteria';

/// Key of the requirement section that holds the edge cases.
const edgeCasesSectionKey = 'edge_cases';

/// Reads the ID of [prefix] at the start of [text], after one optional `**`;
/// null when [text] does not open with [prefix] and an ASCII digit.
IdRead? readItemId(String text, String prefix) =>
    readItemIdAt(text, text.startsWith('**') ? 2 : 0, prefix);

/// Reads the ID of [prefix] at index [at] of [text], in place; null when
/// [text] holds no [prefix] and ASCII digit there.
IdRead? readItemIdAt(String text, int at, String prefix) {
  if (!text.startsWith(prefix, at)) return null;
  return _readIdAt(text, prefix, at + prefix.length);
}

/// Reads the ID at the start of [text] that carries no declared prefix: the
/// letters and hyphens before its first digit, after one optional `**`, are
/// the prefix; null when [text] opens with no such prefix and digit.
IdRead? readItemIdOfWrittenPrefix(String text) {
  final prefix = _writtenPrefix.firstMatch(text)?.group(1);
  return prefix == null ? null : readItemId(text, prefix);
}

final _writtenPrefix = RegExp(r'^(?:\*\*)?([A-Za-z][A-Za-z-]*)\d');

/// Returns each item ID of [prefixes] written in [prose], in order, with its
/// offset.
///
/// An ID is a token of one of [prefixes], the longest first, so `SHA256` is
/// no ID unless a doc type's section holds the prefix `SHA`. The digits are
/// read by [readItemIdAt]: a lettered or unreadable form is no ID.
List<ItemIdAt> itemIdsInProse(String prose, {required Set<String> prefixes}) {
  final found = <ItemIdAt>[];
  final longestFirst = prefixes.toList()..sort((a, b) => b.length - a.length);
  for (final prefix in longestFirst) {
    for (
      var at = prose.indexOf(prefix);
      at >= 0;
      at = prose.indexOf(prefix, at + 1)
    ) {
      if (at > 0 && _endsWord(prose, at)) continue;
      if (readItemIdAt(prose, at, prefix) case final ItemId id) {
        final end = at + id.written.length;
        final overlaps = found.any(
          (f) => at < f.at + f.id.written.length && f.at < end,
        );
        if (!overlaps) found.add(ItemIdAt(at: at, id: id));
      }
    }
  }
  return found..sort((a, b) => a.at - b.at);
}

/// An ID of an item-ID run and its 0-based column on the line.
final class RunItem {
  const new({required this.at, required this.id});

  final int at;

  /// An [ItemId] or a [LetteredId]; an [UnreadableId] ends a run.
  final IdRead id;
}

/// The text that may stand between two IDs of a run, longest first so `, and `
/// is not read as `, `.
const _runJoiners = [', and ', ' and ', ' or ', ', ', ' to '];

/// Reads the item IDs of [prefixes] that run right after column [from] of
/// [line], the end of a citation.
///
/// The first ID follows zero or more spaces and each next one a joiner; the
/// first other text ends the run. [line] is read as written, so a code span
/// ends the run. A lettered ID joins the run; an unreadable one ends it.
List<RunItem> itemIdRunAt(
  String line,
  int from, {
  required Set<String> prefixes,
}) {
  final longestFirst = prefixes.toList()..sort((a, b) => b.length - a.length);
  final items = <RunItem>[];
  var at = from;
  while (at < line.length && line.codeUnitAt(at) == _spaceUnit) {
    at++;
  }
  while (true) {
    final id = _runIdAt(line, at, longestFirst);
    if (id == null) break;
    items.add(RunItem(at: at, id: id));
    final end = at + id.written.length;
    final joiner = _runJoiners.where((it) => line.startsWith(it, end));
    if (joiner.isEmpty) break;
    at = end + joiner.first.length;
  }
  return items;
}

/// Reads the item or lettered ID of one of [longestFirst] at [at]; null when
/// none starts there, or the form is unreadable.
IdRead? _runIdAt(String line, int at, List<String> longestFirst) {
  if (at >= line.length) return null;
  if (at > 0 && _endsWord(line, at)) return null;
  for (final prefix in longestFirst) {
    final id = readItemIdAt(line, at, prefix);
    if (id == null) continue;
    return id is UnreadableId ? null : id;
  }
  return null;
}

const _spaceUnit = 0x20;

/// Whether the character before [at] in [text] is a letter or digit.
bool _endsWord(String text, int at) {
  final unit = text.codeUnitAt(at - 1);
  return _isDigit(unit) || _letters.hasMatch(text[at - 1]);
}

/// Returns the key `check` holds an item by: `Scenario <n>` for the number
/// value of a scenario heading (`Scenario 01` repeats `Scenario 1`), else the
/// ID as written.
String itemKeyOf(IdRead id, {required bool isScenario}) => switch (id) {
  ItemId(:final number) when isScenario => '$scenarioIdPrefix$number',
  _ => id.written,
};

/// Reads the number of the `### Scenario <N>` heading item [line] opens, a
/// quoted one included, as [headingItemTextOf] reads it; null for any other
/// line.
IdRead? readScenarioHeading(String line) => switch (headingItemTextOf(line)) {
  final head? => readScenarioHead(head),
  null => null,
};

/// Reads the number of a scenario heading item's text [head], `Scenario <N>`
/// at its start; null for any other text.
IdRead? readScenarioHead(String head) {
  if (!head.startsWith(scenarioIdPrefix)) return null;
  return _readIdAt(head, scenarioIdPrefix, scenarioIdPrefix.length);
}

/// Reads the digits at [start] and any letter run that follows; a
/// digit after that run makes the form unreadable.
IdRead? _readIdAt(String text, String prefix, int start) {
  final end = _digitsEnd(text, start);
  if (end == start) return null;
  final digits = text.substring(start, end);
  final letterEnd = _lettersEnd(text, end);
  if (letterEnd == end) return ItemId(prefix: prefix, digits: digits);
  if (letterEnd < text.length && _isDigit(text.codeUnitAt(letterEnd))) {
    return UnreadableId(
      prefix: prefix,
      digits: digits,
      rest: text.substring(end, _alphanumericEnd(text, letterEnd)),
    );
  }
  return LetteredId(
    prefix: prefix,
    digits: digits,
    letters: text.substring(end, letterEnd),
  );
}

int _digitsEnd(String text, int start) {
  var end = start;
  while (end < text.length && _isDigit(text.codeUnitAt(end))) {
    end++;
  }
  return end;
}

/// The index past the run of letters and ASCII digits starting at [start].
int _alphanumericEnd(String text, int start) {
  var end = start;
  while (true) {
    final past = _lettersEnd(text, _digitsEnd(text, end));
    if (past == end) return end;
    end = past;
  }
}

/// The index past a letter run starting at [start], astral letters
/// included (the test is the code point, not the UTF-16 unit).
int _lettersEnd(String text, int start) {
  var end = start;
  while (end < text.length) {
    final width = _isHighSurrogate(text.codeUnitAt(end)) ? 2 : 1;
    final next = end + width > text.length ? text.length : end + width;
    if (!_letters.hasMatch(text.substring(end, next))) break;
    end = next;
  }
  return end;
}

bool _isHighSurrogate(int unit) => unit >= 0xD800 && unit <= 0xDBFF;

// MARK: - Link targets

/// A markdown link target read through the grammar.
sealed class LinkTargetForm;

/// A target opening with a scheme, any scheme.
final class SchemeLink extends LinkTargetForm {
  new(this.scheme);

  /// The scheme, lower case.
  final String scheme;
}

/// A target whose `//` opens the path: a protocol-relative authority.
final class AuthorityLink extends LinkTargetForm;

/// A target whose path opens with `/`.
final class RootedLink extends LinkTargetForm;

/// A target relative to the linking doc.
final class RelativeLink extends LinkTargetForm {
  new({
    required this.segments,
    required this.anchor,
    required this.rawAnchor,
    required this.pathEnd,
  });

  /// The path split on `/`, each segment percent-decoded; empty
  /// for `#x`, `?q`.
  final List<String> segments;

  /// The fragment decoded as a segment is; null with no `#`; `''` for `#`
  /// alone (the doc's top).
  final String? anchor;

  /// The text after the first `#` as written, escapes kept; null with no `#`.
  final String? rawAnchor;

  /// The index in the href as written where the path ends: where `?` or `#`
  /// begins, else the href's length.
  final int pathEnd;
}

/// Reads [href] as a link target form; every target reads as one of them.
LinkTargetForm readLinkTarget(String href) {
  final fragmentAt = href.indexOf('#');
  final beforeFragment = fragmentAt < 0 ? href : href.substring(0, fragmentAt);
  final rawAnchor = fragmentAt < 0 ? null : href.substring(fragmentAt + 1);
  final anchor = rawAnchor == null ? null : percentDecoded(rawAnchor);
  final schemeEnd = schemeEndOf(beforeFragment);
  if (schemeEnd > 0) {
    return SchemeLink(beforeFragment.substring(0, schemeEnd - 1).toLowerCase());
  }
  if (beforeFragment.startsWith('//')) return AuthorityLink();
  if (beforeFragment.startsWith('/')) return RootedLink();
  final queryAt = beforeFragment.indexOf('?');
  final path = queryAt < 0
      ? beforeFragment
      : beforeFragment.substring(0, queryAt);
  return RelativeLink(
    segments: path.isEmpty
        ? const <String>[]
        : [for (final segment in path.split('/')) percentDecoded(segment)],
    anchor: anchor,
    rawAnchor: rawAnchor,
    pathEnd: path.length,
  );
}

/// How `markdown` 7.3.1 reads a link destination as written, which decides
/// the backslashes its link parser drops before the rest is decoded.
enum DestinationKind {
  /// An inline link's or image's destination, bare.
  inline,

  /// An inline link's or image's destination in angle brackets.
  angleInline,

  /// A link reference definition's destination, bare or in angle brackets.
  definition,
}

/// One code unit of a destination as decoding reads it, and the range of the
/// text written for it.
final class _ReadUnit {
  const new({required this.code, required this.start, required this.end});

  final int code;
  final int start;
  final int end;
}

const _backslash = 0x5C;
const _hash = 0x23;
const _questionMark = 0x3F;
const _openParen = 0x28;
const _closeParen = 0x29;
const _greaterThan = 0x3E;

/// The code a character reference decodes to that is neither `#` nor `?`.
const _otherCode = -1;

/// The character references `markdown` 7.3.1 decodes in a destination, the
/// pattern of its `decodeHtmlCharacters`, which it does not export.
final _characterReference = RegExp(
  '&(?:([a-z0-9]+)|#([0-9]{1,7})|#x([a-f0-9]{1,6}));',
  caseSensitive: false,
);

/// The named references to `#` and `?` in `markdown` 7.3.1's entity table.
const Map<String, int> _namedSplitters = {
  '&num;': _hash,
  '&quest;': _questionMark,
};

/// Returns the parts of [written], a link destination as written, angle
/// brackets left out, read as `markdown` 7.3.1 reads a [kind] destination.
///
/// A `#` or `?` the href takes from a backslash escape or a character
/// reference splits where the text written for it starts and ends; a percent
/// escape splits nothing.
DestinationParts destinationPartsOf(String written, DestinationKind kind) {
  int? pathEnd;
  final units = _punctuationUnescaped(_parserUnescaped(written, kind));
  for (final _ReadUnit(:code, :start, :end) in _referencesDecoded(units)) {
    if (code == _questionMark) pathEnd ??= start;
    if (code == _hash) {
      return DestinationParts(pathEnd: pathEnd ?? start, anchorStart: end);
    }
  }
  return DestinationParts(
    pathEnd: pathEnd ?? written.length,
    anchorStart: null,
  );
}

/// Returns [written], a [kind] destination as written, angle brackets left
/// out, as `markdown`'s link parser hands it to `LinkSyntax.createNode`.
String parsedDestinationOf(String written, DestinationKind kind) =>
    String.fromCharCodes([
      for (final _ReadUnit(:code) in _parserUnescaped(written, kind)) code,
    ]);

/// The units of [written] after the link parser of a [kind] destination
/// drops the backslash before a backslash or a delimiter it may hold.
List<_ReadUnit> _parserUnescaped(String written, DestinationKind kind) {
  final dropsBefore = switch (kind) {
    DestinationKind.inline => const {_backslash, _openParen, _closeParen},
    DestinationKind.angleInline => const {_backslash, _greaterThan},
    DestinationKind.definition => const <int>{},
  };
  final units = <_ReadUnit>[];
  for (var i = 0; i < written.length; i++) {
    final code = written.codeUnitAt(i);
    final next = i + 1 < written.length ? written.codeUnitAt(i + 1) : null;
    if (code != _backslash || next == null) {
      units.add(_ReadUnit(code: code, start: i, end: i + 1));
      continue;
    }
    if (dropsBefore.contains(next)) {
      units.add(_ReadUnit(code: next, start: i, end: i + 2));
    } else {
      units
        ..add(_ReadUnit(code: code, start: i, end: i + 1))
        ..add(_ReadUnit(code: next, start: i + 1, end: i + 2));
    }
    // The parser takes the unit after a backslash as it is, never again.
    i++;
  }
  return units;
}

/// [units] after `markdown`'s `escapePunctuation`: a backslash before ASCII
/// punctuation drops, its text joining the unit after it.
List<_ReadUnit> _punctuationUnescaped(List<_ReadUnit> units) {
  final unescaped = <_ReadUnit>[];
  for (var i = 0; i < units.length; i++) {
    final unit = units[i];
    if (unit.code == _backslash &&
        i + 1 < units.length &&
        _isAsciiPunctuation(units[i + 1].code)) {
      final next = units[i + 1];
      unescaped.add(
        _ReadUnit(code: next.code, start: unit.start, end: next.end),
      );
      i++;
      continue;
    }
    unescaped.add(unit);
  }
  return unescaped;
}

/// [units] with each character reference read as the one unit it decodes
/// to, its text the reference's.
Iterable<_ReadUnit> _referencesDecoded(List<_ReadUnit> units) sync* {
  final text = String.fromCharCodes([for (final unit in units) unit.code]);
  var at = 0;
  for (final match in _characterReference.allMatches(text)) {
    yield* units.getRange(at, match.start);
    yield _ReadUnit(
      code: _referenceCode(match),
      start: units[match.start].start,
      end: units[match.end - 1].end,
    );
    at = match.end;
  }
  yield* units.getRange(at, units.length);
}

/// The code unit [match], a character reference, decodes to when that is a
/// `#` or a `?`; another code otherwise.
int _referenceCode(Match match) {
  if (match[1] != null) return _namedSplitters[match[0]] ?? _otherCode;
  final decimal = match[2];
  return decimal != null ? int.parse(decimal) : int.parse(match[3]!, radix: 16);
}

bool _isAsciiPunctuation(int code) =>
    (code >= 0x21 && code <= 0x2F) ||
    (code >= 0x3A && code <= 0x40) ||
    (code >= 0x5B && code <= 0x60) ||
    (code >= 0x7B && code <= 0x7E);

/// Returns the index past the `:` of a scheme at [start] of [text], or -1
/// when none opens there: an ASCII letter, then letters, digits, `+`, `-`,
/// `.`, then `:`.
int schemeEndOf(String text, [int start = 0]) {
  if (start >= text.length || !_isAsciiLetter(text.codeUnitAt(start))) {
    return -1;
  }
  var i = start + 1;
  for (; i < text.length; i++) {
    final code = text.codeUnitAt(i);
    if (_isAsciiLetter(code) || _isDigit(code)) continue;
    if (code == 0x2B || code == 0x2D || code == 0x2E) continue; // + - .
    break;
  }
  return i < text.length && text.codeUnitAt(i) == 0x3A ? i + 1 : -1;
}

bool _isAsciiLetter(int code) =>
    (code >= 0x41 && code <= 0x5A) || (code >= 0x61 && code <= 0x7A);

final _webLink = RegExp('^https?://', caseSensitive: false);

/// Whether [text] opens with an `http://` or `https://` web address.
bool isWebLink(String text) => _webLink.hasMatch(text);

final _rootedOrDrivePath = RegExp(r'^(?:[/\\]|[A-Za-z]:)');

/// Whether [path] opens with a `/` or `\`, or a drive letter and `:`: a path
/// that is not relative to the folder it is read in.
bool isRootedOrDrivePath(String path) => _rootedOrDrivePath.hasMatch(path);

final _angleDestinationOpen = RegExp(r'\]\(\s*<');

/// Whether [source] holds, at index [at], the `](` that closes a link's text
/// and opens its destination in angle brackets.
bool opensAngleDestinationAt(String source, int at) =>
    _angleDestinationOpen.matchAsPrefix(source, at) != null;

/// Returns, keyed by its index in [ids], the next free ID of each
/// [LetteredId], counted per prefix in list order: the
/// highest [ItemId] number of that prefix plus one, plus one per earlier
/// [LetteredId] of that prefix, zero-padded to the digit count of that
/// highest [ItemId] (1 when none).
Map<int, String> nextFreeIds(List<IdRead> ids) {
  final highest = <String, BigInt>{};
  final digitWidth = <String, int>{};
  for (final id in ids) {
    if (id is! ItemId) continue;
    final current = highest[id.prefix];
    if (current != null && id.number <= current) continue;
    highest[id.prefix] = id.number;
    digitWidth[id.prefix] = id.digits.length;
  }
  final nextOf = <int, String>{};
  final takenPerPrefix = <String, int>{};
  for (var i = 0; i < ids.length; i++) {
    final id = ids[i];
    if (id is! LetteredId) continue;
    final taken = takenPerPrefix[id.prefix] ?? 0;
    takenPerPrefix[id.prefix] = taken + 1;
    final base = (highest[id.prefix] ?? BigInt.zero) + BigInt.from(taken + 1);
    final width = digitWidth[id.prefix] ?? 1;
    nextOf[i] = '${id.prefix}${base.toString().padLeft(width, '0')}';
  }
  return nextOf;
}

/// A scenario ref: `S<N>` of the own story when [storyName] is
/// null, else `<story Name>#S<N>`, or a journey `<story Name> S<N>`.
final class ScenarioRef {
  const new(this.number, {this.storyName});

  /// Prefix `S`; a LetteredId names no scenario.
  final IdRead number;

  final String? storyName;

  /// The scenario number; null for a LetteredId.
  BigInt? get scenario => number is ItemId ? (number as ItemId).number : null;

  /// `S<N>` or `<story Name>#S<N>`, as written.
  String get label =>
      storyName == null ? number.written : '$storyName#${number.written}';
}

/// Reads [text], whole, as `S<N>` or `<story Name>#S<N>`; null for any other
/// text.
ScenarioRef? readScenarioRef(String text) {
  final hash = text.indexOf('#');
  final storyPart = hash < 0 ? null : text.substring(0, hash);
  if (storyPart != null && storyPart.isEmpty) return null;
  if (storyPart != null && storyPart.contains(' ')) return null;
  final number = _readNumberPart(hash < 0 ? text : text.substring(hash + 1));
  if (number == null) return null;
  return ScenarioRef(number, storyName: storyPart);
}

/// Reads a journey `step:` value, whole, as `<story Name> S<N>`, one space
/// between.
ScenarioRef? readStepTargetValue(String value) {
  final space = value.lastIndexOf(' ');
  if (space <= 0) return null;
  final storyName = value.substring(0, space);
  if (storyName.contains(' ')) return null;
  final number = _readNumberPart(value.substring(space + 1));
  if (number == null) return null;
  return ScenarioRef(number, storyName: storyName);
}

/// Reads `S<N>` [text], whole; any text past the ID reads as null.
IdRead? _readNumberPart(String text) {
  if (!text.startsWith('S')) return null;
  final id = _readIdAt(text, 'S', 1);
  return id != null && id.written.length == text.length ? id : null;
}

/// The first word of a `confirmed` entry (domain:consistency_check
/// LinkLabel).
sealed class LinkLabel {
  const new();

  String get written;

  /// The link the label names, which an entry and a link match by.
  String get identity => written;
}

final class ScenarioLabel extends LinkLabel {
  const new(this.ref);

  final ScenarioRef ref;

  @override
  String get written => ref.label;

  /// `S<value>` or `<story Name>#S<value>`, so `a/b#S09` names `a/b#S9`;
  /// a lettered number as written.
  @override
  String get identity {
    final scenario = ref.scenario;
    if (scenario == null) return written;
    final storyName = ref.storyName;
    return storyName == null ? 'S$scenario' : '$storyName#S$scenario';
  }
}

/// An id `NFR-`, letters, digits, as `NFR-P01`.
final class NfrLabel extends LinkLabel {
  const new(this.id);

  final String id;

  @override
  String get written => id;
}

/// An FR ref: a Name of 2 or more slugs, as `login/email_login`.
final class FrRefLabel extends LinkLabel {
  const new(this.name);

  final String name;

  @override
  String get written => name;
}

/// An override address: `<doc type>:<name>#<item ID>`, as
/// `project_domain:domain#INV-3`.
final class OverrideLabel extends LinkLabel {
  const new(this.address, this.itemId);

  /// The doc the address names, never looked up.
  final DocAddress address;

  /// The item ID after the `#`, as written.
  final String itemId;

  @override
  String get written => '${address.docPart}#$itemId';
}

/// Reads [text], whole, as a `confirmed` entry's first word.
LinkLabel? readLinkLabel(String text) {
  final override = _readOverrideLabel(text);
  if (override != null) return override;
  final scenario = readScenarioRef(text);
  if (scenario != null) return ScenarioLabel(scenario);
  if (_isNfrId(text)) return NfrLabel(text);
  if (DocAddress(body: text).isReferenceWithoutLookup) return FrRefLabel(text);
  return null;
}

/// Returns the [LinkLabel.identity] of [label], or [label] as written when
/// it reads as no link label.
///
/// Every reader that matches a `confirmed` entry to its link compares this.
String linkIdentityOf(String label) => readLinkLabel(label)?.identity ?? label;

final _leadingLinkTarget = RegExp(r'^\[[^\]]*\]\(([^)\s]*)');

/// Returns the target of the markdown link that opens [text], as written, or
/// null when [text] opens with no link.
String? readLeadingLinkTarget(String text) =>
    _leadingLinkTarget.firstMatch(text)?.group(1);

/// Reads [text], whole, as `<doc type>:<name>#<item ID>`; null for any other
/// text, a lettered or unreadable ID included.
OverrideLabel? _readOverrideLabel(String text) {
  final address = readDocAddress(text);
  final key = address.sectionKey;
  if (address.typeId == null || !address.isName || key == null) return null;
  final prefixEnd = _firstDigitAt(key);
  if (prefixEnd <= 0) return null;
  final id = readItemIdAt(key, 0, key.substring(0, prefixEnd));
  if (id is! ItemId || id.written.length != key.length) return null;
  return OverrideLabel(address, key);
}

bool _isNfrId(String text) {
  const open = 'NFR-';
  if (!text.startsWith(open)) return false;
  final lettersEnd = _lettersEnd(text, open.length);
  if (lettersEnd == open.length) return false;
  final digitsStart = lettersEnd;
  var i = digitsStart;
  while (i < text.length && _isDigit(text.codeUnitAt(i))) {
    i++;
  }
  return i > digitsStart && i == text.length;
}
