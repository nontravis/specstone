import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/doc_model/models/section_item.dart';
import 'package:specstone_core/src/doc_model/reference_grammar.dart';
import 'package:specstone_core/src/document_writing/author_decisions.dart';
import 'package:specstone_core/src/document_writing/draft_sections.dart';
import 'package:specstone_core/src/document_writing/report_file.dart';
import 'package:specstone_core/src/document_writing/report_grammar.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart'
    show docStructureOf;
import 'package:specstone_core/src/index_query/item_facts.dart'
    show sectionItemsAt;
import 'package:specstone_core/src/index_query/models/doc_content.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';

export 'package:specstone_core/src/document_writing/report_file.dart'
    show ReportFile;
export 'package:specstone_core/src/document_writing/report_grammar.dart'
    show leadNameOf, leadNamesOf;

const _styleToken = '[style]';
const _noAuditReason = 'no audit report names it';

final _leadingBlanks = RegExp(r'^[ \t]*');

/// One fix line of an audit item: the whole new body of one section of a doc.
final class FixLine {
  const new({
    required this.docName,
    required this.sectionKey,
    required this.body,
  });

  /// The `<type>:<name>` or DocPath the line names.
  final String docName;

  /// The key of the section the body replaces.
  final String sectionKey;

  /// The section's new text without its `## ` line, the opening fence line's
  /// indent dropped from each line.
  final String body;
}

/// The audit and author report files of one call, read from disk.
final class ReportFiles {
  new _(this.audits, this.authors, this.unreadableReason);

  /// Reads each report, relative paths from [workingDirectory].
  ///
  /// Stops at the first file that is missing, unreadable, or not UTF-8; it
  /// sets [unreadableReason], and the lists hold the files read before it.
  static ReportFiles read({
    required List<String> auditPaths,
    required List<String> authorPaths,
    required Directory workingDirectory,
  }) {
    final audits = <ReportFile>[];
    final authors = <ReportFile>[];
    final unreadable =
        _readAll(auditPaths, audits, workingDirectory) ??
        _readAll(authorPaths, authors, workingDirectory);
    return ReportFiles._(audits, authors, unreadable);
  }

  /// The reason every draft is asked, or null when every file was read.
  final String? unreadableReason;

  final List<ReportFile> audits;
  final List<ReportFile> authors;
}

String? _readAll(
  List<String> paths,
  List<ReportFile> into,
  Directory workingDirectory,
) {
  for (final path in paths) {
    final file = File(path).isAbsolute
        ? File(path)
        : File('${workingDirectory.path}${Platform.pathSeparator}$path');
    try {
      into.add(
        ReportFile(path: path, text: utf8.decode(file.readAsBytesSync())),
      );
    } on FileSystemException catch (error) {
      return _unreadableReason(path, error.osError?.message ?? error.message);
    } on FormatException catch (error) {
      return _unreadableReason(path, error.message);
    }
  }
  return null;
}

String _unreadableReason(String path, String osMessage) =>
    'report $path unreadable: $osMessage';

/// The audit reports of a call, read as parts in argument then file order.
final class AuditSequence {
  new _(this._parts) : queued = {for (final part in _parts) ...part.queued};

  factory parse(List<ReportFile> audits) {
    final parts = [for (final file in audits) ..._partsOf(file)];
    _clearAddressedItems(parts);
    return AuditSequence._(parts);
  }

  final List<_Part> _parts;

  /// Every `Queued:` name of every part.
  final Set<String> queued;

  /// The index of the last part whose `Audited:` line names any of [names].
  int? _auditPartOf(Set<String> names) {
    for (var i = _parts.length - 1; i >= 0; i--) {
      if (names.any(_parts[i].audited.containsKey)) return i;
    }
    return null;
  }

  /// Returns the `Audited:` hash of the last part that names any of [names],
  /// or null when no part does.
  String? auditedHashOf(Set<String> names) {
    final part = _auditPartOf(names);
    return part == null ? null : _hashIn(_parts[part].audited, names);
  }

