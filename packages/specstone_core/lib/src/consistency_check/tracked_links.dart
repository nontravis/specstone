import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/doc_lines.dart';
import 'package:specstone_core/src/consistency_check/edge_case_blocks.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/consistency_check/fingerprint.dart';
import 'package:specstone_core/src/consistency_check/models/fr_trace_row.dart';
import 'package:specstone_core/src/consistency_check/override_lines.dart';
import 'package:specstone_core/src/consistency_check/record_doc.dart';
import 'package:specstone_core/src/consistency_check/scenario_blocks.dart';
import 'package:specstone_core/src/doc_model/doc_splice.dart'
    show isFingerprint;
import 'package:specstone_core/src/doc_model/models/section_item.dart';
import 'package:specstone_core/src/doc_model/reference_grammar.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/item_facts.dart'
    show itemKeyOfHead;
import 'package:specstone_core/src/index_query/item_links.dart'
    show citedSectionsOf;
import 'package:specstone_core/src/index_query/models/matrix_line.dart';
import 'package:specstone_core/src/index_query/override_chain.dart';
import 'package:specstone_core/src/index_query/record_entries.dart'
    show recordItemsOf;
import 'package:specstone_core/src/journeys/journey_steps.dart';
import 'package:specstone_core/src/journeys/step_scenarios.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart'
    show verificationMatrixKey;

const _frType = 'fr';
const _nfType = 'nf';
const _apiType = 'api';
const _tracedFromKey = 'traced_from';
const _kindKey = 'kind';
const _overridesKey = 'overrides';
const _confirmedKey = 'confirmed';
const _overrideEntriesKey = 'overrides';
const _statementSection = 'statement';
const _statementBlock = 'Statement';
const _tighten = 'tighten';
const _relax = 'relax';

/// Whether a tracked link is current, changed, or without a matching entry.
enum LinkState { clean, suspect, unconfirmed }

/// What kind of upstream block a tracked entry records.
enum TrackedBlockKind { scenario, item, frStatement, nfrStatement, edgeCase }

/// The upstream block a tracked entry records a fingerprint of.
final class TrackedBlock {
  const new({
    required this.kind,
    required this.upstream,
    required this.key,
    this.section,
  });

  final TrackedBlockKind kind;

  /// The DocPath of the doc that holds the block.
  final String upstream;

  /// The block's key in that doc: a scenario key `S<N>`, an item ID, an
  /// edge case ID, an NFR id, or `Statement` for an FR's Statement.
  final String key;

  /// The key of the section an item sits in, as a cited section reads it;
  /// null for any other kind.
  final String? section;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  bool operator ==(Object other) =>
      other is TrackedBlock &&
      other.kind == kind &&
      other.upstream == upstream &&
      other.key == key &&
      other.section == section;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  int get hashCode => Object.hash(kind, upstream, key, section);
}

/// One recorded fingerprint of a downstream doc: a `confirmed` or `overrides`
/// entry, or a record's Verification matrix row.
final class TrackedEntry {
  const new({
    required this.docPath,
    required this.entryKey,
    required this.label,
    required this.block,
    this.literal,
    this.recorded,
  });

  /// The DocPath of the doc that holds the entry.
  final String docPath;

  /// `confirmed`, `overrides`, or `verification_matrix` for a row.
  final String entryKey;

  /// The link label the entry names.
  final String label;

  /// The block the entry records.
  final TrackedBlock block;

  /// A row's literal, or a skip row's reason; null for any other entry.
  final String? literal;

  /// The fingerprint the entry records; null for a row that records none.
  final String? recorded;
}

/// One link from a downstream doc to an upstream block.
final class TrackedLink {
  /// The link [label] traced at [traceLine].
  ///
  /// [upstream], [block], [source], [fingerprint], and [tracked] stay null
  /// when the upstream block is missing; the link then has no [LinkState].
  const new({
    required this.label,
    required this.traceLine,
    this.upstream,
    this.block,
    this.source,
    this.fingerprint,
    this.tracked,
    this.entryKey = _confirmedKey,
  });

