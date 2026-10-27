import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';

const _frType = 'fr';
const _nfType = 'nf';
const _tracedFromKey = 'traced_from';
const _kindKey = 'kind';
const _overridesKey = 'overrides';
const _selfDerived = 'self-derived';
const _tighten = 'tighten';
const _relax = 'relax';
const _add = 'add';
const _personaType = 'persona';
const _storyType = 'user_story';
const _roleKey = 'role';
const _idKey = 'id';
const _asAPrefix = '- **As a** ';
const _whoSeparator = ' who ';
const _storyVisionKeys = ['vision', 'goals'];

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
  if (story == null) return;
  final scenarios = context.scenarioBlocksOf(story);
  final line = context.linesOf(doc).keyLine(_tracedFromKey);
  if (line == null) return;
  for (final entry in doc.valuesOf(_tracedFromKey)) {
    if (entry == _selfDerived || scenarios.containsKey(entry)) continue;
    yield context.finding(
      doc,
      FindingKind.scenarioTraceUnresolved,
      line: line,
      message: '$entry is no scenario of the story and not $_selfDerived',
      keys: {'entry': entry},
    );
  }
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
/// A `persona` or `user_story` role names a Role entry of a `project` doc; a
/// story's `vision:` and `goals:` IDs sit in its feature and a project
/// heading. The rule runs only when the merged set holds `project`.
Iterable<Finding> checkRolesAndGoals(
  CheckContext context,
  IndexedDoc doc,
) sync* {
  if (!context.hasProject) return;
  switch (doc.docTypeId) {
    case _personaType:
      yield* _personaRole(context, doc);
    case _storyType:
      yield* _storyRole(context, doc);
      yield* _storyGoalSets(context, doc);
  }
}

Iterable<Finding> _personaRole(CheckContext context, IndexedDoc doc) sync* {
  final role = doc.valuesOf(_roleKey).firstOrNull;
  final line = context.linesOf(doc).keyLine(_roleKey);
  if (role == null || line == null) return;
  yield* _unresolvedRole(context, doc, role, line);
}

Iterable<Finding> _storyRole(CheckContext context, IndexedDoc doc) sync* {
  final lines = context.linesOf(doc).lines;
  final index = lines.indexWhere((line) => line.startsWith(_asAPrefix));
  if (index < 0) return;
  final text = lines[index].substring(_asAPrefix.length);
  final who = text.indexOf(_whoSeparator);
  final role = (who < 0 ? text : text.substring(0, who)).trim();
  yield* _unresolvedRole(context, doc, role, index + 1);
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

Iterable<Finding> _storyGoalSets(CheckContext context, IndexedDoc doc) sync* {
  final feature = context.index.parentOf(doc);
  for (final key in _storyVisionKeys) {
    final line = context.linesOf(doc).keyLine(key);
    if (line == null) continue;
    final held = feature?.valuesOf(key).toSet();
    for (final id in doc.valuesOf(key)) {
      if (!context.projectHeadingIds().contains(id)) {
        yield context.finding(
          doc,
          FindingKind.visionGoalUnresolved,
          line: line,
          message: '$id is no heading of the project',
          keys: {_idKey: id},
        );
      }
      if (held != null && !held.contains(id)) {
        yield context.finding(
          doc,
          FindingKind.visionGoalWidened,
          line: line,
          message: '$id is not in the $key of the feature',
          keys: {_idKey: id},
        );
      }
    }
  }
}