  /// Returns the fix lines in force for a draft whose names are [addresses]:
  /// the last one per doc and section key in part [from] and later parts.
  ///
  /// The names in [addresses] count as one doc.
  List<FixLine> fixesInForceOf(Set<String> addresses, {required int from}) {
    final inForce = <String, FixLine>{};
    for (final part in _parts.skip(from)) {
      for (final item in part.items) {
        for (final fix in item.fixes) {
          final doc = addresses.contains(fix.docName) ? '' : fix.docName;
          inForce['$doc\u0000${fix.sectionKey}'] = fix;
        }
      }
    }
    return inForce.values.toList();
  }

  /// The hash of the last `Styled:` line for any of [names] from part [from]
  /// on, else the hash of its `Audited:` line in part [from].
  String _judgedHash(Set<String> names, {required int from}) {
    for (var i = _parts.length - 1; i >= from; i--) {
      final styled = _hashIn(_parts[i].styled, names);
      if (styled != null) return styled;
    }
    return _hashIn(_parts[from].audited, names)!;
  }

  /// Returns the reason for the first counted item from part [from] on that
  /// [name] matches, else null.
  ///
  /// A `Findings:` item with fix lines that all satisfy [isApplied] is not
  /// counted. A `Verdicts:` item matches on [name] anywhere; any other item
  /// matches only when one of its lead names is in [draftNames], or, with no
  /// lead name, when [leadless] finds a mention (D4). A lead name in
  /// [handedOn] clears an item only for itself.
  String? _namedIn(
    RegExp name,
    RegExp leadless,
    Set<String> names, {
    required Set<String> draftNames,
    required int from,
    required Set<String> handedOn,
    required bool Function(FixLine fix) isApplied,
  }) {
    for (final part in _parts.skip(from)) {
      final styleItemsSkipped = names.any(part.styled.containsKey);
      for (final item in part.items) {
        if (styleItemsSkipped && item.isStyle) continue;
        if (item.isAddressed || item.isCleared) continue;
        if (item.fixes.isNotEmpty && item.fixes.every(isApplied)) continue;
        if (item.names(name, leadless, draftNames, handedOn)) {
          return 'named in ${item.section.label} of ${part.fileName}';
        }
      }
    }
    return null;
  }
}

enum _Section {
  findings('Findings'),
  outsideTheDrafts('Outside the drafts'),
  outsideTheRound('Outside the round'),
  verdicts('Verdicts');

  new(this.label);

  final String label;
}

final class _Item {
  new(this.section, this.text, {this.isAddressed = false}) : firstLine = text;

  final _Section section;
  String text;

  /// The item's own first line, its leading `- ` dropped, continuation lines
  /// left out.
  final String firstLine;

  /// Whether an `ADDRESSED:` verdict of a later part clears this finding item.
  bool isCleared = false;

  /// The fix lines of a `Findings:` item, read from its raw continuation
  /// lines; empty for any other item.
  final fixes = <FixLine>[];

  /// Whether a `Verdicts:` item opens with `ADDRESSED:`; it names no finding.
  final bool isAddressed;

  bool get isStyle => text.contains(_styleToken);

  /// Whether the item names a draft of [draftNames]: a `Verdicts:` item by
  /// [name] anywhere in its text, any other by its lead names alone.
  ///
  /// An item with no lead name (D4) is read by [leadless] over its whole text
  /// instead, and no `Queued:` name clears it.
  ///
  /// A queued lead name in [handedOn] clears a `NOT ADDRESSED` verdict or an
  /// `Outside the drafts:` item for that name alone; a draft that is another
  /// of its lead names is still named.
  bool names(
    RegExp name,
    RegExp leadless,
    Set<String> draftNames,
    Set<String> handedOn,
  ) {
    final leads = leadNamesOf(firstLine);
    if (leads == null && section != _Section.verdicts) {
      return leadless.hasMatch(text);
    }
    final lead = leads ?? const <String>[];
    final isLed = lead.any(
      (n) => draftNames.contains(n) && !handedOn.contains(n),
    );
    return switch (section) {
      _Section.verdicts =>
        name.hasMatch(text) &&
            (isLed ||
                !text.startsWith(notAddressedLead) ||
                !lead.any(handedOn.contains)),
      _Section.outsideTheDrafts => isLed,
      _Section.findings ||
      _Section.outsideTheRound => lead.any(draftNames.contains),
    };
  }
}