  /// The LinkLabel: `S<N>`, an NFR id, `<story slug>/<fr slug>`,
  /// `<story Name>#S<N>`, or an override address
  /// `<doc type>:<name>#<ID>`.
  final String label;

  /// The frontmatter field that holds the link's entry: `confirmed`, or
  /// `overrides` for an override line's link.
  final String entryKey;

  /// The file line of the key or table row that traces the link.
  final int traceLine;

  /// The DocPath of the upstream doc.
  final String? upstream;

  /// The upstream block's name as a message prints it.
  final String? block;

  /// The upstream block as the doc holds it, before layout.
  final String? source;

  /// The Fingerprint of the upstream block now.
  final String? fingerprint;

  /// The upstream block's address, as [trackedBlockTextOf] reads it.
  final TrackedBlock? tracked;
}

/// Returns the text of [block] as [context] holds it, or null when its doc or
/// the block is missing.
///
/// The one reader of a tracked block's text, for the check and for the
/// re-stamp of a restructure write. An item is the first of its ID in the
/// first held section of its section key, its own text, nested items aside.
String? trackedBlockTextOf(CheckContext context, TrackedBlock block) {
  final doc = context.index.at(block.upstream);
  if (doc == null) return null;
  return switch (block.kind) {
    TrackedBlockKind.scenario => context.scenarioBlocksOf(doc)[block.key],
    TrackedBlockKind.edgeCase => edgeCaseBlocksOf(context, doc)[block.key],
    TrackedBlockKind.frStatement =>
      context.heldSection(doc, _statementSection)?.body ?? '',
    TrackedBlockKind.nfrStatement => context.nfrStatements()[block.key]?.text,
    TrackedBlockKind.item => _itemTextOf(context, doc, block),
  };
}

String? _itemTextOf(CheckContext context, IndexedDoc doc, TrackedBlock block) {
  final sections = citedSectionsOf(context.contentOf(doc), context.typeOf(doc));
  final at = sections.indexWhere((section) => section.key == block.section);
  if (at < 0) return null;
  final section = sections[at];
  for (final item in context.itemsIn(doc, at)) {
    final key = itemKeyOfHead(
      item.head,
      isHeading: item.kind == SectionItemKind.heading,
      prefixId: section.prefixId,
      isAcceptanceCriteria: section.isAcceptanceCriteria,
    );
    if (key == block.key) return item.text;
  }
  return null;
}

/// Returns the `confirmed` and `overrides` entries [doc] records for the
/// links it tracks, and its Verification matrix rows, each with its block.
///
/// A link with no upstream block, or with no entry, yields none; a row whose
/// edge case is missing yields none, as the check reads them.
List<TrackedEntry> trackedEntriesOf(CheckContext context, IndexedDoc doc) {
  final rows = [
    for (final link in _rowLinksOf(context, doc))
      TrackedEntry(
        docPath: doc.docPath,
        entryKey: verificationMatrixKey,
        label: link.row.label,
        block: link.block,
        literal: matrixRowLiteralOf(link.row),
        recorded: link.row.fingerprint,
      ),
  ];
  if (_entryKeysOf(context, doc).isEmpty) return rows;
  final lines = context.linesOf(doc);
  return [
    ...rows,
    for (final link in trackedLinksOf(context, doc))
      if (link.tracked case final block?)
        if (_entryOf(lines, link) case final entry?)
          TrackedEntry(
            docPath: doc.docPath,
            entryKey: link.entryKey,
            label: link.label,
            block: block,
            recorded: entry.fingerprint,
          ),
  ];
}

/// Returns [row]'s literal, or a skip row's reason.
String matrixRowLiteralOf(MatrixRow row) => switch (row) {
  TestRow(:final literal) => literal,
  SkipRow(:final reason) => reason,
};

