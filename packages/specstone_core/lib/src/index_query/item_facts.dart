import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_items.dart';
import 'package:specstone_core/src/doc_model/markdown_lines.dart'
    show itemHeadingMarker;
import 'package:specstone_core/src/doc_model/reference_grammar.dart';
import 'package:specstone_core/src/doc_model/text_scan.dart';
import 'package:specstone_core/src/index_query/held_sections.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart'
    show indexedSectionsOf;
import 'package:specstone_core/src/index_query/line_facts.dart';
import 'package:specstone_core/src/index_query/section_counts.dart'
    show SectionCounts;
import 'package:specstone_core/src/rendering/formatter.dart' show Formatted;
import 'package:specstone_core/src/templates/merged_doc_type.dart';

/// One item of a doc: the key `check` holds it by when it reads one, its
/// first line, and its code points.
///
/// `line` and `chars` are those of the text the doc's counts cover.
typedef ItemFact = ({String? id, int line, int chars});

/// The items of one doc, the lead's included, as the index stores them.
final class ItemFacts {
  const new({
    required this.lead,
    required this.leadItems,
    required this.sectionItems,
  });

  /// Reads the facts [toJson] wrote.
  factory fromJson(Object? json) {
    final map = json! as Map<String, Object?>;
    final lead = map['lead'] as List<Object?>?;
    return ItemFacts(
      lead: lead == null
          ? null
          : (lines: lead[0]! as int, chars: lead[1]! as int),
      leadItems: _itemsOfJson(map['lead_items']),
      sectionItems: [
        for (final items in map['sections']! as List<Object?>)
          _itemsOfJson(items),
      ],
    );
  }

  /// The lines and code points of the lead; null when the lead holds no text.
  final SectionCounts? lead;

  /// The items of the lead, in order.
  final List<ItemFact> leadItems;

  /// The items of each section, one list per `DocContent.sections` entry, in
  /// the same order.
  final List<List<ItemFact>> sectionItems;

  /// Returns the facts as JSON values, each item one `[id, line, chars]`
  /// array.
  Object toJson() => {
    'lead': switch (lead) {
      final counts? => [counts.lines, counts.chars],
      null => null,
    },
    'lead_items': _itemsToJson(leadItems),
    'sections': [for (final items in sectionItems) _itemsToJson(items)],
  };
}

/// Returns the items of [doc], the file's parse, in the text its counts cover.
///
/// [lineFacts] are those of [lfText]. The counts cover [laid]'s text when
/// [laid] is not null, else [lfText]; each section of [doc] takes the items of
/// its twin there, which [Formatted.twinOf] names.
ItemFacts itemFactsOf({
  required Doc doc,
  required String lfText,
  required LineFacts lineFacts,
  required Formatted? laid,
  required MergedDocType? type,
}) {
  final counted = laid?.doc ?? doc;
  final countedText = laid?.text ?? lfText;
  final lines = countedText == lfText
      ? lineFacts
      : LineFacts.structureOf(lfText: countedText, doc: counted);
  final held = indexedSectionsOf(counted, type);
  final templates = heldTemplatesOf(held, type);
  final (:counts, :items) = _leadOf(counted, countedText, lines);
  return ItemFacts(
    lead: counts,
    leadItems: items,
    sectionItems: [
      for (var i = 0; i < doc.sections.length; i++)
        _itemFactsIn(
          sectionBodyLines(held, lines, laid?.twinOf[i] ?? i),
          templates[laid?.twinOf[i] ?? i],
        ),
    ],
  );
}

/// Returns the lead of [doc]: its counts, from its first line of text to its
/// last with the line feeds between, and its items.
///
/// The counts are null when the lead holds no text.
({SectionCounts? counts, List<ItemFact> items}) _leadOf(
  Doc doc,
  String text,
  LineFacts lines,
) {
  final firstBodyLine = linesBeforeBodyOf(doc, text) + 1;
  final skip = switch (doc.titleLineIndex) {
    final at? => at + 1,
    null => 0,
  };
  final head = lfLinesOf(doc.head);
  final body = <BodyLine>[
    for (var k = skip; k < head.length; k++)
      (
        text: head[k],
        line: firstBodyLine + k,
        fenced: lines.isFenced(firstBodyLine + k),
      ),
  ];
  bool holdsText(BodyLine line) => line.text.trim().isNotEmpty;
  final first = body.indexWhere(holdsText);
  if (first < 0) return (counts: null, items: const []);
  final last = body.lastIndexWhere(holdsText);
  var chars = last - first;
  for (var k = first; k <= last; k++) {
    chars += _codePointsOf(body[k].text);
  }
  return (
    counts: (lines: last - first + 1, chars: chars),
    items: _itemFactsIn(body, null),
  );
}

int _codePointsOf(String text) => text.length - scanText(text).pairs;

List<ItemFact> _itemFactsIn(List<BodyLine> body, MergedSection? template) => [
  for (final item in itemsOf(body))
    (id: _itemIdOf(item, template), line: item.line, chars: item.chars),
];

/// Returns the key `check` holds [item] by, or null when it holds none.
///
/// A letter right after the digits makes no ID (RULE-12), so a lettered or
/// unreadable form holds none.
String? _itemIdOf(DocItem item, MergedSection? template) {
  if (item.heading && template?.id == acceptanceSectionId) {
    final scenario = readScenarioHeading('$itemHeadingMarker${item.text}');
    if (scenario is ItemId) return itemKeyOf(scenario, isScenario: true);
  }
  final prefix = template?.prefixId;
  if (prefix == null) return null;
  return switch (readItemId(item.text, prefix)) {
    final ItemId id => itemKeyOf(id, isScenario: false),
    _ => null,
  };
}

List<List<Object?>> _itemsToJson(List<ItemFact> items) => [
  for (final item in items) [item.id, item.line, item.chars],
];

List<ItemFact> _itemsOfJson(Object? json) => [
  for (final item in (json! as List<Object?>).cast<List<Object?>>())
    (id: item[0] as String?, line: item[1]! as int, chars: item[2]! as int),
];
