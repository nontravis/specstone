import 'package:specstone_core/src/doc_model/reference_grammar.dart';

/// What a report line is, read by its form alone.
enum ReportLineKind {
  audited,
  styled,
  sectionOpen,
  verdicts,
  addressed,
  item,
  queued,
  decision,
  notLanded,
  label,
  heading,

  /// A `Fix:` line under a finding item, followed by its fenced body.
  fix,

  /// An item under `Notes:`, which no reader takes; by its form alone it
  /// reads as [item].
  observation,

  /// The line that opens an author report.
  header,
}

/// How a report line writes a doc's name.
enum NameForm { typedName, docPath }

/// One line a report template writes.
final class ReportLine {
  const new({
    required this.kind,
    required this.label,
    required this.placeholders,
  });

  final ReportLineKind kind;

  /// The line as the template writes it, each placeholder as a `<token>`.
  final String label;

  /// The tokens [label] holds, in order.
  final List<String> placeholders;
}

/// The lines of one report shape a template writes as a fenced block.
final class ReportBlock {
  const new({
    required this.id,
    required this.templatePath,
    required this.lines,
  });

  final String id;

  /// The template holding the block, `/`-separated under `assets/agent/`.
  final String templatePath;

  final List<ReportLine> lines;

  /// The line that opens the block's fence body, which finds the fence in
  /// [templatePath].
  String get firstLine => lines.first.label;
}

const _brainstormingReferences = 'specstone-brainstorming-sdd/references';

const _docToken = '<doc>';
const _docsToken = '<docs>';
const _leadDocsToken = '<docs whose fix it is>';
const _nameToken = '<type>:<name>';
const _keyedToken = '<type>:<name>#<key>';
const _sectionToken = '<type>:<name>#<section>';
const _hashToken = '<hash>';
const _decisionToken = 'D<n>';
const _roundToken = '<n>';
const _whyToken = '<why>';
const _pointToken = '<point>';
const _gapToken = '<gap>';
const _itemToken = '<item>';
const _labelToken = '<Label>';
const _observationToken = '<observation>';
const _whyNoDocToken = '<why no doc took it>';
const _outsideGapToken = '<gap whose fix lies in no draft of the round>';
const _openPointsToken =
    "<each point only the Owner's answer settles that a draft must state>";
const _findingsToken =
    '<each finding left after step 5, each reason the change note lacks, '
    'or none>';

const _findings = ReportLine(
  kind: ReportLineKind.sectionOpen,
  label: 'Findings:',
  placeholders: [],
);
const _notes = ReportLine(
  kind: ReportLineKind.label,
  label: 'Notes:',
  placeholders: [],
);
const _observation = ReportLine(
  kind: ReportLineKind.observation,
  label: '- $_observationToken',
  placeholders: [_observationToken],
);
const _fix = ReportLine(
  kind: ReportLineKind.fix,
  label: '  Fix: $_keyedToken',
  placeholders: [_keyedToken],
);
const _audited = ReportLine(
  kind: ReportLineKind.audited,
  label: 'Audited: $_docToken@$_hashToken',
  placeholders: [_docToken, _hashToken],
);
const _verdicts = ReportLine(
  kind: ReportLineKind.verdicts,
  label: 'Verdicts:',
  placeholders: [],
);
const _outsideTheRound = ReportLine(
  kind: ReportLineKind.sectionOpen,
  label: 'Outside the round:',
  placeholders: [],
);
const _outsideTheDrafts = ReportLine(
  kind: ReportLineKind.sectionOpen,
  label: 'Outside the drafts:',
  placeholders: [],
);
const _guess = ReportLine(
  kind: ReportLineKind.item,
  label: '- Guess: $_docsToken: $_pointToken',
  placeholders: [_docsToken, _pointToken],
);
const _contradiction = ReportLine(
  kind: ReportLineKind.item,
  label: '- Contradiction: $_docsToken: $_pointToken',
  placeholders: [_docsToken, _pointToken],
);
const _staleReader = ReportLine(
  kind: ReportLineKind.item,
  label: '- Stale reader: $_docsToken: $_pointToken',
  placeholders: [_docsToken, _pointToken],
);
const _notCarried = ReportLine(
  kind: ReportLineKind.item,
  label: '- Not carried: $_docsToken: $_pointToken',
  placeholders: [_docsToken, _pointToken],
);
const _misplaced = ReportLine(
  kind: ReportLineKind.item,
  label: '- Misplaced: $_docsToken: $_pointToken',
  placeholders: [_docsToken, _pointToken],
);
const _labeledItem = ReportLine(
  kind: ReportLineKind.item,
  label: '- $_labelToken: $_docsToken: $_pointToken',
  placeholders: [_labelToken, _docsToken, _pointToken],
);
const _decision = ReportLine(
  kind: ReportLineKind.decision,
  label: 'Decision: $_decisionToken -> $_keyedToken, …',
  placeholders: [_decisionToken, _keyedToken],
);
const _notLanded = ReportLine(
  kind: ReportLineKind.notLanded,
  label: 'Not landed: $_decisionToken: $_whyNoDocToken',
  placeholders: [_decisionToken, _whyNoDocToken],
);