/// Returns the links [doc] tracks, one per link identity, in trace order:
/// `S6` and `S06` are one link.
///
/// An `fr` tracks its `S<N>` and sibling `<story Name>#S<N>` trace
/// entries (a lettered number yields a link with no upstream), an `nf` of
/// kind `tighten` or `relax` its overridden NFR, an `api` doc each FR of its
/// trace table, and a `journey` the story scenario each step names.
///
/// A doc type that carries override lines adds one link per distinct override
/// address after its own links; an `api` doc holds both.
List<TrackedLink> trackedLinksOf(CheckContext context, IndexedDoc doc) {
  final links = [
    ...switch (doc.docTypeId) {
      _frType => _scenarioLinks(context, doc),
      _nfType => _overrideLinks(context, doc),
      _apiType => _frRowLinks(context, doc),
      journeyTypeId => _stepLinks(context, doc),
      _ => const <TrackedLink>[],
    },
    if (carriesOverrides(context.typeOf(doc)))
      ..._overrideLineLinks(context, doc),
  ];
  final seen = <String>{};
  return [
    for (final link in links)
      if (seen.add(linkIdentityOf(link.label))) link,
  ];
}

// The link of an override line that names an item; its item is the upstream
// block, by the ID the line links. A line that tracks no link yields none.
Iterable<TrackedLink> _overrideLineLinks(
  CheckContext context,
  IndexedDoc doc,
) sync* {
  for (final line in overrideLinesOf(context, doc)) {
    if (line case OverrideLine(
      :final address?,
      :final upstream?,
      :final itemId?,
      :final section?,
    )) {
      final tracked = TrackedBlock(
        kind: TrackedBlockKind.item,
        upstream: upstream,
        key: itemId,
        section: section,
      );
      final text = trackedBlockTextOf(context, tracked);
      yield text == null
          ? TrackedLink(
              label: address,
              traceLine: line.line,
              entryKey: _overrideEntriesKey,
            )
          : TrackedLink(
              label: address,
              traceLine: line.line,
              upstream: upstream,
              block: itemId,
              source: text,
              fingerprint: fingerprintOf(text),
              tracked: tracked,
              entryKey: _overrideEntriesKey,
            );
    }
  }
}

Iterable<TrackedLink> _scenarioLinks(
  CheckContext context,
  IndexedDoc fr,
) sync* {
  final story = context.index.parentOf(fr);
  final line = context.linesOf(fr).keyLine(_tracedFromKey);
  if (story == null || line == null) return;
  for (final entry in fr.valuesOf(_tracedFromKey)) {
    final ref = readScenarioRef(entry);
    if (ref == null) continue;
    final traced = tracedStoryOf(context.index, story, ref);
    if (traced == null) continue;
    final key = scenarioKeyOf(ref);
    final tracked = key == null
        ? null
        : TrackedBlock(
            kind: TrackedBlockKind.scenario,
            upstream: traced.docPath,
            key: key,
          );
    final text = tracked == null ? null : trackedBlockTextOf(context, tracked);
    yield text == null
        ? TrackedLink(label: ref.label, traceLine: line)
        : TrackedLink(
            label: ref.label,
            traceLine: line,
            upstream: traced.docPath,
            block: 'Scenario ${ref.scenario}',
            source: text,
            fingerprint: fingerprintOf(text),
            tracked: tracked,
          );
  }
}

