import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/code_rules.dart'
    show ImplementedWork;
import 'package:specstone_core/src/consistency_check/doc_lines.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/consistency_check/record_doc.dart';
import 'package:specstone_core/src/consistency_check/scenario_blocks.dart';
import 'package:specstone_core/src/doc_model/reference_grammar.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/record_entries.dart';
import 'package:specstone_core/src/journeys/step_scenarios.dart';
import 'package:specstone_core/src/templates/code_target.dart';
import 'package:specstone_core/src/templates/doc_type_layer.dart'
    show RecordStatus;
import 'package:specstone_core/src/templates/merged_doc_type.dart';

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
const _personaType = 'persona';
const _storyType = 'user_story';
const _roleKey = 'role';
const _idKey = 'id';
const _asPrefixes = ['- **As a** ', '- **As an** '];
const _whoSeparator = ' who ';
const _storyVisionKeys = ['vision', 'goals'];
const _apiType = 'api';
const _architectureType = 'architecture';
const _goalsSection = 'goals';
const _visionIdPrefix = 'PV-';
const _goalIdPrefix = 'PG-';
final _servesLine = RegExp(r'^\*\*Serves:\*\*(.*)$');

/// Where a Serves ID may open: an upper-case-led prefix ending `-` that no
/// letter or digit precedes; the grammar reads the ID from there.
final _servedPrefix = RegExp('(?<![A-Za-z0-9])[A-Z][A-Za-z]*-');

/// Returns the requirement trace findings of a typed [doc] (`consistency_check/find_prd_spec_disagreements/check_requirement_traces`).
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
      !context.typeHoldsSection(storyType, acceptanceSectionId)) {
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
/// Covers `consistency_check/find_prd_spec_disagreements/check_roles_and_goal_sets`.
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

/// Returns the findings of a spec doc read against its PRD (`consistency_check/find_prd_spec_disagreements/check_spec_against_prd`).
///
/// An `api` row must name an FR of its feature as `<feature name>/<cell>`. A
/// `feature` whose record in a target names code needs, for that target, an
/// `architecture` doc of its own or of a feature above it when the merged set
/// holds that type.
Iterable<Finding> checkSpecAgainstPrd(
  CheckContext context,
  ImplementedWork work,
  IndexedDoc doc,
) sync* {
  switch (doc.docTypeId) {
    case _apiType:
      yield* _unresolvedFrRows(context, doc);
    case featureType:
      if (context.hasArchitecture) {
        yield* _missingArchitecture(context, work, doc);
      }
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
  ImplementedWork work,
  IndexedDoc feature,
) sync* {
  final recordType = context.set.recordDocType;
  if (recordType == null) return;
  final index = context.index;
  for (final target in work.targets) {
    if (!_recordsNameCode(context, work, recordType, feature, target)) continue;
    final hasArchitecture = index
        .chainOf(feature)
        .expand(index.childrenOf)
        .any(
          (doc) =>
              doc.docTypeId == _architectureType &&
              work.targetOf(doc) == target,
        );
    if (hasArchitecture) continue;
    final shown = _shownTargetName(context, target.name);
    yield context.finding(
      feature,
      FindingKind.architectureMissing,
      line: 1,
      message: shown == null
          ? 'code is pointed at but no architecture doc covers the feature'
          : 'code is pointed at but no architecture doc of target $shown '
                'covers the feature',
      keys: {'target': ?shown},
    );
  }
}

/// Whether a record of [feature] or of a feature below it, in [target], names
/// a code path for an item the target does not skip.
bool _recordsNameCode(
  CheckContext context,
  ImplementedWork work,
  MergedDocType recordType,
  IndexedDoc feature,
  CodeTarget target,
) {
  final index = context.index;
  for (final member in index.subtreeOf(feature)) {
    if (member.docTypeId != featureType) continue;
    final items = recordItemsOf(member, index.childrenOf);
    for (final record in index.ofTypeNamed(recordType.id, member.name)) {
      if (work.targetOf(record) != target) continue;
      for (final entry in recordEntriesOf(record, recordType)) {
        if (entry.codePaths.isEmpty) continue;
        if (!_isLeftOut(index, items[entry.item], record)) return true;
      }
    }
  }
  return false;
}

/// Whether an entry of [record] for [item] counts no code: its story or FR is
/// skipped in the record's target, or it names no item of the feature.
///
/// The feature's own entry holds no code path, so it never gets here.
bool _isLeftOut(DocIndex index, IndexedDoc? item, IndexedDoc record) =>
    item == null ||
    index.itemStatus(item, codeTarget: record.target) == RecordStatus.skipped;

/// Returns the name of a target a finding names, or null when the project
/// holds one code target, so its output stays as it was.
String? _shownTargetName(CheckContext context, String? name) =>
    context.index.hasTwins ? name : null;

/// Returns the file line of each item's `statuses` line; an item with a second
/// line has none, as `check_record_entries` reports that line alone.
Map<String, int> _singleStatusLines(DocLines lines, String statusFieldId) {
  final found = <String, int>{};
  final repeated = <String>{};
  for (final (:value, :line, text: _) in lines.entriesOf(statusFieldId)) {
    if (value is! String) continue;
    final item = recordStatusLineOf(value)?.item;
    if (item == null) continue;
    if (found.containsKey(item)) repeated.add(item);
    found[item] = line;
  }
  return found..removeWhere((item, _) => repeated.contains(item));
}

/// Returns `implements_missing` for each entry of a record [doc] whose status
/// is `implemented` and that names no code path (`consistency_check/find_prd_spec_disagreements/check_implemented_status`).
///
/// An entry's status is its status in the record's own target (INV-29); an
/// entry no story or FR of the feature carries is `check_record_entries`'s.
Iterable<Finding> checkImplementedStatus(
  CheckContext context,
  IndexedDoc doc,
) sync* {
  final read = recordDocOf(context, doc);
  if (read == null) return;
  final (:type, :feature, :lines) = read;
  final statusField = recordStatusFieldOf(type);
  if (statusField == null) return;
  final index = context.index;
  final items = recordItemsOf(feature, index.childrenOf);
  final statusLines = _singleStatusLines(lines, statusField.id);
  final inTarget = switch (_shownTargetName(context, doc.target)) {
    final name? => ' in target $name',
    null => '',
  };
  for (final entry in recordEntriesOf(doc, type)) {
    final item = items[entry.item];
    final line = statusLines[entry.item];
    if (item == null ||
        line == null ||
        entry.status != RecordStatus.implemented ||
        entry.codePaths.isNotEmpty ||
        index.itemStatus(item, codeTarget: doc.target) !=
            RecordStatus.implemented) {
      continue;
    }
    yield context.finding(
      doc,
      FindingKind.implementsMissing,
      line: line,
      message: '${entry.item} is implemented$inTarget and names no code path',
    );
  }
}