final class _Part {
  new(this.fileName);

  final String fileName;
  final audited = <String, String>{};
  final styled = <String, String>{};
  final items = <_Item>[];
  final queued = <String>{};
}

/// Marks each finding item that an `ADDRESSED:` verdict of a later part names
/// by its first line, equal by the Equal text rule.
void _clearAddressedItems(List<_Part> parts) {
  for (final (at, part) in parts.indexed) {
    for (final verdict in part.items.where((item) => item.isAddressed)) {
      final cleared = verdict.firstLine.substring(addressedLead.length);
      for (final earlier in parts.take(at)) {
        for (final item in earlier.items) {
          if (!item.isAddressed && sameByEqualText(item.firstLine, cleared)) {
            item.isCleared = true;
          }
        }
      }
    }
  }
}

List<_Part> _partsOf(ReportFile file) {
  final segments = <List<String>>[[]];
  for (final line in reportLinesOf(file.text)) {
    if (isRoundHeading(line)) {
      segments.add([]);
    } else {
      segments.last.add(line);
    }
  }
  final hasRounds = segments.length > 1;
  return [
    for (final (index, lines) in segments.indexed)
      if (index > 0 || !hasRounds || lines.any(_isNonBlank))
        _readPart(file.name, lines),
  ];
}

/// Returns the hash of the last line in [hashes] that names any of [names],
/// else null.
String? _hashIn(Map<String, String> hashes, Set<String> names) {
  String? last;
  for (final MapEntry(:key, :value) in hashes.entries) {
    if (names.contains(key)) last = value;
  }
  return last;
}

bool _isNonBlank(String line) => trimmedReportLine(line).isNotEmpty;

bool _isContinuation(String raw) =>
    (raw.startsWith(' ') || raw.startsWith('\t')) && _isNonBlank(raw);

/// A closed fix block: the [fix] and the index of the line after its closing
/// fence.
final class _FixBlock {
  const new(this.fix, this.end);

  final FixLine fix;
  final int end;
}

/// Returns the fix block whose fix line is `lines[at]`, else null.
///
/// The opening fence is the raw line after it. The block closes at the first
/// line holding only that fence; one that leaves the item's indented lines
/// before it closes is no fix.
_FixBlock? _fixBlockAt(List<String> lines, int at) {
  final fix = readFixLine(trimmedReportLine(lines[at]));
  if (fix == null || at + 1 >= lines.length) return null;
  final opening = lines[at + 1];
  final fence = trimmedReportLine(opening);
  if (!_isContinuation(opening) || !isFenceLine(fence)) return null;
  final indent = _leadingBlanks.stringMatch(opening)!;
  for (var close = at + 2; close < lines.length; close++) {
    if (_isNonBlank(lines[close]) && !_isContinuation(lines[close])) {
      return null;
    }
    if (trimmedReportLine(lines[close]) != fence) continue;
    return _FixBlock(
      FixLine(
        docName: fix.docName,
        sectionKey: fix.sectionKey,
        body: [
          for (final line in lines.sublist(at + 2, close))
            _dedented(line, indent.length),
        ].join('\n'),
      ),
      close + 1,
    );
  }
  return null;
}

/// Returns [line] without up to [width] leading blanks; a blank line is empty.
String _dedented(String line, int width) {
  if (!_isNonBlank(line)) return '';
  final blanks = _leadingBlanks.stringMatch(line)!.length;
  return line.substring(min(blanks, width));
}