Iterable<TrackedLink> _overrideLinks(
  CheckContext context,
  IndexedDoc nf,
) sync* {
  final kind = nf.valuesOf(_kindKey).firstOrNull;
  final id = nf.valuesOf(_overridesKey).firstOrNull;
  final line = context.linesOf(nf).keyLine(_overridesKey);
  if ((kind != _tighten && kind != _relax) || id == null || line == null) {
    return;
  }
  final path = context.nfrStatements()[id]?.path;
  final tracked = path == null
      ? null
      : TrackedBlock(
          kind: TrackedBlockKind.nfrStatement,
          upstream: path,
          key: id,
        );
  final text = tracked == null ? null : trackedBlockTextOf(context, tracked);
  yield path == null || text == null
      ? TrackedLink(label: id, traceLine: line)
      : TrackedLink(
          label: id,
          traceLine: line,
          upstream: path,
          block: '$id $_statementBlock',
          source: text,
          fingerprint: fingerprintOf(text),
          tracked: tracked,
        );
}

Iterable<TrackedLink> _frRowLinks(CheckContext context, IndexedDoc api) sync* {
  final feature = context.index.parentOf(api);
  if (feature == null) return;
  for (final FrTraceRow(:cell, :line) in context.frTraceRowsOf(api)) {
    final fr = context.frNamed('${feature.name}/$cell');
    yield fr == null
        ? TrackedLink(label: cell, traceLine: line)
        : _statementLink(context, cell, line, fr);
  }
}

TrackedLink _statementLink(
  CheckContext context,
  String label,
  int line,
  IndexedDoc fr,
) {
  final tracked = TrackedBlock(
    kind: TrackedBlockKind.frStatement,
    upstream: fr.docPath,
    key: _statementBlock,
  );
  final statement = trackedBlockTextOf(context, tracked) ?? '';
  return TrackedLink(
    label: label,
    traceLine: line,
    upstream: fr.docPath,
    block: _statementBlock,
    source: statement,
    fingerprint: fingerprintOf(statement),
    tracked: tracked,
  );
}

// A step whose `step:` reads as a target tracks that story scenario; a missing
// story or scenario leaves the link without an upstream.
Iterable<TrackedLink> _stepLinks(
  CheckContext context,
  IndexedDoc journey,
) sync* {
  final section = context.heldIndexOf(journey, stepsSectionId);
  if (section == null) return;
  final body = context.bodyLinesOf(journey, section);
  for (final step in stepsOfIndexed(context.index, journey).steps) {
    final target = step.target;
    final stepIndex = step.stepIndex;
    if (target == null || stepIndex == null) continue;
    final line = body[stepIndex].line;
    final story = storyNamed(context.index, target.identity);
    final tracked = story == null
        ? null
        : TrackedBlock(
            kind: TrackedBlockKind.scenario,
            upstream: story.docPath,
            key: target.scenarioLabel,
          );
    final text = tracked == null ? null : trackedBlockTextOf(context, tracked);
    yield tracked == null || text == null
        ? TrackedLink(label: target.label, traceLine: line)
        : TrackedLink(
            label: target.label,
            traceLine: line,
            upstream: tracked.upstream,
            block: 'Scenario ${target.scenario}',
            source: text,
            fingerprint: fingerprintOf(text),
            tracked: tracked,
          );
  }
}

typedef _Entry = ({String fingerprint, int line});

// Reads [value] of the field [entryKey] as `<LinkLabel> <12 lowercase hex
// characters>`, one space between; the label goes through the doc model
// reference grammar, where a lettered scenario number names no scenario. An
// override address is a label of `overrides` entries alone, and `overrides`
// takes no other label.
({String label, String fingerprint})? _readEntry(
  Object? value,
  String entryKey,
) {
  if (value is! String) return null;
  final space = value.indexOf(' ');
  if (space < 0) return null;
  final fingerprint = value.substring(space + 1);
  final label = readLinkLabel(value.substring(0, space));
  if (label == null || !isFingerprint(fingerprint)) return null;
  if (label is ScenarioLabel && label.ref.scenario == null) return null;
  if ((label is OverrideLabel) != (entryKey == _overrideEntriesKey)) {
    return null;
  }
  return (label: label.written, fingerprint: fingerprint);
}

