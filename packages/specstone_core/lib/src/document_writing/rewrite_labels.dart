import 'package:specstone_core/src/consistency_check/fr_trace_rows.dart';
import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_splice.dart';
import 'package:specstone_core/src/doc_model/reference_grammar.dart';
import 'package:specstone_core/src/document_writing/key_block_values.dart';
import 'package:specstone_core/src/document_writing/rewrite_mentions.dart'
    show renamedNameOf;
import 'package:specstone_core/src/index_query/override_chain.dart'
    show carriesOverrides;
import 'package:specstone_core/src/journeys/journey_steps.dart';
import 'package:specstone_core/src/rendering/formatter.dart' show headerKey;
import 'package:specstone_core/src/templates/merged_doc_type.dart';

// MARK: - Constants

/// Id of the doc type whose FR trace cells and entries name FRs.
const apiTypeId = 'api';

const _storyType = 'user_story';
const _frType = 'fr';
const _frTraceSection = 'fr_trace';
const _confirmedKey = 'confirmed';
const _tracedFromKey = 'traced_from';
const _overridesKey = 'overrides';
const _stepPrefix = 'step:';

// MARK: - rewriteLinkLabels

/// Whether a doc of [docType] holds step identities, FR cells, `traced_from`
/// entries, `confirmed` labels, or `overrides` entries that a rename can
/// change.
bool carriesLinkLabels(MergedDocType? docType) =>
    docType != null &&
    (docType.id == journeyTypeId ||
        docType.id == apiTypeId ||
        docType.id == _frType ||
        carriesOverrides(docType));

/// Returns [lfText] with each step: identity, FR trace cell, `traced_from`
/// entry, confirmed label, and override entry naming a renamed doc set to its
/// new name; null when nothing changes.
///
/// [renamed] maps `(doc type id, old name)` to the new name. An FR cell is the
/// FR's Name less `<feature>/`: it resolves under [featureName] and becomes
/// the new Name less `<newFeatureName>/`, kept when that prefix is missing. An
/// override entry changes only the Name of its address.
String? rewriteLinkLabels(
  String lfText, {
  required MergedDocType? docType,
  required String? featureName,
  String? newFeatureName,
  required Map<(String, String), String> renamed,
}) {
  if (!carriesLinkLabels(docType) || renamed.isEmpty) return null;
  final newLabel = switch (docType!.id) {
    journeyTypeId ||
    _frType => (String label) => _scenarioEntryLabel(label, renamed),
    apiTypeId => (String label) => _frCell(
      label,
      featureName,
      newFeatureName ?? featureName,
      renamed,
    ),
    _ => null,
  };
  final doc = Doc.parse(lfText);
  var result = lfText;
  if (newLabel != null) {
    result = docType.id == _frType
        ? _withRenamedBlock(
            result,
            doc,
            _tracedFromKey,
            (block) => renameKeyBlockValues(block.text, block.key, newLabel),
          )
        : _withRewrittenBody(
            result,
            doc,
            docType,
            newLabel,
            (value, target) => _renamedStep(value, target, renamed),
          );
    result = _withRenamedBlock(
      result,
      doc,
      _confirmedKey,
      (block) => _renameEntries(block, newLabel),
    );
  }
  if (carriesOverrides(docType)) {
    result = _withRenamedBlock(
      result,
      doc,
      _overridesKey,
      (block) =>
          _renameEntries(block, (label) => _overrideEntryLabel(label, renamed)),
    );
  }
  return result == lfText ? null : result;
}

/// Returns the FR [lfText] with its `traced_from` and `confirmed` scenario
/// entries set for a move out of [sourceStory]; null when nothing changes.
///
/// A bare `S<N>` becomes `<sourceStory>#S<N>`; an entry whose story part
/// [isTargetStory] accepts, the story the FR lands in, becomes bare. Every
/// other entry and each fingerprint keeps its text and list shape.
String? rewriteMovedFrTraces(
  String lfText, {
  required String sourceStory,
  required bool Function(String storyName) isTargetStory,
}) {
  final result = _withScenarioEntries(
    lfText,
    (label) => _movedFrLabel(label, sourceStory, isTargetStory),
  );
  return result == lfText ? null : result;
}