_Part _readPart(String fileName, List<String> lines) {
  final part = _Part(fileName);
  _Section? open;
  _Item? last;

  void addItem(String text) {
    last = _Item(
      open!,
      text,
      isAddressed: open == _Section.verdicts && text.startsWith(addressedLead),
    );
    part.items.add(last!);
  }

  var index = 0;
  while (index < lines.length) {
    final raw = lines[index++];
    if (open != null && _isContinuation(raw)) {
      final line = trimmedReportLine(raw);
      if (last case final item?) {
        item.text = '${item.text}\n$line';
        if (item.section == _Section.findings) {
          final block = _fixBlockAt(lines, index - 1);
          if (block != null) {
            item.fixes.add(block.fix);
            index = block.end;
          }
        }
      } else {
        addItem(itemTextOf(line));
      }
      continue;
    }
    final line = trimmedReportLine(raw);
    if (line.isEmpty) continue;

    switch (kindOf(line)) {
      case ReportLineKind.queued:
        if (leadNameOf(queuedTextOf(line)!) case final name?) {
          part.queued.add(name);
        }
        open = null;
        last = null;
      case ReportLineKind.audited || ReportLineKind.styled:
        final draft = readDraftLine(line)!;
        final into = draft.kind == ReportLineKind.audited
            ? part.audited
            : part.styled;
        final name = draft.name;
        into
          ..remove(name)
          ..[name] = draft.hash;
        open = null;
        last = null;
      case ReportLineKind.sectionOpen:
        final section = readSectionLine(line)!;
        open = _Section.values.firstWhere((s) => s.label == section.label);
        last = null;
        final first = section.firstItem;
        if (first != null && first.isNotEmpty && first != 'none') {
          addItem(first);
        }
      case ReportLineKind.verdicts:
        open = _Section.verdicts;
        last = null;
      case ReportLineKind.decision ||
          ReportLineKind.notLanded ||
          ReportLineKind.label ||
          ReportLineKind.heading ||
          ReportLineKind.fix:
        open = null;
        last = null;
      case ReportLineKind.addressed ||
          ReportLineKind.item ||
          ReportLineKind.observation ||
          ReportLineKind.header ||
          null:
        if (open != null) addItem(itemTextOf(line));
    }
  }
  return part;
}

/// Returns the key that names [finding] to a [CleanDraftJudge]: its kind, doc,
/// line, and section.
String findingKeyOf(Finding finding) =>
    '${finding.kind.wire}\u0000${finding.path}\u0000${finding.line}'
    '\u0000${finding.keys['section']}';

const Set<FindingKind> _sizeKinds = {
  FindingKind.linesOverLimit,
  FindingKind.charsOverLimit,
  FindingKind.itemCountOutOfRange,
};

/// The place string of a finding at the doc level.
const _docPlace = 'doc';

/// Joins a section key to the text of a `###` heading in a place string.
const _subsectionJoin = ' ### ';

/// A finding of the draft its approved copy gives too, at the same place.
final class CarriedFinding {
  const new({required this.kind, required this.place});

  /// The wire name of the finding's kind.
  final String kind;

  /// `doc`, `<section key>`, or `<section key> ### <heading text>`.
  final String place;

  /// Returns the `kind` and `place` keys of a `carried` JSON entry.
  Map<String, String> toJson() => {'kind': kind, 'place': place};
}

/// Reads the place of a finding in one doc: the doc, a section, or a `###`
/// subsection heading.
final class FindingPlaces {
  /// Reads the structure of [lf], the LF text of a doc of the given type.
  new(String lf, this._type) : _content = docStructureOf(lf, _type);

  final DocContent _content;
  final MergedDocType? _type;

