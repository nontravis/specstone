import 'package:specstone_core/src/doc_model/check_sentences.dart';
import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_items.dart';
import 'package:specstone_core/src/doc_model/markdown_lines.dart'
    show tableCellRanges;
import 'package:specstone_core/src/doc_model/models/id_read.dart';
import 'package:specstone_core/src/doc_model/reference_grammar.dart';
import 'package:specstone_core/src/doc_model/sentence_measure.dart';
import 'package:specstone_core/src/doc_model/text_scan.dart';
import 'package:specstone_core/src/doc_model/trace_notes.dart';
import 'package:specstone_core/src/index_query/held_sections.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart'
    show DocContent, IndexedSection, indexedSectionsOf;
import 'package:specstone_core/src/index_query/item_words.dart';
import 'package:specstone_core/src/index_query/line_facts.dart';
import 'package:specstone_core/src/index_query/section_counts.dart'
    show SectionCounts;
import 'package:specstone_core/src/index_query/visible_text.dart';
import 'package:specstone_core/src/rendering/formatter.dart' show Formatted;
import 'package:specstone_core/src/rendering/generated_blocks.dart'
    show generatedBlockLines;
import 'package:specstone_core/src/rendering/line_ending.dart' show toLf;
import 'package:specstone_core/src/templates/merged_doc_type.dart';

/// One sentence of an item as `check` counts it: its language and counts, and
/// whether a `###` heading ends it.
///
/// `countsChars` says which counts the language reads; see [SentenceMeasure].
typedef SentenceFact = ({
  String language,
  bool countsChars,
  int words,
  int chars,
  int runs,
  bool isHeading,
});

/// What `check` reads of an item's readability.
///
/// `cells` holds the sentences of the item, one list for an item that is no
/// table row and one per cell for a table row; `notes` holds its trace notes.
/// A doc with no doc type holds none of either.
typedef ReadabilityFacts = ({
  List<List<SentenceFact>> cells,
  List<TraceNote> notes,
});

const ReadabilityFacts _noReadability = (cells: [], notes: []);

/// One item of a doc: the key `check` holds it by when it reads one, its
/// first line, its visible code points, and its readability facts.
///
/// `line`, `visibleChars`, and `readability` are those of the text the doc's
/// counts cover; `visibleChars` leaves out what a link or a link reference
/// definition hides, as [HiddenText] reads it.
typedef ItemFact = ({
  String? id,
  int line,
  int visibleChars,
  ReadabilityFacts readability,
});

/// The readability facts of one prose field value, read as one item.
final class FieldFact {
  const new({required this.readability});

  /// The sentences of the value, as one item holds them.
  final ReadabilityFacts readability;
}

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
          : (lines: lead[0]! as int, chars: lead[1]! as int),
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

/// Returns the items of [doc], the file's parse, in the text its counts cover.
///
/// [lineFacts] are those of [lfText]. The counts cover [laid]'s text when
/// [laid] is not null, else [lfText]; each section of [doc] takes the items of
/// its twin there, which [Formatted.twinOf] names. A doc of a [type] holds the
/// readability facts of its items, read against [idPrefixes], the item ID
/// prefixes of the merged doc type set, and of each prose field whose value in
/// [frontmatter] is a string.
ItemFacts itemFactsOf({
  required Doc doc,
  required String lfText,
  required LineFacts lineFacts,
  required Formatted? laid,
  required MergedDocType? type,
  Set<String> idPrefixes = const {},
  Map<String, Object?> frontmatter = const {},
}) {
  final counted = laid?.doc ?? doc;
  final countedText = laid?.text ?? lfText;
  final lines = countedText == lfText
      ? lineFacts
      : LineFacts.structureOf(lfText: countedText, doc: counted);
  final reads = _Reads(
    isTyped: type != null,
    idPrefixes: idPrefixes,
    hidden: HiddenText.of(
      counted.afterFrontmatter,
      firstLine: linesBeforeBodyOf(counted, countedText) + 1,
    ),
  );
  final held = indexedSectionsOf(counted, type);
  final templates = heldTemplatesOf(held, type);
  final isGenerated = generatedLineTest(
    counted,
    countedText,
    type?.listedGenerators.toSet() ?? const {},
  );
  final (:counts, :items) = _leadOf(
    counted,
    countedText,
    lines,
    isGenerated,
    reads,
  );
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
          reads,
        ),
    ],
    fieldItems: _fieldFactsOf(type, frontmatter),
  );
}

/// Returns the facts of each prose field of [type] whose value in
/// [frontmatter] is a string; any other value is left out.
Map<String, FieldFact> _fieldFactsOf(
  MergedDocType? type,
  Map<String, Object?> frontmatter,
) => {
  for (final field in type?.fields ?? const <MergedField>[])
    if (field.isProse)
      if (frontmatter[field.id] case final String value)
        field.id: FieldFact(
          readability: (cells: [_sentencesIn(value)], notes: const []),
        ),
};