/// Every report shape a template writes as a fenced block, each line in the
/// template's order.
const reportBlocks = <ReportBlock>[
  ReportBlock(
    id: 'author',
    templatePath: '$_brainstormingReferences/author.md',
    lines: [
      ReportLine(
        kind: ReportLineKind.header,
        label:
            "Drafts for the Owner's specstone approve $_nameToken: "
            '$_nameToken, ...',
        placeholders: [_nameToken, _nameToken],
      ),
      _decision,
      _notLanded,
      ReportLine(
        kind: ReportLineKind.label,
        label: 'Readers: $_keyedToken changed|linked|unaffected: $_whyToken',
        placeholders: [_keyedToken, _whyToken],
      ),
      ReportLine(
        kind: ReportLineKind.label,
        label: 'Elsewhere: $_keyedToken: $_whyToken',
        placeholders: [_keyedToken, _whyToken],
      ),
      ReportLine(
        kind: ReportLineKind.label,
        label: 'Move: <plan file path>',
        placeholders: ['<plan file path>'],
      ),
      ReportLine(
        kind: ReportLineKind.label,
        label: 'Rename: specstone rename $_docToken --to <slug>',
        placeholders: [_docToken, '<slug>'],
      ),
      ReportLine(
        kind: ReportLineKind.label,
        label: 'Delete: $_nameToken',
        placeholders: [_nameToken],
      ),
      ReportLine(
        kind: ReportLineKind.label,
        label: 'Open questions: $_openPointsToken',
        placeholders: [_openPointsToken],
      ),
      ReportLine(
        kind: ReportLineKind.label,
        label: 'Check: <path>',
        placeholders: ['<path>'],
      ),
      ReportLine(
        kind: ReportLineKind.label,
        label:
            'Counts: <count> drafts; $_nameToken: <d> dropped, '
            '$_roundToken new; ...',
        placeholders: ['<count>', _nameToken, '<d>', _roundToken],
      ),
      ReportLine(
        kind: ReportLineKind.label,
        label: 'Other drafts: $_nameToken, ..., or none',
        placeholders: [_nameToken],
      ),
      ReportLine(
        kind: ReportLineKind.sectionOpen,
        label: 'Findings: $_findingsToken',
        placeholders: [_findingsToken],
      ),
    ],
  ),
  ReportBlock(
    id: 'builderCheck',
    templatePath: '$_brainstormingReferences/audit.md',
    lines: [
      _findings,
      _guess,
      _fix,
      _contradiction,
      _staleReader,
      _notCarried,
      _misplaced,
      _notes,
      _observation,
      _audited,
    ],
  ),
  ReportBlock(
    id: 'reReview',
    templatePath: '$_brainstormingReferences/re-review.md',
    lines: [
      _findings,
      _labeledItem,
      _fix,
      _verdicts,
      ReportLine(
        kind: ReportLineKind.addressed,
        label: '- ADDRESSED: $_itemToken',
        placeholders: [_itemToken],
      ),
      ReportLine(
        kind: ReportLineKind.item,
        label: '- NOT ADDRESSED: $_itemToken',
        placeholders: [_itemToken],
      ),
      _outsideTheRound,
      ReportLine(
        kind: ReportLineKind.item,
        label: '- $_leadDocsToken: <gap>',
        placeholders: [_leadDocsToken, '<gap>'],
      ),
      _notes,
      _observation,
      _audited,
    ],
  ),
  ReportBlock(
    id: 'decidedAudit',
    templatePath: '$_brainstormingReferences/build-first-audit.md',
    lines: [
      _findings,
      _contradiction,
      _fix,
      _staleReader,
      _notCarried,
      _notes,
      _observation,
      _audited,
    ],
  ),
  ReportBlock(
    id: 'trimAudit',
    templatePath: '$_brainstormingReferences/trim-audit.md',
    lines: [
      _findings,
      ReportLine(
        kind: ReportLineKind.item,
        label: '- $_sectionToken: $_gapToken',
        placeholders: [_sectionToken, _gapToken],
      ),
      _outsideTheDrafts,
      ReportLine(
        kind: ReportLineKind.item,
        label: '- $_leadDocsToken: $_outsideGapToken',
        placeholders: [_leadDocsToken, _outsideGapToken],
      ),
      _notes,
      _observation,
      _audited,
    ],
  ),
  ReportBlock(
    id: 'syncDecided',
    templatePath: 'specstone-sync-sdd/references/decided.md',
    lines: [
      _decision,
      ReportLine(
        kind: ReportLineKind.notLanded,
        label: 'Not landed: $_decisionToken: <missing fact>',
        placeholders: [_decisionToken, '<missing fact>'],
      ),
    ],
  ),
];

