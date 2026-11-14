import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_items.dart';
import 'package:specstone_core/src/doc_model/markdown_lines.dart'
    show itemHeadingMarker;
import 'package:specstone_core/src/doc_model/reference_grammar.dart';
import 'package:specstone_core/src/doc_model/text_scan.dart';
import 'package:specstone_core/src/index_query/held_sections.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart'
    show IndexedSection, indexedSectionsOf;
import 'package:specstone_core/src/index_query/item_words.dart';
import 'package:specstone_core/src/index_query/line_facts.dart';
import 'package:specstone_core/src/index_query/section_counts.dart'
    show SectionCounts;
import 'package:specstone_core/src/rendering/formatter.dart' show Formatted;
import 'package:specstone_core/src/rendering/generated_blocks.dart'
    show generatedBlockLines;
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
  final isGenerated = generatedLineTest(
    counted,
    countedText,
    type?.listedGenerators.toSet() ?? const {},
  );
  final (:counts, :items) = _leadOf(counted, countedText, lines, isGenerated);
  return ItemFacts(
    lead: counts,
    leadItems: items,
    sectionItems: [
      for (var i = 0; i < doc.sections.length; i++)
        _itemFactsIn(
          withGeneratedFenced(
            sectionBodyLines(held, lines, laid?.twinOf[i] ?? i),
            isGenerated,
          ),
          templates[laid?.twinOf[i] ?? i],
        ),
    ],
  );
}

/// Returns the items of the rule-bearing sections of [doc], a typed doc of
/// [type] parsed from [lfText], each as [RuleItemWords], in file order.
///
/// [sections] are the held sections of [doc] and [lineFacts] its facts, so
/// each line is a line of the file. Fenced code, a generated block, and an
/// HTML comment hold no item; see [wordsOfItem] for the items left out.
List<RuleItemWords> ruleItemWordsOf({
  required Doc doc,
  required String lfText,
  required List<IndexedSection> sections,
  required LineFacts lineFacts,
  required MergedDocType type,
  required Set<String> idPrefixes,
}) {
  final templates = heldTemplatesOf(sections, type);
  final definitions = definitionLinesOf(doc.afterFrontmatter);
  final isGenerated = generatedLineTest(
    doc,
    lfText,
    type.listedGenerators.toSet(),
  );
  return [
    for (var i = 0; i < sections.length; i++)
      if (ruleBearingSectionKeys.contains(sections[i].key))
        for (final item in sectionItemsOf(
          withCommentsBlanked(
            withGeneratedFenced(
              sectionBodyLines(sections, lineFacts, i),
              isGenerated,
            ),
          ),
        ))
          ?wordsOfItem(
            item,
            templates[i]?.prefixId,
            idPrefixes: idPrefixes,
            definitions: definitions,
          ),
  ];
}

/// Returns a test of whether a file line of [text] is a marker line or inner
/// line of a closed generated block of one of [kinds].
///
/// The block finder `format` protects blocks with; no generator runs, so the
/// lines are those on disk.
bool Function(int line) generatedLineTest(
  Doc doc,
  String text,
  Set<String> kinds,
) {
  if (kinds.isEmpty) return (_) => false;
  final first = linesBeforeBodyOf(doc, text) + 1;
  final marked = generatedBlockLines(lfLinesOf(doc.afterFrontmatter), kinds);
  return (line) {
    final at = line - first;
    return at >= 0 && at < marked.length && marked[at];
  };
}

/// Returns [body] with each line [isGenerated] marks fenced, so it is no item
/// and still a line of its section.
List<BodyLine> withGeneratedFenced(
  List<BodyLine> body,
  bool Function(int line) isGenerated,
) => [
  for (final line in body)
    (
      text: line.text,
      line: line.line,
      fenced: line.fenced || isGenerated(line.line),
    ),
];

/// Returns the lead of [doc]: its counts, from its first line of text to its
/// last with the line feeds between, and its items.
///
/// The counts are null when the lead holds no text.
({SectionCounts? counts, List<ItemFact> items}) _leadOf(
  Doc doc,
  String text,
  LineFacts lines,
  bool Function(int line) isGenerated,
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
        fenced:
            lines.isFenced(firstBodyLine + k) || isGenerated(firstBodyLine + k),
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
String? _itemIdOf(DocItem item, MergedSection? template) => itemKeyOfHead(
  item.text,
  isHeading: item.heading,
  prefixId: template?.prefixId,
  isAcceptanceCriteria: template?.id == acceptanceSectionId,
);

/// Returns the key `check` holds an item by, read from its [head] (the
/// item's first line after any marker), or null when it holds none.
///
/// The one reader of an item's ID: a `### Scenario <N>` heading of an
/// `acceptance_criteria` section keys by the number's value; any other item
/// keys by the ID of [prefixId] at its start, as RULE-19 reads it.
String? itemKeyOfHead(
  String head, {
  required bool isHeading,
  required String? prefixId,
  required bool isAcceptanceCriteria,
}) {
  if (isHeading && isAcceptanceCriteria) {
    final scenario = readScenarioHeading('$itemHeadingMarker$head');
    if (scenario is ItemId) return itemKeyOf(scenario, isScenario: true);
  }
  if (prefixId == null) return null;
  return switch (readItemId(head, prefixId)) {
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