  /// Returns the place string of [finding].
  ///
  /// A finding above the first section is at the doc. Else the place is the
  /// key of the section that holds its line, and for a finding at a `###`
  /// heading line, that heading's text too, so two subsections of one section
  /// never share a place.
  String of(Finding finding) {
    final headerLines = _content.lineFacts.sectionLines;
    final at = headerLines.lastIndexWhere((line) => line <= finding.line);
    if (at < 0) return _docPlace;
    final key = _content.sections[at].key;
    final heading = sectionItemsAt(_content, at, _type)
        .where(
          (item) =>
              item.kind == SectionItemKind.heading && item.line == finding.line,
        )
        .firstOrNull;
    return heading == null ? key : '$key$_subsectionJoin${heading.head.trim()}';
  }
}

/// Returns the [draftFindings] its approved copy carries, each one itself.
///
/// A carried finding is of any kind but `item_over_limit`, and not one the
/// Owner's approval clears unless [includeApprovalCleared]; the copy gives it
/// too at the same place and kind, by count. A size finding carries only when
/// its excess is no larger than the copy's.
Set<Finding> carriedFindingsOf({
  required List<Finding> draftFindings,
  required List<Finding> copyFindings,
  required String draftLf,
  required String copyLf,
  required MergedDocType? type,
  bool includeApprovalCleared = false,
}) {
  final candidates = _carryable(draftFindings, includeApprovalCleared);
  if (candidates.isEmpty) return const {};
  final draftPlaces = FindingPlaces(draftLf, type);
  final copyPlaces = FindingPlaces(copyLf, type);
  final held = <String, List<Finding>>{};
  for (final finding in _carryable(copyFindings, includeApprovalCleared)) {
    final slot = _slotOf(finding, copyPlaces);
    if (slot != null) held.putIfAbsent(slot, () => []).add(finding);
  }
  final grouped = <String, List<Finding>>{};
  for (final finding in candidates) {
    final slot = _slotOf(finding, draftPlaces);
    if (slot != null) grouped.putIfAbsent(slot, () => []).add(finding);
  }
  return {
    for (final MapEntry(:key, :value) in grouped.entries)
      ..._carriedOfSlot(value, held[key] ?? const []),
  };
}

List<Finding> _carryable(List<Finding> findings, bool includeApprovalCleared) =>
    [
      for (final finding in findings)
        if (finding.kind != FindingKind.itemOverLimit &&
            (includeApprovalCleared || !finding.isClearedByApproval))
          finding,
    ];

/// Returns the key that pairs findings of one kind at one place, null for a
/// size finding that holds no bound to compare.
///
/// A count under its floor and a count over its cap never pair.
String? _slotOf(Finding finding, FindingPlaces places) {
  final slot = '${finding.kind.wire}\u0000${places.of(finding)}';
  if (!_sizeKinds.contains(finding.kind)) return slot;
  final excess = _excessOf(finding);
  if (excess == null) return null;
  return '$slot\u0000${excess.isFloor}';
}

/// Returns the first as many of [found] as [held] gives, none when a size
/// finding of [found] lies farther past its bound than every one of [held].
Iterable<Finding> _carriedOfSlot(List<Finding> found, List<Finding> held) {
  if (held.isEmpty) return const [];
  final ordered = [...found]..sort((a, b) => a.line.compareTo(b.line));
  if (_sizeKinds.contains(ordered.first.kind)) {
    // Two copy findings at one place pair with the smaller excess, and two
    // draft findings with the larger, so a pass never rests on the looser
    // reading.
    final least = held.map((f) => _excessOf(f)!.size).reduce(min);
    final most = ordered.map((f) => _excessOf(f)!.size).reduce(max);
    if (most > least) return const [];
  }
  return ordered.take(held.length);
}

/// How far a size finding lies past its bound, and on which side.
final class _Excess {
  const new({required this.size, required this.isFloor});

  final int size;
  final bool isFloor;
}

_Excess? _excessOf(Finding finding) {
  final (limit, actual) = (finding.keys['limit'], finding.keys['actual']);
  if (limit is! int || actual is! int) return null;
  return _Excess(size: (actual - limit).abs(), isFloor: actual < limit);
}

