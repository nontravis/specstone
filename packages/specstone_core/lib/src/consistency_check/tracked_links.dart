import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/doc_lines.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/consistency_check/fingerprint.dart';
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
const _statementSection = 'statement';
const _statementBlock = 'Statement';
const _tighten = 'tighten';
const _relax = 'relax';
final _fingerprintShape = RegExp(r'^[0-9a-f]{12}$');

/// Whether a tracked link is current, changed, or without a matching entry.
enum LinkState { clean, suspect, unconfirmed }

/// One link from a downstream doc to an upstream block (INV-5).
final class TrackedLink {
  /// The link [label] traced at [traceLine].
  ///
  /// [upstream], [block], and [fingerprint] stay null when the upstream block
  /// is missing; the link then has no [LinkState] (INV-6).
  const new({
    required this.label,
    required this.traceLine,
    this.upstream,
    this.block,
    this.fingerprint,
  });

  /// The LinkLabel: `S<N>`, an NFR id, `<story slug>/<fr slug>`, or
  /// `<story Name>#S<N>`.
  final String label;

  /// The file line of the key or table row that traces the link.
  final int traceLine;

  /// The DocPath of the upstream doc.
  final String? upstream;

  /// The upstream block's name as a message prints it.
  final String? block;

  /// The Fingerprint of the upstream block now.
  final String? fingerprint;
}

/// Returns the links [doc] tracks, one per link identity, in trace order
/// (INV-5): `S6` and `S06` are one link.
///
/// An `fr` tracks its `S<N>` and sibling `<story Name>#S<N>` trace
/// entries (a lettered number yields a link with no upstream), an `nf` of
/// kind `tighten` or `relax` its overridden NFR, an `api` doc each FR of its
/// trace table, and a `journey` the story scenario each step names.
List<TrackedLink> trackedLinksOf(CheckContext context, IndexedDoc doc) {
  final links = switch (doc.docTypeId) {
    _frType => _scenarioLinks(context, doc),
    _nfType => _overrideLinks(context, doc),
    _apiType => _frRowLinks(context, doc),
    journeyTypeId => _stepLinks(context, doc),
    _ => const <TrackedLink>[],
  };
  final seen = <String>{};
  return [
    for (final link in links)
      if (seen.add(_identityOf(link.label))) link,
  ];
}

// A scenario label names its link by story Name and the number's value, so
// the entry `a/b#S09` names the link `a/b#S9` (W9); any other label as written.
String _identityOf(String label) {
  final read = readLinkLabel(label);
  if (read is! ScenarioLabel) return label;
  final key = scenarioKeyOf(read.ref);
  if (key == null) return label;
  final story = read.ref.storyName;
  return story == null ? key : '$story#$key';
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
        : TrackedLink(
            label: cell,
            traceLine: line,
            upstream: fr.docPath,
            block: _statementBlock,
            fingerprint: fingerprintOf(
              context.heldSection(fr, _statementSection)?.body ?? '',
            ),
          );
  }
}

// A step whose `step:` reads as a target tracks that story scenario; a missing
// story or scenario leaves the link without an upstream (INV-6).
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
            fingerprint: fingerprintOf(text),
          );
  }
}

typedef _Entry = ({String fingerprint, int line});

// Reads [value] as `<LinkLabel> <12 lowercase hex characters>`, one space
// between; the label goes through the doc model reference grammar, where a
// lettered scenario number names no scenario.
({String label, String fingerprint})? _readEntry(Object? value) {
  if (value is! String) return null;
  final space = value.indexOf(' ');
  if (space < 0) return null;
  final fingerprint = value.substring(space + 1);
  final label = readLinkLabel(value.substring(0, space));
  if (label == null || !_fingerprintShape.hasMatch(fingerprint)) return null;
  if (label is ScenarioLabel && label.ref.scenario == null) return null;
  return (label: label.written, fingerprint: fingerprint);
}

// The first well-formed entry naming the link of [label] is its entry (PD19).
_Entry? _entryOf(DocLines lines, String label) {
  final identity = _identityOf(label);
  for (final item in lines.entriesOf(_confirmedKey)) {
    final entry = _readEntry(item.value);
    if (entry != null && _identityOf(entry.label) == identity) {
      return (fingerprint: entry.fingerprint, line: item.line);
    }
  }
  return null;
}

