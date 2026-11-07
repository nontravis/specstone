import 'dart:convert';

import 'package:specstone_core/src/consistency_check/item_id_rules.dart';
import 'package:specstone_core/src/consistency_check/scenario_blocks.dart';
import 'package:specstone_core/src/doc_model/doc_type_matcher.dart';
import 'package:specstone_core/src/doc_model/reference_grammar.dart';
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
const _statementPrefix = '- **Statement:**';

// MARK: - Types

/// One lettered ID of a doc and the number the renumber pass gives it.
typedef LetteredItem = ({String docPath, IdAt item, String from, String to});

/// A renumbering a reference names: the renumbered doc and its ID's change.
typedef Renumbering = ({String docPath, String from, String to});

/// The kinds of block a `confirmed` entry tracks.
enum TrackedBlockKind { scenario, nfrStatement, frStatement }

/// Returns the `S<N>` ref of the scenario ID [id], `Scenario <N>`; any other
/// ID as it is.
String scenarioRefOf(String id) {
  if (!id.startsWith(scenarioIdPrefix)) return id;
  return '$_scenarioRefPrefix${id.substring(scenarioIdPrefix.length)}';
}

// MARK: - RenumberDoc

/// One typed doc of the renumber pass, parsed once as `check` parses it.
final class RenumberDoc {
  new(this.docPath, this.lf, this.type)
    : parsed = parseIndexedDoc(
        docPath: docPath,
        bytes: utf8.encode(lf),
        match: MatchedDocType(type),
      );

  final String docPath;
  final String lf;
  final MergedDocType type;
  final ParsedDoc parsed;

  DocContent get content => parsed.content;

  String get name => parsed.doc.name;

  late final List<String> lines = lf.split('\n');

  late final List<IdAt> items = idsInDoc(content, type);

  /// The doc's lettered IDs, each with the next free number of its prefix,
  /// counted as `check`'s `item_id_lettered` counts it (R61).
  late final List<LetteredItem> lettered = _letteredOf();

  /// The `### Scenario <N>` blocks, keyed `S<N>`, as `check` reads them.
  late final Map<String, String> scenarioBlocks = _scenarioBlocksOf();

  bool get holdsScenarios =>
      type.sections.any((section) => section.id == acceptanceSectionId);

  /// The first unfenced `- **Statement:**` line of [item], trimmed, as
  /// `check` fingerprints an NFR; empty without one.
  String statementOf(IdAt item) {
    for (var line = item.line; line <= item.endLine; line++) {
      if (content.lineFacts.isFenced(line)) continue;
      final text = lines[line - 1].trim();
      if (text.startsWith(_statementPrefix)) return text;
    }
    return '';
  }

  /// The body of the held `statement` section, as `check` fingerprints an
  /// FR; null without one.
  String? get statementBody {
    final index = heldSectionIndex(content, type, statementSectionId);
    return index == null ? null : content.sections[index].body;
  }

  /// The text a link fingerprints of the block [key] of [kind]; empty when
  /// the doc holds none.
  String trackedText(TrackedBlockKind kind, String key) => switch (kind) {
    TrackedBlockKind.scenario => scenarioBlocks[key] ?? '',
    TrackedBlockKind.nfrStatement => _nfrStatementOf(key),
    TrackedBlockKind.frStatement => statementBody ?? '',
  };

  String _nfrStatementOf(String id) {
    final item = items.where((item) => item.id?.written == id).firstOrNull;
    return item == null ? '' : statementOf(item);
  }

  List<LetteredItem> _letteredOf() {
    final read = [
      for (final item in items)
        if (item.id case final id?) (item: item, id: id),
    ];
    final next = nextFreeIds([for (final entry in read) entry.id]);
    return [
      for (final (index, (:item, :id)) in read.indexed)
        if (id is LetteredId)
          if (next[index] case final to?)
            (docPath: docPath, item: item, from: id.written, to: to),
    ];
  }

  Map<String, String> _scenarioBlocksOf() {
    final index = heldSectionIndex(content, type, acceptanceSectionId);
    if (index == null) return const {};
    return scenarioBlocksIn(
      sectionBodyLines(content.sections, content.lineFacts, index),
    );
  }
}
