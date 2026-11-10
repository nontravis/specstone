import 'package:specstone_core/src/doc_model/percent_decode.dart';
import 'package:specstone_core/src/doc_model/whatwg_url.dart';

/// A doc reference split into its parts (doc_model RULE-11); DocIndex
/// resolves it.
final class DocAddress {
  const new({this.typeId, required this.body, this.sectionKey});

  /// The text before the first `:`, when that text is one slug
  /// (`[a-z][a-z0-9_]*`) and the `:` sits before any `#`.
  final String? typeId;

  /// The Name or path after any `<doc type>:`, before any `#`, as written.
  final String body;

  /// The text after the first `#`; null when the text holds no `#`.
  final String? sectionKey;

  /// Whether [body] is a Name: one or more slugs (`[a-z0-9_]+`) joined by
  /// `/`.
  bool get isName => _slugCount(body) >= 1;

  /// Whether the form alone marks a reference (R62): a Name of 2 or more
  /// slugs, bare or after `<doc type>:`, or a one-slug Name after
  /// `<doc type>:`.
  bool get isReferenceWithoutLookup =>
      typeId != null ? isName : _slugCount(body) >= 2;

  /// The text as written, less any `#<section key>`.
  String get docPart => typeId == null ? body : '$typeId:$body';
}

/// The number of `/`-joined slugs in [text]; 0 when any segment is not a
/// non-empty run of `[a-z0-9_]`.
int _slugCount(String text) {
  var count = 0;
  var segmentLength = 0;
  for (var i = 0; i <= text.length; i++) {
    if (i < text.length && _isSlugChar(text.codeUnitAt(i))) {
      segmentLength++;
      continue;
    }
    if (i < text.length && text.codeUnitAt(i) != 0x2F) return 0;
    if (segmentLength == 0) return 0;
    count++;
    segmentLength = 0;
  }
  return count;
}

/// The one-code-point letter test P9 allows (RULE-12: a letter ends no ID).
final _letters = RegExp(r'\p{L}', unicode: true);

bool _isSlugChar(int code) =>
    (code >= 0x61 && code <= 0x7A) || // a-z
    (code >= 0x30 && code <= 0x39) || // 0-9
    code == 0x5F; // _

bool _isDigit(int code) => code >= 0x30 && code <= 0x39;

final _docTypeId = RegExp(r'^[a-z][a-z0-9_]*$');

/// Whether all of [text] is shaped like a doc type id: `[a-z][a-z0-9_]*`.
bool isDocTypeIdShaped(String text) => _docTypeId.hasMatch(text);

/// Reads [text] as a doc address: an optional `<doc type>:` prefix, a Name
/// or path, and an optional `#<section key>` (RULE-11).
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

/// An item ID or a scenario number where its item opens (doc_model RULE-12).
sealed class IdRead {
  const new({required this.prefix, required this.digits});

  final String prefix;
  final String digits;

  /// Prefix plus digits, plus any letter.
  String get written;
}

/// Prefix and digits that end at a character that is no letter and no digit.
final class ItemId extends IdRead {
  const new({required super.prefix, required super.digits});

  BigInt get number => BigInt.parse(digits);

  @override
  String get written => '$prefix$digits';
}

/// Digits a letter follows (`RULE-7a`, `Scenario 6a`): no ID, its own or the
/// digits'.
final class LetteredId extends IdRead {
  const new({
    required super.prefix,
    required super.digits,
    required this.letters,
  });

  final String letters;

  @override
  String get written => '$prefix$digits$letters';
}

/// Digits, a letter run, then a digit (`RULE-7a1`, `Scenario 6a2`): a form
/// the grammar cannot read, neither an ID nor a lettered one.
final class UnreadableId extends IdRead {
  const new({required super.prefix, required super.digits, required this.rest});

  /// The letter and digit run after [digits], as written.
  final String rest;

  @override
  String get written => '$prefix$digits$rest';
}

/// The prefix a `### Scenario <N>` heading's number carries in IDs:
/// `Scenario `.
const scenarioIdPrefix = 'Scenario ';

/// Id of the story section that holds the scenarios.
const acceptanceSectionId = 'acceptance_criteria';

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

/// Returns the key `check` holds an item by: `Scenario <n>` for the number
/// value of a scenario heading (`Scenario 01` repeats `Scenario 1`), else the
/// ID as written.
String itemKeyOf(IdRead id, {required bool isScenario}) => switch (id) {
  ItemId(:final number) when isScenario => '$scenarioIdPrefix$number',
  _ => id.written,
};

