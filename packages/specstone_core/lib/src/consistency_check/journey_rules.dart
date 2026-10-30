import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/journeys/journey_steps.dart';
import 'package:specstone_core/src/journeys/step_scenarios.dart';

/// Returns the `journey_step_unresolved`, `journey_after_unresolved`, and
/// `journey_step_duplicate` findings of [doc].
///
/// Yields nothing unless [doc] is a journey whose type holds the `steps`
/// section (INV-2). Each finding sits on the line of the key it reports, else
/// on the step heading.
Iterable<Finding> checkJourneySteps(
  CheckContext context,
  IndexedDoc doc,
) sync* {
  if (doc.docTypeId != journeyTypeId ||
      !context.typeHoldsSection(journeyTypeId, stepsSectionId)) {
    return;
  }
  final section = context.heldIndexOf(doc, stepsSectionId);
  if (section == null) return;
  final body = context.bodyLinesOf(doc, section);
  int lineOf(int bodyIndex) => body[bodyIndex].line;

  final steps = stepsOfIndexed(context.index, doc);
  for (final step in steps.steps) {
    if (_resolves(context, step)) continue;
    final value = step.stepValue;
    yield context.finding(
      doc,
      FindingKind.journeyStepUnresolved,
      line: lineOf(step.stepIndex ?? step.headingIndex),
      message: value == null
          ? 'the step has no step: line'
          : 'step: $value names no scenario a story holds',
      keys: {'step': value ?? ''},
    );
  }
  for (final i in steps.unresolvedAfterIndexes) {
    final step = steps.steps[i];
    yield context.finding(
      doc,
      FindingKind.journeyAfterUnresolved,
      line: lineOf(step.afterIndex!),
      message: 'after: ${step.afterValue} names no step written above it',
      keys: {'after': step.afterValue!},
    );
  }
  for (final i in steps.duplicateIndexes) {
    final step = steps.steps[i];
    yield context.finding(
      doc,
      FindingKind.journeyStepDuplicate,
      line: lineOf(step.headingIndex),
      message: 'step number ${step.number} is carried by a step above',
      keys: {'number': step.number},
    );
  }
}

bool _resolves(CheckContext context, JourneyStep step) {
  final target = step.target;
  return target != null && scenarioBlockOf(context.index, target) != null;
}
