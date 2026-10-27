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