/// Returns the items of the held section [at] of [content], a doc of [type],
/// each at its file line, with the structure a move cuts and lands by.
///
/// A closed generated block holds none, as the index reads items.
List<SectionItem> sectionItemsAt(
  DocContent content,
  int at,
  MergedDocType? type,
) {
  final body = sectionBodyLines(content.sections, content.lineFacts, at);
  final kinds = type?.listedGenerators.toSet() ?? const <String>{};
  if (kinds.isEmpty) return sectionItemsOf(body);
  final isGenerated = _generatedLines[content] ??= () {
    final text = toLf(content.text);
    return generatedLineTest(Doc.parse(text), text, kinds);
  }();
  return sectionItemsOf(withGeneratedFenced(body, isGenerated));
}

/// The generated-line test of each doc [sectionItemsAt] read, so a doc is
/// parsed once however many of its sections are read.
final _generatedLines = Expando<bool Function(int line)>();

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

/// Returns the body lines of the lead of [doc], the head after its title line,
/// each a line of the file [text].
///
/// A fenced line and a line [isGenerated] marks are fenced, so they hold no
/// item.
List<BodyLine> leadBodyLinesOf(
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
  return [
    for (var k = skip; k < head.length; k++)
      (
        text: head[k],
        line: firstBodyLine + k,
        fenced:
            lines.isFenced(firstBodyLine + k) || isGenerated(firstBodyLine + k),
      ),
  ];
}

/// Returns the lead of [doc]: its counts, from its first line of text to its
/// last with the line feeds between, and its items.
///
/// The counts are null when the lead holds no text.
({SectionCounts? counts, List<ItemFact> items}) _leadOf(
  Doc doc,
  String text,
  LineFacts lines,
  bool Function(int line) isGenerated,
  _Reads reads,
) {
  final body = leadBodyLinesOf(doc, text, lines, isGenerated);
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
    items: _itemFactsIn(body, null, reads),
  );
}

/// What an item's visible count and readability facts are read against.
///
/// A doc with no doc type holds no readability facts; a typed doc's trace notes
/// read item references of [idPrefixes]. [hidden] is what the counted text's
/// links and definitions hide.
final class _Reads {
  const new({
    required this.isTyped,
    required this.idPrefixes,
    required this.hidden,
  });

  final bool isTyped;
  final Set<String> idPrefixes;
  final HiddenText hidden;
}

List<ItemFact> _itemFactsIn(
  List<BodyLine> body,
  MergedSection? template,
  _Reads reads,
) => [
  for (final item in sectionItemsOf(body))
    _itemFactOf(item, _idReadOf(item, template), reads),
];

ItemFact _itemFactOf(SectionItem item, _ItemIdRead? read, _Reads reads) => (
  id: read == null ? null : itemKeyOf(read.id, isScenario: read.isScenario),
  line: item.line,
  visibleChars: _visibleCharsOf(item, reads.hidden),
  readability: reads.isTyped
      ? _readabilityOf(item, read, reads.idPrefixes)
      : _noReadability,
);

/// Returns the code points of [item] less those [hidden] hides on its lines.
int _visibleCharsOf(SectionItem item, HiddenText hidden) {
  final lastLine = item.line + '\n'.allMatches(item.text).length;
  return _codePointsOf(item.text) - hidden.codePointsOn(item.line, lastLine);
}

/// Returns the sentences and trace notes of [item].
///
/// Its leading ID [read], the `> <lang>:` marker of a quote line, and its
/// closing trace notes count in no sentence; a table row is cut into its cells
/// first, so each cell's end ends a sentence.
ReadabilityFacts _readabilityOf(
  SectionItem item,
  _ItemIdRead? read,
  Set<String> idPrefixes,
) {
  final isRow = item.kind == SectionItemKind.tableRow;
  final own = isRow ? item.firstLine : item.text;
  final (:notes, :counted) = traceNotesOf(own, idPrefixes, isTableRow: isRow);
  // A scenario number is not an item ID; only an item ID is stripped.
  final id = read != null && !read.isScenario ? read.id.written : null;
  return (
    cells: isRow
        ? _rowCells(counted, id)
        : [
            _sentencesIn(
              _withoutLanguageMarkers(
                _withoutIdAt(counted, _idStartOf(own, item.head), id),
              ),
            ),
          ],
    notes: [
      for (final note in notes)
        (text: note.closes ? '' : note.text, closes: note.closes),
    ],
  );
}

/// Returns the sentences of each cell of the table [row], less the item [id]
/// that opens its first cell.
List<List<SentenceFact>> _rowCells(String row, String? id) => [
  for (final (i, range) in tableCellRanges(row).indexed)
    _sentencesIn(
      i == 0
          ? _withoutIdAt(
              row.substring(range.start, range.end),
              _boldLengthOf(row.substring(range.start, range.end)),
              id,
            )
          : row.substring(range.start, range.end),
    ),
];