/// The lines a reader takes that no template fence holds.
const readerOnlyLines = <ReportLine>[
  ReportLine(
    kind: ReportLineKind.queued,
    label: 'Queued: <name>',
    placeholders: ['<name>'],
  ),
  ReportLine(
    kind: ReportLineKind.styled,
    label: 'Styled: $_docToken@$_hashToken',
    placeholders: [_docToken, _hashToken],
  ),
  ReportLine(
    kind: ReportLineKind.heading,
    label: '## Round $_roundToken',
    placeholders: [_roundToken],
  ),
];

const _typedSample = 'fr:a';
const _pathSample = 'a/b.md';
const _hashSample = 'aaaaaaaaaaaa';
const _keySample = 'statement';

/// Returns a name written in [form].
String sampleNameOf(NameForm form) => switch (form) {
  NameForm.typedName => _typedSample,
  NameForm.docPath => _pathSample,
};

bool _isNameToken(String token) => switch (token) {
  _docToken ||
  _docsToken ||
  _nameToken ||
  _keyedToken ||
  _sectionToken ||
  _itemToken ||
  _leadDocsToken ||
  '<name>' => true,
  _ => false,
};

/// Returns the name forms [line] allows a doc's name in.
Set<NameForm> formsOf(ReportLine line) {
  final holdsName = line.placeholders.any(_isNameToken);
  if (!holdsName) return const {NameForm.typedName};
  return NameForm.values.toSet();
}

String _sampleOf(String token, NameForm form) {
  final name = sampleNameOf(form);
  return switch (token) {
    _keyedToken || _sectionToken => '$name#$_keySample',
    _docToken || _docsToken || _leadDocsToken || _nameToken || '<name>' => name,
    _itemToken => '$name: point',
    _hashToken => _hashSample,
    _decisionToken => 'D1',
    _roundToken => '2',
    _labelToken => 'Guess',
    _ => 'x',
  };
}

/// Returns [line] with each placeholder filled by a sample of [form].
String filledLine(ReportLine line, NameForm form) {
  var filled = line.label;
  var from = 0;
  for (final token in line.placeholders) {
    final at = filled.indexOf(token, from);
    if (at < 0) continue;
    final sample = _sampleOf(token, form);
    filled = filled.replaceRange(at, at + token.length, sample);
    from = at + sample.length;
  }
  return filled;
}

// MARK: - Line kinds

const decisionLead = 'Decision:';
const notLandedLead = 'Not landed:';
const notLandedMark = 'NOT LANDED';
const addressedLead = 'ADDRESSED:';
const notAddressedLead = 'NOT ADDRESSED:';
const _headerLead = "Drafts for the Owner's specstone approve ";

/// Round heading, a part break of an audit file.
final _roundHeading = RegExp(r'^## Round [0-9]+[ \t]*$');

/// `Audited:` and `Styled:` lines, each naming one draft at one hash; the
/// grammar reads the name, which is typed or a DocPath.
final _draftLine = RegExp(r'^(Audited|Styled): ([^\s@]+)@([0-9a-f]{12})$');

/// A `Findings:`, `Outside the drafts:`, or `Outside the round:` line, with an
/// optional first item.
final _sectionLine = RegExp(
  r'^(Findings|Outside the drafts|Outside the round):(?:[ \t]+(.*))?$',
);

/// A bare `Verdicts:` line; one with text after the colon is a label line.
final _verdictsLine = RegExp(r'^Verdicts:$');

/// Any label line: a capital, then letters, spaces, or `'`, then a colon.
final _labelLine = RegExp(r"^[A-Z][A-Za-z ']*:(?: |$)");

/// A Markdown ATX heading: 1 to 6 `#`, then a blank or the line end.
final _atxHeading = RegExp(r'^#{1,6}(?:[ \t]|$)');

/// A `Queued:` line; the text after it is read by [leadNameOf].
final _queuedLine = RegExp(r'^Queued: (.+)$');

final _dashItem = RegExp(r'^-[ \t]+(.+)$');

