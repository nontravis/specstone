import 'package:specstone_core/src/consistency_check/item_id_rules.dart';
import 'package:specstone_core/src/consistency_check/models/heading_block.dart';
import 'package:specstone_core/src/consistency_check/models/id_at.dart';
import 'package:specstone_core/src/consistency_check/scenario_blocks.dart';
import 'package:specstone_core/src/doc_model/models/id_read.dart';
import 'package:specstone_core/src/doc_model/reference_grammar.dart';
import 'package:specstone_core/src/document_writing/move_item.dart'
    show positionWidthOf;
import 'package:specstone_core/src/document_writing/retired_ids.dart';
import 'package:specstone_core/src/index_query/held_sections.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';

// MARK: - Constants

/// Id of the doc type whose NFR Statements a `nf` link tracks.
const gnfrTypeId = 'gnfr';

/// Id of the doc type whose Statement an api FR trace link tracks.
const frTypeId = 'fr';

/// Id of the FR section an api FR trace link fingerprints.
const statementSectionId = 'statement';

const _scenarioRefPrefix = 'S';

// MARK: - Types

/// One item ID of a doc and the number the renumber pass gives it: a lettered
/// ID, or an edge case or scenario that moves to its position.
typedef LetteredItem = ({String docPath, IdAt item, String from, String to});

/// Returns the `S<N>` ref of the scenario ID [id], `Scenario <N>`; any other
/// ID as it is.
String scenarioRefOf(String id) {
  if (!id.startsWith(scenarioIdPrefix)) return id;
  return '$_scenarioRefPrefix${id.substring(scenarioIdPrefix.length)}';
}

/// Returns the key of the scenario block [number] names, by the value of its
/// digits: `S<value>`, and `S<value><letters>` for a lettered number.
String scenarioBlockKeyOf(IdRead number) => switch (number) {
  ItemId(:final number) => '$_scenarioRefPrefix$number',
  LetteredId(:final digits, :final letters) =>
    '$_scenarioRefPrefix${BigInt.parse(digits)}$letters',
  UnreadableId(:final written) => written,
};

/// Returns the block key of the scenario ID [id], `Scenario <N>`, as
/// [scenarioBlockKeyOf] names it; [id] itself for any other text.
String scenarioBlockKeyOfId(String id) =>
    switch (readItemIdAt(id, 0, scenarioIdPrefix)) {
      final number? => scenarioBlockKeyOf(number),
      null => id,
    };

// MARK: - RenumberDoc

/// One typed doc of the renumber pass, read for its structure only, as
/// `check` reads its items and blocks: no markdown parse runs.
final class RenumberDoc {
  new(this.docPath, this.lf, this.type) : name = docNameOf(docPath, type);

  final String docPath;
  final String lf;
  final MergedDocType type;

  /// The Name the index gives the doc.
  final String name;

  late final DocContent content = docStructureOf(lf, type);

  late final List<String> lines = lf.split('\n');

  late final List<IdAt> items = idsInDoc(content, type);

  /// The doc's renumbered IDs: each lettered ID with the next free number of
  /// its prefix, counted as `check`'s `item_id_lettered` counts it, and each
  /// edge case or scenario of a section holding a lettered one with its
  /// position.
  late final List<LetteredItem> lettered = _mayHoldLettered()
      ? _letteredOf()
      : const [];

  /// The `### Scenario <N>` blocks, keyed `S<N>` by value, as `check` reads
  /// them.
  late final Map<String, String> scenarioBlocks = _scenarioBlocksOf();

  /// The frontmatter lines with their delimiters; empty without any.
  late final String frontmatterText = content.frontmatterText ?? '';

  bool get holdsScenarios =>
      type.sections.any((section) => section.id == acceptanceSectionId);

  /// The first unfenced `- **Statement:**` line of [item], trimmed, as
  /// `check` fingerprints an NFR; empty without one.
  String statementOf(IdAt item) => nfrStatementOf([
    for (var line = item.line; line <= item.endLine; line++)
      BodyLine(
        text: lines[line - 1],
        line: line,
        fenced: content.lineFacts.isFenced(line),
      ),
  ]);

