import 'package:specstone_core/src/doc_model/doc_items.dart';
import 'package:specstone_core/src/doc_model/reference_grammar.dart';
import 'package:specstone_core/src/document_writing/move_item.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/item_facts.dart'
    show itemKeyOfHead, sectionItemsAt;
import 'package:specstone_core/src/index_query/item_links.dart'
    show citedSectionsOf;

// MARK: - Scenario IDs

/// The prefix of a scenario's ID in an address: `S2` names Scenario 2.
const _refPrefix = 'S';

const _travelHint = 'move both in one call';

/// Whether [id] names a scenario: `S` and digits, as `S2`.
bool isScenarioId(String id) => switch (readItemId(id, _refPrefix)) {
  final ItemId read => read.written == id,
  _ => false,
};

/// Returns the scenario ID [id] by its number's value: `S02` reads `S2`.
String scenarioIdByValue(String id) => switch (readItemId(id, _refPrefix)) {
  ItemId(:final number) => '$_refPrefix$number',
  _ => throw ArgumentError.value(id, 'id', 'names no scenario'),
};

/// Returns the key the index holds the scenario [id] by: `Scenario <N>`, by
/// the number's value.
String scenarioKeyOfId(String id) => switch (readItemId(id, _refPrefix)) {
  ItemId(:final digits) => itemKeyOf(
    ItemId(prefix: scenarioIdPrefix, digits: digits),
    isScenario: true,
  ),
  _ => throw ArgumentError.value(id, 'id', 'names no scenario'),
};

/// Returns the scenario [target] names in its story's acceptance criteria.
///
/// Throws `WriteFault` `item_not_found` when the story holds no such scenario.
LocatedItem locateScenario(DocIndex index, ItemTarget target) {
  final content = index.contentOf(target.doc);
  final sections = citedSectionsOf(content, index.typeOf(target.doc));
  final key = scenarioKeyOfId(target.id);
  for (final (at, section) in sections.indexed) {
    if (!section.isAcceptanceCriteria) continue;
    final holds = content.itemFacts.sectionItems[at].any(
      (fact) => fact.id == key,
    );
    if (holds) {
      return LocatedItem(target, at, section.key, _refPrefix, isScenario: true);
    }
  }
  throw itemNotFoundOf(target);
}

/// Returns the scenario numbers [story]'s acceptance criteria holds, as `S`
/// IDs in file order; none when it lacks the section.
List<IdRead> scenarioIdsIn(DocIndex index, IndexedDoc story) {
  final content = index.contentOf(story);
  final type = index.typeOf(story);
  final at = citedSectionsOf(
    content,
    type,
  ).indexWhere((section) => section.isAcceptanceCriteria);
  if (at < 0) return [];
  return [
    for (final item in sectionItemsAt(content, at, type))
      if (item.kind == SectionItemKind.heading) ?_refOf(item.head),
  ];
}

/// Reads the number of the scenario heading whose text after `### ` is
/// [head] as an `S` ID by its value; null for any other heading.
IdRead? _refOf(String head) => switch (readScenarioHead(head)) {
  ItemId(:final number) => ItemId(prefix: _refPrefix, digits: '$number'),
  LetteredId(:final digits, :final letters) => LetteredId(
    prefix: _refPrefix,
    digits: digits,
    letters: letters,
  ),
  _ => null,
};

// MARK: - Landing

/// Returns the scenario heading line [raw] as [landing] lands it: numbered as
/// its new ID when that changed, and each ID [renamed] holds set to its new
/// ID.
///
/// - [renamed]: new IDs by old ID, of the items of the scenario's own story
///   that the call renumbers.
String landedScenarioHeading(
  String raw,
  ItemLanding landing,
  Map<String, String> renamed,
) {
  final head = headingItemTextOf(raw);
  final number = head == null ? null : readScenarioHead(head);
  if (head == null || number == null) {
    throw StateError('$raw is no scenario heading');
  }
  // The head is the tail of [raw], after any `>` marks and the `### `.
  final at = raw.length - head.length + scenarioIdPrefix.length;
  final numbered = landing.newId == landing.from.id
      ? raw
      : raw.replaceRange(
          at,
          at + number.digits.length,
          landing.newId.substring(_refPrefix.length),
        );
  return _withIds(numbered, renamed);
}