/// Returns the FR [lfText] with each `traced_from` and `confirmed` entry
/// that names the moved Scenario [fromNumber] set to Scenario [toNumber] of
/// [targetStory]; null when nothing changes.
///
/// A bare `S<N>` names the scenario when [isInSourceStory], a `<story>#S<N>`
/// when [isSourceStory] accepts its story part; numbers compare by value. The
/// entry turns bare when [isInTargetStory]. Each fingerprint is kept.
String? rewriteScenarioTraces(
  String lfText, {
  required int fromNumber,
  required String targetStory,
  required int toNumber,
  required bool Function(String storyName) isSourceStory,
  required bool isInSourceStory,
  required bool isInTargetStory,
}) {
  final newRef = isInTargetStory ? 'S$toNumber' : '$targetStory#S$toNumber';
  String? newLabel(String label) {
    if (readLinkLabel(label) case ScenarioLabel(:final ref)
        when ref.scenario == BigInt.from(fromNumber)) {
      final story = ref.storyName;
      final names = story == null ? isInSourceStory : isSourceStory(story);
      return names ? newRef : null;
    }
    return null;
  }

  final result = _withScenarioEntries(lfText, newLabel);
  return result == lfText ? null : result;
}

/// Returns [lfText] with each `traced_from` entry and `confirmed` label set
/// to [newLabel], where it gives one; fingerprints and list shapes kept.
String _withScenarioEntries(
  String lfText,
  String? Function(String label) newLabel,
) {
  final doc = Doc.parse(lfText);
  final result = _withRenamedBlock(
    lfText,
    doc,
    _tracedFromKey,
    (block) => renameKeyBlockValues(block.text, block.key, newLabel),
  );
  return _withRenamedBlock(
    result,
    doc,
    _confirmedKey,
    (block) => _renameEntries(block, newLabel),
  );
}

/// Returns the journey [lfText] with each `step:` line and `confirmed`
/// entry that names Scenario [fromNumber] of a story [isSourceStory]
/// accepts set to Scenario [toNumber] of [targetStory]; null when nothing
/// changes. Each fingerprint is kept.
String? rewriteScenarioSteps(
  String lfText, {
  required MergedDocType docType,
  required int fromNumber,
  required String targetStory,
  required int toNumber,
  required bool Function(String storyName) isSourceStory,
}) {
  String? newStep(String value, StepTarget target) {
    if (target.scenario != fromNumber || !isSourceStory(target.identity)) {
      return null;
    }
    final written = value.trim();
    final at = value.indexOf(written);
    return '${value.substring(0, at)}$targetStory S$toNumber'
        '${value.substring(at + written.length)}';
  }

  final stepped = _withRewrittenBody(
    lfText,
    Doc.parse(lfText),
    docType,
    (_) => null,
    newStep,
  );
  final result =
      rewriteScenarioTraces(
        stepped,
        fromNumber: fromNumber,
        targetStory: targetStory,
        toNumber: toNumber,
        isSourceStory: isSourceStory,
        isInSourceStory: false,
        isInTargetStory: false,
      ) ??
      stepped;
  return result == lfText ? null : result;
}

/// Returns the scenario label [label] becomes when its FR leaves
/// [sourceStory], or null.
String? _movedFrLabel(
  String label,
  String sourceStory,
  bool Function(String storyName) isTargetStory,
) {
  if (readLinkLabel(label) case ScenarioLabel(:final ref)) {
    final story = ref.storyName;
    if (story == null) return '$sourceStory#${ref.number.written}';
    return isTargetStory(story) ? ref.number.written : null;
  }
  return null;
}

/// Returns [lfText] with each FR trace cell set to [newLabel] and each step
/// value to [newStep], where it gives one.
String _withRewrittenBody(
  String lfText,
  Doc doc,
  MergedDocType docType,
  String? Function(String label) newLabel,
  _StepRewrite newStep,
) {
  final lines = lfText.split('\n');
  final prefixLength = lfText.length - doc.afterFrontmatter.length;
  final firstLine = '\n'.allMatches(lfText.substring(0, prefixLength)).length;
  _rewriteBody(lines, doc, firstLine, docType, newLabel, newStep);
  return lines.join('\n');
}

/// Returns [text] with the frontmatter block [name] of [doc] rewritten by
/// [rewrite], or [text] itself when the block is absent or unchanged.
String _withRenamedBlock(
  String text,
  Doc doc,
  String name,
  String Function(KeyBlock block) rewrite,
) {
  final block = doc.frontmatter
      ?.where((candidate) => candidate.name == name)
      .firstOrNull;
  if (block == null) return text;
  final renamed = rewrite(block);
  return renamed == block.text ? text : withKeyBlock(text, name, renamed);
}

// MARK: - Body

/// Returns the value after `step:` that the step value [value], naming
/// [target], becomes, or null when it keeps its text.
typedef _StepRewrite = String? Function(String value, StepTarget target);