/// What the judge needs to know of one draft.
final class JudgedDraft {
  const new({
    required this.name,
    required this.docPath,
    required this.currentHash,
    this.currentLf = '',
    this.type,
    this.auditedTextAt,
    this.sectionTextOf = _noSectionText,
  });

  /// The address `DocIndex.addressOf` gives: a DocPath when the typed name
  /// is shared.
  final String name;
  final String docPath;

  /// The draft's current whole-doc `base` hash.
  final String currentHash;

  /// The LF text of the draft now, read only with [auditedTextAt].
  final String currentLf;

  /// The doc type of the draft; null for an untyped doc.
  final MergedDocType? type;

  /// Returns the audited copy saved at `hash`, null when none is; a null
  /// function means no copy store, so the draft reads as wholly changed.
  final String? Function(String hash)? auditedTextAt;

  /// Returns the current body of section `sectionKey` of the doc named
  /// `docName`, null when the name resolves to no doc or the doc lacks the
  /// section.
  final String? Function(String docName, String sectionKey) sectionTextOf;
}

String? _noSectionText(String docName, String sectionKey) => null;

/// Who clears an ask of `approve --auto`.
enum AskWaitsFor {
  owner('owner'),
  audit('audit');

  new(this.wire);

  /// The JSON value of the `waitsFor` key.
  final String wire;
}

/// Why `approve --auto` asks a draft, and who clears it.
final class DraftAsk {
  const new(
    this.reason, {
    this.waitsFor = AskWaitsFor.owner,
    this.changedSections,
  });

  /// The text after `ask <name>: `.
  final String reason;
  final AskWaitsFor waitsFor;

  /// The keys of the sections whose text differs from the draft's audited
  /// copy, in doc order; set for an ask that waits for the audit, unless the
  /// draft changed outside its sections or has no audited copy.
  final List<String>? changedSections;

  /// Returns the `reason` and `waitsFor` keys of an `asked` JSON entry, and
  /// `changedSections` for an ask that waits for the audit.
  Map<String, Object?> toJson() => {
    'reason': reason,
    'waitsFor': waitsFor.wire,
    if (waitsFor == AskWaitsFor.audit && changedSections != null)
      'changedSections': changedSections,
  };
}

/// Judges each draft of an `approve --auto` call by the clean-draft tests.
final class CleanDraftJudge {
  new({
    required List<Finding> findings,
    required AuditSequence? audit,
    required bool noAudit,
    required List<ReportFile> authors,
    required String? unreadableReason,
    required Set<String> callNames,
    required Set<String> passedFindings,
    required SectionLookup sections,
    Set<Finding> carriedFindings = const {},
  }) : _findings = findings,
       _passedFindings = passedFindings,
       _carriedFindings = carriedFindings,
       _audit = audit,
       _noAudit = noAudit,
       _handedOn = audit?.queued.difference(callNames) ?? const {},
       _unreadableReason = unreadableReason,
       _authorDecisions = AuthorDecisions.read(authors, sections);

  /// Fails every draft when set: [ReportFiles.unreadableReason] of the call.
  final String? _unreadableReason;
  final List<Finding> _findings;
  final AuditSequence? _audit;
  final bool _noAudit;

  /// The `Queued:` names that are no draft of this call.
  final Set<String> _handedOn;
  final AuthorDecisions _authorDecisions;

  /// The [findingKeyOf] keys of the `item_over_limit` findings whose item the
  /// approved copy holds, which the judge does not count; a carried finding
  /// goes in [_carriedFindings] instead. The judge never reads a copy itself.
  final Set<String> _passedFindings;

  /// The findings of [_findings], by identity, that the approved copy gives
  /// too; a key cannot tell two findings on one line apart, so these count one
  /// by one.
  final Set<Finding> _carriedFindings;