/// Returns where the item ID starts in [own], whose first line ends with
/// [head].
int _idStartOf(String own, String head) {
  final firstLineEnd = own.contains('\n') ? own.indexOf('\n') : own.length;
  return firstLineEnd - head.length + _boldLengthOf(head);
}

/// Returns the length of the `**` an item ID may open behind, else 0.
int _boldLengthOf(String text) =>
    text.startsWith(_boldMark) ? _boldMark.length : 0;

/// Returns [counted] without [id] at [start]; text with no [id] there, since a
/// closing note took its place, stays whole.
String _withoutIdAt(String counted, int start, String? id) {
  if (id == null || start > counted.length || !counted.startsWith(id, start)) {
    return counted;
  }
  return counted.replaceRange(start, start + id.length, '');
}

const _boldMark = '**';

/// The `<lang>:` a quote line opens with, after its `>` marks.
final _languageMarker = RegExp(r'^([ \t]*(?:>[ \t]?)+)[a-z]{2}:[ \t]*');

/// Returns [text] without the language marker its quote lines open with, the
/// `>` marks kept.
///
/// A marker leads when its line is the first quote line or sits right under a
/// line that carried one; a later `<xx>:` is text.
String _withoutLanguageMarkers(String text) {
  var seenQuote = false;
  var previousMarked = false;
  final lines = <String>[];
  for (final line in text.split('\n')) {
    final marker = _languageMarker.firstMatch(line);
    final isQuote = line.trimLeft().startsWith('>');
    final leads = marker != null && (!seenQuote || previousMarked);
    lines.add(leads ? line.replaceFirst(_languageMarker, marker[1]!) : line);
    previousMarked = leads;
    seenQuote = seenQuote || isQuote;
  }
  return lines.join('\n');
}

List<SentenceFact> _sentencesIn(String text) => [
  for (final sentence in checkSentencesOf(text))
    _factOf(measureSentence(sentence.text), isHeading: sentence.isHeading),
];

SentenceFact _factOf(SentenceMeasure measure, {required bool isHeading}) => (
  language: measure.language,
  countsChars: measure.countsChars,
  words: measure.words,
  chars: measure.chars,
  runs: measure.runs,
  isHeading: isHeading,
);

/// Returns the ID and kind [item] holds at its start, or null when it holds
/// none.
///
/// A letter right after the digits makes no ID, so a lettered or
/// unreadable form holds none.
_ItemIdRead? _idReadOf(SectionItem item, MergedSection? template) =>
    _idReadOfHead(
      item.head,
      isHeading: item.kind == SectionItemKind.heading,
      prefixId: template?.prefixId,
      isAcceptanceCriteria: template?.id == acceptanceSectionId,
    );

int _codePointsOf(String text) => text.length - scanText(text).pairs;

/// Returns the key `check` holds an item by, read from its [head] (the
/// item's first line after any marker), or null when it holds none.
///
/// The one reader of an item's ID: a `### Scenario <N>` heading of an
/// `acceptance_criteria` section keys by the number's value; any other item
/// keys by the ID of [prefixId] at its start.
String? itemKeyOfHead(
  String head, {
  required bool isHeading,
  required String? prefixId,
  required bool isAcceptanceCriteria,
}) => switch (_idReadOfHead(
  head,
  isHeading: isHeading,
  prefixId: prefixId,
  isAcceptanceCriteria: isAcceptanceCriteria,
)) {
  final read? => itemKeyOf(read.id, isScenario: read.isScenario),
  null => null,
};

/// An item ID read at the start of an item, and whether it is the number of a
/// `### Scenario <N>` heading.
typedef _ItemIdRead = ({ItemId id, bool isScenario});

_ItemIdRead? _idReadOfHead(
  String head, {
  required bool isHeading,
  required String? prefixId,
  required bool isAcceptanceCriteria,
}) {
  if (isHeading && isAcceptanceCriteria) {
    final scenario = readScenarioHead(head);
    if (scenario is ItemId) return (id: scenario, isScenario: true);
  }
  if (prefixId == null) return null;
  return switch (readItemId(head, prefixId)) {
    final ItemId id => (id: id, isScenario: false),
    _ => null,
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
    (
      id: item[0] as String?,
      line: item[1]! as int,
      visibleChars: item[2]! as int,
      readability: _readabilityOfJson(item.sublist(3)),
    ),
];

/// Reads the `[cells, notes]` pair [_cellsToJson] and [_notesToJson] wrote.
ReadabilityFacts _readabilityOfJson(List<Object?> json) => (
  cells: [
    for (final cell in (json[0]! as List<Object?>).cast<List<Object?>>())
      [
        for (final s in cell.cast<List<Object?>>())
          (
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
      (text: note[0]! as String, closes: note[1]! as bool),
  ],
);