// Whether [value] opens with an override address, whatever follows it.
bool _isOverrideEntry(Object? value) =>
    value is String && readLinkLabel(value.split(' ').first) is OverrideLabel;

// The first well-formed entry naming [link] is its entry.
_Entry? _entryOf(DocLines lines, TrackedLink link) {
  final identity = linkIdentityOf(link.label);
  for (final item in lines.entriesOf(link.entryKey)) {
    final entry = _readEntry(item.value, link.entryKey);
    if (entry != null && linkIdentityOf(entry.label) == identity) {
      return (fingerprint: entry.fingerprint, line: item.line);
    }
  }
  return null;
}

// The entry fields [doc] holds: `confirmed` for the link kinds that record
// there, `overrides` for a doc type that carries override lines.
List<String> _entryKeysOf(CheckContext context, IndexedDoc doc) {
  final type = context.typeOf(doc);
  return [
    if (context.typeHoldsField(type, _confirmedKey)) _confirmedKey,
    if (carriesOverrides(type)) _overrideEntriesKey,
  ];
}

// A draft's links are never clean or suspect: its entries wait for approval.
LinkState _stateOf(IndexedDoc doc, TrackedLink link, _Entry? entry) {
  if (doc.isDraft || entry == null) return LinkState.unconfirmed;
  return entry.fingerprint == link.fingerprint
      ? LinkState.clean
      : LinkState.suspect;
}

/// One matrix row of a record read against the edge case it names.
final class _RowLink {
  const new({
    required this.row,
    required this.fr,
    required this.source,
    required this.fingerprint,
  });

  final MatrixRow row;

  /// The requirement that holds the edge case.
  final IndexedDoc fr;

  /// The edge case's block as the requirement holds it, before layout.
  final String source;

  /// The Fingerprint of the edge case's block now.
  final String fingerprint;

  TrackedBlock get block => TrackedBlock(
    kind: TrackedBlockKind.edgeCase,
    upstream: fr.docPath,
    key: row.edgeCase,
  );

  bool get isSuspect {
    final recorded = row.fingerprint;
    return recorded != null && recorded != fingerprint;
  }

  // The Agent's stamp clears a row, but no Agent stamps a row against text the
  // Owner has not approved.
  WaitsFor get waitsFor => fr.isDraft ? WaitsFor.owner : WaitsFor.agent;
}

// The rows of [record] whose edge case exists: a row naming a story, a
// missing item, a missing edge case, or a skipped requirement takes no state.
// The edge case blocks are those [trackedBlockTextOf] reads, cached per FR.
Iterable<_RowLink> _rowLinksOf(CheckContext context, IndexedDoc record) sync* {
  final read = recordDocOf(context, record);
  if (read == null || record.matrixLines.isEmpty) return;
  final items = recordItemsOf(read.feature, context.index.childrenOf);
  final blocksOf = <String, Map<String, String>>{};
  for (final row in record.matrixLines.whereType<MatrixRow>()) {
    final fr = items[row.item];
    if (fr == null ||
        fr.docTypeId != _frType ||
        isSkippedIn(context, record, fr)) {
      continue;
    }
    final blocks = blocksOf.putIfAbsent(
      fr.docPath,
      () => edgeCaseBlocksOf(context, fr),
    );
    final source = blocks[row.edgeCase];
    if (source == null) continue;
    yield _RowLink(
      row: row,
      fr: fr,
      source: source,
      fingerprint: fingerprintOf(source),
    );
  }
}

/// Whether any link [doc] tracks is `suspect`.
///
/// A record holds a `suspect` link when a row's fingerprint differs from its
/// edge case's.
bool hasSuspectLink(CheckContext context, IndexedDoc doc) {
  if (_rowLinksOf(context, doc).any((link) => link.isSuspect)) return true;
  if (_entryKeysOf(context, doc).isEmpty) return false;
  final lines = context.linesOf(doc);
  return trackedLinksOf(context, doc).any(
    (link) =>
        link.fingerprint != null &&
        _stateOf(doc, link, _entryOf(lines, link)) == LinkState.suspect,
  );
}

