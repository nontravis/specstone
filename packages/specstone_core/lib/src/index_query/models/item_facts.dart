import 'package:specstone_core/src/doc_model/models/trace_note.dart';
import 'package:specstone_core/src/index_query/models/field_fact.dart';
import 'package:specstone_core/src/index_query/models/item_fact.dart';
import 'package:specstone_core/src/index_query/models/readability_facts.dart';
import 'package:specstone_core/src/index_query/models/section_counts.dart';
import 'package:specstone_core/src/index_query/models/sentence_fact.dart';

/// The items of one doc, the lead's included, as the index stores them.
final class ItemFacts {
  const new({
    required this.lead,
    required this.leadItems,
    required this.sectionItems,
    required this.fieldItems,
  });

  /// Reads the facts [toJson] wrote.
  factory fromJson(Object? json) {
    final map = json! as Map<String, Object?>;
    final lead = map['lead'] as List<Object?>?;
    return ItemFacts(
      lead: lead == null
          ? null
          : SectionCounts(lines: lead[0]! as int, chars: lead[1]! as int),
      leadItems: _itemsOfJson(map['lead_items']),
      sectionItems: [
        for (final items in map['sections']! as List<Object?>)
          _itemsOfJson(items),
      ],
      fieldItems: {
        for (final MapEntry(:key, :value)
            in (map['fields']! as Map<String, Object?>).entries)
          key: FieldFact(
            readability: _readabilityOfJson(value! as List<Object?>),
          ),
      },
    );
  }

  /// The lines and code points of the lead; null when the lead holds no text.
  final SectionCounts? lead;

  /// The items of the lead, in order.
  final List<ItemFact> leadItems;

  /// The items of each section, one list per `DocContent.sections` entry, in
  /// the same order.
  final List<List<ItemFact>> sectionItems;

  /// The facts of each prose field whose value is a string, by field id.
  ///
  /// A field with no string value holds none, and no item count covers one.
  final Map<String, FieldFact> fieldItems;

  /// Returns the facts as JSON values, each item one
  /// `[id, line, visibleChars, cells, notes]` array and each field one
  /// `[cells, notes]` array.
  Object toJson() => {
    'lead': switch (lead) {
      final counts? => [counts.lines, counts.chars],
      null => null,
    },
    'lead_items': _itemsToJson(leadItems),
    'sections': [for (final items in sectionItems) _itemsToJson(items)],
    'fields': {
      for (final MapEntry(:key, :value) in fieldItems.entries)
        key: [
          _cellsToJson(value.readability.cells),
          _notesToJson(value.readability.notes),
        ],
    },
  };
}

List<List<Object?>> _itemsToJson(List<ItemFact> items) => [
  for (final item in items)
    [
      item.id,
      item.line,
      item.visibleChars,
      _cellsToJson(item.readability.cells),
      _notesToJson(item.readability.notes),
    ],
];

List<Object?> _cellsToJson(List<List<SentenceFact>> cells) => [
  for (final cell in cells)
    [
      for (final s in cell)
        [s.language, s.countsChars, s.words, s.chars, s.runs, s.isHeading],
    ],
];

List<Object?> _notesToJson(List<TraceNote> notes) => [
  for (final note in notes) [note.text, note.closes],
];

List<ItemFact> _itemsOfJson(Object? json) => [
  for (final item in (json! as List<Object?>).cast<List<Object?>>())
    ItemFact(
      id: item[0] as String?,
      line: item[1]! as int,
      visibleChars: item[2]! as int,
      readability: _readabilityOfJson(item.sublist(3)),
    ),
];

/// Reads the `[cells, notes]` pair [_cellsToJson] and [_notesToJson] wrote.
ReadabilityFacts _readabilityOfJson(List<Object?> json) => ReadabilityFacts(
  cells: [
    for (final cell in (json[0]! as List<Object?>).cast<List<Object?>>())
      [
        for (final s in cell.cast<List<Object?>>())
          SentenceFact(
            language: s[0]! as String,
            countsChars: s[1]! as bool,
            words: s[2]! as int,
            chars: s[3]! as int,
            runs: s[4]! as int,
            isHeading: s[5]! as bool,
          ),
      ],
  ],
  notes: [
    for (final note in (json[1]! as List<Object?>).cast<List<Object?>>())
      TraceNote(text: note[0]! as String, closes: note[1]! as bool),
  ],
);
