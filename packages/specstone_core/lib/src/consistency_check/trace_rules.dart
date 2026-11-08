import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/consistency_check/scenario_blocks.dart';
import 'package:specstone_core/src/doc_model/reference_grammar.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/journeys/step_scenarios.dart';

const _frType = 'fr';
const _nfType = 'nf';
const _tracedFromKey = 'traced_from';
const _kindKey = 'kind';
const _overridesKey = 'overrides';
const _selfDerived = 'self-derived';
const _tighten = 'tighten';
const _relax = 'relax';
const _add = 'add';
const _projectType = 'project';
const _rolesSection = 'roles';
const _acceptanceSection = 'acceptance_criteria';
const _personaType = 'persona';
const _storyType = 'user_story';
const _roleKey = 'role';
const _idKey = 'id';
const _asPrefixes = ['- **As a** ', '- **As an** '];
const _whoSeparator = ' who ';
const _storyVisionKeys = ['vision', 'goals'];
const _apiType = 'api';
const _architectureType = 'architecture';
const _implementsKey = 'implements';
const _statusKey = 'status';
const _implemented = 'implemented';
const _goalsSection = 'goals';
const _visionIdPrefix = 'PV-';
const _goalIdPrefix = 'PG-';
final _servesLine = RegExp(r'^\*\*Serves:\*\*(.*)$');

/// Where a Serves ID may open: an upper-case-led prefix ending `-` that no
/// letter or digit precedes; the grammar reads the ID from there.
final _servedPrefix = RegExp('(?<![A-Za-z0-9])[A-Z][A-Za-z]*-');

/// Returns the requirement trace findings of a typed [doc] (US-03 FR-01).
///
/// An `fr` traces to scenarios of its story; an `nf` overrides a GNFR item
/// only as its `kind` says. A doc whose story is gone gets no finding.
Iterable<Finding> checkTraces(CheckContext context, IndexedDoc doc) sync* {
  switch (doc.docTypeId) {
    case _frType:
      yield* _unresolvedScenarioTraces(context, doc);
    case _nfType:
      if (context.hasGnfr) yield* _overrideProblems(context, doc);
  }
}

Iterable<Finding> _unresolvedScenarioTraces(
  CheckContext context,
  IndexedDoc doc,
) sync* {
  final story = context.index.parentOf(doc);
  final storyType = story?.docTypeId;
  if (story == null ||
      storyType == null ||
      !context.typeHoldsSection(storyType, _acceptanceSection)) {
    return;
  }
  final line = context.linesOf(doc).keyLine(_tracedFromKey);
  if (line == null) return;
  for (final entry in doc.valuesOf(_tracedFromKey)) {
    if (entry == _selfDerived || _tracesScenario(context, story, entry)) {
      continue;
    }
    yield context.finding(
      doc,
      FindingKind.scenarioTraceUnresolved,
      line: line,
      message:
          '$entry is no scenario the story may trace and not $_selfDerived',
      keys: {'entry': entry},
    );
  }
}

// Whether [entry] reads as a scenario ref naming a scenario [story] or a
// sibling story holds.
bool _tracesScenario(CheckContext context, IndexedDoc story, String entry) {
  final ref = readScenarioRef(entry);
  if (ref == null) return false;
  final traced = tracedStoryOf(context.index, story, ref);
  return traced != null &&
      context.scenarioBlocksOf(traced).containsKey(scenarioKeyOf(ref));
}

Iterable<Finding> _overrideProblems(
  CheckContext context,
  IndexedDoc doc,
) sync* {
  final kind = doc.valuesOf(_kindKey).firstOrNull;
  if (kind != _tighten && kind != _relax && kind != _add) return;
  final overrides = doc.valuesOf(_overridesKey).firstOrNull ?? '';
  final lines = context.linesOf(doc);
  final kindLine = lines.keyLine(_kindKey);
  final overridesLine = lines.keyLine(_overridesKey);
  final needsOverride = kind != _add;
  if (needsOverride == overrides.isEmpty && kindLine != null) {
    yield context.finding(
      doc,
      FindingKind.overrideKindMismatch,
      line: kindLine,
      message: needsOverride
          ? '$kind needs an overrides entry'
          : 'add takes no overrides entry',
      keys: {'kind': kind!, 'overrides': overrides},
    );
    return;
  }
  if (needsOverride &&
      overridesLine != null &&
      !context.nfrStatements().containsKey(overrides)) {
    yield context.finding(
      doc,
      FindingKind.overrideUnresolved,
      line: overridesLine,
      message: '$overrides is no NFR of the project-wide requirements',
      keys: {'overrides': overrides},
    );
  }
}