// A draft's links are never clean or suspect: its entries wait for approval.
LinkState _stateOf(IndexedDoc doc, TrackedLink link, _Entry? entry) {
  if (doc.isDraft || entry == null) return LinkState.unconfirmed;
  return entry.fingerprint == link.fingerprint
      ? LinkState.clean
      : LinkState.suspect;
}

/// Whether any link [doc] tracks is `suspect` (INV-6).
bool hasSuspectLink(CheckContext context, IndexedDoc doc) {
  if (!context.typeHoldsField(context.typeOf(doc), _confirmedKey)) return false;
  final lines = context.linesOf(doc);
  return trackedLinksOf(context, doc).any(
    (link) =>
        link.fingerprint != null &&
        _stateOf(doc, link, _entryOf(lines, link.label)) == LinkState.suspect,
  );
}

/// Returns the `suspect` and `unconfirmed` findings of [doc] (INV-6, INV-7).
///
/// A link whose upstream block is missing takes no state; US-03 reports it.
/// Only a doc type that defines `confirmed` is read (INV-2).
Iterable<Finding> checkTrackedLinks(
  CheckContext context,
  IndexedDoc doc,
) sync* {
  if (!context.typeHoldsField(context.typeOf(doc), _confirmedKey)) return;
  final lines = context.linesOf(doc);
  for (final link in trackedLinksOf(context, doc)) {
    final current = link.fingerprint;
    final upstream = link.upstream;
    final block = link.block;
    if (current == null || upstream == null || block == null) continue;
    final entry = _entryOf(lines, link.label);
    final read = 'read $block of $upstream, then record ${link.label} $current';
    final keys = <String, Object>{
      'link': link.label,
      'fingerprint': current,
      'upstream': upstream,
      'block': block,
      if (entry != null) 'recorded': entry.fingerprint,
    };
    switch (_stateOf(doc, link, entry)) {
      case LinkState.clean:
        break;
      case LinkState.suspect:
        yield context.finding(
          doc,
          FindingKind.suspect,
          line: entry!.line,
          message:
              '${link.label} changed after it was confirmed: recorded '
              '${entry.fingerprint}, current $current; $read',
          keys: keys,
        );
      case LinkState.unconfirmed:
        yield context.finding(
          doc,
          FindingKind.unconfirmed,
          line: entry?.line ?? link.traceLine,
          message: _unconfirmedMessage(link.label, current, entry, read),
          keys: keys,
        );
    }
  }
}

/// Returns the malformed and stale `confirmed` entries of [doc] (INV-7).
///
/// Only a doc type that defines `confirmed` is read; a draft is read too.
Iterable<Finding> checkConfirmedEntries(
  CheckContext context,
  IndexedDoc doc,
) sync* {
  if (!context.typeHoldsField(context.typeOf(doc), _confirmedKey)) return;
  final tracked = {
    for (final link in trackedLinksOf(context, doc)) _identityOf(link.label),
  };
  for (final item in context.linesOf(doc).entriesOf(_confirmedKey)) {
    // A block map item's span ends with its line break.
    final text = item.text.trim();
    final entry = _readEntry(item.value);
    if (entry == null) {
      yield context.finding(
        doc,
        FindingKind.confirmedEntryMalformed,
        line: item.line,
        message:
            '$text is not a confirmed entry; write '
            '"<link> <12 lowercase hex characters>"',
        keys: {'entry': text},
      );
      continue;
    }
    final label = entry.label;
    if (tracked.contains(_identityOf(label))) continue;
    yield context.finding(
      doc,
      FindingKind.confirmedEntryStale,
      line: item.line,
      message: '$text names $label, which this doc does not trace',
      keys: {'entry': text, 'link': label},
    );
  }
}

// An entry with an unconfirmed state means the doc is a draft.
String _unconfirmedMessage(
  String label,
  String current,
  _Entry? entry,
  String read,
) {
  if (entry == null) {
    return '$label has no confirmed entry: current $current; $read';
  }
  return entry.fingerprint == current
      ? "$label $current is recorded in a draft; it waits for the Owner's "
            'approve'
      : '$label is not confirmed: the draft records ${entry.fingerprint}, '
            'current $current; $read';
}