/// Reads the number of a `### Scenario <N>` heading [line]; null for any
/// other line.
IdRead? readScenarioHeading(String line) {
  const open = '### $scenarioIdPrefix';
  if (!line.startsWith(open)) return null;
  return _readIdAt(line, scenarioIdPrefix, open.length);
}

/// Reads the digits at [start] and any letter run that follows (RULE-12); a
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
/// included (P9: the test is the code point, not the UTF-16 unit).
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

/// A markdown link target read through the grammar (RULE-11).
sealed class LinkTargetForm;

/// A target the WHATWG URL parser fails on, the linking doc's file URL as
/// its base (RULE-11): the only unreadable class.
final class UnreadableLink extends LinkTargetForm;

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

  /// The path split on `/`, each segment percent-decoded (RULE-7); empty
  /// for `#x`, `?q`.
  final List<String> segments;

  /// The fragment decoded as a segment is; null with no `#`; `''` for `#`
  /// alone (the doc's top, RULE-13).
  final String? anchor;

  /// The text after the first `#` as written, escapes kept; null with no `#`.
  final String? rawAnchor;

  /// The index in the href as written where the path ends: where `?` or `#`
  /// begins, else the href's length.
  final int pathEnd;
}

/// Reads [href] as a link target form (RULE-11): only a target the WHATWG
/// URL parser fails on with a `file:` base is unreadable.
LinkTargetForm readLinkTarget(String href) {
  if (whatwgParseFails(href)) return UnreadableLink();
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

/// A link destination as written, split as `markdown` reads it: the index
/// where the text of its href's first `?` or `#` starts, else its length,
/// and the index past the text of its href's first `#`, null with none.
typedef DestinationParts = ({int pathEnd, int? anchorStart});

/// One code unit of a destination as decoding reads it, and the range of the
/// text written for it.
typedef _ReadUnit = ({int code, int start, int end});

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
  for (final (:code, :start, :end) in _referencesDecoded(units)) {
    if (code == _questionMark) pathEnd ??= start;
    if (code == _hash) return (pathEnd: pathEnd ?? start, anchorStart: end);
  }
  return (pathEnd: pathEnd ?? written.length, anchorStart: null);
}

/// Returns [written], a [kind] destination as written, angle brackets left
/// out, as `markdown`'s link parser hands it to `LinkSyntax.createNode`.
String parsedDestinationOf(String written, DestinationKind kind) =>
    String.fromCharCodes([
      for (final (:code, start: _, end: _) in _parserUnescaped(written, kind))
        code,
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
      units.add((code: code, start: i, end: i + 1));
      continue;
    }
    if (dropsBefore.contains(next)) {
      units.add((code: next, start: i, end: i + 2));
    } else {
      units
        ..add((code: code, start: i, end: i + 1))
        ..add((code: next, start: i + 1, end: i + 2));
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
      unescaped.add((code: next.code, start: unit.start, end: next.end));
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
    yield (
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
/// `.`, then `:` (RULE-11).
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

/// Returns, keyed by its index in [ids], the next free ID of each
/// [LetteredId], counted per prefix in list order (RULE-12, R61): the
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

/// A scenario ref (RULE-11): `S<N>` of the own story when [storyName] is
/// null, else `<story Name>#S<N>`, or a journey `<story Name> S<N>`.
final class ScenarioRef {
  const new(this.number, {this.storyName});

  /// Prefix `S`; a LetteredId names no scenario.
  final IdRead number;

  final String? storyName;

  /// The scenario number; null for a LetteredId.
  BigInt? get scenario => number is ItemId ? (number as ItemId).number : null;

  /// `S<N>` or `<story Name>#S<N>`, as written (P10).
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

  /// `S<value>` or `<story Name>#S<value>`, so `a/b#S09` names `a/b#S9`
  /// (W9); a lettered number as written.
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

/// Reads [text], whole, as a `confirmed` entry's first word (RULE-11).
LinkLabel? readLinkLabel(String text) {
  final scenario = readScenarioRef(text);
  if (scenario != null) return ScenarioLabel(scenario);
  if (_isNfrId(text)) return NfrLabel(text);
  if (_slugCount(text) >= 2) return FrRefLabel(text);
  return null;
}

/// Returns the [LinkLabel.identity] of [label], or [label] as written when
/// it reads as no link label.
///
/// Every reader that matches a `confirmed` entry to its link compares this.
String linkIdentityOf(String label) => readLinkLabel(label)?.identity ?? label;

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