/// Returns the role and vision and goal findings of a typed [doc].
///
/// Covers US-03 FR-02.
///
/// A role names a `project` Role entry (INV-2); vision and goal IDs sit in
/// the parent feature, if any, and a project heading; a project goal names
/// its `PV-` headings in `**Serves:**`. Runs only with `project` in the set.
Iterable<Finding> checkRolesAndGoals(
  CheckContext context,
  IndexedDoc doc,
) sync* {
  if (!context.hasProject) return;
  final readsRoles = context.typeHoldsSection(_projectType, _rolesSection);
  switch (doc.docTypeId) {
    case _personaType:
      if (readsRoles) yield* _personaRole(context, doc);
    case _storyType:
      if (readsRoles) yield* _storyRole(context, doc);
      yield* _storyGoalSets(context, doc);
    case featureType:
      yield* _featureGoalSets(context, doc);
    case _projectType:
      yield* _goalServes(context, doc);
  }
}

Iterable<Finding> _personaRole(CheckContext context, IndexedDoc doc) sync* {
  final role = doc.valuesOf(_roleKey).firstOrNull;
  final line = context.linesOf(doc).keyLine(_roleKey);
  if (role == null || line == null) return;
  yield* _unresolvedRole(context, doc, role, line);
}

String? _asPrefixOf(String line) =>
    _asPrefixes.where(line.startsWith).firstOrNull;

Iterable<Finding> _storyRole(CheckContext context, IndexedDoc doc) sync* {
  final lines = context.linesOf(doc);
  for (final (index, line) in lines.lines.indexed) {
    final prefix = _asPrefixOf(line);
    if (prefix == null || lines.isFenced(index + 1)) continue;
    final text = line.substring(prefix.length);
    final who = text.indexOf(_whoSeparator);
    final role = (who < 0 ? text : text.substring(0, who)).trim();
    yield* _unresolvedRole(context, doc, role, index + 1);
    return;
  }
}

Iterable<Finding> _unresolvedRole(
  CheckContext context,
  IndexedDoc doc,
  String role,
  int line,
) sync* {
  if (context.roleNames().contains(role)) return;
  yield context.finding(
    doc,
    FindingKind.roleUnresolved,
    line: line,
    message: '$role is no Role entry of the project',
    keys: {_roleKey: role},
  );
}

Iterable<Finding> _storyGoalSets(CheckContext context, IndexedDoc doc) =>
    _goalSets(context, doc, switch (context.index.parentOf(doc)) {
      final feature? => (doc: feature, label: 'feature'),
      null => null,
    });

Iterable<Finding> _featureGoalSets(CheckContext context, IndexedDoc doc) {
  final parent = context.index.parentOf(doc);
  if (parent == null || parent.docTypeId != doc.docTypeId) {
    return _goalSets(context, doc, null);
  }
  return _goalSets(context, doc, (doc: parent, label: 'parent feature'));
}

/// Yields the unresolved and widened ids of [doc]; a null [holder] skips the
/// widened check, and the holder's label names it in the message.
Iterable<Finding> _goalSets(
  CheckContext context,
  IndexedDoc doc,
  ({IndexedDoc doc, String label})? holder,
) sync* {
  for (final key in _storyVisionKeys) {
    final line = context.linesOf(doc).keyLine(key);
    if (line == null) continue;
    final held = holder?.doc.valuesOf(key).toSet();
    for (final id in doc.valuesOf(key)) {
      yield* _unresolvedId(context, doc, id, line);
      if (held != null && !held.contains(id)) {
        yield context.finding(
          doc,
          FindingKind.visionGoalWidened,
          line: line,
          message: '$id is not in the $key of the ${holder!.label}',
          keys: {_idKey: id},
        );
      }
    }
  }
}

Iterable<Finding> _unresolvedId(
  CheckContext context,
  IndexedDoc doc,
  String id,
  int line,
) sync* {
  if (context.projectHeadingIds().contains(id)) return;
  yield context.finding(
    doc,
    FindingKind.visionGoalUnresolved,
    line: line,
    message: '$id is no heading of the project',
    keys: {_idKey: id},
  );
}

String? _goalKeyOf(String heading) {
  final text = itemHeadingTextOf(heading);
  if (text == null) return null;
  return switch (readItemId(text, _goalIdPrefix)) {
    ItemId(:final written) => written,
    _ => null,
  };
}