/// Returns the `suspect` and `unconfirmed` findings of [doc].
///
/// A link whose upstream block is missing takes no state; the broken-pointer
/// check reports it.
/// Only a doc type that defines `confirmed` or carries override lines is
/// read, and a record's matrix rows, each against its edge case whatever the
/// record's draft flag.
Iterable<Finding> checkTrackedLinks(
  CheckContext context,
  IndexedDoc doc,
) sync* {
  yield* _checkRowLinks(context, doc);
  if (_entryKeysOf(context, doc).isEmpty) return;
  final lines = context.linesOf(doc);
  for (final link in trackedLinksOf(context, doc)) {
    final current = link.fingerprint;
    final upstream = link.upstream;
    final block = link.block;
    final source = link.source;
    if (current == null ||
        upstream == null ||
        block == null ||
        source == null) {
      continue;
    }
    final entry = _entryOf(lines, link);
    final field = link.entryKey == _overrideEntriesKey
        ? ' in `$_overrideEntriesKey`'
        : '';
    final read =
        'read $block of $upstream below, then record ${link.label}$field '
        'with the fingerprint after it';
    final text = _blockText(source);
    switch (_stateOf(doc, link, entry)) {
      case LinkState.clean:
        break;
      case LinkState.suspect:
        yield context.finding(
          doc,
          FindingKind.suspect,
          line: entry!.line,
          message:
              '${link.label} changed after it was confirmed, recorded '
              '${entry.fingerprint}; $read',
          keys: {
            'link': link.label,
            'recorded': entry.fingerprint,
            'upstream': upstream,
            'block': block,
            'text': text,
            'fingerprint': current,
          },
        );
      case LinkState.unconfirmed:
        final waitsFor = _waitsForOf(doc, current, entry);
        yield context.finding(
          doc,
          FindingKind.unconfirmed,
          line: entry?.line ?? link.traceLine,
          message: _unconfirmedMessage(
            link.label,
            current,
            entry,
            waitsFor,
            read,
          ),
          waitsFor: waitsFor,
          keys: {
            'link': link.label,
            'upstream': upstream,
            'block': block,
            if (entry != null) 'recorded': entry.fingerprint,
            if (waitsFor == WaitsFor.agent) 'text': text,
            'fingerprint': current,
          },
        );
    }
  }
}

Iterable<Finding> _checkRowLinks(
  CheckContext context,
  IndexedDoc record,
) sync* {
  for (final link in _rowLinksOf(context, record)) {
    final row = link.row;
    final recorded = row.fingerprint;
    final isOwner = link.waitsFor == WaitsFor.owner;
    if (recorded == null) {
      yield context.finding(
        record,
        FindingKind.unconfirmed,
        line: row.line,
        message: isOwner
            ? '${row.label} ${_rowWaitsMessage(link)}'
            : '${row.label} records no fingerprint; ${_rowReadMessage(link)}',
        waitsFor: link.waitsFor,
        keys: {
          'link': row.label,
          'upstream': link.fr.docPath,
          'block': row.edgeCase,
          if (!isOwner) 'text': _blockText(link.source),
          'fingerprint': link.fingerprint,
        },
      );
    } else if (link.isSuspect) {
      yield context.finding(
        record,
        FindingKind.suspect,
        line: row.line,
        message:
            '${row.label} changed after it was confirmed, recorded $recorded; '
            '${isOwner ? _rowOwnerSuspectTail(link) : _rowReadMessage(link)}',
        waitsFor: link.waitsFor,
        keys: {
          'link': row.label,
          'recorded': recorded,
          'upstream': link.fr.docPath,
          'block': row.edgeCase,
          'text': _blockText(link.source),
          'fingerprint': link.fingerprint,
        },
      );
    }
  }
}

