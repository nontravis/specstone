import 'package:specstone_core/src/consistency_check/scenario_blocks.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/journeys/journey_steps.dart';

const _storyType = 'user_story';

/// Returns the `user_story` doc whose Name is [identity], or null.
IndexedDoc? storyNamed(DocIndex index, String identity) => index.docs
    .where((doc) => doc.docTypeId == _storyType && doc.name == identity)
    .firstOrNull;

/// Returns the scenario block [target] names, heading line included.
///
/// Null when no story carries the identity or the story holds no such
/// scenario.
String? scenarioBlockOf(DocIndex index, StepTarget target) {
  final story = storyNamed(index, target.identity);
  if (story == null) return null;
  return storyScenarioBlocks(index, story)[target.scenarioLabel];
}

/// Returns the lines of [block] after its heading line.
String scenarioCopyOf(String block) {
  final newline = block.indexOf('\n');
  return newline < 0 ? '' : block.substring(newline + 1);
}

/// Reads the steps of the indexed [journey].
///
/// Empty when its doc type holds no `steps` section.
JourneySteps stepsOfIndexed(DocIndex index, IndexedDoc journey) {
  final type = index.typeOf(journey);
  final content = index.contentOf(journey);
  final section = heldSectionIndex(content, type, stepsSectionId);
  return readJourneySteps(
    section == null ? '' : content.sections[section].body,
    blockKinds: type?.listedGenerators.toSet() ?? const {},
  );
}
