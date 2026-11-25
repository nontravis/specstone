import 'package:specstone_core/src/consistency_check/scenario_blocks.dart';
import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/reference_grammar.dart';
import 'package:specstone_core/src/document_writing/rewrite_refs.dart'
    show rebaseDocLinks;
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/journeys/journey_steps.dart';
import 'package:specstone_core/src/rendering/generated_blocks.dart';
import 'package:specstone_core/src/rendering/layout.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';

const _storyType = 'user_story';

/// Returns the first `user_story` doc in tree order whose Name is [identity],
/// or null; among [codeTarget]'s docs and the shared docs when [codeTarget]
/// is given, among every target's docs without it.
IndexedDoc? storyNamed(DocIndex index, String identity, {String? codeTarget}) {
  final docs = index
      .ofTypeNamed(_storyType, identity)
      .where((doc) => doc.inTarget(codeTarget));
  return docs.firstOrNull;
}

/// Returns the story an `fr` under [ownStory] traces through [ref].
///
/// [ownStory] for an own-story ref; else the story Named by [ref] when it
/// shares the feature of [ownStory] (a story with no feature doc has no
/// siblings); null for a story of another feature or
/// of no doc.
IndexedDoc? tracedStoryOf(
  DocIndex index,
  IndexedDoc ownStory,
  ScenarioRef ref,
) {
  final name = ref.storyName;
  if (name == null) return ownStory;
  final story = storyNamed(index, name);
  if (story == null) return null;
  final feature = ownStory.parentPath;
  return feature != null && story.parentPath == feature ? story : null;
}

/// Returns the scenario block [target] names, heading line included.
///
/// Null when no story carries the identity or the story holds no such
/// scenario; the story is sought among [codeTarget]'s docs and the shared
/// docs when given.
String? scenarioBlockOf(
  DocIndex index,
  StepTarget target, {
  String? codeTarget,
}) {
  final story = storyNamed(index, target.identity, codeTarget: codeTarget);
  if (story == null) return null;
  return storyScenarioBlocks(index, story)[target.scenarioLabel];
}

/// Returns the copy of the scenario [target] names for the journey at
/// [journeyPath], or null when [scenarioBlockOf] finds no block.
///
/// Holds [scenarioCopyOf]'s lines, each relative link rewritten to reach from
/// the journey's folder what it reaches from the story.
String? scenarioCopyFor(
  DocIndex index,
  StepTarget target, {
  required String journeyPath,
  String? codeTarget,
}) {
  final story = storyNamed(index, target.identity, codeTarget: codeTarget);
  if (story == null) return null;
  final block = storyScenarioBlocks(index, story)[target.scenarioLabel];
  if (block == null) return null;
  return rebaseDocLinks(
    scenarioCopyOf(block),
    fromDocPath: story.docPath,
    toDocPath: journeyPath,
  );
}

/// Returns the lines of [block] after its heading line, in the format layout.
///
/// Leaves out the blank line under the heading and the whitespace at the end,
/// as the fingerprint reads the block.
String scenarioCopyOf(String block) {
  final newline = block.indexOf('\n');
  if (newline < 0) return '';
  final laidOut = layOutText(block.substring(newline + 1), underHeading: true);
  final withoutGap = laidOut.startsWith('\n') ? laidOut.substring(1) : laidOut;
  return withoutGap.trimRight();
}

/// Reads the steps of the journey [doc], parsed against [docType].
///
/// Empty when [docType] holds no `steps` section or [doc] lacks its header.
JourneySteps stepsOfDoc(Doc doc, MergedDocType docType) {
  final section = sectionIndexOf(doc, docType, stepsSectionId);
  return readJourneySteps(
    section == null ? '' : doc.sections[section].body,
    blockKinds: docType.listedGenerators.toSet(),
  );
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