String _rowReadMessage(_RowLink link) =>
    'read ${link.row.edgeCase} of ${link.fr.docPath} below, then record '
    '${link.row.label} with the fingerprint after it';

String _rowOwnerSuspectTail(_RowLink link) => 'it ${_rowWaitsMessage(link)}';

String _rowWaitsMessage(_RowLink link) =>
    "waits for the Owner's approve of ${link.fr.docPath}";

// The block as `format` lays it out, with the one line break that ends it
// dropped, so each of its lines prints once and a trailing space the layout
// keeps stays in the text the fingerprint hashes.
String _blockText(String source) {
  final text = upstreamText(source);
  return text.endsWith('\n') ? text.substring(0, text.length - 1) : text;
}

/// Returns the malformed, repeated, and stale entries of [doc]'s `confirmed`
/// and `overrides` fields.
///
/// Only a doc type that defines `confirmed` or carries override lines is
/// read, each entry field against its own links; a draft is read too.
Iterable<Finding> checkConfirmedEntries(
  CheckContext context,
  IndexedDoc doc,
) sync* {
  final keys = _entryKeysOf(context, doc);
  if (keys.isEmpty) return;
  final links = trackedLinksOf(context, doc);
  for (final key in keys) {
    final tracked = {
      for (final link in links)
        if (link.entryKey == key) linkIdentityOf(link.label),
    };
    final firstLineOf = <Object, int>{};
    for (final item in context.linesOf(doc).entriesOf(key)) {
      // A block map item's span ends with its line break.
      final text = item.text.trim();
      final entry = _readEntry(item.value, key);
      if (entry == null) {
        yield context.finding(
          doc,
          FindingKind.confirmedEntryMalformed,
          line: item.line,
          message: key == _overrideEntriesKey
              ? '$text is not an overrides entry; write '
                    '"<doc type>:<name>#<ID> <12 lowercase hex characters>"'
              : _isOverrideEntry(item.value)
              ? '$text is an override address, which belongs in '
                    '`$_overrideEntriesKey`, not in `$_confirmedKey`'
              : '$text is not a confirmed entry; write '
                    '"<link> <12 lowercase hex characters>"',
          keys: {'entry': text},
        );
        continue;
      }
      final label = entry.label;
      final identity = linkIdentityOf(label);
      final first = firstLineOf[identity];
      if (first == null) {
        firstLineOf[identity] = item.line;
      } else {
        yield context.finding(
          doc,
          FindingKind.confirmedEntryRepeated,
          line: item.line,
          message:
              '$text names $label again; line $first records it, keep one '
              'entry',
          keys: {'entry': text, 'link': label, 'first': first},
        );
        continue;
      }
      if (tracked.contains(identity)) continue;
      yield context.finding(
        doc,
        FindingKind.confirmedEntryStale,
        line: item.line,
        message: '$text names $label, which this doc does not trace',
        keys: {'entry': text, 'link': label},
      );
    }
  }
}

// Only a draft whose entry records the current fingerprint waits for the
// Owner's `approve` alone; every other unconfirmed link still needs the Agent
// to read the upstream block and record the entry.
WaitsFor _waitsForOf(IndexedDoc doc, String current, _Entry? entry) =>
    doc.isDraft && entry?.fingerprint == current
    ? WaitsFor.owner
    : WaitsFor.agent;

// An entry with an unconfirmed state means the doc is a draft.
// [waitsFor] is the one owner or agent decision; the message follows it.
String _unconfirmedMessage(
  String label,
  String current,
  _Entry? entry,
  WaitsFor waitsFor,
  String read,
) {
  if (waitsFor == WaitsFor.owner) {
    return "$label $current is recorded in a draft; it waits for the Owner's "
        'approve';
  }
  return entry == null
      ? '$label has no confirmed entry; $read'
      : '$label is not confirmed: the draft records ${entry.fingerprint}; '
            '$read';
}