/// Returns the kind of [line], a line with its edge blanks trimmed, or null
/// when its form is none of the kinds: the text of an item that no `- `
/// opens.
ReportLineKind? kindOf(String line) {
  if (_queuedLine.hasMatch(line)) return ReportLineKind.queued;
  if (readDraftLine(line) case final draft?) return draft.kind;
  if (_sectionLine.hasMatch(line)) return ReportLineKind.sectionOpen;
  if (_verdictsLine.hasMatch(line)) return ReportLineKind.verdicts;
  if (readFixLine(line) != null) return ReportLineKind.fix;
  if (line.startsWith(_headerLead)) return ReportLineKind.header;
  if (line.startsWith(decisionLead)) return ReportLineKind.decision;
  if (line.startsWith(notLandedLead)) return ReportLineKind.notLanded;
  if (_labelLine.hasMatch(line)) return ReportLineKind.label;
  if (_atxHeading.hasMatch(line)) return ReportLineKind.heading;
  final item = _dashItem.firstMatch(line)?[1];
  if (item == null) return null;
  return item.startsWith(addressedLead)
      ? ReportLineKind.addressed
      : ReportLineKind.item;
}

/// Reads [line], trimmed, as `Fix: <doc name>#<section key>`, else null.
FixReference? readFixLine(String line) => readFixReference(line);

/// A fence line: three or more backticks and nothing else.
final _fenceLine = RegExp(r'^`{3,}$');

/// Whether [line], trimmed, is a fence line.
bool isFenceLine(String line) => _fenceLine.hasMatch(line);

/// Whether [line] is the `## Round <n>` heading that starts a part.
bool isRoundHeading(String line) => _roundHeading.hasMatch(line);

/// Returns the text of an item line [line]: its text after `- `, else all of
/// it.
String itemTextOf(String line) => _dashItem.firstMatch(line)?[1] ?? line;

/// An `Audited:` or `Styled:` line.
final class DraftLine {
  const new({required this.kind, required this.name, required this.hash});

  /// [ReportLineKind.audited] or [ReportLineKind.styled].
  final ReportLineKind kind;
  final String name;
  final String hash;
}

/// Reads [line] as an `Audited:` or `Styled:` line that names a typed draft
/// or a DocPath, else null.
DraftLine? readDraftLine(String line) {
  final match = _draftLine.firstMatch(line);
  if (match == null) return null;
  final name = match[2]!;
  if (!name.endsWith('.md')) {
    final typeId = readDocAddress(name).typeId;
    if (typeId == null || name.length <= typeId.length + 1) return null;
  }
  return DraftLine(
    kind: match[1] == 'Audited'
        ? ReportLineKind.audited
        : ReportLineKind.styled,
    name: name,
    hash: match[3]!,
  );
}

/// A `Findings:`, `Outside the drafts:`, or `Outside the round:` line.
final class SectionLine {
  const new({required this.label, required this.firstItem});

  /// The words before the colon.
  final String label;

  /// The text after the colon, null when none.
  final String? firstItem;
}

/// Reads [line] as a section line, else null.
SectionLine? readSectionLine(String line) {
  final match = _sectionLine.firstMatch(line);
  return match == null
      ? null
      : SectionLine(label: match[1]!, firstItem: match[2]);
}

/// Returns the text after `Queued: ` in [line], else null.
String? queuedTextOf(String line) => _queuedLine.firstMatch(line)?[1];

// MARK: - Decision lines

/// The word `none` at the start of a line, bounded by no letter, digit, or `_`.
final _noneWord = RegExp('^none(?![A-Za-z0-9_])');

/// A decision key right after a label, ended by a space, `:`, `(`, or the
/// line end, so `D1` and `D10` stay apart.
final _decisionKey = RegExp(r'^D([0-9]+)(?=[ :(]|$)');

/// What a `Decision:` or `Not landed:` line says of a decision.
final class DecisionRead {
  const new({
    required this.key,
    required this.isOpen,
    required this.sections,
    required this.isUnkeyedAsk,
  });

  /// The number after `D`, null when the line names none.
  final int? key;

  /// Whether the line leaves the decision open: a `Not landed:` line, or a
  /// `Decision:` line that names no section.
  final bool isOpen;

  /// The sections the line names; empty when the line leaves the decision
  /// open.
  final List<NamedSection> sections;

  /// Whether a `Not landed:` line that names no decision and opens with no
  /// `none` asks.
  final bool isUnkeyedAsk;
}