  /// The Statement of each NFR block of a gnfr doc's held sections with no
  /// `prefix_id`, keyed by the ID the grammar reads at its `###` heading, as
  /// `check` keys it; empty for any other doc.
  late final Map<String, String> unprefixedNfrStatements = type.id == gnfrTypeId
      ? _unprefixedNfrStatementsOf()
      : const {};

  /// The body of the held `statement` section, as `check` fingerprints an
  /// FR; null without one.
  String? get statementBody {
    final index = heldSectionIndex(content, type, statementSectionId);
    return index == null ? null : content.sections[index].body;
  }

  /// Whether [lf] holds a token the grammar reads as a lettered ID of a
  /// prefix the doc's items take; when not, no item is lettered, so its
  /// sections need no read.
  bool _mayHoldLettered() {
    final prefixes = {
      for (final section in type.sections) ?section.prefixId,
      if (holdsScenarios) scenarioIdPrefix,
    };
    for (final prefix in prefixes) {
      for (
        var at = lf.indexOf(prefix);
        at >= 0;
        at = lf.indexOf(prefix, at + 1)
      ) {
        if (readItemIdAt(lf, at, prefix) is LetteredId) return true;
      }
    }
    return false;
  }

  List<LetteredItem> _letteredOf() {
    final read = [
      for (final item in items)
        if (item.id case final id?) (item: item, id: id),
    ];
    final next = nextFreeIds([
      for (final entry in read) entry.id,
    ], retired: RetiredIds.readFrom(lf).ids);
    final positions = _positionNumbers();
    final renumbered = <LetteredItem>[];
    for (final (index, (:item, :id)) in read.indexed) {
      final to = isPositionalPrefix(id.prefix) ? positions[item] : next[index];
      if (to == null) continue;
      renumbered.add((docPath: docPath, item: item, from: id.written, to: to));
    }
    return renumbered;
  }

  /// The new number of each edge case or scenario that moves to its position
  /// in a section holding a lettered one, keyed by item.
  Map<IdAt, String> _positionNumbers() {
    final sections = <String, List<IdAt>>{};
    for (final item in items) {
      if (isPositionalPrefix(item.prefix)) {
        (sections[item.sectionKey] ??= []).add(item);
      }
    }
    final numbers = <IdAt, String>{};
    for (final held in sections.values) {
      if (held.any((item) => item.id is LetteredId)) {
        numbers.addAll(_sectionPositions(held));
      }
    }
    return numbers;
  }

  /// The new number of each item of [held], one section's edge cases or
  /// scenarios, that differs from its position.
  Map<IdAt, String> _sectionPositions(List<IdAt> held) {
    final width = positionWidthOf(held.first.prefix, [
      for (final item in held) item.id,
    ]);
    final numbers = <IdAt, String>{};
    for (final (index, item) in held.indexed) {
      final position = BigInt.from(index + 1);
      final moves = switch (item.id) {
        LetteredId() => true,
        ItemId(:final number) => number != position,
        _ => false,
      };
      if (!moves) continue;
      numbers[item] =
          '${item.prefix}${position.toString().padLeft(width, '0')}';
    }
    return numbers;
  }

  Map<String, String> _unprefixedNfrStatementsOf() {
    final statements = <String, String>{};
    for (final (i, template) in heldTemplatesOf(
      content.sections,
      type,
    ).indexed) {
      if (template == null || template.prefixId != null) continue;
      final body = sectionBodyLines(content.sections, content.lineFacts, i);
      for (final HeadingBlock(:key, :lines) in headingBlocksOf(
        body,
        (heading) => itemHeadingKeyOf(heading, null),
      )) {
        statements.putIfAbsent(key, () => nfrStatementOf(lines));
      }
    }
    return statements;
  }

  Map<String, String> _scenarioBlocksOf() {
    final index = heldSectionIndex(content, type, acceptanceSectionId);
    if (index == null) return const {};
    return scenarioBlocksIn(
      sectionBodyLines(content.sections, content.lineFacts, index),
    );
  }
}
