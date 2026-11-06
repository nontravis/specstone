import 'package:specstone_core/src/doc_model/reference_grammar.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/held_sections.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';

export 'package:specstone_core/src/index_query/held_sections.dart'
    show BodyLine;

/// Id of the story section that holds the scenarios.
const acceptanceSectionId = 'acceptance_criteria';
const _subHeadingMarker = '###';
const _deeperHeadingMarker = '####';
const _itemHeadingMarker = '### ';

// MARK: - Held sections

/// Returns the index of the first held section of [content] that maps to
/// [sectionId], or null.
int? heldSectionIndex(
  DocContent content,
  MergedDocType? type,
  String sectionId,
) => heldSectionIndexIn(heldTemplatesOf(content.sections, type), sectionId);

/// Returns the index of the first entry of [templates], as
/// [heldTemplatesOf] returns them, that has the id [sectionId], or null.
int? heldSectionIndexIn(List<MergedSection?> templates, String sectionId) {
  final index = templates.indexWhere((template) => template?.id == sectionId);
  return index < 0 ? null : index;
}

// MARK: - Blocks

/// Returns the text after the `### ` of [line], or null for any other line.
String? itemHeadingTextOf(String line) => line.startsWith(_itemHeadingMarker)
    ? line.substring(_itemHeadingMarker.length)
    : null;

/// Whether [line] opens a `###` heading (not a deeper one).
bool isSubHeading(String line) =>
    line.startsWith(_subHeadingMarker) &&
    !line.startsWith(_deeperHeadingMarker);

/// Splits [body] into the `###` blocks that [keyOf] names.
///
/// A block runs from its heading line to the next `###` line outside fenced
/// code, or the end of [body]. [keyOf] names a block from its heading line;
/// null opens no block and closes the one above.
List<({String key, List<BodyLine> lines})> headingBlocksOf(
  List<BodyLine> body,
  String? Function(String heading) keyOf,
) {
  final blocks = <({String key, List<BodyLine> lines})>[];
  String? key;
  var lines = <BodyLine>[];
  void close() {
    if (key case final closed?) blocks.add((key: closed, lines: lines));
  }

  for (final line in body) {
    if (line.fenced || !isSubHeading(line.text)) {
      lines.add(line);
      continue;
    }
    close();
    key = keyOf(line.text);
    lines = [line];
  }
  close();
  return blocks;
}

/// Returns the `### Scenario <N>` blocks of [body], keyed `S<N>`.
///
/// The first block of a repeated number wins. A heading whose number a
/// letter follows keys no block and ends the one above.
Map<String, String> scenarioBlocksIn(List<BodyLine> body) {
  final blocks = <String, String>{};
  for (final (:key, :lines) in headingBlocksOf(body, _scenarioKeyOf)) {
    blocks.putIfAbsent(key, () => _blockText(lines));
  }
  return blocks;
}

/// Returns the `### Scenario <N>` blocks of [story], keyed `S<N>`.
///
/// Reads the `acceptance_criteria` section; empty when [story] holds none.
Map<String, String> storyScenarioBlocks(DocIndex index, IndexedDoc story) {
  final content = index.contentOf(story);
  final section = heldSectionIndex(
    content,
    index.typeOf(story),
    acceptanceSectionId,
  );
  if (section == null) return const {};
  return scenarioBlocksIn(
    sectionBodyLines(content.sections, content.lineFacts, section),
  );
}

String? _scenarioKeyOf(String heading) =>
    switch (readScenarioHeading(heading)) {
      ItemId(:final digits) => 'S$digits',
      _ => null,
    };

String _blockText(List<BodyLine> lines) =>
    lines.map((line) => line.text).join('\n').trimRight();
