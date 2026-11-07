import 'package:specstone_core/src/consistency_check/fr_trace_rows.dart';
import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_splice.dart';
import 'package:specstone_core/src/doc_model/reference_grammar.dart';
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
final _entryLine = RegExp(
  r'''^(?<head>\s*-\s+(?<q>["']?))(?<label>[^\s"']+)'''
  r'''(?<tail> [0-9a-f]{12}\k<q>.*)$''',
);

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
  final lines = lfText.split('\n');
  final prefixLength = lfText.length - doc.afterFrontmatter.length;
  final firstLine = '\n'.allMatches(lfText.substring(0, prefixLength)).length;
  if (docType.id != _frType) {
    _rewriteBody(lines, doc, firstLine, docType, newLabel, renamed);
  }
  var result = lines.join('\n');
  if (docType.id == _frType) {
    result = _withRenamedBlock(
      result,
      doc,
      _tracedFromKey,
      (block) => _renameTraced(block, newLabel),
    );
  }
  result = _withRenamedBlock(
    result,
    doc,
    _confirmedKey,
    (block) => _renameEntries(block.text, newLabel),
  );
  return result == lfText ? null : result;
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

/// Returns the `traced_from` key block [block] with each entry label set to
/// [newLabel]; a flow list and a block list both rewrite.
String _renameTraced(KeyBlock block, String? Function(String) newLabel) {
  final lines = block.text.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final start = i == 0
        ? _afterKey(lines[i], block.key)
        : _afterDash(lines[i]);
    if (start < 0) continue;
    lines[i] =
        lines[i].substring(0, start) +
        _renameRegion(lines[i].substring(start), newLabel);
  }
  return lines.join('\n');
}

/// Returns the index in [line] past `<key>:` and its spaces, or -1.
int _afterKey(String line, String key) {
  if (!line.startsWith(key)) return -1;
  final colon = line.indexOf(':', key.length);
  return colon < 0 ? -1 : colon + 1 + _spaces(line, colon + 1);
}

/// Returns the index in [line] past a `- ` list marker, or -1.
int _afterDash(String line) {
  final dash = line.length - line.trimLeft().length;
  if (!line.startsWith('- ', dash)) return -1;
  return dash + 1 + _spaces(line, dash + 1);
}

int _spaces(String line, int from) {
  var end = from;
  while (end < line.length && line[end] == ' ') {
    end++;
  }
  return end - from;
}

/// Returns [region], the value text of a `traced_from` line, with each entry
/// label set to [newLabel]; the brackets, commas, quotes, and comment stay.
String _renameRegion(String region, String? Function(String) newLabel) {
  if (!region.startsWith('[')) return _renameItem(region, newLabel);
  final close = region.indexOf(']');
  if (close < 0) return region;
  final items = region.substring(1, close).split(',');
  final joined = items.map((item) => _renameItem(item, newLabel)).join(',');
  return '[$joined${region.substring(close)}';
}

/// Returns [item] with its leading entry, quoted or bare, set to [newLabel].
String _renameItem(String item, String? Function(String) newLabel) {
  final start = item.length - item.trimLeft().length;
  final quote = start < item.length && '"\''.contains(item[start])
      ? item[start]
      : '';
  final labelStart = start + quote.length;
  var end = labelStart;
  while (end < item.length && !' ,]"\''.contains(item[end])) {
    end++;
  }
  final renamed = newLabel(item.substring(labelStart, end));
  return renamed == null ? item : item.replaceRange(labelStart, end, renamed);
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
