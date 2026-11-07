import 'package:specstone_core/src/consistency_check/fr_trace_rows.dart';
import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_splice.dart';
import 'package:specstone_core/src/doc_model/reference_grammar.dart';
import 'package:specstone_core/src/document_writing/key_block_values.dart';
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
const _stepPrefix = 'step:';

// MARK: - rewriteLinkLabels

/// Whether a doc of [docTypeId] holds step identities, FR cells,
/// `traced_from` entries, or `confirmed` labels that a rename can change.
bool carriesLinkLabels(String? docTypeId) =>
    docTypeId == journeyTypeId ||
    docTypeId == apiTypeId ||
    docTypeId == _frType;

/// Returns [lfText] with each step: identity, FR trace cell, `traced_from`
/// entry, and confirmed label naming a renamed doc set to its new name; null
/// when nothing changes.
///
/// [renamed] maps `(doc type id, old name)` to the new name. An FR cell is the
/// FR's Name less `<feature>/`: it resolves under [featureName] and becomes
/// the new Name less `<newFeatureName>/`, kept when that prefix is missing.
String? rewriteLinkLabels(
  String lfText, {
  required MergedDocType? docType,
  required String? featureName,
  String? newFeatureName,
  required Map<(String, String), String> renamed,
}) {
  if (docType == null || renamed.isEmpty) return null;
  final newLabel = switch (docType.id) {
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
  if (newLabel == null) return null;
  final doc = Doc.parse(lfText);
  var result = docType.id == _frType
      ? _withRenamedBlock(
          lfText,
          doc,
          _tracedFromKey,
          (block) => renameKeyBlockValues(block.text, block.key, newLabel),
        )
      : _withRewrittenBody(lfText, doc, docType, newLabel, renamed);
  result = _withRenamedBlock(
    result,
    doc,
    _confirmedKey,
    (block) => _renameEntries(block, newLabel),
  );
  return result == lfText ? null : result;
}

/// Returns [lfText] with the step and FR trace lines that name a renamed doc
/// set to the new name.
String _withRewrittenBody(
  String lfText,
  Doc doc,
  MergedDocType docType,
  String? Function(String label) newLabel,
  Map<(String, String), String> renamed,
) {
  final lines = lfText.split('\n');
  final prefixLength = lfText.length - doc.afterFrontmatter.length;
  final firstLine = '\n'.allMatches(lfText.substring(0, prefixLength)).length;
  _rewriteBody(lines, doc, firstLine, docType, newLabel, renamed);
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

/// Sets the step and FR trace lines of [lines] that name a renamed doc.
///
/// [firstLine] is the index in [lines] of the first line after the
/// frontmatter.
void _rewriteBody(
  List<String> lines,
  Doc doc,
  int firstLine,
  MergedDocType docType,
  String? Function(String label) newLabel,
  Map<(String, String), String> renamed,
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
    _rewriteSteps(lines, start, body, docType, renamed);
  } else {
    _rewriteFrRows(lines, start, body, newLabel);
  }
}

void _rewriteSteps(
  List<String> lines,
  int start,
  String body,
  MergedDocType docType,
  Map<(String, String), String> renamed,
) {
  final steps = readJourneySteps(
    body,
    blockKinds: docType.listedGenerators.toSet(),
  );
  for (final step in steps.steps) {
    final target = step.target;
    final stepIndex = step.stepIndex;
    final name = target == null ? null : renamed[(_storyType, target.identity)];
    if (target == null || stepIndex == null || name == null) continue;
    final line = lines[start + stepIndex];
    final value = line.substring(_stepPrefix.length);
    lines[start + stepIndex] =
        '$_stepPrefix${value.replaceFirst(target.identity, name)}';
  }
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

/// Returns the `confirmed` key [block] with each entry label set to
/// [newLabel], read by the shared key-block scan, so a flow list is read as a
/// block list is; [block]'s text itself when none changes.
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
