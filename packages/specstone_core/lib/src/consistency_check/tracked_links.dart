import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/doc_lines.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/consistency_check/fingerprint.dart';
import 'package:specstone_core/src/consistency_check/override_lines.dart';
import 'package:specstone_core/src/consistency_check/scenario_blocks.dart';
import 'package:specstone_core/src/doc_model/reference_grammar.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/journeys/journey_steps.dart';
import 'package:specstone_core/src/journeys/step_scenarios.dart';

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
final _fingerprintShape = RegExp(r'^[0-9a-f]{12}$');

/// Whether a tracked link is current, changed, or without a matching entry.
enum LinkState { clean, suspect, unconfirmed }

/// One link from a downstream doc to an upstream block.
final class TrackedLink {
  /// The link [label] traced at [traceLine].
  ///
  /// [upstream], [block], [source], and [fingerprint] stay null when the
  /// upstream block is missing; the link then has no [LinkState].
  const new({
    required this.label,
    required this.traceLine,
    this.upstream,
    this.block,
    this.source,
    this.fingerprint,
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
}

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
    if (line case OverrideLine(:final address?, :final upstream?)) {
      final itemId = line.itemId;
      final text = line.itemText;
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
    final text = context.scenarioBlocksOf(traced)[scenarioKeyOf(ref)];
    yield text == null
        ? TrackedLink(label: ref.label, traceLine: line)
        : TrackedLink(
            label: ref.label,
            traceLine: line,
            upstream: traced.docPath,
            block: 'Scenario ${ref.scenario}',
            source: text,
            fingerprint: fingerprintOf(text),
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
  final statement = context.nfrStatements()[id];
  yield statement == null
      ? TrackedLink(label: id, traceLine: line)
      : TrackedLink(
          label: id,
          traceLine: line,
          upstream: statement.path,
          block: '$id $_statementBlock',
          source: statement.text,
          fingerprint: fingerprintOf(statement.text),
        );
}

Iterable<TrackedLink> _frRowLinks(CheckContext context, IndexedDoc api) sync* {
  final feature = context.index.parentOf(api);
  if (feature == null) return;
  for (final (:cell, :line) in context.frTraceRowsOf(api)) {
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
  final statement = context.heldSection(fr, _statementSection)?.body ?? '';
  return TrackedLink(
    label: label,
    traceLine: line,
    upstream: fr.docPath,
    block: _statementBlock,
    source: statement,
    fingerprint: fingerprintOf(statement),
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
    final text = story == null
        ? null
        : context.scenarioBlocksOf(story)[target.scenarioLabel];
    yield text == null
        ? TrackedLink(label: target.label, traceLine: line)
        : TrackedLink(
            label: target.label,
            traceLine: line,
            upstream: story!.docPath,
            block: 'Scenario ${target.scenario}',
            source: text,
            fingerprint: fingerprintOf(text),
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
  if (label == null || !_fingerprintShape.hasMatch(fingerprint)) return null;
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

/// Whether any link [doc] tracks is `suspect`.
bool hasSuspectLink(CheckContext context, IndexedDoc doc) {
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
/// read.
Iterable<Finding> checkTrackedLinks(
  CheckContext context,
  IndexedDoc doc,
) sync* {
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

// The block as `format` lays it out, with the one line break that ends it
// dropped, so each of its lines prints once and a trailing space the layout
// keeps stays in the text the fingerprint hashes.
String _blockText(String source) {
  final text = upstreamText(source);
  return text.endsWith('\n') ? text.substring(0, text.length - 1) : text;
}

/// Returns the malformed and stale `confirmed` entries of [doc].
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
      final first = firstLineOf.putIfAbsent(identity, () => item.line);
      if (first != item.line) {
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
