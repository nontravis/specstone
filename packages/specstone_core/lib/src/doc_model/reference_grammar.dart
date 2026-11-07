import 'package:specstone_core/src/doc_model/percent_decode.dart';
import 'package:specstone_core/src/doc_model/whatwg_url.dart';

/// A doc reference split into its parts (doc_model RULE-11); DocIndex
/// resolves it.
final class DocAddress {
  const new({this.typeId, required this.body, this.sectionKey});

  /// The text before the first `:`, when that `:` sits past index 0 and
  /// before any `#`.
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

/// Reads [text] as a doc address: an optional `<doc type>:` prefix, a Name
/// or path, and an optional `#<section key>` (RULE-11).
DocAddress readDocAddress(String text) {
  final hash = text.indexOf('#');
  final beforeHash = hash < 0 ? text : text.substring(0, hash);
  final sectionKey = hash < 0 ? null : text.substring(hash + 1);
  final colon = beforeHash.indexOf(':');
  if (colon <= 0) {
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

/// Reads the ID of [prefix] at the start of [text], after one optional `**`;
/// null when [text] does not open with [prefix] and an ASCII digit.
IdRead? readItemId(String text, String prefix) {
  var rest = text;
  if (rest.startsWith('**')) rest = rest.substring(2);
  if (!rest.startsWith(prefix)) return null;
  return _readIdAt(rest, prefix, prefix.length);
}

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
  var offset = 0;
  for (final rune in text.runes) {
    if (offset < end) {
      offset += _runeWidth(rune);
      continue;
    }
    if (!_letters.hasMatch(String.fromCharCode(rune))) break;
    end += _runeWidth(rune);
    offset = end;
  }
  return end;
}

int _runeWidth(int rune) => rune > 0xFFFF ? 2 : 1;

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
  final schemeEnd = _schemeEndOf(beforeFragment);
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

/// Returns the index past the `:` of a scheme at the start of [text], or -1
/// when [text] opens with none: an ASCII letter, then letters, digits, `+`,
/// `-`, `.`, then `:`.
int _schemeEndOf(String text) {
  if (text.isEmpty || !_isAsciiLetter(text.codeUnitAt(0))) return -1;
  var i = 1;
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
}

final class ScenarioLabel extends LinkLabel {
  const new(this.ref);

  final ScenarioRef ref;

  @override
  String get written => ref.label;
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