String _withIds(String text, Map<String, String> renamed) {
  if (renamed.isEmpty) return text;
  final prefixes = {
    for (final id in renamed.keys) ?readItemIdOfWrittenPrefix(id)?.prefix,
  };
  var result = text;
  for (final found in itemIdsInProse(text, prefixes: prefixes).reversed) {
    final to = renamed[found.id.written];
    if (to == null) continue;
    result = result.replaceRange(
      found.at,
      found.at + found.id.written.length,
      to,
    );
  }
  return result;
}

// MARK: - Rule refusal

/// A scenario title of a story: its key and the item IDs of its story it
/// names.
final class _Title {
  const new(this.key, this.names);

  /// The key the index holds the scenario by, `Scenario <N>`.
  final String key;
  final List<String> names;
}

/// Refuses a move that parts a scenario title from an item of its story it
/// names, such as `(BR-02)`.
///
/// Throws [IndexFault] `argument_invalid` naming the item and the scenario,
/// for a scenario of [moving] whose named item stays and for an item of
/// [moving] that a staying scenario's title names, in the order given.
void requireRulesTravel(DocIndex index, List<LocatedItem> moving) {
  final moved = {for (final item in moving) _keyOf(item.target.doc, item)};
  final titles = <String, List<_Title>>{};
  for (final item in moving) {
    final story = item.target.doc;
    final held = titles.putIfAbsent(
      story.docPath,
      () => _titlesOf(index, story),
    );
    for (final title in held) {
      final fault = item.isScenario
          ? _scenarioParted(story, item, title, moved)
          : _itemParted(story, item, title, moved);
      if (fault != null) throw fault;
    }
  }
}

String _keyOf(IndexedDoc doc, LocatedItem item) =>
    '${doc.docPath}#${item.heldAs}';

IndexFault? _scenarioParted(
  IndexedDoc story,
  LocatedItem scenario,
  _Title title,
  Set<String> moved,
) {
  if (title.key != scenario.heldAs) return null;
  for (final name in title.names) {
    if (moved.contains('${story.docPath}#$name')) continue;
    return IndexFault(
      IndexFaultCode.argumentInvalid,
      '${story.name}#${scenario.target.id} names $name, which stays; '
      '$_travelHint',
    );
  }
  return null;
}

IndexFault? _itemParted(
  IndexedDoc story,
  LocatedItem item,
  _Title title,
  Set<String> moved,
) {
  final id = item.target.id;
  if (!title.names.contains(id) ||
      moved.contains('${story.docPath}#${title.key}')) {
    return null;
  }
  return IndexFault(
    IndexFaultCode.argumentInvalid,
    '${story.name}#$id is named by ${title.key}, which stays; $_travelHint',
  );
}

/// Returns the scenario titles of [story], each with the IDs it names that
/// the items of [story] hold; none for a doc with no acceptance criteria.
List<_Title> _titlesOf(DocIndex index, IndexedDoc story) {
  final content = index.contentOf(story);
  final type = index.typeOf(story);
  final sections = citedSectionsOf(content, type);
  final at = sections.indexWhere((section) => section.isAcceptanceCriteria);
  if (at < 0) return const [];
  final prefixes = {for (final section in sections) ?section.prefixId};
  final held = {
    for (final (k, section) in sections.indexed)
      if (section.prefixId != null)
        for (final fact in content.itemFacts.sectionItems[k]) ?fact.id,
  };
  return [
    for (final item in sectionItemsAt(content, at, type))
      if (_scenarioKeyOf(item) case final key?)
        _Title(key, [
          for (final found in itemIdsInProse(item.head, prefixes: prefixes))
            if (held.contains(found.id.written)) found.id.written,
        ]),
  ];
}

String? _scenarioKeyOf(SectionItem item) => item.kind == SectionItemKind.heading
    ? itemKeyOfHead(
        item.head,
        isHeading: true,
        prefixId: null,
        isAcceptanceCriteria: true,
      )
    : null;