/// Reads [line] as a `Decision:` or `Not landed:` line, else null.
DecisionRead? readDecisionLine(String line) {
  final kind = kindOf(line);
  final isNotLanded = kind == ReportLineKind.notLanded;
  if (!isNotLanded && kind != ReportLineKind.decision) return null;
  final lead = isNotLanded ? notLandedLead : decisionLead;
  final rest = line.substring(lead.length).trimLeft();
  final digits = _decisionKey.firstMatch(rest);
  final number = digits == null ? null : int.tryParse(digits[1]!);
  final isOpen =
      isNotLanded ||
      rest.toUpperCase().contains(notLandedMark) ||
      holdsUnreadSectionToken(rest);
  final sections = isOpen
      ? const <NamedSection>[]
      : sectionsNamedIn(rest).toList();
  return DecisionRead(
    key: number,
    isOpen: sections.isEmpty,
    sections: sections,
    isUnkeyedAsk:
        number == null &&
        (digits != null || isNotLanded && !_noneWord.hasMatch(rest)),
  );
}

// MARK: - Lead names

/// The labels of a gap item, one of which can lead an item.
const _gapLabels = [
  'Guess',
  'Contradiction',
  'Stale reader',
  'Not carried',
  'Misplaced',
];

/// The leading labels of an item, dropped before its lead names are read.
final _itemLabels = RegExp('^(?:NOT ADDRESSED: )?(?:check: )?`?');

/// Returns [itemText] without its leading `NOT ADDRESSED: `, `check: `, one
/// gap label, and a backtick.
String _withoutLabels(String itemText) {
  final bare = itemText.replaceFirst(_itemLabels, '');
  for (final label in _gapLabels) {
    final lead = '$label: ';
    if (!bare.startsWith(lead)) continue;
    final rest = bare.substring(lead.length);
    return rest.startsWith('`') ? rest.substring(1) : rest;
  }
  return bare;
}

/// The punctuation that can close a lead name at the end of an item.
final _trailingMarks = RegExp(r'[.;)]+$');

/// The characters that end an item's lead name, `:` and `.` aside.
const _leadStops = ' \t\n`@#,;)]';

/// The characters that end the body of a typed lead name.
const _bodyStops = ':.';

/// Returns the lead names of an item's [itemText], each a `<type>:<name>` or a
/// DocPath without its `#<key>`, or null when its lead reads no name.
///
/// Drops a leading `NOT ADDRESSED: `, `check: `, and a gap
/// label, then reads the lead up to the first ` — ` or `: `. A lead holding a
/// `,` is a list: each of its `, `-joined pieces must be a name, else the item
/// has none. Any other lead yields its own name, else [leadNameOf].
List<String>? leadNamesOf(String itemText) {
  final lead = leadTextOf(_withoutLabels(itemText));
  if (lead.contains(',')) {
    final names = [for (final piece in lead.split(', ')) _leadNameIn(piece)];
    return names.contains(null) ? null : [...names.nonNulls];
  }
  final name = _leadNameIn(lead) ?? _realNameOf(leadNameOf(itemText));
  return name == null ? null : [name];
}

/// Returns [name] when it is a `<type>:<name>` with a clean body or a DocPath,
/// else null: [leadNameOf] also takes a name with a mark before it, such as
/// `(prds/a.md`.
String? _realNameOf(String? name) {
  if (name == null) return null;
  final address = readDocAddress(name);
  final isReal = address.typeId == null
      ? isDocPathText(address.body)
      : isCleanNameBody(address.body);
  return isReal ? name : null;
}

/// Returns [piece] as a `<type>:<name>` or a DocPath, backticks, `#<key>`, and
/// a trailing `.`, `;`, or `)` dropped, else null.
String? _leadNameIn(String piece) {
  final written = piece.replaceAll('`', '').replaceFirst(_trailingMarks, '');
  final address = readDocAddress(written);
  if (address.typeId case final typeId?) {
    return isCleanNameBody(address.body) ? '$typeId:${address.body}' : null;
  }
  return isDocPathText(address.body) ? address.body : null;
}

/// Returns the name that opens an item's [itemText], a `<type>:<name>` or a
/// DocPath, else null.
///
/// Drops a leading `NOT ADDRESSED: `, then `check: `, then a backtick.
String? leadNameOf(String itemText) {
  final bare = _withoutLabels(itemText);
  final token = _upTo(bare, _leadStops);
  final address = readDocAddress(token);
  if (address.typeId case final typeId?) {
    final name = _upTo(address.body, _bodyStops);
    return name.isEmpty ? null : '$typeId:$name';
  }
  return docPathPrefixOf(token);
}

/// Returns the characters of [text] before the first one in [stops].
String _upTo(String text, String stops) =>
    text.split('').takeWhile((char) => !stops.contains(char)).join();