/// The IDs of a Serves line's [text] as the grammar reads each: plain,
/// lettered, or unreadable, each whole, so none is skipped (INV-21).
List<String> _servedIdsOf(String text) {
  final ids = <String>[];
  var readUpTo = 0;
  for (final match in _servedPrefix.allMatches(text)) {
    if (match.start < readUpTo) continue;
    final id = readItemId(text.substring(match.start), match[0]!);
    if (id == null) continue;
    ids.add(id.written);
    readUpTo = match.start + id.written.length;
  }
  return ids;
}

Iterable<Finding> _goalServes(CheckContext context, IndexedDoc doc) sync* {
  final section = context.heldIndexOf(doc, _goalsSection);
  if (section == null) return;
  final blocks = headingBlocksOf(context.bodyLinesOf(doc, section), _goalKeyOf);
  for (final (:key, :lines) in blocks) {
    final serves = lines
        .where((line) => !line.fenced)
        .map(
          (line) => (line: line.line, match: _servesLine.firstMatch(line.text)),
        )
        .where((entry) => entry.match != null)
        .firstOrNull;
    final ids = _servedIdsOf(serves?.match!.group(1) ?? '');
    if (ids.isEmpty) {
      yield context.finding(
        doc,
        FindingKind.goalServesMissing,
        line: lines.first.line,
        message: '$key names no vision in a **Serves:** line',
        keys: {'goal': key},
      );
      continue;
    }
    for (final id in ids) {
      if (id.startsWith(_visionIdPrefix) &&
          context.projectHeadingIds().contains(id)) {
        continue;
      }
      yield context.finding(
        doc,
        FindingKind.visionGoalUnresolved,
        line: serves!.line,
        message: '$id is no vision heading of the project',
        keys: {_idKey: id},
      );
    }
  }
}

/// Returns the findings of a spec doc read against its PRD (US-03 FR-03).
///
/// An `api` row must name an FR of its feature as `<feature name>/<cell>`. A
/// `feature` with code pointers needs an `architecture` doc of its own or of a
/// feature above it when the merged set holds that type.
Iterable<Finding> checkSpecAgainstPrd(
  CheckContext context,
  IndexedDoc doc,
) sync* {
  switch (doc.docTypeId) {
    case _apiType:
      yield* _unresolvedFrRows(context, doc);
    case featureType:
      if (context.hasArchitecture) yield* _missingArchitecture(context, doc);
  }
}

Iterable<Finding> _unresolvedFrRows(
  CheckContext context,
  IndexedDoc api,
) sync* {
  final feature = context.index.parentOf(api);
  if (feature == null) return;
  for (final (:cell, :line) in context.frTraceRowsOf(api)) {
    if (context.frNamed('${feature.name}/$cell') != null) continue;
    yield context.finding(
      api,
      FindingKind.frTraceUnresolved,
      line: line,
      message: '$cell is no requirement of ${feature.name}',
      keys: {'fr': cell},
    );
  }
}

Iterable<Finding> _missingArchitecture(
  CheckContext context,
  IndexedDoc feature,
) sync* {
  final index = context.index;
  final hasCode = index
      .subtreeOf(feature)
      .any((doc) => doc.valuesOf(_implementsKey).isNotEmpty);
  if (!hasCode) return;
  final hasArchitecture = index
      .chainOf(feature)
      .expand(index.childrenOf)
      .any((doc) => doc.docTypeId == _architectureType);
  if (hasArchitecture) return;
  yield context.finding(
    feature,
    FindingKind.architectureMissing,
    line: 1,
    message: 'code is pointed at but no architecture doc covers the feature',
  );
}

/// Returns `implements_missing` for a doc whose status is `implemented` and
/// that holds no `implements` entry (US-03 FR-04).
///
/// Only a doc type that defines `implements` is read (INV-2).
Iterable<Finding> checkImplementedStatus(
  CheckContext context,
  IndexedDoc doc,
) sync* {
  if (!context.typeHoldsField(context.typeOf(doc), _implementsKey)) return;
  if (doc.writtenStatus != _implemented) return;
  if (doc.valuesOf(_implementsKey).isNotEmpty) return;
  final line = context.linesOf(doc).keyLine(_statusKey);
  if (line == null) return;
  yield context.finding(
    doc,
    FindingKind.implementsMissing,
    line: line,
    message: 'status is $_implemented but no implements entry points at code',
  );
}
