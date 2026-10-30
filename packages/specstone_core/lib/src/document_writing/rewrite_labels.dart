import 'package:specstone_core/src/consistency_check/fr_trace_rows.dart';
import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_splice.dart';
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
const _stepPrefix = 'step:';
final _journeyLabel = RegExp(r'^(.+)#(S[0-9]+)$');
final _entryLine = RegExp(
  r'''^(?<head>\s*-\s+(?<q>["']?))(?<label>[^\s"']+)'''
  r'''(?<tail> [0-9a-f]{12}\k<q>.*)$''',
);

// MARK: - rewriteLinkLabels

/// Whether a doc of [docTypeId] holds step identities, FR cells, or
/// `confirmed` labels that a rename can change.
bool carriesLinkLabels(String? docTypeId) =>
    docTypeId == journeyTypeId || docTypeId == apiTypeId;

/// Returns [lfText] with each step: identity, FR trace cell, and confirmed
/// label naming a renamed doc set to its new name, the `S<N>` and every
/// fingerprint kept; null when nothing changes.
///
/// [renamed] maps `(doc type id, old name)` to the new name. Only a `journey`
/// and an `api` doc change. [featureName] is the `api` doc's feature before
/// the rename: an FR ref holds no feature slug, so a cell resolves under it
/// alone, and a feature rename leaves every cell as written. A step line
/// inside a fence or a generated block, and the prose, keep every byte.
String? rewriteLinkLabels(
  String lfText, {
  required MergedDocType? docType,
  required String? featureName,
  required Map<(String, String), String> renamed,
}) {
  if (docType == null || renamed.isEmpty) return null;
  final newLabel = switch (docType.id) {
    journeyTypeId => (String label) => _journeyEntryLabel(label, renamed),
    apiTypeId => (String label) => _frCell(label, featureName, renamed),
    _ => null,
  };
  if (newLabel == null) return null;
  final doc = Doc.parse(lfText);
  final lines = lfText.split('\n');
  final prefixLength = lfText.length - doc.afterFrontmatter.length;
  final firstLine = '\n'.allMatches(lfText.substring(0, prefixLength)).length;
  _rewriteBody(lines, doc, firstLine, docType, featureName, renamed);
  var result = lines.join('\n');
  final confirmed = doc.frontmatter
      ?.where((block) => block.name == _confirmedKey)
      .firstOrNull;
  if (confirmed != null) {
    final text = _renameEntries(confirmed.text, newLabel);
    if (text != confirmed.text) {
      result = withKeyBlock(result, _confirmedKey, text);
    }
  }
  return result == lfText ? null : result;
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
  String? featureName,
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
    _rewriteFrRows(lines, start, body, featureName, renamed);
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
  String? featureName,
  Map<(String, String), String> renamed,
) {
  final bodyLines = body.split('\n');
  final fenced = fencedLines(bodyLines);
  final rows = readFrTraceRows([
    for (var i = 0; i < bodyLines.length; i++)
      (text: bodyLines[i], line: i, fenced: fenced[i]),
  ]);
  for (final (:cell, :line) in rows) {
    final name = _frCell(cell, featureName, renamed);
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
  Map<(String, String), String> renamed,
) {
  if (featureName == null) return null;
  final name = renamed[(_frType, '$featureName/$cell')];
  final cut = name?.indexOf('/') ?? -1;
  if (name == null || cut < 0) return null;
  final renamedCell = name.substring(cut + 1);
  return renamedCell == cell ? null : renamedCell;
}

/// Returns the `<identity>#S<N>` label [label] becomes when its story is
/// renamed, or null.
String? _journeyEntryLabel(
  String label,
  Map<(String, String), String> renamed,
) {
  final match = _journeyLabel.firstMatch(label);
  final name = match == null ? null : renamed[(_storyType, match.group(1)!)];
  return name == null ? null : '$name#${match!.group(2)}';
}

/// Returns the `confirmed` key block [text] with each entry label set to
/// [newLabel], or [text] itself when none changes.
String _renameEntries(String text, String? Function(String label) newLabel) {
  final lines = text.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final match = _entryLine.firstMatch(lines[i]);
    if (match == null) continue;
    final renamed = newLabel(match.namedGroup('label')!);
    if (renamed == null) continue;
    lines[i] = '${match.namedGroup('head')}$renamed${match.namedGroup('tail')}';
  }
  return lines.join('\n');
}