/// Sets the step and FR trace lines of [lines] that [newStep] or [newLabel]
/// rewrite.
///
/// [firstLine] is the index in [lines] of the first line after the
/// frontmatter.
void _rewriteBody(
  List<String> lines,
  Doc doc,
  int firstLine,
  MergedDocType docType,
  String? Function(String label) newLabel,
  _StepRewrite newStep,
) {
  final isJourney = docType.id == journeyTypeId;
  final sectionId = isJourney ? stepsSectionId : _frTraceSection;
  final headers = {
    for (final section in docType.sections)
      if (section.id == sectionId) headerKey(section.header),
  };
  final index = doc.sections.indexWhere(
    (section) => headers.contains(headerKey(section.headerText)),
  );
  if (index < 0) return;
  final start = firstLine + doc.sectionLineIndexes[index] + 1;
  final body = doc.sections[index].body;
  if (isJourney) {
    _rewriteSteps(lines, start, body, docType, newStep);
  } else {
    _rewriteFrRows(lines, start, body, newLabel);
  }
}

void _rewriteSteps(
  List<String> lines,
  int start,
  String body,
  MergedDocType docType,
  _StepRewrite newStep,
) {
  final steps = readJourneySteps(
    body,
    blockKinds: docType.listedGenerators.toSet(),
  );
  for (final step in steps.steps) {
    final target = step.target;
    final stepIndex = step.stepIndex;
    if (target == null || stepIndex == null) continue;
    final line = lines[start + stepIndex];
    final value = newStep(line.substring(_stepPrefix.length), target);
    if (value != null) lines[start + stepIndex] = '$_stepPrefix$value';
  }
}

/// Returns the step value [value] with [target]'s story set to its new name,
/// or null when [renamed] holds none for it.
String? _renamedStep(
  String value,
  StepTarget target,
  Map<(String, String), String> renamed,
) {
  final name = renamed[(_storyType, target.identity)];
  return name == null ? null : value.replaceFirst(target.identity, name);
}

void _rewriteFrRows(
  List<String> lines,
  int start,
  String body,
  String? Function(String cell) newCell,
) {
  final bodyLines = body.split('\n');
  final fenced = fencedLines(bodyLines);
  final rows = readFrTraceRows([
    for (var i = 0; i < bodyLines.length; i++)
      (text: bodyLines[i], line: i, fenced: fenced[i]),
  ]);
  for (final (:cell, :line) in rows) {
    final name = newCell(cell);
    if (name == null) continue;
    lines[start + line] = _withFirstCell(lines[start + line], cell, name);
  }
}

/// Returns the table [row] with [cell] in its first cell set to [name].
String _withFirstCell(String row, String cell, String name) {
  final open = row.indexOf('|') + 1;
  final close = row.indexOf('|', open);
  final end = close < 0 ? row.length : close;
  return row.substring(0, open) +
      row.substring(open, end).replaceFirst(cell, name) +
      row.substring(end);
}

// MARK: - Labels

/// Returns the FR cell [cell] becomes when its FR is renamed, or null.
String? _frCell(
  String cell,
  String? featureName,
  String? newFeatureName,
  Map<(String, String), String> renamed,
) {
  if (featureName == null || newFeatureName == null) return null;
  final name = renamed[(_frType, '$featureName/$cell')];
  final prefix = '$newFeatureName/';
  if (name == null || !name.startsWith(prefix)) return null;
  final renamedCell = name.substring(prefix.length);
  return renamedCell == cell ? null : renamedCell;
}

/// Returns the `<story Name>#S<N>` label [label] becomes when its story is
/// renamed, or null.
String? _scenarioEntryLabel(
  String label,
  Map<(String, String), String> renamed,
) {
  if (readLinkLabel(label) case ScenarioLabel(:final ref)) {
    final story = ref.storyName;
    final name = story == null ? null : renamed[(_storyType, story)];
    return name == null ? null : '$name#${ref.number.written}';
  }
  return null;
}

/// Returns the `<doc type>:<name>#<item ID>` label [label] becomes when the
/// doc it names is renamed, or null.
String? _overrideEntryLabel(
  String label,
  Map<(String, String), String> renamed,
) {
  if (readLinkLabel(label) case OverrideLabel(:final address, :final itemId)) {
    final name = renamedNameOf(address, renamed);
    return name == null ? null : '${address.typeId}:$name#$itemId';
  }
  return null;
}

/// Returns the `confirmed` or `overrides` key [block] with each entry label
/// set to [newLabel], read by the shared key-block scan, so a flow list is
/// read as a block list is; [block]'s text itself when none changes.
///
/// The scan passes a bare entry's label and fingerprint one at a time, and a
/// quoted entry whole; only its label part is renamed.
String _renameEntries(
  KeyBlock block,
  String? Function(String label) newLabel,
) => renameKeyBlockValues(block.text, block.key, (value) {
  final space = value.indexOf(' ');
  if (space < 0) return newLabel(value);
  final renamed = newLabel(value.substring(0, space));
  return renamed == null ? null : '$renamed${value.substring(space)}';
});