  /// Returns the reason of the first failing test, or null for a clean draft.
  String? reasonFor(JudgedDraft draft) => askFor(draft)?.reason;

  /// Returns what the first failing test asks, or null for a clean draft.
  DraftAsk? askFor(JudgedDraft draft) =>
      _asked(_unreadableReason) ??
      _checkAsk(draft) ??
      (_noAudit ? null : _auditAsk(draft)) ??
      _asked(_authorReason());

  DraftAsk? _checkAsk(JudgedDraft draft) {
    for (final finding in _findings) {
      if (finding.path != draft.docPath) continue;
      if (_passedFindings.contains(findingKeyOf(finding))) continue;
      if (_carriedFindings.contains(finding)) continue;
      if (!finding.isClearedByApproval) {
        return DraftAsk('check finding ${finding.kind.wire}');
      }
    }
    return null;
  }

  DraftAsk? _auditAsk(JudgedDraft draft) {
    final audit = _audit;
    final addresses = {draft.name, draft.docPath};
    final from = audit?._auditPartOf(addresses);
    if (audit == null || from == null) return const DraftAsk(_noAuditReason);
    final inForce = audit.fixesInForceOf(addresses, from: from);
    final judged = audit._judgedHash(addresses, from: from);
    if (judged != draft.currentHash) {
      final delta = draftDeltaOf(
        draft.currentLf,
        draft.auditedTextAt?.call(judged),
        draft.type,
      );
      if (!_isFixed(draft, addresses, inForce, delta)) {
        return DraftAsk(
          'audited at $judged, now ${draft.currentHash}',
          waitsFor: AskWaitsFor.audit,
          changedSections: delta.changesOutsideSections
              ? null
              : delta.changedSections,
        );
      }
    }
    return _asked(
      audit._namedIn(
        _nameIn(draft),
        _leadlessNameIn(draft),
        addresses,
        draftNames: {draft.name, draft.docPath},
        from: from,
        handedOn: _handedOn,
        isApplied: (fix) => _isInForce(draft, addresses, inForce, fix),
      ),
    );
  }

  /// Whether every part that differs from the audited copy is a section
  /// whose current text equals a fix block of the audit part.
  bool _isFixed(
    JudgedDraft draft,
    Set<String> addresses,
    List<FixLine> fixes,
    DraftDelta delta,
  ) =>
      !delta.changesOutsideSections &&
      delta.changedSections.every(
        (key) => fixes.any(
          (fix) =>
              addresses.contains(fix.docName) &&
              fix.sectionKey == key &&
              _isApplied(draft, fix),
        ),
      );

  /// Whether the section [fix] names holds the body in force for its doc and
  /// key; the names in [addresses] count as one doc.
  bool _isInForce(
    JudgedDraft draft,
    Set<String> addresses,
    List<FixLine> inForce,
    FixLine fix,
  ) {
    final isOwn = addresses.contains(fix.docName);
    return inForce.any(
      (line) =>
          line.sectionKey == fix.sectionKey &&
          (isOwn
              ? addresses.contains(line.docName)
              : line.docName == fix.docName) &&
          _isApplied(draft, line),
    );
  }

  /// Whether the current text of the section [fix] names equals its body.
  bool _isApplied(JudgedDraft draft, FixLine fix) {
    final text = draft.sectionTextOf(fix.docName, fix.sectionKey);
    return text != null && sameByEqualText(fix.body, text);
  }

  String? _authorReason() => _authorDecisions.reason;
}

DraftAsk? _asked(String? reason) => reason == null ? null : DraftAsk(reason);

/// One bounded search for the draft's `name` or its `docPath`.
RegExp _nameIn(JudgedDraft draft) =>
    mentionSearchOf({draft.name, draft.docPath});

/// [_nameIn] with the wider bounds an item led by no doc name is read by (D4).
RegExp _leadlessNameIn(JudgedDraft draft) =>
    mentionSearchOf({draft.name, draft.docPath}, isLeadless: true);
